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
