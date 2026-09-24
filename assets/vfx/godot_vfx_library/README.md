# RUN//UNIT feedback VFX provenance

The two particle scenes in this folder are adapted from the MIT-licensed
Godot VFX Library by haowg:

- https://github.com/haowg/GODOT-VFX-LIBRARY
- `jump_dust.tscn` was the starting point for `run_unit_jump_dust.tscn`.
- `wall_slide_spark.tscn` / `sparks.tscn` informed `run_unit_metal_sparks.tscn`.

RUN//UNIT changes the palette, lifetime, particle count, velocity and scale to
fit the game's small industrial robot. The deliberate cap of six particles is
part of the art direction: ordinary movement should never obscure the robot
animation or read like an explosion.

See `LICENSE.txt` for the upstream MIT license.
