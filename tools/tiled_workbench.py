#!/usr/bin/env python3
"""Fast, lossless Tiled editing helpers for RUN//UNIT.

This is deliberately a small companion to ``level_kit.py`` rather than a
second level system.  ``level_kit`` remains responsible for semantic route
editing and reachability checks; this module adds two deadline-oriented pieces:

* ``build`` wraps level_kit's builder but preserves map metadata, custom object
  groups and decorative layer metadata that the route sketch does not own.
* ``stamp`` captures and places reusable multi-layer chunks.  Stamps store
  tileset-local ids instead of map-global gids, so they remain portable when a
  target map declares the same tilesets at different firstgid values.

Gameplay collision is intentionally excluded from stamps by default.  Pass
``--include-gameplay`` to capture Semantic/Obstacles on purpose.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

import level_kit

PROJECT_ROOT = level_kit.PROJECT_ROOT
STAMP_DIR = PROJECT_ROOT / "assets" / "tiled" / "stamps"
STAMP_VERSION = 1
GAMEPLAY_LAYERS = {level_kit.SEMANTIC_LAYER, level_kit.OBSTACLE_LAYER}
OWNED_BUILD_LAYERS = {level_kit.SEMANTIC_LAYER, level_kit.OBSTACLE_LAYER, level_kit.MARKER_LAYER}


class WorkbenchError(Exception):
    """User-facing error raised for invalid workbench input."""


def _resolve(value: str | Path) -> Path:
    path = Path(value)
    if path.is_absolute() or path.exists():
        return path
    return PROJECT_ROOT / path


def _deepcopy(value):
    return copy.deepcopy(value)


def _max_object_id(layers: list[dict]) -> int:
    return max(
        [
            int(obj.get("id", 0))
            for layer in layers
            if layer.get("type") == "objectgroup"
            for obj in layer.get("objects", [])
        ]
        + [0]
    )


def safe_build_map(sketch: level_kit.Sketch, out_path: Path, template: level_kit.LevelMap | None) -> dict:
    """Build through level_kit while preserving everything the sketch does not own.

    Semantic, Obstacles and Spawn/Goal are route-authoring concerns and come
    from ``level_kit.build_map``.  Existing custom object groups (StoryZones),
    decorative layer metadata, map properties and unknown future Tiled fields
    survive untouched whenever possible.
    """
    built = level_kit.build_map(sketch, out_path, template)
    if template is None:
        return built

    original = template.data
    merged = _deepcopy(original)

    # These fields genuinely belong to the rebuilt map rather than the template.
    for key in (
        "compressionlevel",
        "height",
        "infinite",
        "orientation",
        "renderorder",
        "tiledversion",
        "tileheight",
        "tilesets",
        "tilewidth",
        "type",
        "version",
        "width",
    ):
        if key in built:
            merged[key] = _deepcopy(built[key])

    built_by_name = {str(layer.get("name", "")): layer for layer in built.get("layers", [])}
    merged_layers: list[dict] = []
    used: set[str] = set()
    same_size = sketch.width == template.width and sketch.height == template.height

    for original_layer in original.get("layers", []):
        name = str(original_layer.get("name", ""))
        rebuilt_layer = built_by_name.get(name)
        if name in OWNED_BUILD_LAYERS and rebuilt_layer is not None:
            merged_layers.append(_deepcopy(rebuilt_layer))
            used.add(name)
            continue

        if original_layer.get("type") == "tilelayer" and rebuilt_layer is not None and not same_size:
            # level_kit already resized the cell data correctly.  Keep all Tiled
            # metadata from the original layer and replace only its grid payload.
            preserved = _deepcopy(original_layer)
            preserved["data"] = _deepcopy(rebuilt_layer.get("data", []))
            preserved["width"] = int(rebuilt_layer.get("width", sketch.width))
            preserved["height"] = int(rebuilt_layer.get("height", sketch.height))
            merged_layers.append(preserved)
            used.add(name)
            continue

        # Unknown object groups and decorative layers are outside the route
        # sketch's ownership.  Preserve them exactly.
        merged_layers.append(_deepcopy(original_layer))
        used.add(name)

    for rebuilt_layer in built.get("layers", []):
        name = str(rebuilt_layer.get("name", ""))
        if name not in used:
            merged_layers.append(_deepcopy(rebuilt_layer))
            used.add(name)

    merged["layers"] = merged_layers
    merged["nextlayerid"] = max([int(layer.get("id", 0)) for layer in merged_layers] + [0]) + 1
    merged["nextobjectid"] = _max_object_id(merged_layers) + 1
    return merged


def safe_build(sketch_path: Path, out_path: Path, template_path: Path | None = None, check: bool = False) -> int:
    sketch = level_kit.parse_sketch(sketch_path.read_text(encoding="utf-8"))
    selected_template = template_path
    if selected_template is None and sketch.template:
        selected_template = _resolve(sketch.template)
    template = level_kit.LevelMap.load(selected_template) if selected_template else None
    result = safe_build_map(sketch, out_path, template)
    level_kit.write_json(out_path, result)
    print("wrote %s" % out_path)
    if not check:
        return 0
    report = level_kit.check_level(level_kit.LevelMap.load(out_path))
    for note in report.notes:
        print("  NOTE %s" % note)
    for warning in report.warnings:
        print("  WARN %s" % warning)
    for error in report.errors:
        print("  ERROR %s" % error)
    print("  %s" % ("PASS" if report.ok else "FAIL (%d error(s))" % len(report.errors)))
    return 0 if report.ok else 1


def _tile_ref(level: level_kit.LevelMap, gid: int):
    if not gid:
        return None
    entry = level.index.entry_for(gid)
    if entry is None:
        raise WorkbenchError("tile id %d does not resolve to a declared tileset" % gid)
    raw = gid & level_kit.GID_MASK
    flags = gid & ~level_kit.GID_MASK
    tileset = Path(entry.source).name if entry.source else entry.name
    ref = {"tileset": tileset, "local_id": raw - entry.firstgid}
    if flags:
        ref["flags"] = flags
    return ref


def _entry_for_stamp_ref(level: level_kit.LevelMap, tileset: str):
    for entry in level.index.entries:
        if entry.source and Path(entry.source).name == tileset:
            return entry
        if entry.name == tileset:
            return entry
    return None


def _gid_from_ref(level: level_kit.LevelMap, ref: dict) -> int:
    tileset = str(ref.get("tileset", ""))
    entry = _entry_for_stamp_ref(level, tileset)
    if entry is None:
        raise WorkbenchError("target map has no tileset matching %r" % tileset)
    local_id = int(ref.get("local_id", -1))
    if local_id < 0 or local_id >= max(entry.tilecount, 1):
        raise WorkbenchError("stamp tile %s:%d is outside the target tileset" % (tileset, local_id))
    return (entry.firstgid + local_id) | int(ref.get("flags", 0))


def capture_stamp(
    level: level_kit.LevelMap,
    rect: tuple[int, int, int, int],
    name: str,
    include_gameplay: bool = False,
    layer_names: list[str] | None = None,
) -> dict:
    """Capture a rectangular collection of tile layers into a portable stamp."""
    x0, y0, width, height = rect
    if width <= 0 or height <= 0:
        raise WorkbenchError("stamp width and height must be positive")
    if x0 < 0 or y0 < 0 or x0 + width > level.width or y0 + height > level.height:
        raise WorkbenchError("stamp rectangle lies outside the map")

    selected = set(layer_names) if layer_names else None
    layers: dict[str, list] = {}
    for layer in level.tile_layers():
        layer_name = str(layer.get("name", ""))
        if selected is not None and layer_name not in selected:
            continue
        if not include_gameplay and layer_name in GAMEPLAY_LAYERS:
            continue
        source_data = [int(gid) for gid in layer.get("data", [])]
        cells: list = []
        any_tile = False
        for dy in range(height):
            for dx in range(width):
                gid = source_data[(y0 + dy) * level.width + x0 + dx]
                ref = _tile_ref(level, gid)
                cells.append(ref)
                any_tile = any_tile or ref is not None
        if any_tile:
            layers[layer_name] = cells

    return {
        "version": STAMP_VERSION,
        "name": name,
        "width": width,
        "height": height,
        "layers": layers,
        "source": str(level.path),
    }


def _blank_tile_layer(level: level_kit.LevelMap, name: str) -> dict:
    next_id = max([int(layer.get("id", 0)) for layer in level.data.get("layers", [])] + [0]) + 1
    return {
        "data": [0] * (level.width * level.height),
        "height": level.height,
        "id": next_id,
        "name": name,
        "opacity": 1.0,
        "type": "tilelayer",
        "visible": True,
        "width": level.width,
        "x": 0,
        "y": 0,
    }


def place_stamp(level: level_kit.LevelMap, stamp: dict, x0: int, y0: int) -> int:
    """Overlay non-empty stamp cells on ``level`` and return changed cell count."""
    if int(stamp.get("version", 0)) != STAMP_VERSION:
        raise WorkbenchError("unsupported stamp version %r" % stamp.get("version"))
    width = int(stamp.get("width", 0))
    height = int(stamp.get("height", 0))
    if width <= 0 or height <= 0:
        raise WorkbenchError("stamp has invalid dimensions")
    if x0 < 0 or y0 < 0 or x0 + width > level.width or y0 + height > level.height:
        raise WorkbenchError("stamp placement lies outside the map")

    changed = 0
    for layer_name, cells in stamp.get("layers", {}).items():
        if len(cells) != width * height:
            raise WorkbenchError("stamp layer %r has the wrong cell count" % layer_name)
        target = level.layer(layer_name)
        if target is None:
            target = _blank_tile_layer(level, layer_name)
            level.data.setdefault("layers", []).append(target)
            level.data["nextlayerid"] = max(int(level.data.get("nextlayerid", 1)), int(target["id"]) + 1)
        if target.get("type") != "tilelayer":
            raise WorkbenchError("target layer %r is not a tile layer" % layer_name)
        data = target.setdefault("data", [0] * (level.width * level.height))
        for dy in range(height):
            for dx in range(width):
                ref = cells[dy * width + dx]
                if ref is None:
                    continue  # Empty stamp cells never erase authored art.
                target_index = (y0 + dy) * level.width + x0 + dx
                gid = _gid_from_ref(level, ref)
                if int(data[target_index]) != gid:
                    data[target_index] = gid
                    changed += 1
    return changed


def write_stamp(path: Path, stamp: dict) -> None:
    level_kit.write_json(path, stamp)


def read_stamp(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise WorkbenchError("missing stamp: %s" % path) from error
    except json.JSONDecodeError as error:
        raise WorkbenchError("invalid stamp JSON: %s" % error) from error
    if not isinstance(value, dict):
        raise WorkbenchError("stamp root must be a JSON object")
    return value


def resolve_stamp(value: str, stamp_dir: Path) -> Path:
    path = Path(value)
    if path.is_file():
        return path
    candidate = stamp_dir / (value if value.endswith(".json") else value + ".json")
    if candidate.is_file():
        return candidate
    raise WorkbenchError("unknown stamp %r in %s" % (value, stamp_dir))


def _parse_rect(value: str) -> tuple[int, int, int, int]:
    try:
        values = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected x,y,width,height") from error
    if len(values) != 4:
        raise argparse.ArgumentTypeError("expected x,y,width,height")
    return values


def _parse_point(value: str) -> tuple[int, int]:
    try:
        values = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected x,y") from error
    if len(values) != 2:
        raise argparse.ArgumentTypeError("expected x,y")
    return values


def command_build(args: argparse.Namespace) -> int:
    return safe_build(
        _resolve(args.sketch),
        _resolve(args.out),
        _resolve(args.template) if args.template else None,
        args.check,
    )


def command_stamp_capture(args: argparse.Namespace) -> int:
    level = level_kit.LevelMap.load(_resolve(args.level))
    stamp = capture_stamp(
        level,
        args.rect,
        args.name,
        include_gameplay=args.include_gameplay,
        layer_names=args.layers.split(",") if args.layers else None,
    )
    stamp_dir = _resolve(args.stamp_dir)
    out = _resolve(args.out) if args.out else stamp_dir / (args.name + ".json")
    write_stamp(out, stamp)
    print("captured %s (%dx%d, %d layers) -> %s" % (args.name, stamp["width"], stamp["height"], len(stamp["layers"]), out))
    return 0


def command_stamp_list(args: argparse.Namespace) -> int:
    stamp_dir = _resolve(args.stamp_dir)
    if not stamp_dir.exists():
        return 0
    for path in sorted(stamp_dir.glob("*.json")):
        stamp = read_stamp(path)
        print("%-24s %dx%d  %s" % (stamp.get("name", path.stem), stamp.get("width", 0), stamp.get("height", 0), ", ".join(stamp.get("layers", {}).keys())))
    return 0


def command_stamp_place(args: argparse.Namespace) -> int:
    level_path = _resolve(args.level)
    level = level_kit.LevelMap.load(level_path)
    stamp = read_stamp(resolve_stamp(args.stamp, _resolve(args.stamp_dir)))
    changed = place_stamp(level, stamp, args.at[0], args.at[1])
    out = _resolve(args.out) if args.out else level_path
    level_kit.write_json(out, level.data)
    print("placed %s at %d,%d (%d cells changed) -> %s" % (stamp.get("name", args.stamp), args.at[0], args.at[1], changed, out))
    if args.check:
        report = level_kit.check_level(level_kit.LevelMap.load(out))
        for error in report.errors:
            print("  ERROR %s" % error)
        print("  %s" % ("PASS" if report.ok else "FAIL"))
        return 0 if report.ok else 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tiled_workbench", description="Lossless builds and reusable multi-layer stamps for RUN//UNIT Tiled maps.")
    commands = parser.add_subparsers(dest="command", required=True)

    build = commands.add_parser("build", help="losslessly rebuild a level_kit sketch")
    build.add_argument("sketch")
    build.add_argument("--out", required=True)
    build.add_argument("--template")
    build.add_argument("--check", action="store_true")
    build.set_defaults(func=command_build)

    stamp = commands.add_parser("stamp", help="capture, list or place reusable Tiled chunks")
    stamp_commands = stamp.add_subparsers(dest="stamp_command", required=True)

    capture = stamp_commands.add_parser("capture", help="capture tile layers from a map rectangle")
    capture.add_argument("level")
    capture.add_argument("--rect", required=True, type=_parse_rect, help="x,y,width,height in tile cells")
    capture.add_argument("--name", required=True)
    capture.add_argument("--layers", help="comma-separated layer names; defaults to every decorative tile layer")
    capture.add_argument("--include-gameplay", action="store_true", help="also capture Semantic/Obstacles collision")
    capture.add_argument("--stamp-dir", default=str(STAMP_DIR))
    capture.add_argument("--out")
    capture.set_defaults(func=command_stamp_capture)

    list_parser = stamp_commands.add_parser("list", help="list saved stamps")
    list_parser.add_argument("--stamp-dir", default=str(STAMP_DIR))
    list_parser.set_defaults(func=command_stamp_list)

    place = stamp_commands.add_parser("place", help="overlay a saved stamp on a Tiled map")
    place.add_argument("stamp")
    place.add_argument("level")
    place.add_argument("--at", required=True, type=_parse_point, help="x,y destination in tile cells")
    place.add_argument("--stamp-dir", default=str(STAMP_DIR))
    place.add_argument("--out")
    place.add_argument("--check", action="store_true")
    place.set_defaults(func=command_stamp_place)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except (WorkbenchError, level_kit.LevelKitError) as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
