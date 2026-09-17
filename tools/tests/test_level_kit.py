import contextlib
import io
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
SHIPPED_LEVEL = PROJECT_ROOT / "assets" / "tiled" / "levels" / "maintenance_shaft.tmj"


def sketch_from_rows(rows: list[str], **directives: str) -> level_kit.Sketch:
    """Build a sketch object from bare grid rows, as a hand-written file would."""
    width = max(len(row) for row in rows)
    lines = ["@size %d %d" % (width, len(rows)), "@tile 32 32"]
    lines += ["@%s %s" % (name, value) for name, value in directives.items()]
    lines += ["%3d | %s" % (index, row.ljust(width, ".")) for index, row in enumerate(rows)]
    return level_kit.parse_sketch("\n".join(lines) + "\n")


def level_from_rows(rows: list[str], directory: Path) -> level_kit.LevelMap:
    out = directory / "level.tmj"
    level_kit.write_json(out, level_kit.build_map(sketch_from_rows(rows), out, None))
    return level_kit.LevelMap.load(out)


class SketchRoundTripTests(unittest.TestCase):
    def test_shipped_level_round_trips_byte_for_byte(self) -> None:
        level = level_kit.LevelMap.load(SHIPPED_LEVEL)
        sketch = level_kit.parse_sketch(level_kit.sketch_text(level))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "round_trip.tmj"
            # Build as if writing next to the original, so the relative tileset
            # paths this map declares are the ones under test.
            level_kit.write_json(out, level_kit.build_map(sketch, SHIPPED_LEVEL, level))
            self.assertEqual(
                out.read_bytes(),
                SHIPPED_LEVEL.read_bytes(),
                "sketch + build must leave an unedited level untouched",
            )

    def test_sketch_never_hides_geometry_behind_a_marker(self) -> None:
        level = level_kit.LevelMap.load(SHIPPED_LEVEL)
        text = level_kit.sketch_text(level)
        self.assertIn("@marker Spawn", text)
        self.assertIn("@marker Goal", text)

    def test_build_reports_a_row_that_is_too_wide(self) -> None:
        with self.assertRaises(level_kit.LevelKitError):
            level_kit.parse_sketch("@size 4 1\n@tile 32 32\n  0 | ######\n")

    def test_build_rejects_an_unknown_glyph(self) -> None:
        with self.assertRaises(level_kit.LevelKitError):
            level_kit.parse_sketch("@size 4 1\n@tile 32 32\n  0 | ##Z#\n")

    def test_new_level_builds_without_a_template(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            level = level_from_rows(["....", "....", "####"], Path(directory))
            self.assertEqual(level.width, 4)
            self.assertEqual(level.semantic_grid()[2][0], level_kit.SEMANTIC_SOLID)
            self.assertIsNotNone(level.layer(level_kit.MARKER_LAYER))


class SurfaceExtractionTests(unittest.TestCase):
    def test_buried_rows_do_not_become_extra_platforms(self) -> None:
        grid = [
            [0, 0, 0],
            [1, 1, 1],
            [1, 1, 1],
        ]
        self.assertEqual(level_kit.surface_runs(grid), [(1, 0, 2, level_kit.SEMANTIC_SOLID)])

    def test_a_gap_splits_one_row_into_two_runs(self) -> None:
        grid = [[0, 0, 0, 0], [1, 1, 0, 1]]
        self.assertEqual(
            level_kit.surface_runs(grid),
            [(1, 0, 1, level_kit.SEMANTIC_SOLID), (1, 3, 3, level_kit.SEMANTIC_SOLID)],
        )


class PhysicsSourceTests(unittest.TestCase):
    def test_constants_are_read_from_the_engine_source(self) -> None:
        physics = level_kit.PlayerPhysics.load()
        motor = (PROJECT_ROOT / "scripts" / "player" / "player_motor.gd").read_text(encoding="utf-8")
        self.assertIn("var jump_velocity: float = %g" % physics.jump_velocity, motor)
        self.assertIn("var max_run_speed: float = %g" % physics.max_run_speed, motor)
        self.assertGreater(physics.body_height, physics.crouch_collision_height)

    def test_a_stronger_charge_launches_harder(self) -> None:
        physics = level_kit.PlayerPhysics()
        self.assertLess(physics.launch_velocity(1.0), physics.launch_velocity(0.0))
        self.assertEqual(physics.launch_velocity(0.0), physics.min_jump_velocity)


class CheckTests(unittest.TestCase):
    def test_shipped_level_passes_and_reports_its_crouch_gate(self) -> None:
        report = level_kit.check_level(level_kit.LevelMap.load(SHIPPED_LEVEL))
        self.assertEqual(report.errors, [])
        self.assertTrue(any("crouch" in note for note in report.notes))
        self.assertTrue(any("route: Spawn -> Goal" in note for note in report.notes))

    def test_an_unjumpable_gap_fails_the_route(self) -> None:
        rows = [
            "." * 40,
            "." * 40,
            "...." + "S" + "." * 32 + "G" + "..",
            "." * 40,
            "#" * 9 + "." * 20 + "#" * 11,
            "#" * 9 + "." * 20 + "#" * 11,
        ]
        with tempfile.TemporaryDirectory() as directory:
            report = level_kit.check_level(level_from_rows(rows, Path(directory)))
        self.assertTrue(any("unreachable" in error for error in report.errors))

    def test_a_jumpable_gap_passes_the_route(self) -> None:
        rows = [
            "." * 40,
            "." * 40,
            "...." + "S" + "." * 32 + "G" + "..",
            "." * 40,
            "#" * 9 + "." * 5 + "#" * 26,
            "#" * 9 + "." * 5 + "#" * 26,
        ]
        with tempfile.TemporaryDirectory() as directory:
            report = level_kit.check_level(level_from_rows(rows, Path(directory)))
        self.assertEqual(report.errors, [])

    def test_a_gate_too_low_to_crouch_under_blocks_the_route(self) -> None:
        rows = [
            "." * 20,
            "...." + "S" + "." * 15,
            "." * 12 + "TTT" + "." * 3 + "G.",
            "#" * 20,
            "#" * 20,
        ]
        with tempfile.TemporaryDirectory() as directory:
            report = level_kit.check_level(level_from_rows(rows, Path(directory)))
        self.assertTrue(any("unreachable" in error for error in report.errors))

    def test_a_pit_with_no_way_out_is_reported_as_a_soft_lock(self) -> None:
        rows = [
            "." * 30,
            "...." + "S" + "." * 23 + "G.",
            "." * 30,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 9 + "." * 5 + "#" * 16,
            "#" * 30,
        ]
        with tempfile.TemporaryDirectory() as directory:
            report = level_kit.check_level(level_from_rows(rows, Path(directory)))
        self.assertEqual(report.errors, [])
        self.assertTrue(any("soft-lock" in warning for warning in report.warnings))

    def test_a_missing_spawn_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            report = level_kit.check_level(level_from_rows(["....", "####"], Path(directory)))
        self.assertTrue(any(level_kit.SPAWN_MARKER in error for error in report.errors))

    def test_decoration_on_the_semantic_layer_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decorated.tmj"
            data = json.loads(SHIPPED_LEVEL.read_text(encoding="utf-8"))
            for layer in data["layers"]:
                if layer.get("name") == level_kit.SEMANTIC_LAYER:
                    layer["data"][0] = 9  # an industrial-zone art tile
            level_kit.write_json(path, data)
            # The tileset paths are relative, so validate the copy in place.
            level = level_kit.LevelMap(
                path=SHIPPED_LEVEL, data=data, index=level_kit.TileIndex.load(SHIPPED_LEVEL, data["tilesets"])
            )
            report = level_kit.check_level(level)
        self.assertTrue(any("data_semantic" in error for error in report.errors))


class TilesetPathTests(unittest.TestCase):
    def test_building_elsewhere_re_points_the_tileset_paths(self) -> None:
        level = level_kit.LevelMap.load(SHIPPED_LEVEL)
        sketch = level_kit.parse_sketch(level_kit.sketch_text(level))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "elsewhere.tmj"
            level_kit.write_json(out, level_kit.build_map(sketch, out, level))
            rebuilt = level_kit.LevelMap.load(out)
        self.assertEqual(len(rebuilt.index.entries), len(level.index.entries))
        self.assertEqual(
            [entry.name for entry in rebuilt.index.entries],
            [entry.name for entry in level.index.entries],
            "a level built outside the template's folder must still resolve its tilesets",
        )


class AutoArtTests(unittest.TestCase):
    def test_autoart_reproduces_the_shipped_decoration(self) -> None:
        level = level_kit.LevelMap.load(SHIPPED_LEVEL)
        self.assertEqual(
            level_kit.autoart(level),
            [],
            "the shipped ArtDeck/TunnelShell layers should already match the geometry",
        )

    def test_autoart_caps_both_ends_of_a_platform(self) -> None:
        level = level_kit.LevelMap.load(SHIPPED_LEVEL)
        entry = level.index.entry_by_source(level_kit.DECK_TILESET)
        self.assertIsNotNone(entry)
        data = level_kit.deck_layer_data(level, entry.firstgid)
        row, x0, x1, _value = level_kit.surface_runs(level.semantic_grid())[0]
        self.assertEqual(data[row * level.width + x0], entry.firstgid + level_kit.DECK_CAP_LEFT)
        self.assertEqual(data[row * level.width + x1], entry.firstgid + level_kit.DECK_CAP_RIGHT)


class CommandLineTests(unittest.TestCase):
    def test_check_command_passes_on_the_shipped_level(self) -> None:
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            exit_code = level_kit.main(["check", str(SHIPPED_LEVEL), "--json"])
        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(captured.getvalue())["ok"])


if __name__ == "__main__":
    unittest.main()
