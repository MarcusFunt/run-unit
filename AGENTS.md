# RUN//UNIT contributor guide

## Stack

- Godot 4.7.1, GDScript, and text-based `.tscn` / `.tres` resources.
- Tiled + YATI are the authored-level pipeline.
- GUT 9.7.1 is bundled under `addons/gut`.
- Python 3 is used for deterministic repository tooling.

## Local commands

```sh
# Open or run in Godot
godot --editor --path .
godot --path .

# Canonical test path: force Tiled reimport, import project, run all GUT tests
python tools/run_gut.py

# Tooling unit tests
python -m unittest discover -s tools/tests -v
```

If Godot is not on `PATH`, use `python tools/run_gut.py --godot <path>`.

## Authored world contract

`assets/tiled/levels/maintenance_shaft.tmj` (the Calibration tutorial, despite its legacy filename) `assets/tiled/levels/level_01_factory.tmj` (Factory Escape), `assets/tiled/levels/level_02_recovery.tmj` (Recovery) and `assets/tiled/levels/level_03_beacon.tmj` (Beacon 9) are the playable maps. Their external semantic tileset is `assets/tiled/semantic/semantic_layer.tsj`. `scenes/world.tscn` and the scenes under `scenes/levels/` wrap the imported maps; level set pieces that must return to their pre-run state on restart implement `reset_level_state()`, which `RunUnitStaticWorld.reset()` propagates; a level that owns its ending (the tutorial lift, Beacon 9's ignition chamber) extends `RunUnitRouteExit`, and `Checkpoint...` markers become respawn points; do not move authored platform geometry back into hand-maintained Godot collision nodes.

`scripts/gameplay/campaign_routes.gd` (`RunUnitCampaign`) is the single source of route copy and world-scene paths, mirroring the campaign in `StorylineSketch.md`. A new level is added by authoring its map and filling in that route's `world_scene`; a route with an empty `world_scene` shows as locked in the selector.

After any `.tmj` or `.tsj` change, use `tools/run_gut.py`. Godot/YATI may otherwise reuse a stale `.tmj` cache when only the external `.tsj` changed.

`tools/level_kit.py` is the supported way to author route geometry outside Tiled: `sketch` a map into a text grid, `build` it back, `autoart` its decorative layers, and `check` it. `check` validates the semantic-tile contract and replays the player motor to prove the Goal is reachable from the Spawn; run it before `tools/run_gut.py` on any level change, since it answers in under a second.

## Repository boundaries

- Commit gameplay source, scenes, themes, authored assets/maps, add-ons, tests, export presets, CI, and useful project documentation.
- Never commit `.godot/`, new `*.import` sidecars, staged template folders, local exports/builds, local MCP state, secrets, logs, or QA screenshots. Legacy tracked sidecars exist; do not intentionally rewrite them.
- Keep `.uid` files next to GDScript source when Godot creates them.
- Preserve LF line endings for Godot scenes/resources and scripts.

## Change discipline

- Keep feature, test, and repository-hygiene changes easy to review.
- Write a regression test before changing gameplay behavior.
- Run `python tools/run_gut.py` before committing gameplay or Tiled changes.
- Keep `StorylineSketch.md` and player-facing route copy aligned; do not restore the retired Solar Ignition Core / Beacon 9 storyline.
- Do not rewrite the Tiled/YATI pipeline, player motor, or menu framework merely to add level content.
- Never force-push shared branches or commit credentials.

## Release

`export_presets.cfg` defines the Windows Desktop build. GitHub Actions installs matching export templates, validates the project, exports the build, and publishes the `RUN_UNIT-windows` artifact. Prefer that reproducible artifact for deadline submissions unless a local export is explicitly required.
