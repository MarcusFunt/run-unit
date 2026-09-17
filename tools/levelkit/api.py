"""Compatibility extensions installed into the public ``level_kit`` module.

``tools/level_kit.py`` remains the stable public module/CLI.  The facade passes
its globals here so new implementation can stay modular without circular
imports or breaking existing ``import level_kit`` callers.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
from collections import Counter
from pathlib import Path

from .analysis import best_route, difficulty_summary, move_difficulty, route_length_m
from .stamps import StampError, apply_stamp_plan, capture_stamp, inspect_stamp, place_stamp, read_stamp, resolve_stamp
from .tiled import merge_unowned_tiled_content


def _parse_rect(value: str) -> tuple[int, int, int, int]:
    try:
        values = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected x,y,width,height") from error
    if len(values) != 4:
        raise argparse.ArgumentTypeError("expected x,y,width,height")
    return values  # type: ignore[return-value]


def _parse_point(value: str) -> tuple[int, int]:
    try:
        values = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected x,y") from error
    if len(values) != 2:
        raise argparse.ArgumentTypeError("expected x,y")
    return values  # type: ignore[return-value]


def _subparsers(parser: argparse.ArgumentParser) -> argparse._SubParsersAction:
    for action in parser._actions:
        if isinstance(action, argparse._SubParsersAction):
            return action
    raise RuntimeError("Level Kit parser has no subparser action")


def install_into(namespace: dict) -> None:
    if namespace.get("_LEVELKIT_EXTENSIONS_INSTALLED"):
        return
    namespace["_LEVELKIT_EXTENSIONS_INSTALLED"] = True

    original_check_structure = namespace["_check_structure"]
    original_check_level = namespace["check_level"]
    original_build_parser = namespace["build_parser"]
    original_build_map = namespace["build_map"]

    semantic_layer = namespace["SEMANTIC_LAYER"]
    obstacle_layer = namespace["OBSTACLE_LAYER"]
    marker_layer = namespace["MARKER_LAYER"]
    spawn_marker = namespace["SPAWN_MARKER"]
    goal_marker = namespace["GOAL_MARKER"]
    flip_diagonal = namespace["FLIP_DIAGONAL"]
    flip_horizontal = namespace["FLIP_HORIZONTAL"]
    flip_vertical = namespace["FLIP_VERTICAL"]
    gid_mask = namespace["GID_MASK"]
    level_error = namespace["LevelKitError"]
    project_root: Path = namespace["PROJECT_ROOT"]
    stamp_dir = project_root / "assets" / "tiled" / "stamps"
    gameplay_layers = {semantic_layer, obstacle_layer}
    owned_build_layers = {semantic_layer, obstacle_layer, marker_layer}

    # ------------------------------------------------------------------
    # Structural hardening
    # ------------------------------------------------------------------

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
            width = max(int(layer.get("width", level.width)), 1)
            for cell, raw_gid in enumerate(layer.get("data", [])):
                gid = int(raw_gid)
                if not gid or not (gid & flip_diagonal):
                    continue
                tile = level.index.tile_for(gid)
                if tile is not None and tile.rects:
                    report.errors.append(
                        "layer '%s' x=%d y=%d: diagonal flip on collidable tile is unsupported by the Level Kit simulator"
                        % (layer_name, cell % width, cell // width)
                    )

    namespace["_check_structure"] = hardened_check_structure

    # ------------------------------------------------------------------
    # Lossless route rebuilds
    # ------------------------------------------------------------------

    def safe_build_map(sketch, out_path: Path, template):
        built = original_build_map(sketch, out_path, template)
        if template is None:
            return built
        return merge_unowned_tiled_content(
            template.data,
            built,
            owned_build_layers,
            int(sketch.width),
            int(sketch.height),
        )

    def command_build(args: argparse.Namespace) -> int:
        source = namespace["_resolve"](args.sketch)
        sketch = namespace["parse_sketch"](source.read_text(encoding="utf-8"))
        out = namespace["_resolve"](args.out)
        template_path = args.template or sketch.template
        template = namespace["LevelMap"].load(namespace["_resolve"](template_path)) if template_path else None
        namespace["write_json"](out, safe_build_map(sketch, out, template))
        print("wrote %s (%dx%d cells)" % (namespace["_relative_to_project"](out), sketch.width, sketch.height))
        if args.check:
            return namespace["command_check"](argparse.Namespace(level=str(out), json=False, quiet=False, margin=0.1))
        return 0

    namespace["safe_build_map"] = safe_build_map
    namespace["command_build"] = command_build

    # ------------------------------------------------------------------
    # Difficulty-aware route analysis
    # ------------------------------------------------------------------

    def _ground_acceleration() -> float:
        value = 2200.0
        motor = project_root / "scripts" / "player" / "player_motor.gd"
        if motor.is_file():
            match = re.search(
                r"var\s+ground_acceleration\s*:\s*float\s*=\s*(-?[0-9.]+)",
                motor.read_text(encoding="utf-8"),
            )
            if match:
                value = float(match.group(1))
        return value

    def _clean_physics(physics):
        """Return a PlayerPhysics containing only dataclass fields.

        The legacy checker clones instances through ``PlayerPhysics(**__dict__)``;
        keeping analysis-only metadata off that object preserves compatibility.
        """
        cls = namespace["PlayerPhysics"]
        return cls(**{name: getattr(physics, name) for name in cls.__dataclass_fields__})

    def enhanced_check_level(level, physics=None, margin: float = 0.1):
        core_physics = _clean_physics(physics or namespace["PlayerPhysics"].load())
        report = original_check_level(level, core_physics, margin)
        if not report.summary.get("checked") or report.errors:
            report.summary.setdefault("route_moves_detail", [])
            report.summary.setdefault("difficulty", difficulty_summary([]))
            return report

        actual_physics = copy.copy(core_physics)
        setattr(actual_physics, "ground_acceleration", _ground_acceleration())
        world = namespace["CollisionWorld"](namespace["collision_rects"](level), level.tilewidth)
        ledges = namespace["build_ledges"](level, world, actual_physics)
        if not ledges:
            return report
        graph = namespace["RouteGraph"](level, world, actual_physics, ledges)
        markers = level.markers()
        spawn = markers.get(spawn_marker)
        goal = markers.get(goal_marker)
        if spawn is None or goal is None:
            return report
        spawn_ledge = graph.drop_onto(*spawn)
        if spawn_ledge is None:
            return report

        edges = graph.edges()
        reachable = graph.reachable_from(spawn_ledge.index, edges)
        half = actual_physics.body_width / 2.0
        trigger_size = namespace["COMPLETION_TRIGGER_SIZE"]
        trigger_x0 = goal[0] - trigger_size[0] / 2.0
        trigger_x1 = goal[0] + trigger_size[0] / 2.0
        trigger_y0 = goal[1] - trigger_size[1] / 2.0
        trigger_y1 = goal[1] + trigger_size[1] / 2.0
        finishers = {
            ledge.index
            for ledge in ledges
            if ledge.left_px(level.tilewidth) - half < trigger_x1
            and trigger_x0 < ledge.right_px(level.tilewidth) + half
            and ledge.top_y - actual_physics.body_height < trigger_y1
            and trigger_y0 < ledge.top_y
        }
        reachable_finishers = finishers & set(reachable)
        if not reachable_finishers:
            return report

        p90 = _clean_physics(actual_physics)
        p90.max_run_speed = actual_physics.max_run_speed * 0.90
        edges90 = namespace["RouteGraph"](level, world, p90, ledges).edges()
        p80 = _clean_physics(actual_physics)
        p80.max_run_speed = actual_physics.max_run_speed * 0.80
        edges80 = namespace["RouteGraph"](level, world, p80, ledges).edges()

        def classify(move, source_ledge):
            return move_difficulty(
                move,
                source_ledge,
                actual_physics,
                level,
                ninety_percent_edges=edges90,
                eighty_percent_edges=edges80,
            )

        route = best_route(spawn_ledge.index, reachable_finishers, edges, ledges, classify)
        details = [classify(move, ledges[int(move["from"])]) for move in route]
        report.summary["route_moves"] = len(route)
        report.summary["goal_ledge"] = (int(route[-1]["to"]) + 1) if route else spawn_ledge.index + 1
        report.summary["route_moves_detail"] = details
        report.summary["difficulty"] = difficulty_summary(details)
        report.summary["route_length_m"] = route_length_m(route, ledges, level.tilewidth)
        report.summary["crouch_spans"] = [
            {
                "ledge": ledge.index + 1,
                "from_column": min(ledge.crouch_columns),
                "to_column": max(ledge.crouch_columns),
            }
            for ledge in ledges
            if ledge.crouch_columns
        ]
        report.summary["unreachable_ledges"] = [
            ledge.index + 1 for ledge in ledges if ledge.index not in reachable and ledge.width > 1
        ]

        soft_locks: list[int] = []
        for ledge in ledges:
            if ledge.index not in reachable or ledge.index in finishers:
                continue
            onward = graph.reachable_from(ledge.index, edges)
            if not (finishers & set(onward)):
                soft_locks.append(ledge.index + 1)
        report.summary["soft_locks"] = soft_locks

        report.notes = [note for note in report.notes if not note.startswith("route: ")]
        report.warnings = [
            warning for warning in report.warnings
            if "needs a full-charge jump" not in warning and not warning.startswith("tight: ")
        ]
        describe = namespace["_describe_move"]
        report.notes.append(
            "route: %s -> %s in %d move(s)" % (spawn_marker, goal_marker, len(route))
            + ("" if not route else ": " + "; ".join(describe(move, ledges, level.tilewidth) for move in route))
        )
        for move, detail in zip(route, details):
            text = describe(move, ledges, level.tilewidth)
            if detail["rating"] == "near_perfect":
                report.warnings.append("near-perfect: %s has almost no takeoff-speed/run-up margin" % text)
            elif detail["rating"] == "tight":
                report.warnings.append("tight: %s has limited takeoff-speed/run-up margin" % text)
            if detail["full_charge"]:
                report.warnings.append("%s needs a full-charge jump, leaving little vertical margin" % text)
        return report

    namespace["check_level"] = enhanced_check_level

    # ------------------------------------------------------------------
    # Portable stamp API
    # ------------------------------------------------------------------

    def public_capture_stamp(level, rect, name, include_gameplay=False, layer_names=None):
        try:
            return capture_stamp(
                level,
                rect,
                name,
                gid_mask=gid_mask,
                gameplay_layers=gameplay_layers,
                include_gameplay=include_gameplay,
                layer_names=layer_names,
            )
        except StampError as error:
            raise level_error(str(error)) from error

    def public_place_stamp(level, stamp, x, y, flip_x=False, flip_y=False):
        try:
            return place_stamp(
                level,
                stamp,
                x,
                y,
                flip_x=flip_x,
                flip_y=flip_y,
                flip_horizontal=flip_horizontal,
                flip_vertical=flip_vertical,
            )
        except StampError as error:
            raise level_error(str(error)) from error

    def public_inspect_stamp(stamp):
        return inspect_stamp(stamp, gameplay_layers)

    def public_apply_stamp_plan(level, plan, stamp_loader):
        try:
            return apply_stamp_plan(
                level,
                plan,
                stamp_loader,
                flip_horizontal=flip_horizontal,
                flip_vertical=flip_vertical,
            )
        except StampError as error:
            raise level_error(str(error)) from error

    namespace["capture_stamp"] = public_capture_stamp
    namespace["place_stamp"] = public_place_stamp
    namespace["inspect_stamp"] = public_inspect_stamp
    namespace["apply_stamp_plan"] = public_apply_stamp_plan

    def _stamp_path(value: str, directory: Path) -> Path:
        try:
            return resolve_stamp(value, directory)
        except StampError as error:
            raise level_error(str(error)) from error

    def _load_stamp(value: str, directory: Path) -> dict:
        try:
            return read_stamp(_stamp_path(value, directory))
        except StampError as error:
            raise level_error(str(error)) from error

    def command_stamp_list(args: argparse.Namespace) -> int:
        directory = namespace["_resolve"](args.stamp_dir)
        rows = []
        if directory.exists():
            for path in sorted(directory.glob("*.json")):
                rows.append(public_inspect_stamp(_load_stamp(str(path), directory)))
        if args.json:
            print(json.dumps(rows, indent=2, sort_keys=True))
        else:
            for item in rows:
                print("%-24s %dx%d  %s" % (item["name"], item["width"], item["height"], ", ".join(item["layers"])))
        return 0

    def command_stamp_inspect(args: argparse.Namespace) -> int:
        directory = namespace["_resolve"](args.stamp_dir)
        item = public_inspect_stamp(_load_stamp(args.stamp, directory))
        if args.json:
            print(json.dumps(item, indent=2, sort_keys=True))
        else:
            print("%s: %dx%d" % (item["name"], item["width"], item["height"]))
            print("  layers: %s" % (", ".join(item["layers"]) or "(none)"))
            print("  tilesets: %s" % (", ".join(item["tilesets"]) or "(none)"))
            print("  gameplay: %s" % ("yes" if item["includes_gameplay"] else "no"))
            if item["source"]:
                print("  source: %s" % item["source"])
        return 0

    def command_stamp_capture(args: argparse.Namespace) -> int:
        level = namespace["LevelMap"].load(namespace["_resolve"](args.level))
        stamp = public_capture_stamp(
            level,
            args.rect,
            args.name,
            args.include_gameplay,
            args.layers.split(",") if args.layers else None,
        )
        directory = namespace["_resolve"](args.stamp_dir)
        out = namespace["_resolve"](args.out) if args.out else directory / (args.name + ".json")
        namespace["write_json"](out, stamp)
        print("captured %s (%dx%d, %d layers) -> %s" % (args.name, stamp["width"], stamp["height"], len(stamp["layers"]), out))
        return 0

    def command_stamp_place(args: argparse.Namespace) -> int:
        level_path = namespace["_resolve"](args.level)
        level = namespace["LevelMap"].load(level_path)
        directory = namespace["_resolve"](args.stamp_dir)
        stamp = _load_stamp(args.stamp, directory)
        changed = public_place_stamp(level, stamp, args.at[0], args.at[1], args.flip_x, args.flip_y)
        out = namespace["_resolve"](args.out) if args.out else level_path
        namespace["write_json"](out, level.data)
        print("placed %s at %d,%d (%d cells changed) -> %s" % (stamp.get("name", args.stamp), args.at[0], args.at[1], changed, out))
        if args.check:
            return namespace["command_check"](argparse.Namespace(level=str(out), json=False, quiet=False, margin=0.1))
        return 0

    def command_stamp_apply(args: argparse.Namespace) -> int:
        level_path = namespace["_resolve"](args.level)
        level = namespace["LevelMap"].load(level_path)
        directory = namespace["_resolve"](args.stamp_dir)
        plan_path = namespace["_resolve"](args.plan)
        try:
            plan = json.loads(plan_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise level_error("invalid stamp plan %s: %s" % (plan_path, error)) from error
        if not isinstance(plan, dict):
            raise level_error("stamp plan root must be a JSON object")
        changed = public_apply_stamp_plan(level, plan, lambda name: _load_stamp(name, directory))
        out = namespace["_resolve"](args.out) if args.out else level_path
        namespace["write_json"](out, level.data)
        print("applied %d placement(s), %d cells changed -> %s" % (len(plan.get("placements", [])), changed, out))
        if args.check:
            return namespace["command_check"](argparse.Namespace(level=str(out), json=False, quiet=False, margin=0.1))
        return 0

    # ------------------------------------------------------------------
    # Campaign-wide checking
    # ------------------------------------------------------------------

    def command_check_all(args: argparse.Namespace) -> int:
        root = namespace["_resolve"](args.path)
        paths = [root] if root.is_file() else sorted(root.rglob("*.tmj")) if root.exists() else []
        if not paths:
            raise level_error("no .tmj levels found under %s" % root)
        results = []
        overall = True
        for path in paths:
            try:
                report = enhanced_check_level(namespace["LevelMap"].load(path), margin=args.margin)
                item = {
                    "level": namespace["_relative_to_project"](path),
                    "ok": report.ok,
                    "errors": report.errors,
                    "warnings": report.warnings,
                    "notes": report.notes,
                    "summary": report.summary,
                }
            except level_error as error:
                item = {
                    "level": namespace["_relative_to_project"](path),
                    "ok": False,
                    "errors": [str(error)],
                    "warnings": [],
                    "notes": [],
                    "summary": {"checked": False},
                }
            results.append(item)
            overall = overall and bool(item["ok"])
        if args.json:
            print(json.dumps({"ok": overall, "levels": results}, indent=2, sort_keys=True))
        else:
            for item in results:
                print("%-60s %s" % (item["level"], "PASS" if item["ok"] else "FAIL"))
                for error in item["errors"]:
                    print("  ERROR %s" % error)
                for warning in item["warnings"]:
                    print("  WARN  %s" % warning)
            print("%s: %d level(s)" % ("PASS" if overall else "FAIL", len(results)))
        return 0 if overall else 1

    # ------------------------------------------------------------------
    # Parser extension. Existing commands and flags remain unchanged.
    # ------------------------------------------------------------------

    def build_parser() -> argparse.ArgumentParser:
        parser = original_build_parser()
        commands = _subparsers(parser)

        stamp = commands.add_parser("stamp", help="capture, inspect and place reusable Tiled chunks")
        stamp_commands = stamp.add_subparsers(dest="stamp_command", required=True)

        capture = stamp_commands.add_parser("capture", help="capture tile layers from a map rectangle")
        capture.add_argument("level")
        capture.add_argument("--rect", required=True, type=_parse_rect, help="x,y,width,height in tile cells")
        capture.add_argument("--name", required=True)
        capture.add_argument("--layers", help="comma-separated layer names; defaults to decorative tile layers")
        capture.add_argument("--include-gameplay", action="store_true", help="also capture Semantic/Obstacles")
        capture.add_argument("--stamp-dir", default=str(stamp_dir))
        capture.add_argument("--out")
        capture.set_defaults(func=command_stamp_capture)

        listing = stamp_commands.add_parser("list", help="list saved stamps")
        listing.add_argument("--stamp-dir", default=str(stamp_dir))
        listing.add_argument("--json", action="store_true")
        listing.set_defaults(func=command_stamp_list)

        inspector = stamp_commands.add_parser("inspect", help="describe one saved stamp")
        inspector.add_argument("stamp")
        inspector.add_argument("--stamp-dir", default=str(stamp_dir))
        inspector.add_argument("--json", action="store_true")
        inspector.set_defaults(func=command_stamp_inspect)

        place = stamp_commands.add_parser("place", help="overlay a saved stamp on a Tiled map")
        place.add_argument("stamp")
        place.add_argument("level")
        place.add_argument("--at", required=True, type=_parse_point, help="x,y destination in tile cells")
        place.add_argument("--flip-x", action="store_true", help="mirror the stamp horizontally")
        place.add_argument("--flip-y", action="store_true", help="mirror the stamp vertically")
        place.add_argument("--stamp-dir", default=str(stamp_dir))
        place.add_argument("--out")
        place.add_argument("--check", action="store_true")
        place.set_defaults(func=command_stamp_place)

        apply_parser = stamp_commands.add_parser("apply", help="apply a JSON placement plan to a map")
        apply_parser.add_argument("level")
        apply_parser.add_argument("plan")
        apply_parser.add_argument("--stamp-dir", default=str(stamp_dir))
        apply_parser.add_argument("--out")
        apply_parser.add_argument("--check", action="store_true")
        apply_parser.set_defaults(func=command_stamp_apply)

        check_all = commands.add_parser("check-all", help="validate every .tmj below a path")
        check_all.add_argument("path", nargs="?", default="assets/tiled/levels")
        check_all.add_argument("--json", action="store_true", help="machine-readable aggregate output")
        check_all.add_argument("--margin", type=float, default=0.1, help="takeoff-speed margin used by analysis")
        check_all.set_defaults(func=command_check_all)
        return parser

    namespace["build_parser"] = build_parser
    namespace["command_check_all"] = command_check_all
    namespace["command_stamp_capture"] = command_stamp_capture
    namespace["command_stamp_place"] = command_stamp_place
    namespace["command_stamp_list"] = command_stamp_list
    namespace["command_stamp_inspect"] = command_stamp_inspect
    namespace["command_stamp_apply"] = command_stamp_apply
