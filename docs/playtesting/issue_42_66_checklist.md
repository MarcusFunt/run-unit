# Issues #42–66: visual review and playtest record

## Review setup

- Primary capture: Godot desktop build, 960×540, Compatibility renderer. The browser check is a separate optional pass; record browser, OS, GPU/driver and viewport if run.
- Walk Calibration, Factory Escape, Recovery and Beacon 9. Take screenshots at spawn, every authored transition/landing, every crouch cue and gate, every hazard warning, module pickup, Beacon calm/interior and each destination reveal. Include one frame before and during each timed warning.
- For each suspected support edge, compare the cyan rim with the semantic support layer and the player's actual collision/landing. Record false-positive rims, missing support rims, invisible collisions, and falls at edges that looked walkable. Inspect decorative layers for collision.
- At each gate, approach while standing, then crouch and cross. Record blocked/admitted and whether the cue was visible before commitment. Confirm decorations do not stop, lift or damage the player.
- At each route start and after damage, ask the player to identify current health out of three. At checkpoints ask them to describe what activated and where a retry will start. At the Recovery cradle ask what was collected and what the next objective means. At the Beacon ask what action starts ignition and when to release.
- Leave controls unexplained. Give only: “Play this route as far as you can. Say what you think is happening when something is unclear.” Do not point at HUD elements or explain a mechanic. Record the first unprompted interpretation before asking a neutral follow-up.

## Acceptance measures and telemetry

| Issue | Observe and record | Instrumentation / evidence |
| --- | --- | --- |
| #42 | Every apparent landing edge: false support / missing support, missed landing, fall; any decoration with collision | Screenshot per edge; semantic support map; `jump_launched`, `damage`, `checkpoint_respawn` and route outcome JSONL events |
| #43 | Identifies the three-cell health display before their second damage event | HUD `HEALTH n / 3`; record first identification time and whether before damage 2 |
| #44 | Recognizes each checkpoint and correctly predicts where the next respawn will be | `checkpoint_activated`, `checkpoint_respawn`; ask before death; target is 5/5 |
| #45 | After Calibration, deliberately demonstrates low, medium and full jumps, including the full-charge lock | `charge_started`, `charge_stage` with ratio, `charge_released`, `jump_launched`; target is 4/5 |
| #46 | Sees the intended landing before committing; record any death primarily caused by camera-hidden geometry | Capture at each camera lookahead transition; target is zero camera-caused blind-drop deaths |
| #47 | Recognizes and uses required crouch interactions; standing is blocked, crouch passes | Screenshot at cue/gate; `crouch_started` / `crouch_ended` duration; target is 4/5 |
| #48 | Identifies the Reserve Depot assembly as an objective rather than a hazard and explains its purpose | Screenshot before/after pickup; ask for identity/purpose; `module_acquired` position; target is 4/5 |
| #53 | Performs Calibration's required actions in order, including the full-charge lesson and crouch gate | Route completion; charge, jump and crouch events in order |
| #54 | Completes Factory's final-third sequence; record retries and perceived pacing without adding route length | Per-step screenshot and route trace; completion/time/damage; player pacing rating (1–5) |
| #55 | Pickup occurs at 60–65% route progress and leaves a short, legible escape | `module_acquired_progress` records world x, ratio and remaining distance; record pickup-to-exit time |
| #56 | Understands the Beacon hazard-to-calm transition, spots the destination, and completes the final interaction | Hazard phase events and screenshots; ask player to identify destination; `beacon_charge_released` ratio and outcome |
| #57 | Each StoryZone effect occurs once per run, including after reset/retry | `story_zone` / `story_effect` event names and counts |
| #58 | Sees/hears a warning before every damaging hazard state | `hazard_phase` transition sequence; record warning lead time and missed cues |
| #59 | Recognizes hazard, ambience and objective sounds without masking speech or cues | Record route/event audio and player recognition; sound event and phase logs |
| #60 | Holds the Beacon interaction and releases only when full; an early release is safe and retryable | `beacon_charge_released` ratio; early-release retry and completed interaction |
| #61 | Understands short narrative messages without stopping or confusing the objective | Ask for a short retell at each route end; record misunderstood terms/objective changes |
| #62 | Finds and correctly reads elapsed/best time, distance, damage, checkpoint activations and recoveries | Results HUD and persisted progress file; record read/interpretation accuracy |
| #63–66 | Checklist/instrumentation used; recurring findings get one corrective iteration; fresh-save campaign completes; visual review works across configurations | This document, JSONL logs, before/after screenshots, fresh-save result, device/browser metadata |

