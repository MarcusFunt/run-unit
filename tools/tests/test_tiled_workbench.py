import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import level_kit
import tiled_workbench

PROJECT_ROOT = level_kit.PROJECT_ROOT
LEVEL_1 = PROJECT_ROOT / "assets" / "tiled" / "levels" / "level_01_factory.tmj"
TUTORIAL = PROJECT_ROOT / "assets" / "tiled" / "levels" / "maintenance_shaft.tmj"


class LosslessBuildTests(unittest.TestCase):
    def test_safe_build_preserves_unowned_object_layers_and_map_properties(self) -> None:
        template = level_kit.LevelMap.load(LEVEL_1)
        sketch = level_kit.parse_sketch(level_kit.sketch_text(template))

        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "level_01_factory.tmj"
            rebuilt = tiled_workbench.safe_build_map(sketch, out, template)

        original_layers = {layer.get("name"): layer for layer in template.data["layers"]}
        rebuilt_layers = {layer.get("name"): layer for layer in rebuilt["layers"]}
        self.assertIn("StoryZones", rebuilt_layers)
        self.assertEqual(rebuilt_layers["StoryZones"], original_layers["StoryZones"])
        self.assertEqual(rebuilt_layers["ArtForeground"], original_layers["ArtForeground"])
        self.assertEqual(rebuilt.get("properties"), template.data.get("properties"))

    def test_safe_build_keeps_story_zone_ids_in_nextobjectid_budget(self) -> None:
        template = level_kit.LevelMap.load(LEVEL_1)
        sketch = level_kit.parse_sketch(level_kit.sketch_text(template))
        rebuilt = tiled_workbench.safe_build_map(sketch, LEVEL_1, template)
        object_ids = [
            int(obj.get("id", 0))
            for layer in rebuilt["layers"]
            if layer.get("type") == "objectgroup"
            for obj in layer.get("objects", [])
        ]
        self.assertGreater(rebuilt["nextobjectid"], max(object_ids))


class StampTests(unittest.TestCase):
    def test_capture_excludes_gameplay_layers_by_default(self) -> None:
        level = level_kit.LevelMap.load(TUTORIAL)
        stamp = tiled_workbench.capture_stamp(level, (0, 13, 8, 3), "deck_piece")
        self.assertIn("ArtDeck", stamp["layers"])
        self.assertNotIn(level_kit.SEMANTIC_LAYER, stamp["layers"])
        self.assertNotIn(level_kit.OBSTACLE_LAYER, stamp["layers"])

    def test_capture_can_include_gameplay_explicitly(self) -> None:
        level = level_kit.LevelMap.load(TUTORIAL)
        stamp = tiled_workbench.capture_stamp(level, (0, 13, 8, 3), "gameplay_piece", include_gameplay=True)
        self.assertIn(level_kit.SEMANTIC_LAYER, stamp["layers"])

    def test_place_uses_tileset_local_ids_not_source_global_gids(self) -> None:
        source = level_kit.LevelMap.load(TUTORIAL)
        stamp = tiled_workbench.capture_stamp(source, (0, 13, 8, 3), "deck_piece")

        target_data = copy.deepcopy(source.data)
        deck = next(layer for layer in target_data["layers"] if layer.get("name") == "ArtDeck")
        for y in range(13, 16):
            for x in range(20, 28):
                deck["data"][y * source.width + x] = 0
        target = level_kit.LevelMap(path=source.path, data=target_data, index=source.index)

        changed = tiled_workbench.place_stamp(target, stamp, 20, 13)
        self.assertGreater(changed, 0)
        placed = target.layer("ArtDeck")["data"]
        original = source.layer("ArtDeck")["data"]
        for dy in range(3):
            for dx in range(8):
                self.assertEqual(
                    placed[(13 + dy) * source.width + 20 + dx],
                    original[(13 + dy) * source.width + dx],
                )

    def test_place_does_not_clear_existing_tiles_for_empty_stamp_cells(self) -> None:
        level = level_kit.LevelMap.load(TUTORIAL)
        stamp = tiled_workbench.capture_stamp(level, (0, 0, 2, 2), "mostly_empty")
        target_data = copy.deepcopy(level.data)
        deck = next(layer for layer in target_data["layers"] if layer.get("name") == "ArtDeck")
        existing_gid = next(gid for gid in deck["data"] if gid)
        deck["data"][10 * level.width + 10] = existing_gid
        target = level_kit.LevelMap(path=level.path, data=target_data, index=level.index)
        tiled_workbench.place_stamp(target, stamp, 10, 10)
        self.assertEqual(target.layer("ArtDeck")["data"][10 * level.width + 10], existing_gid)


if __name__ == "__main__":
    unittest.main()
