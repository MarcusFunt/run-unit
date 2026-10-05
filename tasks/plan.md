# Implementation Plan: RUN//UNIT Campaign Polish and Release

## Objective

Deliver a complete four-route campaign with readable authored hazards, responsive checkpoint retries, and a reproducible Windows release. The first-time campaign target is roughly 7–9 minutes, as described in `StorylineSketch.md`.

## Current state

- **Campaign content:** Calibration, Factory Escape, Recovery, and Beacon 9 are authored and connected in campaign order.
- **Route polish:** Non-colliding clearance visuals and tuned landing gaps are present in the later routes (`f0e8ed2`). The authored-world reachability contract remains enforced by `tools/level_kit.py`.
- **Retry flow:** A failed run resets in place and resumes from the active checkpoint. Completed-result redeploy clears prior route timing/damage counters and opens a new telemetry attempt; completion clears the checkpoint so retry starts at spawn (`a29e110` plus the retry-boundary fix).
- **Ambient motion:** Electrical warning art and the Recovery monitor use a deterministic pulse that restores its authored phase on world reset (`a33e6bf`). Focused presentation tests and the complete GUT suite pass; an in-game visual pass remains.
- **Controller input:** Default gamepad movement, jump, crouch, menu accept, and cancel bindings are now present (`b8e7253`). Runtime probes confirmed movement, jump, crouch, selector navigation/deploy, and pause; full route traversal with both control schemes remains open.
- **Playtest and release evidence:** The full keyboard/controller campaign pass and current release checks remain open. The September visual report predates the October route changes.

## Work sequence

### 1. Close the current polish pass

- [x] Retry a failed run through `RunUnitGame.reset_run()` without replacing the scene.
- [x] Cover checkpoint retries and post-completion spawn retries in GUT.
- [x] Pulse the electric arc warning stripe, active glow, and Recovery monitor using a resettable, alpha-only script.
- [x] Cover pulse behavior and non-collision in focused presentation tests.
- [x] Add gamepad defaults to the existing action map and cover them with input-map regression assertions.
- [x] Run the complete gameplay and tooling suites after the final polish changes; GUT exits 0 and 49 tooling tests pass.
- [ ] Inspect the rendered electrical warning and Recovery monitor across their pulse cycle.

### 2. Playtest the campaign

- [ ] Complete Calibration, Factory Escape, Recovery, and Beacon 9 using keyboard input.
- [ ] Complete the same route chain using a controller.
- [x] Run the built-in scripted controller through the complete route chain; it reported routes `[0, 1, 2, 3]`, 1 damage event, 1 failed attempt, and exited successfully.
- [ ] Check hazard timing, checkpoint recovery, clearance readability, and the October route edits in both passes.
- [ ] Record route completion time and update the visual gameplay report; compare the first-time run with the 7–9 minute target.

### 3. Run release checks

- [x] Run `python tools/level_kit.py check-all assets/tiled/levels --json`; all four maps pass with reachable goals and no soft locks.
- [x] Run `python tools/run_gut.py` with Godot 4.7.1; exit code 0 after the fresh import.
- [x] Run `python -m unittest discover -s tools/tests -v`; 49 tests pass.
- [x] Run `git diff --check` and review repository status; generated imports were restored, and the map report stays ignored.
- [ ] Publish the Windows Desktop artifact from the repository’s GitHub Actions workflow.

## Architecture and guardrails

- `RunUnitPlayerMotor` owns movement physics; keyboard and gamepad bindings, plus the scripted controller, feed the same player action interface.
- `RunUnitStaticWorld` reads the authored Tiled/YATI world and propagates `reset_level_state()` to resettable set pieces.
- `RunUnitCampaign` owns route copy and scene paths. Keep route order aligned with `StorylineSketch.md`.
- Keep platform geometry in Tiled. Use `tools/level_kit.py` for map edits and validate a changed map before GUT.
- Preserve movement constants, health, input bindings, existing checkpoint semantics, and the current project/menu framework.
- Do not commit `.godot/`, new import sidecars, local exports, screenshots, logs, or secrets.

## Completion criteria

- All four routes are playable in campaign order with both control schemes.
- Retry and ambient reset behavior pass GUT; authored maps pass the level-kit reachability check.
- Gameplay and tooling suites pass, and the Windows artifact is produced by the documented CI workflow.
- The current visual report and roadmap describe the campaign that is actually in the repository.
