# Tense, Snappy Level Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three later routes a little tenser and more legible without changing the core movement model, expanding instructional text, or adding score-chasing systems.

**Architecture:** Keep the player motor and authored semantic world contract intact. Replace scene reload on retry with a `RunUnitGame` reset of the active run, add one reusable non-colliding visual treatment for low-clearance passages, and add a reusable deterministic pulse to existing hazard and landmark art. Tighten one authored gap in each later Tiled route through `level_kit` so reachability is proven by the project’s motor replay.

**Tech Stack:** Godot 4.7.1, GDScript, text `.tscn` resources, Tiled/YATI, GUT 9.7.1, Python repository tooling.

**Spec:** `docs/superpowers/specs/2026-09-19-tense-snappy-level-polish-design.md`

## Global Constraints

- Keep three health, existing route progression, existing checkpoints, compact HUD, and all current input bindings.
- Do not change player movement constants, coyote time, jump buffering, damage values, enemy logic, or the Calibration tutorial geometry.
- Do not add score, combo, timer, choice, or persistent instructional UI text.
- Use `tools/level_kit.py` for every `.tmj` geometry edit. Run `check` before `tools/run_gut.py` after every map change.
- Treat `tests/test_hazard_system.gd` as user-owned while it has uncommitted changes; do not edit, stage, or revert it.
- Keep generated captures and temporary sketches out of Git. Do not overwrite tracked files below `verification/`.
- Preserve LF endings in all Godot text resources and scripts.

## File Structure

| Area | Files | Responsibility |
| --- | --- | --- |
| Retry flow | `scripts/ui/run_unit_death_menu.gd`, `scripts/gameplay/game.gd`, `tests/test_run_presentation.gd` | Request and execute an in-place retry without replacing the active scene. |
| Ambient response | `scripts/world/ambient_pulse.gd`, `scenes/hazards/electric_floor_arc.tscn`, `scenes/levels/level_02_recovery.tscn`, `tests/test_run_presentation.gd` | Give existing warning and landmark art deterministic, resettable motion. |
| Clearance readability | `scripts/world/clearance_gate_visual.gd`, `scenes/props/clearance_gate_visual.tscn`, `scenes/levels/level_01_factory.tscn`, `scenes/levels/level_02_recovery.tscn`, `scenes/levels/level_03_beacon.tscn`, route tests | Overlay visually unambiguous crouch-only thresholds with no physics impact. |
| Tension pass | `assets/tiled/levels/level_01_factory.tmj`, `assets/tiled/levels/level_02_recovery.tmj`, `assets/tiled/levels/level_03_beacon.tmj`, matching route tests | Remove one platform cell from one early jump in each later route. |

## Review Focus

| Risk | Guardrail and proving test |
| --- | --- |
| A retry accidentally reloads, loses the active checkpoint, or leaves pause on | GUT drives a failed Level 3 run through the retry button and asserts the same `RunUnitGame` instance, restored health, resumed simulation, and checkpoint position. |
| A finished run reuses an old checkpoint | GUT completes a route, retries, and asserts spawn is used after campaign completion clears the resume point. |
| Decorative clearance art changes collision | Route tests assert each treatment is a `Node2D`, not a `CollisionObject2D`; the existing standing-versus-crouching collision tests remain green. |
| Decorative animation desynchronizes after restart | GUT advances a pulse, resets it through `reset_level_state()`, and asserts authored-phase opacity is restored. |
| Longer gaps become unreliable | Each map is rebuilt by `level_kit`, then its JSON result must report the edited transition as `comfortable` with zero soft locks and zero unreachable goals. |

---

## Task 1: Retry the Current Run In Place

**Files:**

- Modify: `scripts/ui/run_unit_death_menu.gd`
- Modify: `scripts/gameplay/game.gd`
- Modify: `tests/test_run_presentation.gd`

**Interfaces:**

- `RunUnitDeathMenu` produces `signal retry_requested` after it has closed and released only its own pause ownership.
- `RunUnitGame` consumes that signal in `_on_retry_requested()` and calls the existing `reset_run(initial_seed)` only when `is_terminal()` is true.
- `RunUnitGame.reset_run()` remains the single reset authority for `RunUnitStaticWorld`, player motor, health, checkpoint resume position, route-exit state, metrics, and HUD state.

