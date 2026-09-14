# Implementation Plan: RUN//UNIT v0.1

## Objective

Deliver a playable Godot 4.x platformer with responsive platform movement, an authored route, score/death/restart, and a controller-neutral AI seam.

## Architecture decisions

- `RunUnitPlayerMotor` owns physics only; controllers translate inputs into `RunUnitPlayerAction`.
- `RunUnitStaticWorld` indexes platform metadata from the authored world scene.
- The game root coordinates reset, UI, death, and score; the environment is a small facade over this state.

## Completed task list

- [x] Create player motor and action/controller separation; verify with Godot parser and a run.
- [x] Create an authored platform route with scene-native collision; verify metadata and collision in a run.
- [x] Add score, death/restart, UI, AI environment facade, scripted bot, and debug overlay; verify the end-to-end gameplay flow.
- [x] Document controls, authored route behavior, difficulty, extension path, and AI contract.
