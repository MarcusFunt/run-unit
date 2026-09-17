# RUN//UNIT v0.1

RUN//UNIT is a small 2D platformer made with Godot 4.7. The campaign in `StorylineSketch.md` runs Calibration -> Factory Escape -> Recovery -> Beacon 9; and all four are playable. The manufactured robot UNIT-07 clears its factory movement checks, crosses the stalled production line and the storage warehouse to escape the factory, crosses the exterior service district into Reserve Depot 03 to recover the replacement ignition module, then carries it across the failing city, climbs Beacon 9, and installs it.

## Run and controls

Open `project.godot` in Godot 4.7.1 (or a compatible Godot 4.x release) and run the project.

Select **START NEW RUN**, then deploy to **CALIBRATION** (the tutorial) **FACTORY ESCAPE** (Level 1), **RECOVERY** (Level 2), or **BEACON 9** (Level 3). The selector lists the campaign in story order.

- A / D or Left / Right: move
- Space / Up Arrow: hold to charge the spring crouch, then release to jump
- Down Arrow: crouch without charging; crouching reduces speed and collision height
- R: restart the authored route, resuming from the last checkpoint reached

Route distance is measured from the authored Spawn marker. The HUD maximum uses the Spawn-to-Goal traversal distance, so reaching the Goal corresponds to 100% route progress.

Longer routes author `Checkpoint...` markers in their Markers layer. Driving past one records it, and restarting resumes there instead of replaying the route; distance is still measured from Spawn. Deploying a route from the selector, or finishing it, starts it clean again. Level 3 ships four; the shorter routes ship none.

## Authoring source of truth

The playable geometry is authored in Tiled and imported through YATI:

- `assets/tiled/levels/maintenance_shaft.tmj` — Calibration tutorial map (legacy filename)
- `assets/tiled/levels/level_01_factory.tmj` — Factory Escape map
- `assets/tiled/levels/level_02_recovery.tmj` — Recovery map
- `assets/tiled/levels/level_03_beacon.tmj` — Beacon 9 map
- `assets/tiled/semantic/semantic_layer.tsj` — semantic/collision tileset
- `scenes/world.tscn` — Godot wrapper that instances the tutorial map and its runtime art
- `scenes/levels/level_01_factory.tscn` — the same wrapper for Factory Escape
- `scenes/levels/level_02_recovery.tscn` — the Recovery wrapper, including the Beacon 9 skyline and the module cradle (`scripts/world/recovery_module_cradle.gd`)
- `scenes/levels/level_03_beacon.tscn` — the Beacon 9 wrapper, including the carried module and the ignition chamber that ends the game (`scripts/world/beacon_ignition.gd`)
- `scenes/props/beacon_9_skyline.tscn` — the Beacon 9 landmark, shared by the levels that show it
- `scenes/ending.tscn` — the ending screen Level 3 hands off to, over `assets/images/ending_beacon_vista.png`
- `scripts/gameplay/campaign_routes.gd` — the campaign route table the selector, game, and results menu all read
- `scripts/world/static_world.gd` — indexes imported semantic tiles and authored markers

`Semantic` owns route collision, `Obstacles` owns non-platform blockers such as the crouch gate, `ArtFill` / `ArtDeck` are decoration-only, and `Markers` supplies Spawn/Goal points.

## Level kit

`tools/level_kit.py` is the single authoring API/CLI for RUN//UNIT's Tiled levels. It reads and writes the same `.tmj` files as Tiled, preserves rich map metadata during route edits, validates gameplay against the player motor, and manages reusable multi-layer environment stamps.

