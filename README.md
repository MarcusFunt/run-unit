# RUN//UNIT v0.1

RUN//UNIT is a small 2D platformer made with Godot 4.7. The campaign in `StorylineSketch.md` runs Calibration -> Factory Escape -> Recovery -> Beacon 9; the current school-project slice ships the first two. The manufactured robot UNIT-07 clears its factory movement checks, then crosses the stalled production line and the storage warehouse to escape the factory as the facility automation fails around it.

## Run and controls

Open `project.godot` in Godot 4.7.1 (or a compatible Godot 4.x release) and run the project.

Select **START NEW RUN**, then deploy to **CALIBRATION** (the tutorial) or **FACTORY ESCAPE** (Level 1). The selector lists the campaign in story order; Recovery and Beacon 9 have no authored world yet and show as locked.

- A / D or Left / Right: move
- Space / Up Arrow: hold to charge the spring crouch, then release to jump
- Down Arrow: crouch without charging; crouching reduces speed and collision height
- R: restart the authored route

Route distance is measured from the authored Spawn marker. The HUD maximum uses the Spawn-to-Goal traversal distance, so reaching the Goal corresponds to 100% route progress.

## Authoring source of truth

The playable geometry is authored in Tiled and imported through YATI:

- `assets/tiled/levels/maintenance_shaft.tmj` — Calibration tutorial map (legacy filename)
- `assets/tiled/levels/level_01_factory.tmj` — Factory Escape map
- `assets/tiled/semantic/semantic_layer.tsj` — semantic/collision tileset
- `scenes/world.tscn` — Godot wrapper that instances the tutorial map and its runtime art
- `scenes/levels/level_01_factory.tscn` — the same wrapper for Factory Escape
- `scripts/gameplay/campaign_routes.gd` — the campaign route table the selector, game, and results menu all read
- `scripts/world/static_world.gd` — indexes imported semantic tiles and authored markers

`Semantic` owns route collision, `Obstacles` owns non-platform blockers such as the crouch gate, `ArtFill` / `ArtDeck` are decoration-only, and `Markers` supplies Spawn/Goal points.

## Level kit

`tools/level_kit.py` is the fast path for sketching and validating route geometry. It reads and writes the same `.tmj` files Tiled does, so it can be used instead of Tiled or alongside it.

```sh
# Start a new level from a blank floor, spawn and goal
python tools/level_kit.py new --out route.sketch --width 90 --height 29

# Or open an existing level as an editable text grid
python tools/level_kit.py sketch assets/tiled/levels/maintenance_shaft.tmj --out route.sketch

# Validate any map on its own
python tools/level_kit.py check assets/tiled/levels/maintenance_shaft.tmj

# Redraw the basic decorative deck trim and tunnel shell from geometry
python tools/level_kit.py autoart assets/tiled/levels/maintenance_shaft.tmj
```

A sketch is one character per cell — `#` solid, `=` one-way, `^` hazard, `>` conveyor, `*` foreground, `T` crouch gate, `S` Spawn, `G` Goal — plus `@` directives that carry the map size and exact marker positions.

`check` validates two different things:

- **The contract.** Layer names `static_world.gd` looks up, 32px tiles, a finite map, tile ids that resolve to a declared tileset, `data_semantic` on every `Semantic` tile, and decoration that would otherwise create collision.
- **The route.** It replays `RunUnitPlayerMotor`'s own integration step — using the constants read straight out of `scripts/player/player_motor.gd` and `scenes/player.tscn` — to work out which ledges connect, then reports whether the Goal can actually be reached from the Spawn. Gaps that are too wide, overhangs too low to crouch under, stranded platforms, and jumps that only clear at a perfect full-speed takeoff all come back as errors or warnings in well under a second, without opening Godot.

## Tiled workbench and reusable stamps

For rich levels such as Factory Escape, use `tools/tiled_workbench.py` for rebuilding and repeated environment chunks. Its `build` command wraps the route builder but preserves custom object groups such as `StoryZones`, top-level map properties, foreground layers and other metadata that the route sketch does not own.