- [ ] Add failing GUT coverage in `tests/test_run_presentation.gd`, leaving the dirty hazard test untouched. Use the existing game fixture style and remove only the fixture’s pause menu controller when it interferes with test pause state.

  ```gdscript
  func test_death_menu_retry_reuses_game_and_restores_checkpoint() -> void:
      RunUnitSession.begin_campaign(3)
      var checkpoint: Vector2 = Vector2(10000.0, 544.0)
      RunUnitSession.set_resume_position(checkpoint)
      var game: RunUnitGame = await _spawn_game()
      var game_id: int = game.get_instance_id()

      game._fail_run()
      game.death_menu.restart_button.emit_signal("pressed")
      await get_tree().process_frame

      assert_eq(game.get_instance_id(), game_id)
      assert_false(get_tree().paused)
      assert_false(game.is_terminal())
      assert_eq(game.player.global_position, checkpoint)
      assert_eq(game.player_health.current_health, game.player_health.max_health)
  ```

- [ ] Add a second failing completion regression in the same file. Start a later route, set a non-spawn resume position, finish the run through the existing game completion path, press retry, and assert the new run uses `world.get_spawn_position()` rather than the cleared checkpoint.

- [ ] Run the focused presentation test and record the expected failure caused by the existing `SceneLoader.reload_current_scene()` path.

  ```powershell
  & 'C:\Users\marcu\Documents\GODOT\Godot_v4.7.1-stable_win64.exe' --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/test_run_presentation.gd -gexit -glog=3
  ```

- [ ] In `run_unit_death_menu.gd`, declare `signal retry_requested`. Change `_on_restart_pressed()` to call `close()` and emit that signal; remove the direct scene reload. Do not force `get_tree().paused = false` separately, because `close()` must retain the menu’s ownership semantics.

- [ ] In `game.gd` `_ready()`, connect `death_menu.retry_requested` to `_on_retry_requested` with the project’s existing duplicate-connection guard style. Implement `_on_retry_requested()` to return when the game is not terminal, otherwise call `reset_run(initial_seed)`.

- [ ] Re-run the focused presentation test and confirm both retry tests pass. Manually inspect that menu focus still returns to the Retry button when a new terminal menu opens.

- [ ] Commit only the retry-flow files and `tests/test_run_presentation.gd` as `fix: retry failed runs in place`. Verify `tests/test_hazard_system.gd` is absent from the staged diff.

## Task 2: Add Deterministic Motion to Existing Warning Art

**Files:**

- Create: `scripts/world/ambient_pulse.gd`
- Modify: `scenes/hazards/electric_floor_arc.tscn`
- Modify: `scenes/levels/level_02_recovery.tscn`
- Modify: `tests/test_run_presentation.gd`

**Interfaces:**

- `ambient_pulse.gd` extends `CanvasItem`, exports `period_seconds`, `dim_factor`, and `phase_offset_seconds`, and implements `reset_level_state()`.
- It consumes the attached item’s authored `modulate` value and produces only an alpha pulse; its RGB channels and all collision state remain unchanged.
- `RunUnitStaticWorld.reset()` already propagates `reset_level_state()` to child set pieces, making pulses restart deterministically without new reset plumbing.

- [ ] Add a failing pulse test in `tests/test_run_presentation.gd`. Attach the new script to a disposable `Polygon2D`, set a short period and a non-white authored modulation, advance frames, then assert alpha changes while RGB remains equal to the authored color. Call `reset_level_state()` and assert alpha returns to the authored phase.

  ```gdscript
  func test_ambient_pulse_resets_to_its_authored_phase() -> void:
      var light: Polygon2D = Polygon2D.new()
      light.modulate = Color(0.9, 0.5, 0.2, 0.8)
      light.set_script(load("res://scripts/world/ambient_pulse.gd"))
      light.set("period_seconds", 0.10)
      add_child_autofree(light)
      await get_tree().process_frame
      var initial_alpha: float = light.modulate.a
      await get_tree().create_timer(0.04).timeout
      assert_ne(light.modulate.a, initial_alpha)
      assert_eq(light.modulate.r, 0.9)
      light.call("reset_level_state")
      assert_eq(light.modulate.a, initial_alpha)
  ```

- [ ] Implement `ambient_pulse.gd` using an accumulated elapsed time and a sine wave. Cache the authored `modulate` in `_ready()`, keep the factor in `[dim_factor, 1.0]`, set only alpha in `_apply_pulse()`, and `queue_redraw()` only if a future drawing user needs it. Do not create tweens, timers, or random phases.

- [ ] Add the script as an external resource to `electric_floor_arc.tscn`. Attach it to the existing warning stripe and active glow only; retain their current polygons, colors, collision shape, phase timings, and damage configuration.

