# RUN//UNIT — game analysis, bugs, and next steps

Scope: full read of `scripts/`, `scenes/`, `menus/` glue, `tests/`, CI, and the
authored Tiled map, against `main` at `2532d67`. Godot is not installed in the
review environment, so every runtime claim below is either derived from the
source or is pinned by a new GUT test that CI runs.

---

## 1. Where the project actually stands

The slice is in better shape than the v0.1 label suggests. The parts that
usually rot first are the parts that are strongest here:

- **Separation of concerns holds.** `RunUnitPlayerMotor` owns physics and
  nothing else; every controller — human, scripted bot, external agent —
  funnels through the same `RunUnitPlayerAction`. That seam is real, not
  aspirational, and it is what makes the bot toggle (`B`) work at all.
- **Level authoring is genuinely data-driven.** Geometry, collision, and even
  Spawn/Goal come out of `maintenance_shaft.tmj`. `static_world.gd` derives
  platforms by scanning for *exposed* standable runs, so a deep block of tiles
  reports one ledge instead of one platform per buried row. That is the right
  call and it is well commented.
- **The test suite is unusually good for a project this size**: 6 GUT files
  covering the shipping map's route shape, the crouch-gate clearance envelope,
  one-way tiles, decorative-tile non-collision, tap-vs-charged jump apex, and
  a 512-line robot-rig suite. Several tests assert against the *real* level
  rather than a fixture, which is what catches bad authoring.
- **CI is complete**: clean Tiled reimport, GUT, Windows export, artifact
  upload. The `run_gut.py` cache-invalidation trick for external `.tsj` changes
  is a real trap correctly handled.

The gap is not architecture. It is **content volume and run-loop shape**: one
route, ~59.5 m, four platforms, one obstacle, one way to fail.

---

## 2. Bugs fixed in this change

| # | Severity | Area | Symptom |
|---|----------|------|---------|
| 1 | High | Perf/memory | Traversal trace grew unbounded |
| 2 | High | UX | `R` did nothing on the results screen |
| 3 | Medium | AI seam | `-1` failure penalty charged on every reward poll |
| 4 | Medium | Perf | World metrics deep-copied twice per physics frame |
| 5 | Medium | Visual | Sparks travelled with the robot |
| 6 | Medium | Audio | Up to 180 ms latency on jump/land sounds |
| 7 | Medium | Audio | Game SFX ignored the options menu's SFX slider |
| 8 | Low | Correctness | World queries broke under a transformed World node |
| 9 | Low | Hygiene | Dead art script describing geometry that no longer exists |

### 1. The traversal trace grew without bound
`game.gd` recorded a `sample` event **every physics frame** — 60 six-key
dictionaries per second, forever, with no cap. A five-minute session accrued
~18,000 dictionaries, then `export_data()` deep-copied the array and
`RunUnitSession.set_traversal_trace()` deep-copied it *again*, producing a
visible hitch at the exact moment of death.

Fixed by sampling on a 0.1 s cadence (`TRACE_SAMPLE_INTERVAL`) and giving
`RunUnitTraversalTrace` an explicit `MAX_SAMPLE_EVENTS` budget. Named events —
obstacle hits, the terminal record — bypass the budget, so an export still
explains how a run ended, and `dropped_samples` reports what was discarded
instead of losing it silently.

### 2. `R` did nothing on the results screen
The README documents `R: restart the authored route`. `RunUnitGame` reads it in
`_physics_process`, and `RunUnitDeathMenu.open_*()` sets `get_tree().paused =
true`. `Game` has no `process_mode` override, so it inherits `PAUSABLE` and
stops processing — the `is_terminal()` / restart branch in `_physics_process`
was unreachable dead code, and the shortcut was silently mouse-only at the one
moment a player most wants it.

Fixed by reading the shortcut on the results menu itself, which already runs
`PROCESS_MODE_ALWAYS`.

While there: `close()` hid the menu without releasing the pause it had taken,
so any non-button close path left the tree frozen. The menu now tracks whether
it *owns* the pause, so it releases its own and never steals one the pause menu
took.

### 3. The failure penalty was charged repeatedly
`consume_reward()` subtracted `1.0` whenever `_run_state == FAILED` — on
*every* call, not on the transition. An agent that polls reward after terminal
(a normal thing for a replay buffer to do) accrued `-1` per poll. Now paid once
per run and re-armed by `reset_run()`.

### 4. World metrics were republished every frame
`set_progress()` ran `_metrics.duplicate(true)` on emit and
`RunUnitSession.set_world_metrics()` deep-copied the result again — two dict
allocations per physics frame for a monotonic progress float nobody samples
that finely. Now broadcast only when progress moves `DIFFICULTY_PUBLISH_STEP`
(0.5%), plus an always-emitted 100% so completion is never missed. Roughly 200
emissions per run instead of 60/second.