```sh
# Losslessly rebuild an edited route sketch and immediately validate it
python tools/tiled_workbench.py build route.sketch \
  --out assets/tiled/levels/level_01_factory.tmj --check

# See the reusable chunks already in the project
python tools/tiled_workbench.py stamp list

# Capture a good multi-layer composition from an existing map.
# Gameplay collision is excluded by default.
python tools/tiled_workbench.py stamp capture \
  assets/tiled/levels/level_01_factory.tmj \
  --rect 96,16,20,12 --name warehouse_section

# Paste that composition somewhere else without clearing art under empty cells
python tools/tiled_workbench.py stamp place warehouse_section \
  assets/tiled/levels/level_02_recovery.tmj --at 40,16 --check
```

Stamps live under `assets/tiled/stamps/`. They store **tileset-local ids** rather than a map's global tile ids, so a stamp remains usable when another map declares the same tilesets at different `firstgid` values. `Semantic` and `Obstacles` are deliberately omitted when capturing; add `--include-gameplay` only when the stamp is intentionally supposed to create collision.

Two starter chunks are included:

- `tunnel_11x7` — one reusable bulkhead tunnel macro.
- `platform_8x3` — the standard capped industrial platform trim.

The fastest deadline workflow is therefore: **sketch geometry -> `level_kit check` -> safe build -> place/capture stamps -> open in Godot for visual review**. Reuse a composition that already looks good instead of procedurally scattering individual props.

`python -m unittest discover -s tools/tests` runs the route and workbench regressions, including a Factory Escape round-trip that ensures `StoryZones` and foreground art survive the safe build.

## Tests

Use the repository runner instead of invoking GUT directly:

```sh
python tools/run_gut.py
```

If Godot is not on `PATH`, pass it explicitly:

```powershell
python tools/run_gut.py --godot "C:\path\to\Godot_v4.7.1-stable_win64.exe"
```

The runner deliberately removes generated `.godot/imported/*.tmj-*` cache entries, performs a Godot import pass, and then runs the full GUT suite. This matters because the Tiled map references an external `.tsj`; changing that tileset does not reliably invalidate an already-generated `.tmj` import on its own.

The repository still carries some legacy tracked `*.import` sidecars. Do not intentionally edit or add sidecars; `tools/run_gut.py` snapshots and restores the existing tracked ones so imports do not create review noise. The `.godot/` directory and newly generated sidecars remain untracked.

## CI and Windows build

`.github/workflows/godot-ci.yml` runs on pull requests and pushes to `main`. It installs Godot 4.7.1 plus export templates, runs the Python tooling tests, performs the clean-import GUT run, exports the **Windows Desktop** preset, and uploads the `build/` directory as the `RUN_UNIT-windows` artifact.

For a local Windows export, install the matching Godot export templates and run:

```sh
godot --headless --path . --export-release "Windows Desktop" build/RUN_UNIT.exe
```

## Project structure

- `scenes/`: game composition, player, world wrapper, HUD, and menus
- `scripts/player/`: player physics and visual feedback
- `scripts/world/`: imported-route indexing and traversal support
- `scripts/ai/`: controller-neutral action/environment interfaces
- `scripts/gameplay/`: run orchestration, session state, and scoring
- `assets/tiled/`: authored Tiled maps, reusable stamps and semantic tilesets
- `tools/`: deterministic asset/test/level-authoring tooling
- `tests/`: GUT regression coverage

## AI interface

`Environment` exposes reset/action/observation/reward/terminal methods. Human, scripted, and external controllers all eventually feed the same `RunUnitPlayerAction -> RunUnitPlayerMotor` path.

The numerical observation contains normalized player velocity, on-floor state, and relative information for upcoming platforms. Current-platform tracing uses the player position, not X alone, so vertically overlapping platforms can be distinguished.

Reward remains newly achieved maximum forward distance in metres, with a one-off `-1` terminal penalty on the transition into a failed run; polling the reward again after that returns `0`. The authored route itself is static; difficulty is a progress metric rather than a terrain-generation input.

## Narrative source

`StorylineSketch.md` is the current narrative source of truth. The retired Helios-9 / Solar Ignition Core / Beacon 9 concept is not part of the current build.
