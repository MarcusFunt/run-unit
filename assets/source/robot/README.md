# RUN//UNIT robot rig

The source files are deliberately independent, transparent SVG components. The robot faces **left** in its authored orientation; flip the `RobotVisual` root on X to face right.

`robot_asset_metadata.json` is the source of truth for SVG dimensions and pivots. The player rig uses `0.357143` artwork scale; stored units add their authored scene scale and cool parent tint. Every child sprite is offset from its documented body or linkage pivot. The hip is at `(180, 115)` on the body and the extended lower/shin link is `145` source pixels long. The authored, left-facing driving stance uses a `25°` upper-link angle and a `105°` relative knee angle. Godot mirrors the complete visual rig for rightward movement, producing the inverse leg pose while keeping body and linkage direction aligned.

The integration lives in `res://scenes/player_robot_visual.tscn` and is instanced by `res://scenes/player.tscn`. That player rig uses the `*_unit07.svg` palette variants: warm ceramic plates and brass link highlights keep UNIT-07 distinct from the cool factory steel. The original SVGs remain available for muted stored units. `res://scripts/player/robot_visual.gd` provides transform-only poses:

- idle: balancing bob and eye pulse
- acceleration: body leans into travel; visual root flips for rightward movement
- jump preparation: links fold while jump is held on the floor
- jump: links extend after the motor emits `jumped`
- landing: one short compression after the motor emits `landed`

The wheel centre is at approximately `(7, -4)` relative to the player collision origin in the neutral pose, with a rendered radius of `18 px`; the visual tire therefore meets the existing platform level while collision remains a separate rectangle.
