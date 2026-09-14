# Menu player-path validation

Date: 2026-09-14
Build: Godot 4.7.1 stable

## Scope and result

Automated player-path validation passed. The tested path is **Main Menu → Route Deployment → Gameplay**. The Main Menu and Route Deployment confirmations were sent as real Space-key events to the focused controls; the final screenshot confirms the gameplay scene is active.

The route selector and Options screens were also rendered at the target 960 × 540 viewport. Their UI reports found no zero-size or off-screen visible controls. The only former overlap report was the intentional full-screen backdrop behind the menu; it is excluded from failure criteria.

## Passed checks

| Check | Evidence | Result |
| --- | --- | --- |
| P1 control list | Only Move Left, Move Right, Jump, Crouch, and Restart are shown; developer debug input is absent. | Passed |
| P1 route truthfulness | One authored route is playable; the other seven are labelled and styled as offline. | Passed |
| P1 activation guidance | Selector wording is `ENTER / SPACE DEPLOY`; Space activates the focused available route. | Passed |
| Consolidated start path | Main Menu → selector → gameplay operates without the retired duplicate title screen. | Passed |
| Automated regression tests | GUT: 7 tests, 22 assertions. | Passed |
| Runtime smoke | Main menu ran in a real Godot window for 60 frames with no diagnostics. | Passed |
| Project loading | 276 project files loaded and 99 scenes instantiated; no static load or parse failures. | Passed |

## Artefacts

- `artifacts/player_validation/route_selector.png` — final route-selector composition.
- `artifacts/player_validation/options.png` — player-facing Controls tab.
- `artifacts/player_validation/full_start_flow.png` — end state after the full keyboard start flow.

## Known validation-tool noise

Godot's project-wide checker exits non-zero because of resource-cleanup diagnostics emitted at engine shutdown and a checker-owned `set_script` message. The checker itself reports 276 files loaded, 99 scenes instantiated, and zero failed loads. It also reports the pre-existing unused `obstacle_triggered` signal in `scripts/world/static_world.gd`; none of these diagnostics originate from the menu changes.

This is automated validation, not a moderated usability study. A human playtest is still needed to assess comprehension, pacing, and accessibility beyond the verified interactions.
