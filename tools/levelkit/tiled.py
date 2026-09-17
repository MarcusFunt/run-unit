"""Lossless Tiled map merge helpers used by the public Level Kit facade."""

from __future__ import annotations

import copy


STRUCTURAL_KEYS = (
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
)


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


def _resize_grid(data: list[int], old_width: int, old_height: int, width: int, height: int) -> list[int]:
    """Resize a tile grid while preserving the overlapping top-left rectangle."""
    if old_width == width and old_height == height:
        return list(data)
    out = [0] * (width * height)
    for y in range(min(old_height, height)):
        for x in range(min(old_width, width)):
            source = y * old_width + x
            if source < len(data):
                out[y * width + x] = int(data[source])
    return out


def merge_unowned_tiled_content(
    original: dict,
    built: dict,
    owned_layer_names: set[str],
    width: int,
    height: int,
) -> dict:
    """Merge a route rebuild with the original map without dropping rich Tiled data.

    ``owned_layer_names`` are replaced by the rebuilt versions. Every other
    object layer and map-level field is preserved. Decorative tile layers keep
    their metadata and are resized non-destructively when the map dimensions
    change.
    """
    merged = copy.deepcopy(original)
    for key in STRUCTURAL_KEYS:
        if key in built:
            merged[key] = copy.deepcopy(built[key])

    old_width = int(original.get("width", width))
    old_height = int(original.get("height", height))
    same_size = old_width == width and old_height == height
    built_by_name = {str(layer.get("name", "")): layer for layer in built.get("layers", [])}

    merged_layers: list[dict] = []
    used: set[str] = set()
    for original_layer in original.get("layers", []):
        name = str(original_layer.get("name", ""))
        rebuilt = built_by_name.get(name)
        if name in owned_layer_names and rebuilt is not None:
            merged_layers.append(copy.deepcopy(rebuilt))
            used.add(name)
            continue

        if original_layer.get("type") == "tilelayer" and not same_size:
            preserved = copy.deepcopy(original_layer)
            preserved["data"] = _resize_grid(
                [int(value) for value in original_layer.get("data", [])],
                int(original_layer.get("width", old_width)),
                int(original_layer.get("height", old_height)),
                width,
                height,
            )
            preserved["width"] = width
            preserved["height"] = height
            merged_layers.append(preserved)
            used.add(name)
            continue

        # Unknown/custom layers are outside the route sketch's ownership.
        merged_layers.append(copy.deepcopy(original_layer))
        used.add(name)

    # Include any layers introduced by the route builder that did not exist in
    # the template, keeping the builder's deterministic ordering at the tail.
    for rebuilt in built.get("layers", []):
        name = str(rebuilt.get("name", ""))
        if name not in used:
            merged_layers.append(copy.deepcopy(rebuilt))
            used.add(name)

    merged["layers"] = merged_layers
    merged["nextlayerid"] = max([int(layer.get("id", 0)) for layer in merged_layers] + [0]) + 1
    merged["nextobjectid"] = _max_object_id(merged_layers) + 1
    return merged
