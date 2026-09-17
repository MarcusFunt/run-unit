# RUN//UNIT v0.1

RUN//UNIT is a small 2D platformer made with Godot 4.7. The current school-project slice follows a manufactured robot through Calibration, Final Inspection, a stalled factory transfer line, and toward storage after the facility automation fails.

## Run and controls

Open `project.godot` in Godot 4.7.1 (or a compatible Godot 4.x release) and run the project.

Select **START NEW RUN** and deploy to **FINAL INSPECTION**. Future route slots are deliberately disabled in the current build.

- A / D or Left / Right: move
- Space / Up Arrow: hold to charge the spring crouch, then release to jump
- Down Arrow: crouch without charging; crouching reduces speed and collision height
- R: restart the authored route

Route distance is measured from the authored Spawn marker. The HUD maximum uses the Spawn-to-Goal traversal distance, so reaching the Goal corresponds to 100% route progress.

## Authoring source of truth

The playable geometry is authored in Tiled and imported through YATI:

- `assets/tiled/levels/maintenance_shaft.tmj` — current level map (legacy filename)
- `assets/tiled/semantic/semantic_layer.tsj` — semantic/collision tileset
- `scenes/world.tscn` — Godot wrapper that instances the imported level and runtime art
- `scripts/world/static_world.gd` — indexes imported semantic tiles and authored markers

`Semantic` owns route collision, `Obstacles` owns non-platform blockers such as the crouch gate, `ArtFill` / `ArtDeck` are decoration-only, and `Markers` supplies Spawn/Goal points.

## Level kit

`tools/level_kit.py` is the fast path for building and changing routes. It reads and writes the same `.tmj` files Tiled does, so it can be used instead of Tiled or alongside it.

```sh
# Start a new level from a blank floor, spawn and goal
python tools/level_kit.py new --out route.sketch --width 90 --height 29

# Or open an existing level as an editable text grid
python tools/level_kit.py sketch assets/tiled/levels/maintenance_shaft.tmj --out route.sketch

# Edit route.sketch in any text editor, then rebuild and validate in one step
python tools/level_kit.py build route.sketch --out assets/tiled/levels/maintenance_shaft.tmj --check

# `build` keeps the template's tilesets and art, so a new map inherits both
python tools/level_kit.py build route.sketch --out assets/tiled/levels/transfer_line.tmj --check

# Redraw the decorative deck trim and tunnel shell from the new geometry
python tools/level_kit.py autoart assets/tiled/levels/maintenance_shaft.tmj

# Validate any map on its own
python tools/level_kit.py check assets/tiled/levels/maintenance_shaft.tmj
```

A sketch is one character per cell — `#` solid, `=` one-way, `^` hazard, `>` conveyor, `*` foreground, `T` crouch gate, `S` Spawn, `G` Goal — plus `@` directives that carry the map size and exact marker positions. A level that is only re-sketched and rebuilt comes back byte-identical, and the decorative layers of the template survive every rebuild.

`check` validates two different things:

- **The contract.** Layer names `static_world.gd` looks up, 32px tiles, a finite map, tile ids that resolve to a declared tileset, `data_semantic` on every `Semantic` tile, and decoration that would otherwise create collision.
- **The route.** It replays `RunUnitPlayerMotor`'s own integration step — using the constants read straight out of `scripts/player/player_motor.gd` and `scenes/player.tscn` — to work out which ledges connect, then reports whether the Goal can actually be reached from the Spawn. Gaps that are too wide, overhangs too low to crouch under, stranded platforms, and jumps that only clear at a perfect full-speed takeoff all come back as errors or warnings in well under a second, without opening Godot.

`python -m unittest discover -s tools/tests` runs `check` against the shipped level, so an unfinishable route fails CI.

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
- `assets/tiled/`: authored Tiled maps and semantic tilesets
- `tools/`: deterministic asset/test tooling
- `tests/`: GUT regression coverage

## AI interface

`Environment` exposes reset/action/observation/reward/terminal methods. Human, scripted, and external controllers all eventually feed the same `RunUnitPlayerAction -> RunUnitPlayerMotor` path.

The numerical observation contains normalized player velocity, on-floor state, and relative information for upcoming platforms. Current-platform tracing uses the player position, not X alone, so vertically overlapping platforms can be distinguished.

Reward remains newly achieved maximum forward distance in metres, with a `-1` terminal penalty after a failed run. The authored route itself is static; difficulty is a progress metric rather than a terrain-generation input.

## Narrative source

`StorylineSketch.md` is the current narrative source of truth. The retired Helios-9 / Solar Ignition Core / Beacon 9 concept is not part of the current build.
