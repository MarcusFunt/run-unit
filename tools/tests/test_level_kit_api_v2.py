import copy
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import level_kit
from levelkit.analysis import best_route, move_difficulty

PROJECT_ROOT = level_kit.PROJECT_ROOT
TUTORIAL = PROJECT_ROOT / "assets" / "tiled" / "levels" / "maintenance_shaft.tmj"
LEVEL_1 = PROJECT_ROOT / "assets" / "tiled" / "levels" / "level_01_factory.tmj"


class UnifiedStampTests(unittest.TestCase):
    def setUp(self) -> None:
        self.level = level_kit.LevelMap.load(TUTORIAL)
        self.entry = self.level.index.entry_by_source("industrial_zone.tsj")
        self.assertIsNotNone(self.entry)

    def _blank_target(self):
        data = copy.deepcopy(self.level.data)
        deck = next(layer for layer in data["layers"] if layer.get("name") == "ArtDeck")
        deck["data"] = [0] * len(deck["data"])
        return level_kit.LevelMap(path=self.level.path, data=data, index=self.level.index)

    def test_public_capture_excludes_gameplay_by_default(self) -> None:
        stamp = level_kit.capture_stamp(self.level, (0, 13, 8, 3), "deck_piece")
        self.assertIn("ArtDeck", stamp["layers"])
        self.assertNotIn(level_kit.SEMANTIC_LAYER, stamp["layers"])
        self.assertNotIn(level_kit.OBSTACLE_LAYER, stamp["layers"])

    def test_public_capture_can_include_gameplay_explicitly(self) -> None:
        stamp = level_kit.capture_stamp(
            self.level,
            (0, 13, 8, 3),
            "gameplay_piece",
            include_gameplay=True,
        )
        self.assertIn(level_kit.SEMANTIC_LAYER, stamp["layers"])

    def test_flip_x_moves_cells_and_toggles_tile_flag(self) -> None:
        target = self._blank_target()
        stamp = {
            "version": 1,
            "name": "asymmetric",
            "width": 2,
            "height": 1,
            "layers": {
                "ArtDeck": [
                    {"tileset": Path(self.entry.source).name, "local_id": 54},
                    None,
                ]
            },
        }
        changed = level_kit.place_stamp(target, stamp, 10, 10, flip_x=True)
        self.assertEqual(changed, 1)
        cells = target.layer("ArtDeck")["data"]
        self.assertEqual(cells[10 * target.width + 10], 0)
        expected = (self.entry.firstgid + 54) | level_kit.FLIP_HORIZONTAL
        self.assertEqual(cells[10 * target.width + 11], expected)

    def test_flip_y_moves_cells_and_toggles_tile_flag(self) -> None:
        target = self._blank_target()
        stamp = {
            "version": 1,
            "name": "vertical",
            "width": 1,
            "height": 2,
            "layers": {
                "ArtDeck": [
                    {"tileset": Path(self.entry.source).name, "local_id": 54},
                    None,
                ]
            },
        }
        level_kit.place_stamp(target, stamp, 10, 10, flip_y=True)
        cells = target.layer("ArtDeck")["data"]
        expected = (self.entry.firstgid + 54) | level_kit.FLIP_VERTICAL
        self.assertEqual(cells[11 * target.width + 10], expected)

    def test_inspect_reports_portability_requirements(self) -> None:
        stamp = level_kit.capture_stamp(self.level, (0, 13, 8, 3), "deck_piece")
        info = level_kit.inspect_stamp(stamp)
        self.assertEqual(info["name"], "deck_piece")
        self.assertEqual(info["width"], 8)
        self.assertEqual(info["height"], 3)
        self.assertIn("ArtDeck", info["layers"])
        self.assertIn("industrial_zone.tsj", info["tilesets"])
        self.assertFalse(info["includes_gameplay"])

    def test_place_does_not_clear_existing_tiles_for_empty_stamp_cells(self) -> None:
        target = self._blank_target()
        deck = target.layer("ArtDeck")
        existing_gid = self.entry.firstgid + 54
        deck["data"][10 * target.width + 10] = existing_gid
        stamp = {
            "version": 1,
            "name": "empty",
            "width": 1,
            "height": 1,
            "layers": {"ArtDeck": [None]},
        }
        changed = level_kit.place_stamp(target, stamp, 10, 10)
        self.assertEqual(changed, 0)
        self.assertEqual(deck["data"][10 * target.width + 10], existing_gid)

    def test_batch_plan_applies_multiple_transformed_stamps(self) -> None:
        target = self._blank_target()
        stamp = {
            "version": 1,
            "name": "unit",
            "width": 1,
            "height": 1,
            "layers": {"ArtDeck": [{"tileset": Path(self.entry.source).name, "local_id": 54}]},
        }
        plan = {
            "placements": [
                {"stamp": "unit", "at": [3, 3]},
                {"stamp": "unit", "at": [5, 3], "flip_x": True},
            ]
        }
        changed = level_kit.apply_stamp_plan(target, plan, lambda _name: stamp)
        self.assertEqual(changed, 2)
        cells = target.layer("ArtDeck")["data"]
        self.assertEqual(cells[3 * target.width + 3], self.entry.firstgid + 54)
        self.assertEqual(cells[3 * target.width + 5], (self.entry.firstgid + 54) | level_kit.FLIP_HORIZONTAL)


