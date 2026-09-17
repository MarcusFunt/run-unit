# RUN//UNIT Hazard System Design

Date: 2026-09-17
Status: approved for implementation

## Purpose

Add hazards to RUN//UNIT without disturbing the current campaign, level-authoring, checkpoint, route-exit, or player-movement architecture. The system must support simple static lethal surfaces and reusable timed/moving hazards authored from Tiled, while preserving deterministic reset behavior and the existing retry/checkpoint flow.

## Scope

This implementation establishes the reusable gameplay foundation and proves it with representative hazards. It does not redesign existing levels around hazards, add combat, add enemy AI, add inventory, or replace the existing failure/retry system.

The initial hazard vocabulary is:

- spike strip: static semantic hazard, lethal
- laser gate: reusable scene instance, one damage
- electrical arc: reusable scene instance, one damage
- steam vent: reusable scene instance, one damage and directional knockback
- saw: reusable scene instance, lethal
- crusher/piston: reusable scene instance, lethal during its dangerous phase

The first implementation pass may use simple project-native presentation for dynamic hazards where dedicated art is not already available. Existing curated spike/laser art should be reused where practical.

## Architectural choice

Use a hybrid authoring model.

Static hazards are authored as cells in the existing Tiled `Semantic` layer using semantic value `3 = hazard`. Decorative art remains separate from collision/gameplay semantics.

Dynamic hazards are reusable Godot scenes under `scenes/hazards/` and are placed in a Tiled object layer as YATI `instance` objects with a `res_path` property. YATI already supports instantiating a Godot scene from such an object and applying authored properties to it.

Do not add a custom level-object parser and do not move authored level geometry back into hand-maintained Godot collision nodes.

## Components

### RunUnitPlayerHealth

Add a small player-owned health component with one responsibility: accepting damage and publishing health state.

Required behavior:

- default/max HP: 3
- normal damage: 1 HP
- global invulnerability after an accepted non-lethal hit: 0.75 seconds
- lethal damage immediately depletes health regardless of remaining HP
- accepted damage emits a signal containing enough information for feedback/gameplay consumers
- depletion emits a dedicated signal
- reset restores full health and clears invulnerability/contact state

The health component does not know about campaign indices, checkpoints, score, route exits, menus, or level scenes.

### Hazard contact contract

All hazards expose damage through Area2D overlap and a small common script/interface rather than calling game failure code directly.

A hazard has:

- damage amount or lethal flag
- knockback vector/policy
- active/inactive state
- per-body exposure tracking

Rules:

1. Entering an active hazard creates a new exposure and attempts one hit.
2. Remaining continuously inside that same active exposure does not repeatedly damage the player.
3. Leaving clears that hazard's exposure state.
4. A timed hazard turning off clears active exposure for overlapping bodies.
5. If it turns on again while the player is still overlapping, that activation is a new exposure and may hit once.
6. Global player i-frames still gate accepted normal damage across different hazards, preventing stacked Area2Ds from deleting all HP in one frame.
7. Lethal hazards bypass normal HP attrition and cause depletion immediately.

### Player motor knockback

Add a narrow transient hit-reaction state to `RunUnitPlayerMotor` rather than rewriting movement.

Expose an API similar to:

`apply_knockback(impulse: Vector2, hitstun_seconds: float)`

During hitstun:

- the impulse is preserved instead of being immediately overwritten by held movement input
- normal horizontal acceleration/input control is suppressed or heavily reduced
- gravity and `move_and_slide()` continue
- normal control resumes automatically after the timer
- reset clears hitstun

Jump, charged jump, crouch, antenna behavior, and normal locomotion remain otherwise unchanged.

### RunUnitGame integration

`RunUnitGame` owns the consequence of health depletion because it already owns run failure/retry behavior.

The game connects to the player's health-depleted signal and invokes the existing failure path. Hazards never call `_fail_run()` or menu code directly.

On `reset_run()` the player health is restored to full. Existing checkpoint selection remains authoritative, so retrying after a hazard death resumes from the current checkpoint when one exists.

Remaining HP is not persisted into checkpoints.

### Static semantic hazards

`RunUnitStaticWorld` already interprets authored semantic data. Extend that import/runtime path so contiguous semantic hazard cells become Area2D detector regions.

Requirements:

- merge horizontally/rectangularly contiguous hazard cells where practical rather than creating one Area2D per cell
- generated hazard Areas must not become solid collision bodies
- they are lethal by default
- decorative hazard art remains independent
- existing route extraction and semantic geometry behavior remain unchanged

### Dynamic hazard scenes

Create reusable scenes/scripts for the dynamic hazard family, sharing a common base where useful.

Representative configuration properties should be exported so YATI can apply Tiled object properties directly:

