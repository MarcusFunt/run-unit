# RUN//UNIT Deadline Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the current authored RUN//UNIT build for the deadline without broad refactoring.

**Architecture:** Keep the existing Tiled/YATI world and player architecture. Add only narrow APIs/scripts around proven problems: authored traversal distance, transform-safe finish placement, position-aware platform lookup, deterministic clean-import testing, CI, and test/documentation cleanup.

**Tech Stack:** Godot 4.7.1, GDScript, GUT 9.7.1, Python 3, GitHub Actions, Tiled/YATI.

**Spec:** `docs/superpowers/specs/2026-09-16-deadline-stabilization-design.md`

## Global Constraints
- Keep Godot 4.7.1 and the existing Tiled/YATI pipeline.
- Preserve recent player-scale and crouch-gate behavior.
- Do not commit generated `.godot` or local MCP/editor state.
- Use test-first changes for gameplay behavior.

---

### Task 1: Route progress and completion semantics
**Files:** `scripts/world/static_world.gd`, `scripts/gameplay/game.gd`, `tests/test_run_progression.gd`, `tests/test_maintenance_shaft.gd`
- [ ] Add failing tests for 138 m Spawn-to-Goal traversal and transformed completion-trigger placement.
- [ ] Run focused GUT tests and verify expected failures.
- [ ] Add `get_traversal_length()` and use it for progress/HUD difficulty normalization.
- [ ] Make completion trigger transform-safe.
- [ ] Add/use a position-aware current-platform query without removing legacy X-only APIs.
- [ ] Run focused tests and full GUT suite.

### Task 2: Deterministic local test runner
**Files:** `tools/run_gut.py`, `tools/tests/test_run_gut.py`, `README.md`, `AGENTS.md`
- [ ] Write unit tests for Tiled import-cache discovery/purge helpers.
- [ ] Verify those tests fail before the runner exists.
- [ ] Implement a cross-platform runner that purges cached `.tmj` imports, runs `godot --import --quit`, then GUT and forwards exit codes.
- [ ] Run Python unit tests and then use the runner against the project.
- [ ] Document the canonical test command and external-TSJ cache reason.

### Task 3: Remove known GUT orphan noise
**Files:** `tests/test_menu_player_flow.gd`, `tests/test_run_progression.gd`
- [ ] Add automatic cleanup for every intentionally instantiated Node that is currently orphaned.
- [ ] Run the full suite and confirm the orphan count materially drops without changing assertions.

### Task 4: Continuous integration
**Files:** `.github/workflows/godot-ci.yml`, `export_presets.cfg`
- [ ] Add a GitHub Actions job using `chickensoft-games/setup-godot@v2` with Godot 4.7.1.
- [ ] Run Python tooling tests and `python tools/run_gut.py` on pull requests and pushes to main.
- [ ] Install export templates, export the Windows Desktop preset, and upload the Windows build artifact.
- [ ] Verify workflow syntax locally where possible and then inspect the PR workflow run on GitHub.

### Task 5: Narrative and repository source-of-truth cleanup
**Files:** `scripts/ui/run_unit_level_selector.gd`, `StorylineSketch.md`, `README.md`, `AGENTS.md`
- [ ] Replace the obsolete Solar Ignition Core/service-tunnel route copy with the approved calibration/final-inspection/transfer-line framing.
- [ ] Update StorylineSketch to the current short factory narrative.
- [ ] Correct README/AGENTS so Tiled/YATI—not `world.tscn` geometry—is documented as route authority.
- [ ] Run the menu-flow and full test suites after copy/docs changes.

### Task 6: Verify, publish, and review
- [ ] Run Python unit tests, clean-import GUT, and inspect `git diff --check` / `git status`.
- [ ] Commit focused changes on `chore/deadline-stabilization`.
- [ ] Push branch and create a pull request to `main`.
- [ ] Inspect GitHub Actions; fix only evidence-backed failures.
