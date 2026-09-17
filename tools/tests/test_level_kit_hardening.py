import copy
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import level_kit

PROJECT_ROOT = level_kit.PROJECT_ROOT
SHIPPED_LEVEL = PROJECT_ROOT / "assets" / "tiled" / "levels" / "maintenance_shaft.tmj"


def cloned_level() -> level_kit.LevelMap:
    source = level_kit.LevelMap.load(SHIPPED_LEVEL)
    data = copy.deepcopy(source.data)
    return level_kit.LevelMap(path=source.path, data=data, index=source.index)


class StructureHardeningTests(unittest.TestCase):
    def test_check_reports_wrong_tile_layer_cell_count_instead_of_crashing(self) -> None:
        level = cloned_level()
        semantic = level.layer(level_kit.SEMANTIC_LAYER)
        self.assertIsNotNone(semantic)
        semantic["data"].pop()

        report = level_kit.check_level(level)

        self.assertFalse(report.ok)
        self.assertTrue(any("cell count" in error for error in report.errors), report.errors)

    def test_duplicate_spawn_marker_is_a_contract_error(self) -> None:
        level = cloned_level()
        markers = level.layer(level_kit.MARKER_LAYER)
        self.assertIsNotNone(markers)
        spawn = next(obj for obj in markers["objects"] if obj.get("name") == level_kit.SPAWN_MARKER)
        duplicate = copy.deepcopy(spawn)
        duplicate["id"] = max(int(obj.get("id", 0)) for obj in markers["objects"]) + 1
        duplicate["x"] = float(duplicate.get("x", 0.0)) + 32.0
        markers["objects"].append(duplicate)

        report = level_kit.check_level(level)

        self.assertFalse(report.ok)
        self.assertTrue(any("duplicate" in error.lower() and "Spawn" in error for error in report.errors), report.errors)

    def test_duplicate_goal_marker_is_a_contract_error(self) -> None:
        level = cloned_level()
        markers = level.layer(level_kit.MARKER_LAYER)
        self.assertIsNotNone(markers)
        goal = next(obj for obj in markers["objects"] if obj.get("name") == level_kit.GOAL_MARKER)
        duplicate = copy.deepcopy(goal)
        duplicate["id"] = max(int(obj.get("id", 0)) for obj in markers["objects"]) + 1
        duplicate["x"] = float(duplicate.get("x", 0.0)) - 32.0
        markers["objects"].append(duplicate)

        report = level_kit.check_level(level)

        self.assertFalse(report.ok)
        self.assertTrue(any("duplicate" in error.lower() and "Goal" in error for error in report.errors), report.errors)

    def test_diagonal_flip_on_collidable_tile_is_rejected(self) -> None:
        level = cloned_level()
        semantic = level.layer(level_kit.SEMANTIC_LAYER)
        self.assertIsNotNone(semantic)
        index = next(i for i, gid in enumerate(semantic["data"]) if gid)
        semantic["data"][index] = int(semantic["data"][index]) | level_kit.FLIP_DIAGONAL

        report = level_kit.check_level(level)

        self.assertFalse(report.ok)
        self.assertTrue(any("diagonal" in error.lower() for error in report.errors), report.errors)


if __name__ == "__main__":
    unittest.main()