- [ ] Add the same script to `AssemblyMonitor/Status` in `level_02_recovery.tscn`, with a slower period and offset distinct from the floor arc. Preserve its animation frames and existing scene hierarchy.

- [ ] Extend the test to instantiate `electric_floor_arc.tscn`, assert the warning stripe and active glow expose `reset_level_state()`, and assert neither object is a `CollisionObject2D`.

- [ ] Run the focused presentation test, then run a headless project validation:

  ```powershell
  & 'C:\Users\marcu\Documents\GODOT\Godot_v4.7.1-stable_win64.exe' --headless --path . --editor --quit-after 8
  ```

- [ ] Capture a short local gameplay run through an electric floor arc and the Recovery monitor using the project’s Godot scenario runner. Inspect frames at rest, warning, and active states for a restrained pulse that does not hide the timing silhouette. Keep captures outside version control.

- [ ] Commit only the ambient-pulse script, two scenes, and presentation test as `feat: animate industrial warning lights`.

## Task 3: Make Crouch-Only Passages Read as Foreground Constraints

**Files:**

- Create: `scripts/world/clearance_gate_visual.gd`
- Create: `scenes/props/clearance_gate_visual.tscn`
- Modify: `scenes/levels/level_01_factory.tscn`
- Modify: `scenes/levels/level_02_recovery.tscn`
- Modify: `scenes/levels/level_03_beacon.tscn`
- Modify: `tests/test_level_01_factory.gd`
- Modify: `tests/test_level_02_recovery.gd`
- Modify: `tests/test_level_03_beacon.gd`

**Interfaces:**

- `RunUnitClearanceGateVisual` is a `Node2D` with `span_width`, `overhang_height`, shell color, trim color, and `get_visual_bounds()`; it contains no physics node.
- It draws an opaque dark overhang and a thin amber foreground edge above the existing authored collision, centered on the existing low-ceiling span.
- Level scenes instantiate that prop under a `ClearanceTreatments` `Node2D`; their positions line up to the authored semantic geometry and do not change any imported map collision.

- [ ] Add a failing assertion in each route test for the exact new treatment nodes and centers:

  ```gdscript
  func test_factory_crouch_gates_have_non_colliding_visual_treatments() -> void:
      var world: Node2D = await _spawn_world()
      var gate: Node2D = world.get_node("ClearanceTreatments/FactoryTransferGate")
      assert_eq(gate.global_position, Vector2(1040.0, 416.0))
      assert_false(gate is CollisionObject2D)
      assert_eq(gate.call("get_visual_bounds").size.x, 96.0)
  ```

- [ ] Add equivalent assertions with these required node names and positions:

  | Scene | Node name | Position |
  | --- | --- | --- |
  | Factory | `FactoryStorageGate` | `Vector2(4560.0, 704.0)` |
  | Recovery | `RecoveryHatch` | `Vector2(4848.0, 416.0)` |
  | Recovery | `RecoveryShutter` | `Vector2(10000.0, 544.0)` |
  | Beacon | `BeaconCanyonGate` | `Vector2(8240.0, 736.0)` |

- [ ] Run the three focused route tests and confirm the new node assertions fail before adding the prop.

  ```powershell
  & 'C:\Users\marcu\Documents\GODOT\Godot_v4.7.1-stable_win64.exe' --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/test_level_01_factory.gd,res://tests/test_level_02_recovery.gd,res://tests/test_level_03_beacon.gd -gexit -glog=3
  ```

- [ ] Implement `clearance_gate_visual.gd` as a draw-only `Node2D`. In `_draw()`, draw a centered dark shell from `-overhang_height` to `-5`, a 3-pixel amber bottom trim at `y = -4`, and short amber side markers. Return the same centered rectangle from `get_visual_bounds()`. Use defaults `span_width = 96.0` and `overhang_height = 32.0`.

- [ ] Create `clearance_gate_visual.tscn` with a `Node2D` root using that script and no children. Do not add `Area2D`, `StaticBody2D`, collision shapes, labels, or particles.

- [ ] Add a `ClearanceTreatments` parent and five instances of the prop to the later level wrapper scenes. Set each instance’s exact name and position from the test table and leave all Tiled-imported node transforms unchanged.

- [ ] Re-run the focused route tests. Confirm existing tests for standing collision, crouched traversal, and imported semantic layers still pass unchanged.

- [ ] Use a visual scenario to approach every treatment both while standing and crouching. Verify the amber edge is in foreground and distinct from the teal background, while the collision remains at the old ceiling height. Keep evidence under ignored local artifacts.

- [ ] Commit only the prop, wrapper-scene instances, and route-test assertions as `feat: clarify crouch-only clearances`.

