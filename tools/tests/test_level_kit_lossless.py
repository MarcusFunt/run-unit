import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import level_kit

PROJECT_ROOT = level_kit.PROJECT_ROOT
LEVEL_1 = PROJECT_ROOT / "assets" / "tiled" / "levels" / "level_01_factory.tmj"


class LosslessPublicBuildTests(unittest.TestCase):
    def test_public_build_preserves_factory_story_zones_foreground_and_properties(self) -> None:
        original = level_kit.LevelMap.load(LEVEL_1)
        original_layers = {layer.get("name"): layer for layer in original.data["layers"]}

        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            sketch_path = directory / "factory.sketch"
            out_path = directory / "factory.tmj"
            sketch_path.write_text(level_kit.sketch_text(original), encoding="utf-8")

            exit_code = level_kit.main(["build", str(sketch_path), "--out", str(out_path)])
            self.assertEqual(exit_code, 0)
            rebuilt = json.loads(out_path.read_text(encoding="utf-8"))

        rebuilt_layers = {layer.get("name"): layer for layer in rebuilt["layers"]}
        self.assertIn("StoryZones", rebuilt_layers)
        self.assertEqual(rebuilt_layers["StoryZones"], original_layers["StoryZones"])
        self.assertEqual(rebuilt_layers["ArtForeground"], original_layers["ArtForeground"])
        self.assertEqual(rebuilt.get("properties"), original.data.get("properties"))
        object_ids = [
            int(obj.get("id", 0))
            for layer in rebuilt["layers"]
            if layer.get("type") == "objectgroup"
            for obj in layer.get("objects", [])
        ]
        self.assertGreater(rebuilt["nextobjectid"], max(object_ids))


if __name__ == "__main__":
    unittest.main()
