# RUN//UNIT campaign and release checklist

Last refreshed: 2026-10-05

The playable campaign is Calibration → Factory Escape → Recovery → Beacon 9. The target first-playthrough time is roughly 7–9 minutes; see `StorylineSketch.md` for story and route intent.

## Completed

- [x] Author and connect all four playable routes and their campaign progression.
- [x] Add non-colliding clearance treatments and tune the later-route landing gaps; preserve the Tiled/YATI world contract. (`f0e8ed2`)
- [x] Retry a failed run in place through the existing run reset, retaining checkpoint recovery; a completed-result redeploy starts at spawn with fresh route metrics and telemetry. (`a29e110`, `9de36d0`)
- [x] Add deterministic, resettable alpha pulses to electrical warning art and the Recovery monitor; focused presentation tests pass. (`a33e6bf`)
- [x] Inspect a live Recovery warning/active cycle and the monitor pulse: the warning stripe varied from about 0.72–0.97 alpha and the monitor status from 0.78–0.99, with RGB unchanged and the warning silhouette clear.
- [x] Add default gamepad bindings for movement, jump, crouch, menu accept, and cancel; verify the actions in the running game. (`b8e7253`)
- [x] Probe live inputs in Godot: keyboard movement reached the Recovery arc and took one damage before falling; controller A retried to spawn, and the left stick moved toward the same hazard. Full route chains remain open.
- [x] Run the built-in scripted campaign traverse with an isolated fresh progress file; it completed routes 0–3 with 1 damage event and 1 failed attempt.

## Remaining before release

- [x] Run `python tools/level_kit.py check-all assets/tiled/levels --json`; all four maps pass with zero errors and all goals reachable.
- [x] Run `python tools/run_gut.py` after the latest gameplay, scene, and input-map changes; exit code 0.
- [x] Run `python -m unittest discover -s tools/tests -v`; 49 tests pass.
- [x] Run Godot 4.7.1 project/import validation; the canonical runner completed its fresh `--import` stage.
- [x] Inspect `git diff --check` and repository status; generated imports were restored and the JSON map report is ignored.
- [ ] Play through Calibration, Factory Escape, Recovery, and Beacon 9 with keyboard controls. Watch hazard warning/active timing, checkpoint recovery, gate readability, and the edited jumps.
- [ ] Complete the full campaign with a controller. The default action bindings and selector/pause input have been probed; route traversal remains to be checked.
- [ ] Record any observed issues and fixes. Re-run the affected checks after fixes.
- [ ] Confirm the first-playthrough pacing remains near the 7–9 minute story target; update the visual gameplay report with the new route pass.
- [ ] Ship the reproducible Windows Desktop artifact from GitHub Actions after all checks pass.
