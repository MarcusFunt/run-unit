# RUN//UNIT visual gameplay and level pass — 2026-09-18

## Scope and method

This pass reviews the complete four-route campaign: Calibration, Factory Escape, Recovery, and Beacon 9.
The analysis combines the authored scenes and Tiled maps, runtime viewport captures, the project story/pacing rules, and the Level Kit route checker.
The Level Kit reads the actual player motor constants, so its jump classifications are tied to the shipping controller rather than hand-estimated distances.

The project-bundled Godot-AI v4 addon and tool catalog were inspected and its configured `godot-ai attach` MCP path was invoked.
The live editor's attach handshake did not complete from the external MCP client on this laptop session, so no successful Godot-AI editor-state/tool result is claimed here.
Runtime evidence was instead captured deterministically from the game itself by loading each route, positioning UNIT-07 at review points, forcing timed hazards visible, and saving the real viewport.

## Campaign-wide findings

The campaign already has a coherent visual identity: cool industrial cyan/teal surfaces, warm warning accents, readable silhouettes, and increasingly large exterior compositions.
The story-specific set dressing is substantially stronger than the raw platform geometry: stored UNIT copies, factory machinery, city parallax, Beacon 9 sightlines, the module cradle, and the ignition chamber all communicate place and purpose.
The main weakness was local gameplay rhythm rather than missing art direction.

Level Kit classified every route move as comfortable before this pass.
That is a good accessibility baseline, but on the long Recovery and Beacon routes it makes consecutive jumps mechanically similar even when the scenery changes.
The safest improvement is therefore to add timing and route-reading decisions without narrowing jump margins.
The project's own pacing rule is effectively Read -> Execute -> Breathe.
The major reveals already work best as Breathe beats, so hazards should not be placed on the factory collapse reveal, module acquisition, Beacon scale reveal, maintenance interior, or ignition finale.
Hazard language also has to be visually diegetic: an invisible semantic kill cell would contradict the otherwise strong readability.

## Calibration

Baseline: short, readable, and appropriately consequence-free. Its weakness was that the floor did little to reinforce the sequence of lessons.
Change: four low-profile floor cues now mark movement, normal jump, spring/charged-jump practice, and the exit approach.
The tutorial remains completely hazard-free.

## Factory Escape

Baseline: the strongest environmental-storytelling level. Rows of stored units and broken transfer machinery make the route feel like a place rather than an abstract course.
The platforming is intentionally forgiving, but the transfer-line and warehouse stretches had little local decision pressure between crouch/jump beats.
Change: two non-lethal cycling electrical floor faults were added to active traversal stretches.
The faults are kept away from the collapse reveal, storage reveal, and breach/exit framing.

## Recovery

Baseline: the first route long enough for repetition to become obvious. It has good exterior-to-interior contrast and strong module-recovery storytelling, but twenty-two comfortable route moves can flatten into a steady cadence.
Change: three electrical faults create short wait-or-jump decisions in the street, cooling, and core traversal phases.
A checkpoint was added just after the jammed maintenance hatch at x=4992, so a late mistake no longer replays the entire first half.
Module acquisition and the reserve-depot reveal remain safe.

## Beacon 9

Baseline: visually the most ambitious route. The city parallax and growing Beacon silhouette provide excellent destination pull, and the final interior/ignition sequence already functions as the narrative payoff.
The long approach, however, still relied mostly on familiar comfortable jumps.
Change: three timed electrical faults are front-loaded into rooftop, viaduct, and canyon traversal.
All added hazards stop before x=9152, preserving the Beacon scale reveal, maintenance perimeter, interior, installation, and ignition sequence as low-noise narrative space.
## New hazard language

The new `electric_floor_arc.tscn` reuses the existing health/hitstun system rather than inventing a parallel mechanic.
It deals one point of damage, is explicitly non-lethal, adds modest knockback/hitstun, and cycles between dangerous and safe phases.
An always-visible dark/orange warning plate remains during the safe phase; a warm glow and zig-zag electrical arc appear during the active phase.

This creates three useful player choices: wait for the safe phase, jump the fault, or accept a health cost and keep momentum.
Because the route geometry is unchanged, none of those choices require a tighter jump than the original level.

## Level Kit result

All four shipping maps still pass the route checker after the changes.
Calibration remains 4 ledges / 3 route moves.
Factory Escape remains 11 ledges / 10 route moves.
Recovery remains 23 ledges / 22 route moves.
Beacon 9 remains 24 ledges / 23 route moves.
The jump-difficulty classifications remain in the comfortable envelope; difficulty is now introduced through timing rather than precision.

## Regression coverage

Tests now cover the electric-floor prefab's persistent warning and switchable active visual.
Level tests assert the exact hazard counts/placements, their non-lethal behavior, the Recovery checkpoint, and the no-hazard Calibration contract.
The older collision tests were tightened to count only imported StoryZones, because intentional hazard Area2D nodes are also collision-free areas.

Validation:
- GUT: 161/161 tests passed, 926 assertions.
- Python tooling: 48/48 tests passed.
- Level Kit: all four shipping maps pass.
- `git diff --check`: no whitespace errors in the intended patch.
## Visual result

The runtime captures show that the added orange fault language contrasts clearly against the cool cyan/teal decks without competing with the larger story landmarks.
The always-visible plate prevents the safe phase from becoming an invisible trap.
The active arc reads as damaged infrastructure, which fits the broken-factory / failing-city fiction better than generic spikes or floating game hazards.

The pass intentionally does not add enemies, moving saws, instant-death pits, or precision-jump escalation.
RUN//UNIT's current strength is narrative movement through a failing industrial world; the new hazards are there to give that movement punctuation, not to change the game into an arcade gauntlet.