## Task 4: Tighten One Landing in Each Later Route and Verify the Whole Pass

**Files:**

- Modify: `assets/tiled/levels/level_01_factory.tmj`
- Modify: `assets/tiled/levels/level_02_recovery.tmj`
- Modify: `assets/tiled/levels/level_03_beacon.tmj`
- Modify: `tests/test_level_01_factory.gd`
- Modify: `tests/test_level_02_recovery.gd`
- Modify: `tests/test_level_03_beacon.gd`

**Interfaces:**

- Factory’s second early platform changes from `[24, 44, 14]` to `[25, 44, 14]`.
- Recovery’s second early platform changes from `[26, 40, 13]` to `[27, 40, 13]`.
- Beacon’s second early platform changes from `[31, 48, 14]` to `[32, 48, 14]`.
- The project-level reachability contract remains: the route starts at `Spawn`, reaches `Goal`, has zero soft locks, and every relevant transition is `comfortable` under the current motor replay.

- [ ] Update the three route tests’ expected platform ranges first and run them. Confirm they fail against the old authored TMJ geometry.

- [ ] Sketch all three maps into ignored local artifact files:

  ```powershell
  python tools/level_kit.py sketch assets/tiled/levels/level_01_factory.tmj --out artifacts/visual_polish/factory.sketch
  python tools/level_kit.py sketch assets/tiled/levels/level_02_recovery.tmj --out artifacts/visual_polish/recovery.sketch
  python tools/level_kit.py sketch assets/tiled/levels/level_03_beacon.tmj --out artifacts/visual_polish/beacon.sketch
  ```

- [ ] In the Factory sketch, change the semantic solid at row 14, column 24 from `#` to `.`. In the Recovery sketch, change the semantic solid at row 13, column 26 from `#` to `.`. In the Beacon sketch, change the semantic solid at row 14, column 31 from `#` to `.`. Do not change spawn, goal, crouch spans, hazards, background structure, or another platform cell.

- [ ] Rebuild each map through `level_kit`, then regenerate its decorative layer through `autoart` and immediately validate the map:

  ```powershell
  python tools/level_kit.py build artifacts/visual_polish/factory.sketch --out assets/tiled/levels/level_01_factory.tmj --check
  python tools/level_kit.py autoart assets/tiled/levels/level_01_factory.tmj
  python tools/level_kit.py check assets/tiled/levels/level_01_factory.tmj
  ```

  Repeat those three commands with the Recovery and Beacon file names. Inspect each output before continuing; require the edited move to remain `comfortable`.

- [ ] Run the aggregate authored-world validation and save its JSON output only under ignored artifacts:

  ```powershell
  python tools/level_kit.py check-all assets/tiled/levels --json | Out-File -Encoding utf8 artifacts/visual_polish/check-all.json
  ```

- [ ] Re-run the three focused route tests. Confirm the ranges match exactly and the crouch-clearance assertions from Task 3 remain green.

- [ ] Run the canonical gameplay suite after all TMJ/TSJ work:

  ```powershell
  python tools/run_gut.py
  python -m unittest discover -s tools/tests -v
  ```

- [ ] Run `git diff --check`, inspect `git diff -- assets/tiled/levels` for exactly three removed semantic cells plus generated decorative correspondence, and visually capture the three edited jumps. Reject the change if `level_kit` reports a soft lock, an unreachable goal, or a non-comfortable edited transition.

- [ ] Commit only the three maps and route tests as `feat: tighten later-route platform gaps`. Do not include local artifacts, `.godot`, imports, verification output, or `tests/test_hazard_system.gd`.

## Final Verification and Handoff

- [ ] Check the working tree and staged diff for accidental generated or user-owned files:

  ```powershell
  git diff --check
  git status --short
  git diff -- tests/test_hazard_system.gd
  ```

- [ ] Re-run `python tools/level_kit.py check-all assets/tiled/levels --json`, `python tools/run_gut.py`, and `python -m unittest discover -s tools/tests -v` from a clean Godot editor process.

- [ ] Run the game once per affected route with a controller and keyboard. Confirm: a failure at a checkpoint returns immediately to that checkpoint; a completed route re-deploys at its spawn; each amber clearance edge is visible before its crouch requirement; each edited gap needs a committed jump but remains forgiving; hazard and monitor motion feels alive without obscuring timing.

- [ ] Report the four focused changes, the validation commands and outcomes, the commits, and the untouched pre-existing `tests/test_hazard_system.gd` change. Do not add design commentary or player-facing text to the game.
