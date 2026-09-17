# Hazard System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reusable static and dynamic hazards, three-hit player health, knockback/hitstun, health HUD feedback, and checkpoint-safe resets without changing campaign architecture.

**Architecture:** Static spike-like hazards come from semantic value `3` and are converted by `RunUnitStaticWorld` into lethal Area2D regions. Dynamic hazards are reusable Godot Area2D scenes whose exported properties are compatible with YATI `instance` objects. `RunUnitPlayerHealth` owns damage/i-frames; `RunUnitPlayerMotor` owns knockback/hitstun; `RunUnitGame` alone converts health depletion into the existing failure flow.

**Tech Stack:** Godot 4.7.1, GDScript, GUT 9.7.1, Tiled/YATI, Python repository tooling.

**Spec:** `docs/superpowers/specs/2026-09-17-hazard-system-design.md`

## Global Constraints

- Default/max HP is exactly 3.
- Normal damage is 1 HP and grants 0.75 seconds of global invulnerability.
- Lethal hazards deplete health immediately.
- Retry restores full health but leaves checkpoint selection entirely to existing `RunUnitSession` behavior.
- Dynamic hazards use deterministic cycle/reset behavior and implement `reset_level_state()`.
- Do not refactor campaign routing, replace `RunUnitStaticWorld`, rewrite YATI, redesign checkpoints, add combat/enemies, or rebalance campaign levels in this pass.
- Follow test-first discipline and run Python tooling tests plus `python tools/run_gut.py` before completion.

---

### Task 1: Player health and motor hit reaction

**Files:**
- Create: `scripts/player/player_health.gd`
- Modify: `scenes/player.tscn`
- Modify: `scripts/player/player_motor.gd`
- Test: `tests/test_hazard_system.gd`

**Interfaces:**
- Produces: `RunUnitPlayerHealth.current_health`, `max_health`, `damage(amount, lethal=false) -> bool`, `reset_health()`, `damaged(current_health, max_health)`, `depleted`, and `RunUnitPlayerMotor.apply_knockback(impulse, hitstun_seconds)`.

- [ ] Add GUT tests that instantiate `scenes/player.tscn` and assert a `Health` child exists with 3/3 HP, normal damage removes one HP, i-frames reject immediate second damage, lethal damage depletes, reset restores 3 HP, and the motor exposes functional knockback/hitstun.
- [ ] Run the test through CI and confirm it fails because the health component/API does not yet exist.
- [ ] Implement `RunUnitPlayerHealth` with a 0.75-second invulnerability countdown in `_physics_process`, accepted-hit/depleted signals, and reset behavior.
- [ ] Add `Health` to `player.tscn` and add `_hitstun_remaining`, `apply_knockback()`, hitstun-aware horizontal movement, and hitstun clearing in `reset_motor()`.
- [ ] Re-run CI and keep the focused tests green before continuing.

### Task 2: Game, HUD, and player feedback integration

**Files:**
- Modify: `scripts/gameplay/game.gd`
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/hud.tscn`
- Modify: `scripts/player/player_feedback.gd`
- Test: `tests/test_hazard_system.gd`

**Interfaces:**
- Consumes: `RunUnitPlayerHealth.damaged/depleted/reset_health()`.
- Produces: `RunUnitHud.set_health(current, maximum)` and `RunUnitPlayerFeedback.play_damage_feedback()`.

- [ ] Add tests proving game reset restores health, depletion enters the existing failed state, and HUD health segments reflect 3/2/1/0 HP.
- [ ] Confirm the new tests fail before production edits.
- [ ] Connect `game.gd` to `$Player/Health`; call `reset_health()` from `reset_run()`; route `depleted` to `_fail_run()`; update HUD from health signals.
- [ ] Add three compact HUD cells and implement `set_health()` by toggling filled/empty styling or visibility.
- [ ] Add a brief damage spark/tone entry point in `player_feedback.gd`; call it on accepted damage without coupling feedback back into health logic.
- [ ] Re-run focused and full GUT tests.

### Task 3: Common dynamic hazard behavior

**Files:**
- Create: `scripts/hazards/hazard_area.gd`
- Create: `scripts/hazards/timed_hazard.gd`
- Create: `scenes/hazards/laser_gate.tscn`
- Create: `scenes/hazards/electrical_arc.tscn`
- Create: `scenes/hazards/steam_vent.tscn`
- Create: `scenes/hazards/saw.tscn`
- Create: `scenes/hazards/crusher.tscn`
- Test: `tests/test_hazard_system.gd`

**Interfaces:**
- `RunUnitHazardArea` exports `active`, `damage`, `lethal`, `knockback`, `hitstun_seconds`; tracks one exposure per overlapping player; `set_active(value)` resets exposure on deactivation and re-hits overlapping players on a new activation.
- `RunUnitTimedHazard` adds `cycle_seconds`, `active_seconds`, `phase_offset_seconds` and deterministic `reset_level_state()`.

- [ ] Add tests for active entry, continuous-contact single hit, exit/re-entry, off/on while overlapping, lethal contact, knockback dispatch, and deterministic reset.
- [ ] Confirm failures before adding hazard scripts/scenes.
- [ ] Implement `hazard_area.gd` around `body_entered/body_exited` and `get_overlapping_bodies()` on activation.
- [ ] Implement deterministic timed cycling and reset.
- [ ] Add simple readable project-native scenes for laser, electric, steam, saw, and crusher; use exported properties rather than per-level scripts.
- [ ] Re-run GUT tests.

### Task 4: Semantic static hazards

**Files:**
- Modify: `scripts/world/static_world.gd`
- Test: `tests/test_hazard_system.gd`
- Test fixture: `tests/fixtures/hazard_semantic_world.tscn` or a small `.tmj` fixture if required by YATI.

**Interfaces:**
- Adds `SEMANTIC_HAZARD = 3` and generated child container `SemanticHazards` containing non-solid lethal Area2D regions.

- [ ] Add a test fixture with adjacent semantic hazard cells and assert the world creates a lethal detector without adding a solid body.
- [ ] Confirm the test fails because semantic hazard cells are currently ignored at runtime.
- [ ] Add hazard-cell scanning and merge each horizontal contiguous run into one rectangular `RunUnitHazardArea` region positioned through the semantic TileMapLayer transform.
- [ ] Keep route extraction restricted to solid/one-way cells exactly as today.
- [ ] Re-run level tests and full GUT.

### Task 5: YATI instance authoring proof and final verification

**Files:**
- Create: `tests/fixtures/hazard_instance.tmj`
- Create or modify: `tests/test_hazard_yati.gd`
- Optionally modify: `tools/tests/test_level_kit_lossless.py` only if the fixture exposes a preservation regression.

**Interfaces:**
- Proves Tiled object class `instance` + file property `res_path` produces a configured hazard scene through YATI.

- [ ] Add an authored Tiled fixture whose `Hazards` object layer instances `res://scenes/hazards/laser_gate.tscn` and overrides at least `damage` and one timing property.
- [ ] Confirm the integration test fails before any fixture-specific correction.
- [ ] Make only the minimum authoring/schema correction needed for YATI to import the scene and properties; do not modify YATI unless a verified importer defect is found.
- [ ] Run `python -m unittest discover -s tools/tests -v`.
- [ ] Run `python tools/run_gut.py` through CI with forced Tiled reimport.
- [ ] Verify Windows export succeeds in CI.
- [ ] Keep the PR draft until local visual/playtest validation is possible; do not claim visual polish while both remote machines are offline.