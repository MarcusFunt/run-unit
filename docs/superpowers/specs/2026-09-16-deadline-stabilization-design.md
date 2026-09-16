# RUN//UNIT Deadline Stabilization Design

## Goal
Make the current authored build safer to finish and submit without broad architecture work.

## Scope
- Make progress use authored Spawn-to-Goal travel distance instead of world extent.
- Make completion-trigger placement correct even when the world node is transformed.
- Keep current platform APIs compatible while adding a position-aware current-platform query.
- Make clean Tiled/YATI imports and GUT tests reproducible from one command.
- Add GitHub Actions coverage for clean import + tests + a Windows release artifact.
- Remove known GUT orphan noise caused by tests that instantiate nodes without freeing them.
- Update repository documentation and player-facing route copy to the current factory/final-inspection narrative.

## Constraints
- Godot 4.7.1, GDScript, bundled GUT, Tiled/YATI remain the stack.
- Do not rewrite the player motor, Tiled pipeline, menu framework, or asset compiler.
- Preserve existing authored route geometry and recent 1.6x player/gate fixes.
- Do not commit `.godot/`, exports, local MCP state, or editor-generated local changes.
- Every gameplay behavior change gets a regression test before production code changes.
