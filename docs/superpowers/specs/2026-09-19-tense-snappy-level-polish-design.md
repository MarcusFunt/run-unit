# Tense, Snappy Level Polish — Design

## Intent

Make RUN//UNIT a little more tense and alive without turning it into a
precision platformer, score chase, or set-piece-heavy action game. The current
industrial look, basic movement model, three-health pressure, authored story
beats, and sparse HUD remain the foundation.

The desired player experience is a readable near-miss or hit followed by a
quick return to motion. Route geometry should ask a little more of a player
who has learned the tutorial, but a normal playthrough must never depend on
pixel-perfect input or unexplained rules.

## Non-goals

- No score, timer, combo, ranking, collectible, enemy, or new player ability.
- No global reduction to jump height, horizontal air control, coyote time, or
  input buffering.
- No large scripted destruction sequence, moving transfer-line set piece, or
  new route.
- No added persistent HUD text or instruction panels.
- No changes to the Tiled/YATI pipeline or the player-motor architecture.

## Player-facing changes

### Slightly firmer authored routes

Calibration stays unchanged and consequence-free. Factory Escape, Recovery,
and Beacon 9 each receive a small number of one-cell gap extensions in existing
open traversal stretches. The chosen transitions must be visually clear,
outside story reveals, clear of checkpoint respawns, and compatible with their
existing jump type. The authored map remains the source of truth.

The Level Kit must still classify every Spawn-to-Goal route transition as
`comfortable`; no new `tight`, `near_perfect`, or `full_charge` classification
is acceptable. Existing crouch and charged-jump lessons remain intact.

### Immediate recovery

The death-menu retry action resets the active `RunUnitGame` in place rather
than loading the scene again. It must keep the session's current route and
furthest checkpoint, restore three health, respawn the player through the
existing `reset_run()` flow, reset dynamic level state, and release the pause
owned by the result menu. Menu return and post-completion behaviour are not
changed.

### Crouch readability

Every gameplay crouch ceiling gets a matching foreground clearance treatment:
a dark, continuous low overhang with a high-contrast amber trim. It makes the
head-clearance boundary legible at a glance and visually differentiates it from
background structure. The treatment communicates only the physical constraint;
it does not add labels or prompts. It must not introduce collision beyond the
authored `Obstacles` layer.

### Restrained world response

Existing hazards and major route landmarks gain low-cost visual life that is
consistent with the established cyan/teal and amber palette: intermittent
warning-light pulses, small energy flickers, or a limited steam/machinery
motion. Effects are local to existing scenery and hazards, never obstruct the
player silhouette, and do not create new damage sources or decision text.

## Implementation boundaries

Gameplay reset work belongs in the existing game/results-menu seam. Visual
motion belongs in reusable level-side or hazard-side presentation components.
Geometry and clearance art remain in the authored Tiled maps and their level
wrappers; decorative layers must remain non-colliding.

Likely production targets are:

- `scripts/ui/run_unit_death_menu.gd` and the game/menu integration for retry.
- The existing player/game tests for restart, checkpoint, health, and pause
  ownership.
- `assets/tiled/levels/level_01_factory.tmj`,
  `assets/tiled/levels/level_02_recovery.tmj`, and
  `assets/tiled/levels/level_03_beacon.tmj` for selected geometry and visual
  clearance treatments.
- The matching level wrappers and existing hazard/feedback presentation for
  local environmental motion.

## Acceptance criteria

1. A failed run retries without a scene reload, at the current checkpoint when
   one exists, with full health and reset level state.
2. The tutorial is unchanged; the three later authored maps pass
   `level_kit check`, have no unreachable ledges or soft locks, and retain only
   comfortable route classifications.
3. Crouch ceilings in shipping routes are visibly distinct from background art
   and retain their standing-blocked/crouched-passable collision contract.
4. Environmental motion is visibly present around the selected existing props
   or hazards while remaining decorative and non-blocking.
5. No new persistent player-facing text appears in the HUD or level worlds.
6. Focused GUT regression tests are written first for retry/reset and any new
   reusable visual-state behaviour, then the complete GUT suite and Python
   tooling suite pass.
7. Fresh rendered captures cover a crouch gate, a damaged/active hazard, a
   checkpoint retry, and at least one late-route landmark; UI layout reports
   remain free of overlap, zero-size, and offscreen findings.

## Verification

Use the project-native workflow: edit authored geometry through
`tools/level_kit.py`, run `check` before imports, then run `tools/run_gut.py`.
Use deterministic Godot scenarios for the retry, HUD layout, and rendered
visual checks. Capture outputs are review evidence only and must not be
committed.