class DifficultyAnalysisTests(unittest.TestCase):
    def test_best_route_prefers_two_comfortable_moves_over_one_near_perfect_move(self) -> None:
        edges = {
            0: [
                {"to": 3, "rating": "near_perfect", "charge": 1.0},
                {"to": 1, "rating": "comfortable", "charge": 0.5},
            ],
            1: [{"to": 3, "rating": "comfortable", "charge": 0.5}],
            2: [],
            3: [],
        }
        ledges = [SimpleNamespace(index=i) for i in range(4)]

        def classify(move, _ledge):
            return {
                "rating": move["rating"],
                "full_charge": move.get("charge") == 1.0,
            }

        route = best_route(0, {3}, edges, ledges, classify)
        self.assertEqual([move["to"] for move in route], [1, 3])

    def test_short_runup_is_not_classified_comfortable(self) -> None:
        move = {"from": 0, "to": 1, "charge": 0.75, "direction": 1}
        ledge = SimpleNamespace(index=0, width=1)
        physics = SimpleNamespace(body_width=50.0, max_run_speed=285.0, ground_acceleration=2200.0)
        level = SimpleNamespace(tilewidth=32)
        detail = move_difficulty(move, ledge, physics, level)
        self.assertEqual(detail["rating"], "near_perfect")

    def test_real_check_exposes_structured_difficulty_fields(self) -> None:
        report = level_kit.check_level(level_kit.LevelMap.load(TUTORIAL))
        self.assertTrue(report.ok, report.errors)
        for key in (
            "route_moves_detail",
            "difficulty",
            "route_length_m",
            "crouch_spans",
            "unreachable_ledges",
            "soft_locks",
        ):
            self.assertIn(key, report.summary)


class CheckAllTests(unittest.TestCase):
    def test_check_all_accepts_real_level_directory(self) -> None:
        stream = io.StringIO()
        with redirect_stdout(stream):
            code = level_kit.main(["check-all", "assets/tiled/levels", "--json"])
        payload = json.loads(stream.getvalue())
        self.assertEqual(code, 0, payload)
        self.assertTrue(payload["ok"])
        self.assertGreaterEqual(len(payload["levels"]), 1)

    def test_check_all_reports_invalid_map_without_crashing(self) -> None:
        source = json.loads(TUTORIAL.read_text(encoding="utf-8"))
        # The fixture is moved outside the repository, so preserve the original
        # tileset resolution with absolute source paths. The failure under test
        # must be the malformed grid, not a deliberately broken dependency.
        for declared in source.get("tilesets", []):
            relative = declared.get("source")
            if relative:
                declared["source"] = str((TUTORIAL.parent / relative).resolve())
        semantic = next(layer for layer in source["layers"] if layer.get("name") == level_kit.SEMANTIC_LAYER)
        semantic["data"] = semantic["data"][:-1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            invalid = root / "broken.tmj"
            invalid.write_text(json.dumps(source), encoding="utf-8")
            stream = io.StringIO()
            with redirect_stdout(stream):
                code = level_kit.main(["check-all", str(root), "--json"])
            payload = json.loads(stream.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertIn("cell count", " ".join(payload["levels"][0]["errors"]))


class PublicCliTests(unittest.TestCase):
    def test_parser_keeps_old_commands_and_adds_stamp_and_check_all(self) -> None:
        parser = level_kit.build_parser()
        subparsers = next(action for action in parser._actions if isinstance(action, __import__("argparse")._SubParsersAction))
        for command in ("new", "sketch", "build", "check", "autoart", "stamp", "check-all"):
            self.assertIn(command, subparsers.choices)

    def test_stamp_inspect_cli(self) -> None:
        stream = io.StringIO()
        with redirect_stdout(stream):
            code = level_kit.main(["stamp", "inspect", "platform_8x3", "--json"])
        payload = json.loads(stream.getvalue())
        self.assertEqual(code, 0)
        self.assertEqual(payload["name"], "platform_8x3")
        self.assertFalse(payload["includes_gameplay"])


if __name__ == "__main__":
    unittest.main()