Instrumentation is enabled by launching Godot with `--playtest`. It writes one JSONL file per route attempt beneath `user://run_unit_playtests/`, with the route index and attempt number in each record. Retries receive their own start/end events while cumulative route time, damage and checkpoint counts carry forward. Events include route progress, hazard phases, charge/release, crouch duration, module acquisition progress, checkpoint activity and run metrics. `--fresh-save` stores progress in a separate `user://run_unit_fresh_progress.cfg` profile for a clean campaign pass.

## Formative acceptance targets from issues #63–64

Record observed behavior per participant, then report the numerator and denominator (for example `4/5`). Do not present a five-person sample as statistically representative.

| Measure | Acceptance target | Evidence to retain |
| --- | --- | --- |
| Calibration completed without help | At least 4/5 | Route completion and any help given |
| Low / medium / full charge demonstrated | At least 4/5 | Charge ratios, jumps selected and lock cue observed |
| Health found before second damage event | At least 4/5 | Identification time and damage-event timestamps |
| Expected checkpoint respawn named | 5/5 | Answer recorded immediately after checkpoint activation |
| Mistaken attempts to stand on background geometry | No more than 1 per player | Position/screenshot and whether the attempt caused a fall |
| Death primarily caused by camera-hidden landing | 0 | Death location, view before commitment and participant behavior |
| Hazard safe window predicted after one cycle | At least 4/5 | Prediction before crossing and actual phase at crossing |
| Crouch used at intended interactions | At least 4/5 | Gate result and crouch event interval |
| Module recognized as mission objective | At least 4/5 | Unprompted explanation before/after acquisition |
| Campaign direction / next objective understood | At least 4/5 | Short route-end retell and Recovery objective interpretation |
| Ending understood as power restoration | At least 4/5 | Short post-ending retell |

