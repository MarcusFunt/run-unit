# Level Kit API Design

## Goal

Make `tools/level_kit.py` the single stable public API/CLI for RUN//UNIT level authoring, while improving correctness, reusable Tiled editing, difficulty analysis, and batch workflows without breaking existing commands or Python imports.

## Public compatibility

The existing commands remain valid and keep their current meaning:

- `new`
- `sketch`
- `build`
- `check`
- `autoart`

Existing Python callers using `import level_kit`, `LevelMap`, `PlayerPhysics`, `check_level`, `build_map`, `autoart`, and the existing constants continue to work.

New commands are additive:

- `check-all`
- `stamp list`
- `stamp inspect`
- `stamp capture`
- `stamp place`
- `stamp apply`

`tools/tiled_workbench.py` is retired after its lossless-build and stamp behavior is absorbed into Level Kit.

## Internal architecture

`tools/level_kit.py` remains the only public entry point. Focused helpers move into `tools/levelkit/` so the public facade can remain stable while implementation code becomes easier to test and reason about:

- `levelkit/tiled.py`: Tiled-safe helpers that do not depend on gameplay simulation.
- `levelkit/stamps.py`: portable multi-layer stamp capture/place/transform/batch operations.
- `levelkit/analysis.py`: difficulty-aware route scoring and structured report helpers.

The existing monolithic code may be migrated incrementally rather than rewritten wholesale in one risky change. Public symbols stay re-exported by `level_kit.py`.

## Hardening fixes

1. Validation must reject tile layers whose `data` length does not equal `width * height` rather than allowing later indexing errors.
2. Duplicate `Spawn` or `Goal` markers must be contract errors instead of being silently collapsed by dictionary conversion.
3. Collidable tiles using Tiled's diagonal flip bit must not be simulated incorrectly. The checker must either transform them correctly or report a validation error; this pass uses explicit rejection for collidable diagonal flips because it is safer and deterministic.
4. Route selection must prefer easier viable routes over merely minimizing jump count. Path cost is lexicographic: fewer near-perfect moves, lower charge/tightness penalty, then fewer moves.
5. The checker must distinguish physical possibility from human feasibility. Short run-up or low margin should produce structured difficulty warnings rather than false route failures.

## Feature additions

### Lossless builds

Normal `level_kit build` becomes metadata-safe. It owns gameplay route layers and Spawn/Goal markers but preserves custom object layers, map properties, decorative layer metadata, and unknown future Tiled fields. Factory Escape's `StoryZones` and `ArtForeground` are regression fixtures.

### Portable stamps

Stamps store `tileset + local_id + flip flags`, never source-map global GIDs. By default capture excludes `Semantic` and `Obstacles`; `--include-gameplay` is explicit. Empty stamp cells never erase existing art.

Stamp placement supports `--flip-x` and `--flip-y`. Arbitrary rotation is intentionally out of scope.

### Stamp inspection and batch application

`stamp inspect NAME` reports dimensions, touched layers, required tilesets, source, and whether gameplay layers are present.

`stamp apply LEVEL plan.json --check` applies a deterministic list of placements such as:

```json
{
  "placements": [
    {"stamp": "warehouse_rack", "at": [40, 16]},
    {"stamp": "warehouse_rack", "at": [58, 16], "flip_x": true}
  ]
}
```

### Better check output

`check --json` keeps its existing keys and adds structured authoring information including route length, selected route moves, crouch spans, unreachable ledges, soft locks, and difficulty counts.

### check-all

`check-all PATH` recursively validates every `.tmj` file under the path, prints a compact result per map, and exits non-zero if any map fails.

## Testing

All changes use TDD. Regression coverage must include:

- malformed layer cell counts;
- duplicate Spawn/Goal objects;
- collidable diagonal flips;
- difficulty-aware path choice;
- short-run-up classification;
- Factory Escape lossless rebuild;
- stamp capture defaults and explicit gameplay capture;
- portable GID remapping;
- non-destructive empty stamp cells;
- X/Y stamp transforms;
- stamp inspect metadata;
- batch stamp application;
- check-all success/failure aggregation;
- backward compatibility of existing CLI commands.

Final verification is the repository's full Python tooling suite plus clean Godot/YATI import, GUT, Windows export, and artifact upload in GitHub Actions.