- `active`
- `damage`
- `lethal`
- `knockback`
- `cycle_seconds`
- `active_seconds`
- `phase_offset_seconds`
- optional movement extent/speed for hazards such as saws

Timed hazards must be deterministic from scene start/reset. They must implement `reset_level_state()` so `RunUnitStaticWorld.reset()` restores their authored phase and position.

For the first implementation, prioritize correctness and authorability over elaborate animation.

### Hazard identities

- Spike strip: lethal static semantic surface; no knockback needed.
- Laser gate: one damage; knockback away from the beam or authored direction; supports active/off cycles.
- Electrical arc: one damage; medium horizontal/upward impulse; supports cycles.
- Steam vent: one damage; pushes along an authored direction; supports cycles.
- Saw: lethal; stationary or simple deterministic rail motion.
- Crusher/piston: lethal while its dangerous moving/closed phase is active; deterministic cycle.

## Feedback and HUD

Add minimal health feedback without turning RUN//UNIT into a combat UI.

- show three compact health cells/segments in the existing HUD
- accepted damage produces a brief player flash and/or spark feedback through `player_feedback.gd`
- avoid a large health bar
- depleted health continues into the existing run-failure presentation rather than adding a second death screen

Presentation must remain separable from damage logic so tests can validate gameplay without depending on animation timing.

## Tiled/YATI authoring contract

Dynamic hazards live in a Tiled object layer named `Hazards` by convention.

Each dynamic hazard object:

- uses YATI's `instance` class/type
- includes a `res_path` file property pointing to a hazard `.tscn`
- may override exported hazard properties from Tiled
- uses the Tiled object transform for position/rotation/scale

Add one small authored integration fixture/map or test asset proving this exact import path works before relying on it in campaign levels.

Level Kit must preserve this object layer losslessly. Do not teach Level Kit a second dynamic-hazard language in the first pass.

## Reset/checkpoint behavior

Hazards do not own respawn locations.

- checkpoints remain authored `Checkpoint...` markers
- failure continues through the existing run failure flow
- retry uses `RunUnitSession`'s current resume position
- health returns to 3 HP on retry
- every stateful dynamic hazard implements `reset_level_state()`
- world reset restores hazard cycle/position deterministically

## Tests

Follow repository TDD discipline. Add regression tests before gameplay implementation.

Health tests:

- starts at 3 HP
- one accepted normal hit removes exactly 1 HP
- a continuous overlap cannot drain repeatedly
- global i-frames reject another normal hit during the window
- damage is accepted again after i-frames plus a new exposure
- lethal hit immediately depletes health
- reset restores 3 HP and clears transient state

Motor tests:

- knockback impulse is not erased immediately by held movement input
- gravity still applies during hitstun
- control resumes after hitstun
- reset clears hitstun

Hazard tests:

- entering an active hazard attempts one hit
- staying inside does not repeat the hit
- exit/re-entry creates a new exposure
- turning a timed hazard off then on while still overlapping creates a new exposure
- lethal hazards deplete immediately
- reset returns timed/moving hazards to authored initial state

World/import tests:

- semantic value 3 produces non-solid lethal detector areas
- adjacent semantic hazard cells are merged rather than emitted as one Area2D per cell where supported
- a YATI `instance` object successfully instantiates a hazard scene and applies custom properties

Game integration tests:

- health depletion enters the existing failure path
- retry restores 3 HP
- retry still resumes from the existing checkpoint rather than Spawn when a checkpoint is active

Validation commands:

- `python -m unittest discover -s tools/tests -v`
- Level Kit `check` for any campaign map changed
- `python tools/run_gut.py`

CI must remain green before completion is claimed.

## Non-goals

Do not, as part of this subsystem:

- refactor campaign routing
- replace `RunUnitStaticWorld`
- rewrite YATI
- redesign checkpoints
- add enemies or combat
- add persistent health between retries
- add a general status-effect framework
- make the ignition module interact with hazards
- rebalance all campaign levels around hazards

## Implementation order

1. Add failing health and knockback regression tests.
2. Implement `RunUnitPlayerHealth` and narrow motor hitstun/knockback support.
3. Connect depletion/reset/HUD feedback to the existing player/game flow.
4. Add common hazard contact logic and representative static/timed hazard tests.
5. Extend semantic hazard-cell runtime handling.
6. Add reusable dynamic hazard scenes.
7. Add a YATI instance integration fixture/test.
8. Run full tooling/GUT/CI verification.
9. Only after the foundation is stable, place hazards into campaign levels in a separate level-design pass.

## Success criteria

The subsystem is complete when a player can take one-hit damage from reusable dynamic hazards, die immediately to lethal hazards, receive real knockback with short hitstun, see three-state health feedback, retry through the existing checkpoint system with full health, and when both semantic static hazards and Tiled/YATI-instanced dynamic hazards are covered by automated regression tests without changing campaign/story architecture.