The corresponding primary issue records are [#42](https://github.com/MarcusFunt/run-unit/issues/42), [#43](https://github.com/MarcusFunt/run-unit/issues/43), [#44](https://github.com/MarcusFunt/run-unit/issues/44), [#45](https://github.com/MarcusFunt/run-unit/issues/45), [#46](https://github.com/MarcusFunt/run-unit/issues/46), [#47](https://github.com/MarcusFunt/run-unit/issues/47), [#48](https://github.com/MarcusFunt/run-unit/issues/48), [#63](https://github.com/MarcusFunt/run-unit/issues/63) and [#64](https://github.com/MarcusFunt/run-unit/issues/64).

## Unfamiliar-player session records

Target: five people who have not played RUN//UNIT and have not been told its controls or mechanics. Use one session per person. Do not enter automated runs or developer sessions as participants. Keep their exact wording in notes and mark not-observed measures `NO` rather than guessing.

| Session | Date / build / device | Routes reached | Control explanation given? (must be no) | Main unexpected behavior / direct quote | Measures missed | Repeat finding? |
| --- | --- | --- | --- | --- | --- | --- |
| P01 | Not run | — | — | — | — | — |
| P02 | Not run | — | — | — | — | — |
| P03 | Not run | — | — | — | — | — |
| P04 | Not run | — | — | — | — | — |
| P05 | Not run | — | — | — | — | — |

Per-person notes should include the acceptance measures above, route completion and retry counts, observed interpretations, and timestamped references to screenshots/telemetry. Store consented recordings separately from the repository.

## Corrective iteration

No unfamiliar-player findings have been recorded yet, so no finding-driven correction is claimed. Once sessions are complete, select the clearest issue repeated by at least two of five players, change only the relevant cue/interaction, then rerun that measure with new or returning players. Record evidence before and after:

| Finding repeated by | Change | Before evidence | After evidence | Retest date/build |
| --- | --- | --- | --- | --- |
| Pending real sessions | Pending | Pending | Pending | Pending |

## Visual review and release sign-off

Reviewed on 2026-09-30 with Godot 4.7.1 desktop, Compatibility renderer, Intel Iris Xe Graphics. The capture harness rendered 70 frames at 960×540 and again at 1280×720: all 61 authored platforms, all seven crouch-gate approaches, Recovery after pickup, and Beacon at full charge. Local PNGs and per-run logs are in the ignored `.godot/issue_42_66_visual_review/` and `.godot/issue_42_66_visual_review_1280x720/` folders; neither is a release artifact. The Godot capture run exited successfully with no script errors or warnings.

Across the captured platforms, cyan top rims coincide with authored support surfaces; no apparent cyan support was found over a background-only ledge. Semantic collision checks confirm decorative layers do not collide. Automated tests confirm all seven crouch gates block standing and admit crouching, and each gate has a visible hanging-obstacle silhouette. The Calibration approach shot exposed a clipped `HOLD THROUGH THE GATE` instruction; its sign moved right and a test now checks that the text fits inside the 960×540 view at the approach point. Health remains isolated and legible, the full-charge lesson is distinct from the health display, and Beacon's charge panel does not overlap its objective. Recovery's pickup frame shows the module mounted, shutdown treatment, and updated exit objective. Beacon's exterior keeps the city destination visible during the full-charge interaction. Checkpoint recognition, health recognition, charge comprehension, background-geometry mistakes, hazard prediction and module recognition remain unmeasured with unfamiliar players.

| Route / configuration | 960×540 capture set | Landing edges / collision | Crouch gates | Health / checkpoint / charge / module | Reviewer / date |
| --- | --- | --- | --- | --- | --- |
| Calibration / desktop | 6 frames per viewport | Cyan rim follows support; decoration-only collision test passes | 1 gate; sign fully visible; standing blocked / crouch passes | Health and full-charge cue visible; recognition unmeasured | Automated visual review / 2026-09-30 |
| Factory Escape / desktop | 17 frames per viewport | Cyan rim follows support; decoration-only collision test passes | 3 gates; standing blocked / crouch passes | Health visible; recognition unmeasured | Automated visual review / 2026-09-30 |
| Recovery / desktop | 21 frames per viewport, including pickup | Cyan rim follows support; art remains non-colliding | 2 gates; standing blocked / crouch passes | Checkpoint markers, mounted pickup, shutdown state and exit objective visible; recognition unmeasured | Automated visual review / 2026-09-30 |
| Beacon 9 / desktop | 26 frames per viewport, including 100% charge | Cyan rim follows support; art remains non-colliding | 1 gate; standing blocked / crouch passes | Health, carried module, charge UI and city destination visible; recognition unmeasured | Automated visual review / 2026-09-30 |
| Second viewport / same desktop | 1280×720 on the same Intel Iris Xe system | Same visual checks | Same route gates | UI remains separated at larger viewport | Automated visual review / 2026-09-30 |
| Additional browser/device | Not available in this environment | Pending | Pending | Pending | Not run |

## Fresh-save campaign run

Passed on 2026-09-30 using Godot 4.7.1 desktop, Compatibility renderer, Intel Iris Xe Graphics. The separate fresh profile was cleared before launch. The process logged `DEMO_CAMPAIGN_COMPLETE completions=1 routes=[0, 1, 2, 3] damage=1 failures=1`, then exited normally. No route was skipped. Recovery's first attempt failed after one damage event; the retry resumed at its checkpoint and completed. This automated controller run verifies route handoff, checkpoint recovery, module delivery, Beacon completion and progress persistence; it does not count as an unfamiliar-player session.

| Route | Outcome / cumulative time | Damage / checkpoint recoveries | Verified telemetry |
| --- | --- | --- | --- |
| Calibration | Completed / 6.998 s | 0 / 0 | Required actions reached the exit |
| Factory Escape | Completed / 33.107 s | 0 / 0 | Final crusher crossed; route length 260.46 m |
| Recovery | Completed on attempt 2 / 48.952 s | 1 / 1 | Module at x=7,808 (61.917%); 4,704 px remained; exit completed |
| Beacon 9 | Completed / 55.130 s | 0 / 0 | Final release at 100%; route length 477.41 m |

The fresh profile `%APPDATA%\Godot\app_userdata\RUN--UNIT\run_unit_fresh_progress.cfg` contains best-time and best-distance records for route indices 0–3 and final Beacon metrics. Attempt JSONL records are under `%APPDATA%\Godot\app_userdata\RUN--UNIT\run_unit_playtests\`, including distinct Recovery files for its failed first attempt and completed checkpoint retry. The Recovery retry log contains the module-progress event and the completed `run_finished` event with cumulative time, damage and checkpoint counts.

Unfamiliar-player sessions P01–P05 and the finding-driven corrective iteration remain pending. The additional browser/device pass was not available; both captured viewport sizes used the same desktop GPU. Automated checks and rendered captures do not substitute for those human observations.