```sh
# Start a new level from a blank floor, spawn and goal
python tools/level_kit.py new --out route.sketch --width 90 --height 29

# Or open an existing level as an editable text grid
python tools/level_kit.py sketch assets/tiled/levels/maintenance_shaft.tmj --out route.sketch

# Rebuild an edited sketch. Rich maps keep StoryZones, map properties,
# foreground/decorative layers and unknown object groups.
python tools/level_kit.py build route.sketch \
  --out assets/tiled/levels/level_01_factory.tmj --check

# Validate one map, or every authored map at once
python tools/level_kit.py check assets/tiled/levels/maintenance_shaft.tmj
python tools/level_kit.py check-all assets/tiled/levels

# Use --json for AI/tooling-friendly structured route and difficulty data
python tools/level_kit.py check assets/tiled/levels/level_01_factory.tmj --json
python tools/level_kit.py check-all assets/tiled/levels --json

# Redraw the basic decorative deck trim and tunnel shell from geometry
python tools/level_kit.py autoart assets/tiled/levels/maintenance_shaft.tmj
```

A sketch is one character per cell — `#` solid, `=` one-way, `^` hazard, `>` conveyor, `*` foreground, `T` crouch gate, `S` Spawn, `G` Goal — plus `@` directives that carry map size and exact marker positions.

`check` validates two different things:

- **The contract.** Layer names, exact tile-layer cell counts, finite 32px maps, resolvable tile ids, semantic properties, duplicate Spawn/Goal markers, unsupported diagonal collision transforms, and decorative tiles that accidentally carry collision.
- **The route.** It replays the player motor's movement model, checks ledge connectivity and crouch clearance, detects unreachable ledges and soft locks, estimates available run-up, and prefers a slightly longer comfortable route over a shorter near-perfect one. JSON output includes per-move difficulty, crouch spans, unreachable ledges, soft locks and route length.

### Reusable Tiled stamps

Stamps copy approved multi-layer compositions instead of procedurally scattering individual props. They live under `assets/tiled/stamps/` and store `tileset + local_id + flip flags`, so they remain portable across maps with different global `firstgid` assignments.

```sh
# Discover and inspect reusable chunks
python tools/level_kit.py stamp list
python tools/level_kit.py stamp inspect platform_8x3

# Capture a good composition from an existing map. Semantic/Obstacles are
# excluded by default so a visual prefab cannot accidentally add collision.
python tools/level_kit.py stamp capture \
  assets/tiled/levels/level_01_factory.tmj \
  --rect 96,16,20,12 --name warehouse_section

# Place it normally or mirrored. Empty stamp cells never erase existing art.
python tools/level_kit.py stamp place warehouse_section \
  assets/tiled/levels/level_02_recovery.tmj --at 40,16 --check
python tools/level_kit.py stamp place warehouse_section \
  assets/tiled/levels/level_02_recovery.tmj --at 64,16 --flip-x

# Deliberately include gameplay collision only when the prefab owns it.
python tools/level_kit.py stamp capture \
  assets/tiled/levels/level_01_factory.tmj \
  --rect 80,10,12,6 --name gameplay_chunk --include-gameplay
```

A batch plan lets code or an AI author a complete decoration pass deterministically:

```json
{
  "placements": [
    {"stamp": "warehouse_section", "at": [40, 16]},
    {"stamp": "warehouse_section", "at": [60, 16], "flip_x": true},
    {"stamp": "platform_8x3", "at": [82, 20], "flip_y": false}
  ]
}
```

```sh
python tools/level_kit.py stamp apply \
  assets/tiled/levels/level_02_recovery.tmj layout.json --check
```

Two starter chunks are included:

- `tunnel_11x7` — one reusable bulkhead tunnel macro.
- `platform_8x3` — the standard capped industrial platform trim.

The fastest deadline workflow is: **sketch geometry -> `build --check` -> `check-all` -> place/capture stamps -> open in Godot for visual review**. Reuse compositions that already look good instead of rebuilding scenery tile by tile.

`python -m unittest discover -s tools/tests -v` exercises route simulation, lossless Factory Escape rebuilding, stamp portability/transforms/batch placement, malformed-map handling, and the campaign-wide checker.

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
