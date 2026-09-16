#!/usr/bin/env python3
"""Compile the supplied RUN//UNIT art archives into engine-ready 2D assets.

The script is deliberately deterministic: source order, atlas coordinates,
palette conversion and Godot resource names do not depend on directory order.
Source archives are identified by content signature, not by filename, so
re-downloading or renaming a source zip does not break the build. All
provenance recorded in the generated metadata is relative (source pack +
path, output path) so two builds on two machines produce byte-identical
JSON. A single output tree is written directly at its final
`install/assets/generated/...` location; nothing is generated twice.
"""
from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import re
import shutil
import tempfile
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source_assets"
OUT = ROOT / "run_unit_generated_assets"

# Reassigned once at the top of main(); free functions read it via rel_out().
INSTALL_BASE = ROOT


def png(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def hash_tree(root: Path) -> dict[str, str]:
    """SHA-256 of every file already written under `root`, keyed by relative path.

    Lets two builds be diffed with `compile` + `verify` instead of trusting
    that "nothing changed" by eye.
    """
    return {path.relative_to(root).as_posix(): sha256(path)
            for path in sorted(root.rglob("*")) if path.is_file()}


def safe_name(value: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", value.lower()).strip("_")


def rel_out(path: Path) -> str:
    """Path relative to the install root, e.g. 'assets/generated/converted/x.png'."""
    return path.relative_to(INSTALL_BASE).as_posix()


# --- Source identification --------------------------------------------------
# Packs are identified by a file that only they contain, not by the zip's
# filename. A re-download that appends "(1)" to a name, or a rename, no
# longer breaks the build.
SOURCE_SIGNATURES: dict[str, str] = {
    "smafu": "tileset.png",
    "industrial_zone": "IndustrialTile_01.png",
    "pzuh": "Tile (1).png",
    "bulkhead": "bulkhead-walls-back.png",
    "dark_city": "paralax1.png",
    "industrial_parallax": "skill-desc_0000_foreground.png",
    "battery": "battery_25x50px1.png",
    "fx_pack": "Free Preview All.gif",
}


def identify_pack(root: Path) -> str | None:
    matches = [key for key, signature in SOURCE_SIGNATURES.items()
               if next(root.rglob(signature), None) is not None]
    return matches[0] if len(matches) == 1 else None


def extract_archives(work: Path) -> tuple[dict[str, Path], list[dict[str, object]]]:
    """Extract every zip in SOURCE and identify it by content signature.

    Returns (pack_key -> extraction root, archive records for the inventory).
    A zip that matches no known signature is recorded with a null
    `detected_pack` and an explanation, rather than silently ignored or
    forced into a hard-coded slot.
    """
    work.mkdir(parents=True, exist_ok=True)
    roots: dict[str, Path] = {}
    records: list[dict[str, object]] = []
    for archive in sorted(SOURCE.glob("*.zip"), key=lambda p: p.name.lower()):
        target = work / archive.stem
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(target)
        pack_key = identify_pack(target)
        record: dict[str, object] = {"filename": archive.name, "sha256": sha256(archive),
                                      "detected_pack": pack_key}
        if pack_key is None:
            record["excluded_reason"] = "no known source signature matched; not used by this compiler pass"
        records.append(record)
        if pack_key is None:
            continue
        if pack_key in roots:
            raise ValueError(f"{archive.name!r} and an earlier archive both matched pack {pack_key!r}; "
                              "source signatures must uniquely identify one archive each")
        roots[pack_key] = target
    missing = sorted(set(SOURCE_SIGNATURES) - set(roots))
    if missing:
        raise FileNotFoundError(f"No supplied archive matched required pack(s): {missing}")
    return roots, records


def first(root: Path, pattern: str) -> Path:
    candidates = sorted(root.rglob(pattern), key=lambda p: str(p).lower())
    if not candidates:
        raise FileNotFoundError(f"No {pattern!r} below {root}")
    return candidates[0]


RUN_UNIT_PALETTE = {
    "void": "#090d18",
    "shadow": "#13213a",
    "steel": "#294b66",
    "detail": "#4d7891",
    "teal_dark": "#007f99",
    "teal": "#16d9e8",
    "highlight": "#dffcff",
    "warning": "#ffb020",
}


def hex_rgba(value: str) -> tuple[int, int, int, int]:
    value = value.removeprefix("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


RAMP = [hex_rgba(RUN_UNIT_PALETTE[key]) for key in
        ("void", "shadow", "steel", "detail", "teal_dark", "teal", "highlight")]
WARNING = hex_rgba(RUN_UNIT_PALETTE["warning"])


def convert_palette(image: Image.Image) -> Image.Image:
    """Map arbitrary pixel art into the RUN//UNIT navy / cyan material ramp."""
    result = Image.new("RGBA", image.size)
    converted = []
    for red, green, blue, alpha in image.getdata():
        if alpha == 0:
            converted.append((0, 0, 0, 0))
            continue
        hue, lightness, saturation = colorsys.rgb_to_hls(red / 255, green / 255, blue / 255)
        # Yellow/orange is reserved for warnings. Reds deliberately become cyan;
        # this removes Industrial Zone's dominant purple/red arcade language.
        is_warning = saturation > 0.42 and 0.075 <= hue <= 0.19 and lightness > 0.24
        if is_warning:
            color = WARNING
        else:
            index = max(0, min(len(RAMP) - 1, round(lightness * (len(RAMP) - 1))))
            color = RAMP[index]
        converted.append((color[0], color[1], color[2], alpha))
    result.putdata(converted)
    return result


def save_converted(pack_key: str, pack_root: Path, source: Path, target: Path) -> dict[str, object]:
    image = png(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    convert_palette(image).save(target)
    return {
        "source_pack": pack_key,
        "source_path": source.relative_to(pack_root).as_posix(),
        "output_path": rel_out(target),
        "size": list(image.size),
    }


def build_atlas(pack_key: str, pack_root: Path, files: list[Path], target: Path,
                tile_size: tuple[int, int], columns: int, convert: bool = True) -> list[dict[str, object]]:
    width, height = tile_size
    for item in files:
        if png(item).size != tile_size:
            raise ValueError(f"{item} is {png(item).size}; expected {tile_size}")
    rows = (len(files) + columns - 1) // columns
    atlas = Image.new("RGBA", (columns * width, rows * height))
    metadata = []
    for index, item in enumerate(files):
        x, y = (index % columns) * width, (index // columns) * height
        image = png(item)
        atlas.alpha_composite(convert_palette(image) if convert else image, (x, y))
        metadata.append({
            "id": index,
            "key": safe_name(item.stem),
            "source_pack": pack_key,
            "source_path": item.relative_to(pack_root).as_posix(),
            "atlas_cell": [index % columns, index // columns],
            "atlas_rect": [x, y, width, height],
            "role": "decoration",
            "collision": "level_semantic_layer",
        })
    target.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(target)
    return metadata


def tiled_atlas(name: str, image_rel: str, image_size: tuple[int, int], tile_size: tuple[int, int],
                tiles: list[dict[str, object]], tile_type: str = "RUN_UNIT_DECOR") -> dict[str, object]:
    tile_w, tile_h = tile_size
    return {
        "columns": image_size[0] // tile_w,
        "image": image_rel,
        "imageheight": image_size[1],
        "imagewidth": image_size[0],
        "name": name,
        "tilecount": len(tiles),
        "tiledversion": "1.11",
        "tileheight": tile_h,
        "tilewidth": tile_w,
        "type": "tileset",
        "version": "1.10",
        "tiles": [
            {
                "id": tile["id"],
                "type": tile_type,
                "properties": [
                    {"name": "asset_key", "type": "string", "value": tile["key"]},
                    {"name": "collision", "type": "string", "value": "level_semantic_layer"},
                    {"name": "review_status", "type": "string", "value": "art_classified"},
                ],
            }
            for tile in tiles
        ],
    }


def write_spriteframes(target: Path, texture_path: str, frame_w: int, frame_h: int,
                       frames: int, palette_rows: int, fps: int = 16) -> None:
    lines = ["[gd_resource type=\"SpriteFrames\" load_steps=%d format=3]" % (1 + frames * palette_rows), "",
             "[ext_resource type=\"Texture2D\" path=\"%s\" id=\"1_sheet\"]" % texture_path, ""]
    subresources = []
    for row in range(palette_rows):
        for frame in range(frames):
            identity = f"AtlasTexture_{row}_{frame}"
            lines.extend([
                f"[sub_resource type=\"AtlasTexture\" id=\"{identity}\"]",
                "atlas = ExtResource(\"1_sheet\")",
                f"region = Rect2({frame * frame_w}, {row * frame_h}, {frame_w}, {frame_h})",
                "",
            ])
            subresources.append((row, frame, identity))
    lines.extend(["[resource]", "animations = ["])
    for row in range(palette_rows):
        lines.extend(["{", "\"frames\": ["])
        for frame in range(frames):
            identity = subresources[row * frames + frame][2]
            lines.extend(["{", "\"duration\": 1.0,", f"\"texture\": SubResource(\"{identity}\")", "},"])
        lines.extend(["],", "\"loop\": true,", f"\"name\": &\"palette_{row}\",", f"\"speed\": {fps}.0", "},"])
    lines.extend(["]", ""])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def parallax_scene(target: Path, layer_paths: list[str], scrolls: list[float] | None = None,
                   repeat_size: tuple[int, int] = (960, 540), pixel_scale: int = 2) -> None:
    scrolls = scrolls or [0.30, 0.18, 0.10, 0.05, 0.02]
    if len(layer_paths) != len(scrolls):
        raise ValueError("Each parallax path needs exactly one scroll scale")
    lines = [f"[gd_scene load_steps={1 + len(layer_paths)} format=3]", ""]
    for index, path in enumerate(layer_paths, start=1):
        lines.append(f"[ext_resource type=\"Texture2D\" path=\"{path}\" id=\"{index}_layer\"]")
    lines.extend(["", "[node name=\"CityParallax\" type=\"Node2D\"]", ""])
    # Asset layer 1 is nearest; scene order uses far -> near.
    for layer in range(len(layer_paths), 0, -1):
        lines.extend([
            f"[node name=\"Layer_{layer}\" type=\"Parallax2D\" parent=\".\"]",
            f"repeat_size = Vector2i({repeat_size[0]}, {repeat_size[1]})",
            f"scroll_scale = Vector2({scrolls[layer - 1]:.2f}, {scrolls[layer - 1]:.2f})",
            "",
            f"[node name=\"Sprite\" type=\"Sprite2D\" parent=\"Layer_{layer}\"]",
            "centered = false",
            f"texture = ExtResource(\"{layer}_layer\")",
            f"scale = Vector2({pixel_scale}, {pixel_scale})",
            "",
        ])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines), encoding="utf-8", newline="\n")


# --- Horizontal sprite-strip frame inference --------------------------------
# Industrial Zone's "4 Animated objects" sheets are horizontal strips whose
# frame is only square *most* of the time: Screen2.png is 128x42 (four
# 32x42 frames), not a 42-wide square frame. Rather than assume
# frame_width == image_height, try the tile widths this project's source
# packs actually use (32px Industrial Zone grid, 16px Smafu-derived pieces)
# and accept the first one that evenly divides the sheet without being
# wider than the sheet is tall.
_FRAME_WIDTH_CANDIDATES = (64, 32, 24, 16)


def infer_frame_width(image: Image.Image) -> int | None:
    for candidate in _FRAME_WIDTH_CANDIDATES:
        if image.width % candidate == 0 and candidate <= image.height:
            return candidate
    if image.width % image.height == 0:
        return image.height
    return None


# --- Semantic asset vocabulary -----------------------------------------------
# Raw tile/frame keys (smafu_038, industrialtile_45, ...) tell an agent that
# an asset *exists*, not what it *means*. This curated table is the first
# pass at closing that gap for run-unit's own gameplay grammar: it names a
# meaningful role, points it at a real, visually verified asset key (or a
# multi-cell "assembly" of them), and records how it sockets against its
# neighbours. It is deliberately a curated subset, not an exhaustive
# classification of every generated tile -- see semantic_tile_contract.json
# for the one rule that is load-bearing (art never creates collision); this
# file is a design aid for *selecting* art, nothing here is authoritative.
SEMANTIC_ASSET_LIBRARY: dict[str, dict[str, object]] = {
    "floor_solid": {
        "summary": "Flat 16px navy panel with no ornamentation; safe generic solid ground/wall block.",
        "pack": "smafu", "asset": "smafu_000", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "solid",
        "sockets": ["left", "right", "top", "bottom"],
        "adjacency": {"left": ["floor_solid"], "right": ["floor_solid"],
                      "top": ["floor_solid"], "bottom": ["floor_solid"]},
        "usage": ["level_geometry", "background_wall"],
    },
    "floor_wedge_nw": {
        "summary": "45-degree corner-cut ground tile, NW cell of a matched 2x2 wedge set. "
                   "Confirm the exact slope direction visually before using it as a walkable ramp.",
        "pack": "smafu", "asset": "smafu_023", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "solid",
        "matched_set": ["smafu_023", "smafu_024", "smafu_041", "smafu_042"],
        "usage": ["level_geometry"],
    },
    "floor_wedge_ne": {
        "summary": "45-degree corner-cut ground tile, NE cell of the same matched 2x2 wedge set as floor_wedge_nw.",
        "pack": "smafu", "asset": "smafu_024", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "solid",
        "matched_set": ["smafu_023", "smafu_024", "smafu_041", "smafu_042"],
        "usage": ["level_geometry"],
    },
    "floor_wedge_sw": {
        "summary": "45-degree corner-cut ground tile, SW cell of the same matched 2x2 wedge set as floor_wedge_nw.",
        "pack": "smafu", "asset": "smafu_041", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "solid",
        "matched_set": ["smafu_023", "smafu_024", "smafu_041", "smafu_042"],
        "usage": ["level_geometry"],
    },
    "floor_wedge_se": {
        "summary": "45-degree corner-cut ground tile, SE cell of the same matched 2x2 wedge set as floor_wedge_nw.",
        "pack": "smafu", "asset": "smafu_042", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "solid",
        "matched_set": ["smafu_023", "smafu_024", "smafu_041", "smafu_042"],
        "usage": ["level_geometry"],
    },
    "floor_hatch_grate": {
        "summary": "2x2 green-bordered floor hatch / grate panel. Whether it should be walkable, "
                   "one-way, or purely decorative is a level-design call this table does not make.",
        "pack": "smafu", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "unassigned",
        "assembly": {"top_left": "smafu_021", "top_right": "smafu_022",
                     "bottom_left": "smafu_039", "bottom_right": "smafu_040"},
        "usage": ["level_geometry", "decoration"],
    },
    "hazard_spike_row": {
        "summary": "Repeatable spike-hazard strip (white spikes on a dark base); variants continue "
                   "through smafu_067-smafu_071.",
        "pack": "smafu", "asset": "smafu_066", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "hazard",
        "sockets": ["left", "right"],
        "adjacency": {"left": ["hazard_spike_row"], "right": ["hazard_spike_row"]},
        "usage": ["hazard"],
    },
    "hazard_stripe_marker": {
        "summary": "Orange diagonal warning-stripe floor marking. This is a decorative caution "
                   "marker, not itself a collision hazard -- pair it with a real hazard tile or a level edge.",
        "pack": "smafu", "asset": "smafu_044", "cell_size": [16, 16],
        "placement": "surface", "semantic_support": "none",
        "usage": ["decoration", "hazard_marker"],
    },
    "hazard_laser_gate_thin": {
        "summary": "3-cell vertical laser-hazard column: emitter cap, single thin beam, emitter base.",
        "pack": "smafu", "cell_size": [16, 16],
        "placement": "vertical_stack", "semantic_support": "hazard",
        "assembly": {"top": "smafu_103", "mid": "smafu_121", "base": "smafu_139"},
        "sockets": ["top", "bottom"], "usage": ["hazard"],
    },
    "hazard_laser_gate_double": {
        "summary": "4-cell vertical laser-hazard column with a taller double beam between cap and base.",
        "pack": "smafu", "cell_size": [16, 16],
        "placement": "vertical_stack", "semantic_support": "hazard",
        "assembly": {"top": "smafu_104", "mid_upper": "smafu_122", "mid_lower": "smafu_140", "base": "smafu_158"},
        "sockets": ["top", "bottom"], "usage": ["hazard"],
    },
    "hazard_laser_gate_wide": {
        "summary": "4-cell vertical laser-hazard column with a wide/pink beam variant of hazard_laser_gate_double.",
        "pack": "smafu", "cell_size": [16, 16],
        "placement": "vertical_stack", "semantic_support": "hazard",
        "assembly": {"top": "smafu_105", "mid_upper": "smafu_123", "mid_lower": "smafu_141", "base": "smafu_159"},
        "sockets": ["top", "bottom"], "usage": ["hazard"],
    },
    "wall_panel_flat": {
        "summary": "Plain flat industrial wall/floor panel with no ornamentation; safe generic 32px solid block.",
        "pack": "industrial_zone", "asset": "industrialtile_03", "cell_size": [32, 32],
        "placement": "surface", "semantic_support": "solid",
        "sockets": ["left", "right", "top", "bottom"],
        "adjacency": {"left": ["wall_panel_flat"], "right": ["wall_panel_flat"],
                      "top": ["wall_panel_flat"], "bottom": ["wall_panel_flat"]},
        "usage": ["level_geometry", "background_wall"],
    },
    "wall_panel_accent": {
        "summary": "Flat violet accent-color panel, same silhouette as wall_panel_flat; "
                   "use to break up large industrial surfaces.",
        "pack": "industrial_zone", "asset": "industrialtile_01", "cell_size": [32, 32],
        "placement": "surface", "semantic_support": "solid",
        "usage": ["level_geometry", "background_wall"],
    },
    "wall_panel_riveted_large": {
        "summary": "3x3 riveted wall section with a recessed bolted center; a large background/"
                   "structural motif, not a single repeatable tile.",
        "pack": "industrial_zone", "cell_size": [32, 32],
        "placement": "background_wall", "semantic_support": "none",
        "assembly": {
            "row0": ["industrialtile_04", "industrialtile_05", "industrialtile_06"],
            "row1": ["industrialtile_13", "industrialtile_14", "industrialtile_15"],
            "row2": ["industrialtile_22", "industrialtile_23", "industrialtile_24"],
        },
        "usage": ["background_wall", "decoration"],
    },
    "pipe_column_reactor": {
        "summary": "Vertical hazard-banded reactor conduit assembled from 4 stacked 32px segments; "
                   "visually distinct from the plain repeatable pipe_v_mid segment.",
        "pack": "industrial_zone", "cell_size": [32, 32],
        "placement": "vertical_stack", "semantic_support": "none",
        "assembly": {"top": "industrialtile_45", "mid": "industrialtile_54",
                     "body": "industrialtile_63", "base": "industrialtile_72"},
        "sockets": ["top", "bottom"], "usage": ["world_prop", "background_wall"],
    },
    "pipe_v_mid": {
        "summary": "Plain gray cylindrical pipe segment with no caps; repeat vertically for a pipe run of any height.",
        "pack": "industrial_zone", "asset": "industrialtile_61", "cell_size": [32, 32],
        "placement": "vertical_stack", "semantic_support": "none",
        "sockets": ["top", "bottom"],
        "adjacency": {"top": ["pipe_v_mid"], "bottom": ["pipe_v_mid"]},
        "usage": ["world_prop", "background_wall"],
    },
    "warning_light_strip": {
        "summary": "Horizontal strip of red warning lights; decorative hazard marker drawn as one wide sprite.",
        "pack": "industrial_zone", "asset": "industrialtile_74", "cell_size": [32, 32],
        "placement": "surface", "semantic_support": "none",
        "usage": ["decoration", "hazard_marker"],
    },
    "energy_cell": {
        "summary": "60-frame battery charge-level animation, previously hard-classified as UI-only. "
                   "Equally usable as a world prop, pickup, or machine component -- the role depends "
                   "on where it is placed, not on the art.",
        "pack": "battery", "asset": "battery_25x50px1", "cell_size": [18, 25],
        "frame_count": 60, "fps": 12,
        "placement": "prop_or_ui", "semantic_support": "none",
        "usage": ["world_prop", "collectible", "machine_component", "hud_icon"],
    },
}


def _semantic_leaf_keys(entry: dict[str, object]) -> list[str]:
    keys: list[str] = []
    if "asset" in entry:
        keys.append(str(entry["asset"]))
    stack = [entry["assembly"]] if "assembly" in entry else []
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
        else:
            keys.append(str(node))
    return keys


def attach_semantic_keys(tiles: list[dict[str, object]]) -> list[dict[str, object]]:
    """Tag each raw tile/frame dict with the semantic entries (if any) that reference it."""
    reverse: dict[str, list[str]] = {}
    for name, entry in SEMANTIC_ASSET_LIBRARY.items():
        for key in _semantic_leaf_keys(entry):
            reverse.setdefault(key, []).append(name)
    for tile in tiles:
        tile["semantic_keys"] = sorted(reverse.get(tile["key"], []))
    return tiles


def main() -> None:
    global SOURCE, INSTALL_BASE
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()
    SOURCE = args.source.resolve()
    output = args.output.resolve()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    # Extract into a real OS temp directory, never next to the script -- ROOT is
    # typically inside the game repo itself, and extracted third-party source
    # archives (unlike the converted/normalised output) must never land in a
    # path a `git add tools/` would pick up.
    work = Path(tempfile.mkdtemp(prefix="run_unit_asset_extract_"))
    roots, archive_records = extract_archives(work)

    # A single output tree, written directly at its final install location --
    # nothing here is generated once and then copied a second time.
    install_base = output / "install"
    INSTALL_BASE = install_base
    install_root = install_base / "assets" / "generated"
    assets = install_root
    atlases = assets / "atlases"
    converted = assets / "converted"
    metadata_dir = install_root / "metadata"
    tiled = install_root / "tiled"
    godot = install_root / "godot"
    licence_dir = install_root / "licenses"

    inventory: dict[str, object] = {
        "palette": RUN_UNIT_PALETTE,
        "source_signatures": SOURCE_SIGNATURES,
        "archives": archive_records,
        "outputs": {},
    }
    write_json(assets / "palettes" / "run_unit_cyan.json", {
        "name": "RUN_UNIT_Cyan_Industrial", "colors": RUN_UNIT_PALETTE,
        "conversion": "Orange/yellow high-saturation pixels become warning amber; all other pixels are quantised by HSL lightness into the navy/cyan material ramp."
    })

    # --- Core 16px Smafu grid -------------------------------------------------
    smafu_root = roots["smafu"]
    smafu_source = first(smafu_root, "tileset.png")
    smafu_converted = converted / "smafu_core_cyan.png"
    save_converted("smafu", smafu_root, smafu_source, smafu_converted)
    smafu_image = png(smafu_source)
    smafu_tiles = []
    for tile_id in range((smafu_image.width // 16) * (smafu_image.height // 16)):
        x, y = (tile_id % (smafu_image.width // 16)) * 16, (tile_id // (smafu_image.width // 16)) * 16
        alpha = smafu_image.crop((x, y, x + 16, y + 16)).getchannel("A").getbbox()
        smafu_tiles.append({"id": tile_id, "key": f"smafu_{tile_id:03d}", "atlas_cell": [tile_id % 18, tile_id // 18],
                            "nonempty": alpha is not None, "role": "decoration", "collision": "level_semantic_layer"})
    smafu_tiles = attach_semantic_keys(smafu_tiles)
    write_json(metadata_dir / "smafu_core.json", {
        "tile_size": [16, 16], "columns": 18, "source_pack": "smafu",
        "source_path": smafu_source.relative_to(smafu_root).as_posix(),
        "atlas_output_path": rel_out(smafu_converted), "tiles": smafu_tiles,
    })
    write_json(tiled / "smafu_core.tsj", tiled_atlas("RUN_UNIT_Smafu_Core", "../converted/smafu_core_cyan.png", smafu_image.size, (16, 16), smafu_tiles))

    # --- Industrial Zone: individual 32px cells assembled into one stable atlas.
    industrial_root = roots["industrial_zone"]
    industrial_tiles = sorted(first(industrial_root, "IndustrialTile_01.png").parent.glob("IndustrialTile_*.png"),
                              key=lambda p: int(re.search(r"(\d+)", p.stem).group(1)))
    industrial_atlas_path = atlases / "industrial_zone_cyan_32.png"
    industrial_meta = build_atlas("industrial_zone", industrial_root, industrial_tiles, industrial_atlas_path, (32, 32), 9)
    industrial_meta = attach_semantic_keys(industrial_meta)
    industrial_atlas = png(industrial_atlas_path)
    write_json(metadata_dir / "industrial_zone_tiles.json", {
        "tile_size": [32, 32], "atlas_output_path": rel_out(industrial_atlas_path), "tiles": industrial_meta,
    })
    write_json(tiled / "industrial_zone.tsj", tiled_atlas("RUN_UNIT_Industrial_Zone", "../atlases/industrial_zone_cyan_32.png", industrial_atlas.size, (32, 32), industrial_meta))

    # Objects remain independently placeable (Tiled image collection is safer than forcing them into a false grid).
    object_root = first(industrial_root, "Barrel1.png").parent
    object_meta = []
    for source in sorted(object_root.glob("*.png"), key=lambda p: p.name.lower()):
        target = converted / "industrial_objects" / f"{safe_name(source.stem)}.png"
        object_meta.append({"key": safe_name(source.stem), **save_converted("industrial_zone", industrial_root, source, target)})
    write_json(metadata_dir / "industrial_objects.json", object_meta)

    # --- CC0 vector donor: raster PNG pages are normalized as 256px atlases.
    vector_root = roots["pzuh"]
    pzuh_tiles = sorted(first(vector_root, "Tile (1).png").parent.glob("*.png"), key=lambda p: p.name.lower())
    pzuh_atlas_path = atlases / "pzuh_tiles_cyan_256.png"
    pzuh_tile_meta = build_atlas("pzuh", vector_root, pzuh_tiles, pzuh_atlas_path, (256, 256), 7)
    pzuh_atlas = png(pzuh_atlas_path)
    write_json(metadata_dir / "pzuh_tiles.json", {"tile_size": [256, 256], "atlas_output_path": rel_out(pzuh_atlas_path),
                                                     "tiles": pzuh_tile_meta,
                                                     "vector_source": "Tile.svg is retained in the original archive"})
    write_json(tiled / "pzuh_structures.tsj", tiled_atlas("RUN_UNIT_PZUH_Structures", "../atlases/pzuh_tiles_cyan_256.png", pzuh_atlas.size, (256, 256), pzuh_tile_meta))
    pzuh_objects = sorted(first(vector_root, "DoorLocked.png").parent.glob("*.png"), key=lambda p: p.name.lower())
    pzuh_object_meta = []
    for tile_id, source in enumerate(pzuh_objects):
        image = png(source)
        key = safe_name(source.stem)
        target = converted / "pzuh_objects" / f"{key}.png"
        save_converted("pzuh", vector_root, source, target)
        pzuh_object_meta.append({"id": tile_id, "key": key, "source_pack": "pzuh",
                                 "source_path": source.relative_to(vector_root).as_posix(),
                                 "output_path": rel_out(target), "size": list(image.size),
                                 "role": "object", "collision": "level_semantic_layer"})
    write_json(metadata_dir / "pzuh_objects.json", pzuh_object_meta)
    write_json(tiled / "pzuh_objects.tsj", {
        "name": "RUN_UNIT_PZUH_Objects", "tilewidth": 512, "tileheight": 512, "tilecount": len(pzuh_object_meta),
        "columns": 0, "type": "tileset", "version": "1.10", "tiledversion": "1.11",
        "tiles": [{"id": item["id"], "type": "RUN_UNIT_DECOR", "image": f"../converted/pzuh_objects/{item['key']}.png",
                   "imagewidth": item["size"][0], "imageheight": item["size"][1],
                   "properties": [{"name": "asset_key", "type": "string", "value": item["key"]},
                                  {"name": "collision", "type": "string", "value": "level_semantic_layer"}]}
                  for item in pzuh_object_meta]
    })

    # --- Bulkhead macro-compositions, intentionally not collision tiles.
    bulkhead_root = roots["bulkhead"]
    layer_root = first(bulkhead_root, "bulkhead-walls-back.png").parent
    layer_order = ["bulkhead-walls-back.png", "cols.png", "bulkhead-walls-pipes.png", "bulkhead-walls-platform.png"]
    bulkhead_layers = [layer_root / name for name in layer_order]
    converted_layers = []
    for source in bulkhead_layers:
        target = converted / "bulkhead" / source.name
        save_converted("bulkhead", bulkhead_root, source, target)
        converted_layers.append(target)
    full = Image.new("RGBA", png(converted_layers[0]).size)
    for layer in converted_layers:
        full.alpha_composite(png(layer))
    (converted / "bulkhead").mkdir(parents=True, exist_ok=True)
    full.save(converted / "bulkhead" / "bulkhead_run_unit_full.png")
    write_json(metadata_dir / "bulkhead_macro.json", {"size": list(full.size), "source_pack": "bulkhead", "layers": layer_order,
                                                        "collision": "none", "use": "background_macro_chunk"})
    write_json(tiled / "bulkhead_macro.tsj", {
        "name": "RUN_UNIT_Bulkhead_Macros", "tilewidth": full.width, "tileheight": full.height,
        "tilecount": 1, "columns": 0, "type": "tileset", "version": "1.10", "tiledversion": "1.11",
                   "tiles": [{"id": 0, "type": "RUN_UNIT_BACKGROUND", "image": "../converted/bulkhead/bulkhead_run_unit_full.png",
                   "imagewidth": full.width, "imageheight": full.height,
                   "properties": [{"name": "collision", "type": "string", "value": "none"},
                                  {"name": "asset_key", "type": "string", "value": "bulkhead_run_unit_full"}]}]
    })

    # --- City parallax: composited preview plus individually-scrolling layers.
    city_root = roots["dark_city"]
    city_blue = city_root / "blue"
    city_targets = []
    for index in range(1, 6):
        source = city_blue / f"paralax{index}.png"
        target = converted / "city_parallax" / f"city_layer_{index}.png"
        save_converted("dark_city", city_root, source, target)
        city_targets.append(target)
    city_composite = Image.new("RGBA", png(city_targets[0]).size)
    for target in reversed(city_targets):
        city_composite.alpha_composite(png(target))
    city_composite.save(converted / "city_parallax" / "city_composite_480x270.png")
    city_composite.resize((960, 540), Image.Resampling.NEAREST).save(converted / "city_parallax" / "city_composite_960x540.png")
    parallax_scene(godot / "parallax" / "city_run_unit.tscn", [f"res://assets/generated/converted/city_parallax/city_layer_{i}.png" for i in range(1, 6)])
    write_json(metadata_dir / "city_parallax.json", {"source_palette": "blue", "native_size": [480, 270], "viewport_size": [960, 540],
        "layers": [{"index": i, "source_pack": "dark_city", "source_path": f"blue/paralax{i}.png",
                    "path": f"assets/generated/converted/city_parallax/city_layer_{i}.png", "scroll_scale": scale}
                   for i, scale in enumerate([0.30, 0.18, 0.10, 0.05, 0.02], start=1)]})

    # --- Industrial skyline: normalise its uneven source layers to one canvas.
    industrial_parallax_root = roots["industrial_parallax"]
    industrial_layers_root = first(industrial_parallax_root, "skill-desc_0000_foreground.png").parent
    industrial_parallax_sources = [
        industrial_layers_root / "skill-desc_0000_foreground.png",
        industrial_layers_root / "skill-desc_0001_buildings.png",
        industrial_layers_root / "skill-desc_0002_far-buildings.png",
        industrial_layers_root / "skill-desc_0003_bg.png",
    ]
    industrial_canvas_size = png(industrial_parallax_sources[-1]).size
    industrial_targets = []
    for index, source in enumerate(industrial_parallax_sources, start=1):
        layer = convert_palette(png(source))
        padded = Image.new("RGBA", industrial_canvas_size)
        padded.alpha_composite(layer, ((industrial_canvas_size[0] - layer.width) // 2, industrial_canvas_size[1] - layer.height))
        target = converted / "industrial_parallax" / f"industrial_layer_{index}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        padded.save(target)
        industrial_targets.append(target)
    industrial_composite = Image.new("RGBA", industrial_canvas_size)
    for target in reversed(industrial_targets):
        industrial_composite.alpha_composite(png(target))
    industrial_composite.save(converted / "industrial_parallax" / "industrial_composite_272x160.png")
    industrial_composite.resize((1088, 640), Image.Resampling.NEAREST).save(converted / "industrial_parallax" / "industrial_composite_1088x640.png")
    parallax_scene(godot / "parallax" / "industrial_skyline_run_unit.tscn",
                   [f"res://assets/generated/converted/industrial_parallax/industrial_layer_{i}.png" for i in range(1, 5)],
                   [0.35, 0.18, 0.08, 0.02], (1088, 640), 4)
    write_json(metadata_dir / "industrial_parallax.json", {
        "license": "CC0; bundled licence.txt from the supplied archive",
        "native_size": list(industrial_canvas_size), "viewport_composition": [1088, 640],
        "layers": [{"index": i, "source_pack": "industrial_parallax",
                    "source_path": source.relative_to(industrial_parallax_root).as_posix(),
                    "scroll_scale": scale, "bottom_aligned": True}
                   for i, (source, scale) in enumerate(zip(industrial_parallax_sources, [0.35, 0.18, 0.08, 0.02]), start=1)]
    })
    licence_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(first(industrial_parallax_root, "license.txt"), licence_dir / "industrial_parallax_CC0.txt")

    # --- Battery HUD: ordered frames are both an atlas and a 60-frame Godot animation.
    battery_root = roots["battery"]
    battery_files = sorted(first(battery_root, "battery_25x50px1.png").parent.glob("battery_25x50px*.png"),
                           key=lambda p: int(re.search(r"(\d+)$", p.stem).group(1)))
    battery_atlas_path = atlases / "battery_charge_cyan_18x25.png"
    battery_meta = build_atlas("battery", battery_root, battery_files, battery_atlas_path, (18, 25), 10)
    for item in battery_meta:
        item["role"] = "ui"
        item["collision"] = "none"
    battery_meta = attach_semantic_keys(battery_meta)
    battery_atlas = png(battery_atlas_path)
    write_json(metadata_dir / "battery_charge.json", {
        "license": "No licence file was present in the supplied archive; verify provenance before release.",
        "frame_size": [18, 25], "frame_count": len(battery_meta), "fps": 12,
        "atlas_output_path": rel_out(battery_atlas_path), "frames": battery_meta,
    })
    write_json(tiled / "battery_charge.tsj", tiled_atlas("RUN_UNIT_Battery_Charge", "../atlases/battery_charge_cyan_18x25.png",
               battery_atlas.size, (18, 25), battery_meta, "RUN_UNIT_UI"))
    write_spriteframes(godot / "spriteframes" / "ui" / "battery_charge.tres",
                       "res://assets/generated/atlases/battery_charge_cyan_18x25.png", 18, 25, len(battery_meta), 1, 12)
    (licence_dir / "battery_provenance.txt").write_text(
        "Battery.zip was supplied by the user and contained no licence file. "
        "Treat the derived battery sprites as provenance-unverified until their upstream source and licence are recorded.\n",
        encoding="utf-8", newline="\n")

    # --- Effects: 180 sheets -> 9 animation variants each with correctly sized AtlasTextures.
    fx_root = roots["fx_pack"]
    fx_entries = []
    for source in sorted(fx_root.rglob("*.png"), key=lambda p: str(p).lower()):
        if "Preview" in source.name:
            continue
        image = png(source)
        if image.height % 64 or image.width % 64 or image.height // 64 != 9:
            continue
        part = safe_name(source.parent.name)
        effect = safe_name(source.stem)
        target = assets / "fx" / "sheets" / part / f"fx_{effect}.png"
        save_converted("fx_pack", fx_root, source, target)
        frames = image.width // 64
        tres = godot / "spriteframes" / "fx" / part / f"fx_{effect}.tres"
        resource_path = f"res://assets/generated/fx/sheets/{part}/fx_{effect}.png"
        write_spriteframes(tres, resource_path, 64, 64, frames, 9)
        fx_entries.append({"key": f"{part}_{effect}", "source_pack": "fx_pack",
                           "source_path": source.relative_to(fx_root).as_posix(),
                           "sheet_output_path": rel_out(target), "spriteframes_output_path": rel_out(tres),
                           "frame_size": [64, 64], "frames": frames, "palette_rows": 9, "fps": 16})
    write_json(metadata_dir / "fx_manifest.json", {
        "curation_status": "uncurated -- all 180 sheets are listed with generator-assigned keys "
                           "(e.g. 'part_7_336'); a follow-up visual pass should promote ~20-30 of these "
                           "into named SEMANTIC_ASSET_LIBRARY entries (spark_small, electrical_arc, ...) "
                           "the way floor_solid or pipe_v_mid were promoted from Smafu/Industrial Zone.",
        "count": len(fx_entries), "effects": fx_entries,
    })

    # Industrial animated objects are simple horizontal sprite sheets; frame width is
    # inferred per-sheet rather than assumed square (see infer_frame_width).
    animated_root = first(industrial_root, "Card.png").parent
    animated_entries = []
    for source in sorted(animated_root.glob("*.png"), key=lambda p: p.name.lower()):
        image = png(source)
        target = assets / "industrial_animated" / f"{safe_name(source.stem)}.png"
        save_converted("industrial_zone", industrial_root, source, target)
        frame_width = infer_frame_width(image)
        if frame_width is not None:
            frames = image.width // frame_width
            tres = godot / "spriteframes" / "industrial" / f"{safe_name(source.stem)}.tres"
            write_spriteframes(tres, f"res://assets/generated/industrial_animated/{safe_name(source.stem)}.png",
                               frame_width, image.height, frames, 1, 8)
            spriteframes_path, frame_size = rel_out(tres), [frame_width, image.height]
        else:
            frames, spriteframes_path, frame_size = None, None, None
        animated_entries.append({"key": safe_name(source.stem), "size": list(image.size), "frame_size": frame_size,
                                 "frames": frames, "spriteframes": spriteframes_path, "source_pack": "industrial_zone",
                                 "source_path": source.relative_to(industrial_root).as_posix()})
    write_json(metadata_dir / "industrial_animated.json", animated_entries)

    write_json(metadata_dir / "semantic_tile_contract.json", {
        "purpose": "Gameplay is independent from art tile IDs.",
        "cell_values": {"0": "empty", "1": "solid", "2": "one_way", "3": "hazard", "4": "conveyor", "5": "foreground"},
        "rule": "Only the level semantic layer may create collision. Generated art tiles are decor/background by default."
    })
    write_json(metadata_dir / "semantic_asset_library.json", {
        "purpose": "Curated, human/agent-readable semantic roles for a subset of generated assets -- a "
                   "design aid for SELECTING art. It never creates collision; semantic_tile_contract.json's "
                   "level layer is the only thing allowed to do that.",
        "schema": {
            "pack": "which source pack (see source_signatures) the asset was drawn from",
            "asset": "a single raw tile/frame key, for a single-cell entry",
            "assembly": "role -> asset key (or nested list of keys) for a multi-cell prop",
            "matched_set": "sibling asset keys authored together as one visual set",
            "cell_size": "[w, h] px of one cell in the assembly's native pack",
            "placement": "surface | background_wall | vertical_stack | prop_or_ui",
            "semantic_support": "solid | hazard | one_way | none | unassigned -- a HINT only; "
                                "semantic_tile_contract.json's level layer is authoritative",
            "sockets": "named connection points this entry exposes",
            "adjacency": "socket -> list of semantic keys that tile naturally against it",
            "usage": "intended roles; an asset may serve more than one",
        },
        "entries": SEMANTIC_ASSET_LIBRARY,
    })

    (output / "tools").mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__), output / "tools" / "compile_run_unit_assets.py")
    requirements_src = ROOT / "requirements.txt"
    if requirements_src.exists():
        shutil.copy2(requirements_src, output / "tools" / "requirements.txt")

    # Hash every file already on disk before writing the inventory itself, so
    # `compile` followed by `verify` can detect whether a regeneration changed anything.
    inventory["outputs"] = hash_tree(install_base)
    write_json(metadata_dir / "asset_inventory.json", inventory)

    (output / "README.md").write_text("""# RUN//UNIT generated asset pack

This pack was generated from eight user-supplied archives, identified by content signature rather than filename (see `metadata/asset_inventory.json` -> `source_signatures`). It contains deterministic atlases, metadata with fully relative provenance, palette-normalised derivatives, Tiled `.tsj` definitions, Godot `SpriteFrames` resources, a 5-layer city `Parallax2D` scene, a 4-layer industrial skyline scene, a 60-frame battery HUD animation, and a curated `metadata/semantic_asset_library.json` mapping a subset of tiles to gameplay-meaningful roles.

## Installation

Copy the contents of `install/` into your Godot project root. It becomes `res://assets/generated/`; the paths in the generated `SpriteFrames`, parallax scenes and Tiled files then resolve without edits. There is exactly one copy of every generated file -- nothing here is duplicated elsewhere in this pack.

## Rebuilding

```sh
pip install -r tools/requirements.txt
python tools/compile_run_unit_assets.py --source /path/to/source_zips --output /path/to/output
```

`metadata/asset_inventory.json` records a SHA-256 for every generated file under `outputs`. Diff two builds' `outputs` maps to confirm a rebuild is byte-identical.

## Important collision rule

The tilesets never infer collision from decoration pixels. Keep collision in the level semantic layer (`metadata/semantic_tile_contract.json`), then let your Tiled/Godot importer select art separately via `metadata/semantic_asset_library.json`.

## Attribution and redistribution

This is a private development derivative, not a relicensed asset library. Keep each original archive and its licence terms with the project. In particular, do not publish the raw or derived 180 FX sheets as a downloadable asset pack; use them only as game content under the creator's terms. Re-check the upstream terms before commercial release.
""", encoding="utf-8", newline="\n")
    shutil.rmtree(work, ignore_errors=True)
    print(json.dumps({"output": str(output), "fx_spriteframes": len(fx_entries), "industrial_tiles": len(industrial_meta)}, indent=2))


if __name__ == "__main__":
    main()
