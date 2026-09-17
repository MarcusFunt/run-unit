"""Compatibility extensions installed into the public ``level_kit`` module.

The public module remains ``tools/level_kit.py``.  This file deliberately avoids
importing it, so the facade can pass its globals here without a circular import.
"""

from __future__ import annotations

from collections import Counter


def install_into(namespace: dict) -> None:
    """Install hardened behavior while preserving the existing public API."""
    if namespace.get("_LEVELKIT_EXTENSIONS_INSTALLED"):
        return
    namespace["_LEVELKIT_EXTENSIONS_INSTALLED"] = True

    original_check_structure = namespace["_check_structure"]
    semantic_layer = namespace["SEMANTIC_LAYER"]
    obstacle_layer = namespace["OBSTACLE_LAYER"]
    marker_layer = namespace["MARKER_LAYER"]
    spawn_marker = namespace["SPAWN_MARKER"]
    goal_marker = namespace["GOAL_MARKER"]
    flip_diagonal = namespace["FLIP_DIAGONAL"]

    def hardened_check_structure(level, report) -> None:
        original_check_structure(level, report)

        for layer in level.tile_layers():
            name = str(layer.get("name", ""))
            width = int(layer.get("width", 0))
            height = int(layer.get("height", 0))
            actual = len(layer.get("data", []))
            expected = width * height
            if actual != expected:
                report.errors.append(
                    "layer '%s' cell count is %d but %dx%d requires %d"
                    % (name, actual, width, height, expected)
                )

        markers = level.layer(marker_layer)
        if markers is not None and markers.get("type") == "objectgroup":
            counts = Counter(
                str(obj.get("name", ""))
                for obj in markers.get("objects", [])
                if str(obj.get("name", "")) in (spawn_marker, goal_marker)
            )
            for name in (spawn_marker, goal_marker):
                if counts[name] > 1:
                    report.errors.append(
                        "duplicate %s markers in '%s': expected at most one, found %d"
                        % (name, marker_layer, counts[name])
                    )

        for layer_name in (semantic_layer, obstacle_layer):
            layer = level.layer(layer_name)
            if layer is None or layer.get("type") != "tilelayer":
                continue
            for cell, raw_gid in enumerate(layer.get("data", [])):
                gid = int(raw_gid)
                if not gid or not (gid & flip_diagonal):
                    continue
                tile = level.index.tile_for(gid)
                if tile is None or not tile.rects:
                    continue
                width = max(int(layer.get("width", level.width)), 1)
                report.errors.append(
                    "layer '%s' x=%d y=%d: diagonal flip on collidable tile is unsupported by the Level Kit simulator"
                    % (layer_name, cell % width, cell // width)
                )

    namespace["_check_structure"] = hardened_check_structure
