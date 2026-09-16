# RUN//UNIT v0.1

RUN//UNIT is a small 2D platformer made with Godot 4.7. Move a robot through an authored industrial route and reach the completion beacon.

## Run and controls

Open `project.godot` in Godot 4.7 (or a compatible Godot 4.x release) and run the project.

Select **START NEW RUN** to open Route Deployment. The Maintenance Shaft is the
current authored route; future routes are visibly offline until they are added.
Cross the beacon at the far end to certify the route.

- A / D: move left / right
- Space / Up Arrow: hold to charge the spring crouch, then release to jump; deeper crouches launch higher
- Down Arrow: crouch without charging or jumping; crouching reduces movement speed and collision height
- R: immediate restart from the beginning of the authored route

Route progress is measured in metres: one 32 px world tile equals one metre,
and distance starts at the launch pad rather than the world origin. The best
distance is retained while the game is running, including retrying from the
end-of-run panel.

## Development

The project includes GUT tests. With `godot` available on your PATH, run:

```sh
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Generated Godot caches, exports, validation screenshots, local research files,
IDE settings, and secrets are intentionally excluded from Git.

## Project structure

- `scenes/`: game composition, player, world, HUD, and debug overlay.
- `scripts/player/`: `RunUnitPlayerMotor` contains all physics; human and bot controllers only create actions.
- `scripts/world/`: authored route indexing and traversal trace support.
- `scripts/ai/`: controller-neutral `RunUnitPlayerAction` and the environment interface.
- `scripts/gameplay/`: run orchestration and scoring.

## Authored route

`scenes/world.tscn` contains the complete platform route, visuals, and collision
geometry. `RunUnitStaticWorld` only reads those scene nodes to expose platform
metadata to the game and AI; it does not create, stream, seed, or repaint terrain.
Difficulty is a presentation metric based on distance travelled, not a terrain
layout input.

## AI interface

`Environment` offers:

```gdscript
environment.reset(seed)
environment.apply_action(action)
environment.get_observation()
environment.get_reward()
environment.is_terminal()
```

Action space: `0` nothing/release, `1` left, `2` right, `3` hold jump to charge, `4` left+hold jump, `5` right+hold jump. Replacing a held-jump action with a non-jump action releases the spring. Every action goes through the same `RunUnitPlayerAction -> RunUnitPlayerMotor` path as human input.

The numerical observation is an ordered vector of player X velocity, player Y velocity, on-floor flag, then relative X, relative Y, and width for each of the next three platforms. Values are normalized and based on world data rather than camera pixels.

Reward is newly achieved maximum forward distance in metres, plus a `-1`
terminal penalty when consumed after a failed run. A baseline NEAT fitness can
use `ScoreManager.best_distance`.