### 5. Sparks travelled with the robot
`Feedback` is a `Node2D` child of `Player` and drew particles in its own local
space, so the whole burst was re-parented to the moving body every frame:
landing sparks slid along with the wheel instead of staying on the deck. Now
`top_level`, with bursts emitted at the player's world position.

### 6. Jump and landing sounds lagged behind the action
`_fill_audio_buffer()` filled *all* available frames of a 0.18 s
`AudioStreamGenerator` buffer every `_process` — with silence while idle. A
tone started after that queue and had to wait for it to drain, putting up to
180 ms between a jump and its sound. The buffer is now kept at a short idle
cushion (`IDLE_BUFFER_FRAMES`, ~12 ms) and only filled to the brim while a tone
is actually playing.

### 7. Game SFX ignored the SFX slider
`default_bus_layout.tres` defines `Music` and `SFX`, and the Maaack options
menu exposes sliders for both — but the only in-game audio source played on
`Master`. Turning SFX down did nothing; turning Master down took the music with
it. Now routed to `SFX`, with a `Master` fallback if the bus is missing.

### 8. World queries mixed global and local space
`get_platform_below_position()` correctly converted via `to_local()`, but
`get_platform_below()`, `get_upcoming_platforms()`, `get_semantic_value()` and
the fallback branch of `get_traversal_length()` treated world-space input as if
the World node sat at the origin. `game.gd`'s observation builder and
`scripted_controller.gd` compared tile-space geometry against
`player.global_position` the same way. This is latent today (World *is* at the
origin) but it is exactly the kind of thing that breaks silently the first time
a level is instanced under an offset parent — and there is already a test that
moves the World node.

All queries now take world space and convert internally. `get_semantic_value()`
resolves through the tile layer's own `to_local`/`local_to_map`, so it honours
every transform between the layer and the viewport. A new
`get_platform_surface_position()` returns world-space platform geometry for
observation and bot callers.

### 9. Dead art script
`scripts/world/maintenance_shaft_art.gd` (108 lines) is referenced by no scene,
script, or `.uid`. Worse, it is actively misleading: it defaults to
`route_length = 4864`, draws gap markers at x=3040–3584 and a completion beacon
at x=4232, in a map that is 90 tiles (2880 px) wide and whose Goal is at 2032.
Deleted. The equivalent dressing is authored in the Tiled `Art*` layers and in
`world.tscn`.

**New tests**: `tests/test_run_instrumentation.gd` (trace budget, one-shot
penalty, metrics throttling, world-space query contract) and
`tests/test_run_presentation.gd` (pause ownership, restart-while-paused,
world-space sparks).

---

## 3. Bugs and risks left open

These are real but each needs a product decision or a running editor to
validate, so they are documented rather than changed under the wire.

### A. The external-agent seam drops frames and fights the keyboard — Medium
Two separate problems in the same seam:

1. **Stale edge flags.** `RunUnitPlayerMotor` reads `_action.jump_pressed` /
   `jump_released` every physics frame (`player_motor.gd:88`, `:98`), but
   `apply_external_action()` sets the action once and it persists. An agent
   stepping at 10 Hz leaves `jump_pressed` true for six physics frames, re-arming
   the press buffer each one. Human and bot controllers don't hit this only
   because they rewrite the action every frame.
   *Fix:* have the motor consume the edge flags after reading them (clear
   `jump_pressed`/`jump_released` at the end of `_physics_process`), which makes
   "pressed" mean pressed-once regardless of caller cadence.
2. **`reset()` hands control back to the keyboard.** `reset_run()` sets
   `human_controller.active = true` and `_external_control = false`
   (`game.gd:93`, `:95`). Between an `Environment.reset()` and the next
   `apply_action()`, live keyboard input drives the robot — so a training run in
   a focused window is contaminated by whatever the operator is typing.
   *Fix:* make control mode sticky (an explicit `set_control_mode()`), and have
   `reset_run()` preserve it instead of forcing HUMAN.

### B. There is exactly one way to fail — Medium (design)
`obstacle_triggered` is declared with `@warning_ignore("unused_signal")`
(`static_world.gd:14`) and **nothing in the shipping level ever emits it**. The
crouch gate blocks you; it doesn't kill you. The only terminal failure is
`player.global_position.y > world.death_y`. So `_on_obstacle_triggered ->
_fail_run` is dead in practice, and the tutorial has no stakes beyond the two
gaps. Either wire hazards (semantic value 3 already exists in the tile contract
and is used in the POC fixture) or drop the signal.

### C. Input bindings are half in `project.godot`, half patched at runtime — Medium
`game.gd:_ensure_input_map()` builds bindings at runtime with `keycode`, while
`project.godot` binds with `physical_keycode`. `InputMap.action_has_event()`
never matches across those two, so every action gets a duplicate event
appended. More importantly, `move_left`/`move_right` have **no arrow-key events
in `project.godot`** — the arrow keys documented in the README exist only
because this runtime patcher adds them, so they are absent anywhere the game
scene hasn't loaded, and they can't be remapped through the options menu's
input tab.
*Fix:* move every binding into `project.godot` using `physical_keycode`, delete
`_ensure_input_map()`/`_add_key_action()` (17 lines), and let the existing
options-menu remapper own input.

