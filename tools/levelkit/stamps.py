"""Portable multi-layer Tiled stamps for Level Kit.

This module deliberately has no dependency on ``level_kit`` so it can be
installed into the public facade without circular imports when the CLI is run as
``python tools/level_kit.py``.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Callable

STAMP_VERSION = 1


class StampError(Exception):
    """Raised for malformed stamps or invalid placements."""


def _tile_ref(level, gid: int, gid_mask: int):
    if not gid:
        return None
    entry = level.index.entry_for(gid)
    if entry is None:
        raise StampError("tile id %d does not resolve to a declared tileset" % gid)
    raw = gid & gid_mask
    flags = gid & ~gid_mask
    tileset = Path(entry.source).name if entry.source else entry.name
    ref = {"tileset": tileset, "local_id": raw - entry.firstgid}
    if flags:
        ref["flags"] = flags
    return ref


def _entry_for_stamp_ref(level, tileset: str):
    for entry in level.index.entries:
        if entry.source and Path(entry.source).name == tileset:
            return entry
        if entry.name == tileset:
            return entry
    return None


def _gid_from_ref(level, ref: dict, flip_x: bool, flip_y: bool, flip_horizontal: int, flip_vertical: int) -> int:
    tileset = str(ref.get("tileset", ""))
    entry = _entry_for_stamp_ref(level, tileset)
    if entry is None:
        raise StampError("target map has no tileset matching %r" % tileset)
    local_id = int(ref.get("local_id", -1))
    if local_id < 0 or local_id >= max(entry.tilecount, 1):
        raise StampError("stamp tile %s:%d is outside the target tileset" % (tileset, local_id))
    flags = int(ref.get("flags", 0))
    # A stamp reflection composes another horizontal/vertical reflection with
    # the tile's authored transform. XOR is the correct composition for the
    # non-diagonal transforms used by RUN//UNIT art; diagonal is preserved.
    if flip_x:
        flags ^= flip_horizontal
    if flip_y:
        flags ^= flip_vertical
    return (entry.firstgid + local_id) | flags


def capture_stamp(
    level,
    rect: tuple[int, int, int, int],
    name: str,
    *,
    gid_mask: int,
    gameplay_layers: set[str],
    include_gameplay: bool = False,
    layer_names: list[str] | None = None,
) -> dict:
    """Capture a rectangular collection of tile layers into a portable stamp."""
    x0, y0, width, height = rect
    if width <= 0 or height <= 0:
        raise StampError("stamp width and height must be positive")
    if x0 < 0 or y0 < 0 or x0 + width > level.width or y0 + height > level.height:
        raise StampError("stamp rectangle lies outside the map")

    selected = set(layer_names) if layer_names else None
    layers: dict[str, list] = {}
    for layer in level.tile_layers():
        layer_name = str(layer.get("name", ""))
        if selected is not None and layer_name not in selected:
            continue
        if not include_gameplay and layer_name in gameplay_layers:
            continue
        source_data = [int(gid) for gid in layer.get("data", [])]
        if len(source_data) != level.width * level.height:
            raise StampError("layer %r has the wrong cell count" % layer_name)
        cells: list = []
        any_tile = False
        for dy in range(height):
            for dx in range(width):
                ref = _tile_ref(level, source_data[(y0 + dy) * level.width + x0 + dx], gid_mask)
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


def _blank_tile_layer(level, name: str) -> dict:
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


def place_stamp(
    level,
    stamp: dict,
    x0: int,
    y0: int,
    *,
    flip_x: bool = False,
    flip_y: bool = False,
    flip_horizontal: int,
    flip_vertical: int,
) -> int:
    """Overlay non-empty stamp cells on ``level`` and return changed cell count."""
    if int(stamp.get("version", 0)) != STAMP_VERSION:
        raise StampError("unsupported stamp version %r" % stamp.get("version"))
    width = int(stamp.get("width", 0))
    height = int(stamp.get("height", 0))
    if width <= 0 or height <= 0:
        raise StampError("stamp has invalid dimensions")
    if x0 < 0 or y0 < 0 or x0 + width > level.width or y0 + height > level.height:
        raise StampError("stamp placement lies outside the map")

    changed = 0
    for layer_name, cells in stamp.get("layers", {}).items():
        if len(cells) != width * height:
            raise StampError("stamp layer %r has the wrong cell count" % layer_name)
        target = level.layer(layer_name)
        if target is None:
            target = _blank_tile_layer(level, layer_name)
            level.data.setdefault("layers", []).append(target)
            level.data["nextlayerid"] = max(int(level.data.get("nextlayerid", 1)), int(target["id"]) + 1)
        if target.get("type") != "tilelayer":
            raise StampError("target layer %r is not a tile layer" % layer_name)
        data = target.setdefault("data", [0] * (level.width * level.height))
        if len(data) != level.width * level.height:
            raise StampError("target layer %r has the wrong cell count" % layer_name)
        for source_y in range(height):
            for source_x in range(width):
                ref = cells[source_y * width + source_x]
                if ref is None:
                    continue  # Empty stamp cells never erase authored art.
                dest_x = width - 1 - source_x if flip_x else source_x
                dest_y = height - 1 - source_y if flip_y else source_y
                target_index = (y0 + dest_y) * level.width + x0 + dest_x
                gid = _gid_from_ref(level, ref, flip_x, flip_y, flip_horizontal, flip_vertical)
                if int(data[target_index]) != gid:
                    data[target_index] = gid
                    changed += 1
    return changed


def inspect_stamp(stamp: dict, gameplay_layers: set[str]) -> dict:
    width = int(stamp.get("width", 0))
    height = int(stamp.get("height", 0))
    layers = stamp.get("layers", {})
    tilesets = sorted(
        {
            str(ref.get("tileset", ""))
            for cells in layers.values()
            for ref in cells
            if isinstance(ref, dict) and ref.get("tileset")
        }
    )
    return {
        "name": str(stamp.get("name", "")),
        "version": int(stamp.get("version", 0)),
        "width": width,
        "height": height,
        "layers": sorted(str(name) for name in layers),
        "tilesets": tilesets,
        "source": stamp.get("source"),
        "includes_gameplay": bool(set(layers) & gameplay_layers),
    }


def apply_stamp_plan(
    level,
    plan: dict,
    stamp_loader: Callable[[str], dict],
    *,
    flip_horizontal: int,
    flip_vertical: int,
) -> int:
    """Apply a deterministic list of stamp placements and return changed cells."""
    placements = plan.get("placements", [])
    if not isinstance(placements, list):
        raise StampError("stamp plan 'placements' must be a list")
    changed = 0
    for index, placement in enumerate(placements):
        if not isinstance(placement, dict):
            raise StampError("stamp plan placement %d must be an object" % index)
        name = str(placement.get("stamp", ""))
        at = placement.get("at")
        if not name or not isinstance(at, list) or len(at) != 2:
            raise StampError("stamp plan placement %d needs 'stamp' and at:[x,y]" % index)
        stamp = stamp_loader(name)
        changed += place_stamp(
            level,
            stamp,
            int(at[0]),
            int(at[1]),
            flip_x=bool(placement.get("flip_x", False)),
            flip_y=bool(placement.get("flip_y", False)),
            flip_horizontal=flip_horizontal,
            flip_vertical=flip_vertical,
        )
    return changed


def read_stamp(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise StampError("missing stamp: %s" % path) from error
    except json.JSONDecodeError as error:
        raise StampError("invalid stamp JSON: %s" % error) from error
    if not isinstance(value, dict):
        raise StampError("stamp root must be a JSON object")
    return value


def resolve_stamp(value: str, stamp_dir: Path) -> Path:
    path = Path(value)
    if path.is_file():
        return path
    candidate = stamp_dir / (value if value.endswith(".json") else value + ".json")
    if candidate.is_file():
        return candidate
    raise StampError("unknown stamp %r in %s" % (value, stamp_dir))