### D. Best distance never survives the process — Low
`RunUnitSession.best_distance` is in-memory only. The HUD promises `BEST` and
the results screen prints it, but quitting resets it to 0. A `user://` save of
one float (plus, later, per-route best times) is a small change with
disproportionate value for a score-driven game.

### E. The level selector ignores its own argument — Low, latent
`_select_sector(level_index)` immediately overwrites its parameter with
`_selected_index = PLAYABLE_LEVEL_INDEX` (`run_unit_level_selector.gd:77`).
Harmless while one route exists; it becomes a confusing bug the day route 2
ships. `PLAYABLE_LEVEL_INDEX` is also duplicated in `game.gd:17` — these should
be one level registry.

### F. Menu button tweens stack — Low
`run_unit_main_menu.gd:44` calls `create_tween()` on every `button_down`,
`button_up`, `mouse_exited` and `focus_exited` without killing the previous
one. Releasing the mouse off a button can start three competing tweens on the
same `scale` property. Cache the tween per button and `kill()` before
retweening.

### G. Camera has no limits — Low
`player.tscn`'s Camera2D has a +309 px lead and smoothing but no `limit_*`. At
the Goal (x=2032) the right edge of the view reaches ~2821 px while
`world.tscn`'s `Backdrop`/`FloorGlow` polygons stop at 2560, so the last stretch
of the route shows a different shade behind it. Set camera limits from the map
bounds (they are available from `static_world`) or widen the polygons.

### H. Observation redundancy — Low
`get_upcoming_platforms()` returns the platform the player is *standing on* as
element 0 (`end_x >= tile_x`). `_update_debug()` compensates by reading
`upcoming[1]`, but `get_observation()` does not — so slot 0 of the AI
observation is usually the current platform, not a lookahead. Worth deciding
deliberately before anyone trains on it.

### I. Distance is X-only — Low, forward-looking
`ScoreManager.record_position()` measures `max(world_x - spawn_x)`. Fine for a
strictly rightward route; it silently breaks on any level with backtracking, a
vertical shaft, or a loop. Worth generalising to path progress before level 2
is authored rather than after.

---

## 4. Suggested next steps

Ordered by value per unit of effort.

**Now — finish the slice (small, mechanical)**
1. Consolidate input into `project.godot` and delete the runtime patcher (C).
2. Persist `best_distance` to `user://` (D).
3. Make control mode sticky and consume action edge flags in the motor (A).
4. Camera limits from map bounds (G).

**Next — give the route stakes (this is what the build most lacks)**
5. Wire one real hazard. The semantic contract already reserves value 3 for
   hazards and the POC fixture already paints one; `obstacle_triggered` already
   exists and is already handled end-to-end in `game.gd`. This is mostly
   authoring plus a small Area2D-per-hazard-run builder in `static_world.gd`,
   mirroring `_ensure_completion_trigger()`.
6. Add a fail/retry loop that doesn't cost a full scene reload. The results
   screen currently calls `SceneLoader.reload_current_scene()` while
   `reset_run()` — a complete, correct, much cheaper reset — already exists and
   is used by the in-run `R`. Point the button at `reset_run()` and the retry
   becomes instant.
7. A run timer. The route is 59.5 m and the game is about movement; a
   best-time-per-route metric gives replay value that distance alone cannot,
   because distance is capped by the Goal.

**Then — make a second level cheap to author**
8. Turn the level registry into data (id, display name, `.tmj` path, tagline)
   and drive both `run_unit_level_selector.gd` and `game.gd` from it, removing
   the duplicated `PLAYABLE_LEVEL_INDEX` and the ignored-argument bug (E).
   `set_level_profile()` is already the hook, currently a no-op.
9. Generalise progress from X-distance to path progress (I) *before* authoring
   level 2, so the second map isn't constrained to be another left-to-right
   corridor.

**Ongoing — keep the seams honest**
10. Add a GUT test that drives the *scripted bot* end to end on the shipping
    map and asserts it reaches the Goal. It is the cheapest possible
    "is the level still completable" regression test, it exercises the whole
    controller→motor→world loop, and the bot already exists.
11. The `Environment` facade has no test at all. A short test that resets,
    steps a fixed discrete action sequence, and asserts observation shape and
    reward monotonicity would protect the AI contract the README advertises.

---

## 5. Things deliberately not changed

- **The player motor's feel constants.** Charge curve, coyote time, and buffer
  windows are tuned and pinned by apex tests; changing them without playing the
  game would be guesswork.
- **The Tiled/YATI pipeline and the robot rig.** Both are explicitly fenced off
  in `AGENTS.md`, both are well covered by tests, and neither showed a defect.
- **`get_upcoming_platforms()` semantics** (H) — changing what slot 0 means is
  an observation-space change, which is the AI client's call, not a drive-by fix.
