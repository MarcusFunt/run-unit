# Level Kit API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify RUN//UNIT level authoring behind one backward-compatible `tools/level_kit.py` API while adding safe rich-map rebuilding, reusable stamps, better validation/difficulty analysis, and batch checking.

**Architecture:** Keep `tools/level_kit.py` as the only public CLI/module. Move new implementation into small `tools/levelkit/` helpers and re-export/wire them through the facade. Preserve all existing commands and public Python names; absorb PR #30's workbench behavior and retire the separate CLI.

**Tech Stack:** Python 3.12 stdlib (`argparse`, `json`, `dataclasses`, `pathlib`, `heapq`, `unittest`), Tiled `.tmj/.tsj`, Godot 4.7.1/YATI via existing CI.

**Spec:** `docs/superpowers/specs/2026-09-17-level-kit-api-design.md`

## Global Constraints

- Preserve `new`, `sketch`, `build`, `check`, and `autoart` CLI compatibility.
- Preserve existing `import level_kit` callers and public symbols.
- Do not add third-party Python dependencies.
- `level_kit build` must become lossless for metadata/layers outside route ownership.
- Gameplay layers are excluded from stamp capture by default.
- No arbitrary stamp rotation in this pass.
- Final verification must include Python tests and the repository's full GitHub Actions Godot/YATI/GUT/export workflow.

---

### Task 1: Harden Tiled contract validation

**Files:**
- Modify: `tools/level_kit.py`
- Modify: `tools/tests/test_level_kit.py`

**Interfaces:**
- Consumes: `LevelMap`, `_check_structure`, `collision_rects`.
- Produces: deterministic validation errors for malformed tile data, duplicate route markers, and collidable diagonal flips.

- [ ] **Step 1: Add failing tests for malformed tile-layer data.** Build a map whose layer declares `width * height` cells but provides one fewer element; assert `check_level` returns an error containing `cell count` rather than raising.
- [ ] **Step 2: Add failing tests for duplicate Spawn and Goal objects.** Duplicate each object in the real `Markers` layer and assert `check_level` reports the duplicate name as a contract error.
- [ ] **Step 3: Add a failing test for diagonal-flipped collision.** Paint a collidable tile with `FLIP_DIAGONAL` and assert validation rejects it explicitly.
- [ ] **Step 4: Run `python -m unittest tools.tests.test_level_kit -v` and confirm the new tests fail.**
- [ ] **Step 5: Implement validation.** Check `len(data) == layer_width * layer_height`; preserve duplicate marker information with a new `marker_objects()` helper while keeping `markers()` backward-compatible; reject diagonal flips only when the tile contributes collision.
- [ ] **Step 6: Re-run the focused tests and commit.**

### Task 2: Absorb lossless build into Level Kit

**Files:**
- Create: `tools/levelkit/__init__.py`
- Create: `tools/levelkit/tiled.py`
- Modify: `tools/level_kit.py`
- Modify: `tools/tests/test_level_kit.py`
- Delete after migration: `tools/tiled_workbench.py`
- Delete after migration: `tools/tests/test_tiled_workbench.py`

**Interfaces:**
- Consumes: existing `build_map(sketch, out_path, template)` result.
- Produces: `merge_unowned_tiled_content(original: dict, built: dict, owned_layer_names: set[str], width: int, height: int) -> dict` and normal `level_kit build` semantics that preserve rich-map metadata.

- [ ] **Step 1: Port PR #30's Factory Escape lossless regression into `test_level_kit.py`.** Assert `StoryZones`, `ArtForeground`, map properties, and object-id budget survive a sketch/build round trip.
- [ ] **Step 2: Run the focused test and confirm current `level_kit build_map` fails it.**
- [ ] **Step 3: Implement `levelkit/tiled.py` with deep-copy merge helpers.** Route-owned layers are `Semantic`, `Obstacles`, and `Markers`; unknown object groups and decorative metadata survive exactly, with tile grids resized only when map dimensions change.
- [ ] **Step 4: Make `command_build` use the safe merge by default while retaining `build_map` as the lower-level compatibility function.**
- [ ] **Step 5: Move/merge the workbench lossless tests into the main test file.**
- [ ] **Step 6: Run focused tests and commit.**

### Task 3: Fold portable stamps into `level_kit.py`

**Files:**
- Create: `tools/levelkit/stamps.py`
- Modify: `tools/level_kit.py`
- Modify: `tools/tests/test_level_kit.py`
- Keep: `assets/tiled/stamps/platform_8x3.json`
- Keep: `assets/tiled/stamps/tunnel_11x7.json`

**Interfaces:**
- Produces: `capture_stamp(level, rect, name, include_gameplay=False, layer_names=None) -> dict`, `place_stamp(level, stamp, x, y, flip_x=False, flip_y=False) -> int`, `inspect_stamp(stamp) -> dict`, `apply_stamp_plan(level, plan, stamp_loader) -> int`.
- CLI: `stamp list|inspect|capture|place|apply`.

- [ ] **Step 1: Move existing PR #30 stamp tests under the main Level Kit suite and verify they fail before wiring.**
- [ ] **Step 2: Add failing tests for `flip_x` and `flip_y` placement.** Use an asymmetric 2×2 stamp and assert cell positions mirror while per-tile Tiled flip flags are preserved/toggled correctly for horizontal/vertical reflection.
- [ ] **Step 3: Add a failing `stamp inspect` test.** Assert dimensions, layers, tilesets, source, and `includes_gameplay` are reported.
- [ ] **Step 4: Add a failing batch-apply test.** Apply two placements from a plan dict, one mirrored, and assert deterministic modified cells/count.
- [ ] **Step 5: Implement `levelkit/stamps.py` by absorbing the PR #30 logic and adding transforms/inspection/batch placement.** Empty cells remain non-destructive.
- [ ] **Step 6: Wire the `stamp` subparser into `level_kit.py` with the same arguments already documented by PR #30 plus `--flip-x`, `--flip-y`, `inspect`, and `apply`.
- [ ] **Step 7: Run focused tests and commit.**

### Task 4: Improve route difficulty analysis and path choice

**Files:**
- Create: `tools/levelkit/analysis.py`
- Modify: `tools/level_kit.py`
- Modify: `tools/tests/test_level_kit.py`

**Interfaces:**
- Produces: `move_difficulty(move, source_ledge, physics, level) -> dict`, `best_route(start, finish_indices, edges, ledges, physics, level) -> list[dict]`.
- `check_level(...).summary` gains structured route/difficulty fields while retaining existing keys.

- [ ] **Step 1: Add a failing test where a one-jump full-charge path competes with a two-jump comfortable path.** Assert the selected route is the comfortable path.
- [ ] **Step 2: Add a failing test for limited run-up.** A short starting ledge requiring near-max horizontal launch should be classified `near_perfect` or `tight`, not `comfortable`.
- [ ] **Step 3: Implement deterministic move difficulty scoring.** Estimate available ground run-up from platform width and ground acceleration, compare attainable takeoff speed to `max_run_speed`, combine with charge and existing reduced-speed margin result.
- [ ] **Step 4: Implement Dijkstra-style best-route selection with lexicographic cost `(near_perfect_count, tightness_cost, move_count)` instead of BFS move count alone.
- [ ] **Step 5: Extend report summary with `route_moves_detail`, `difficulty`, `crouch_spans`, `unreachable_ledges`, `soft_locks`, and `route_length_m` while preserving current prose notes/warnings.
- [ ] **Step 6: Run focused tests and commit.**

### Task 5: Add campaign-wide `check-all`

**Files:**
- Modify: `tools/level_kit.py`
- Modify: `tools/tests/test_level_kit.py`

**Interfaces:**
- CLI: `level_kit.py check-all PATH [--json] [--margin FLOAT]`.

- [ ] **Step 1: Add a failing CLI test with a temporary directory containing one valid and one invalid `.tmj`; assert non-zero exit and both paths appear in output.**
- [ ] **Step 2: Add a success test for the real `assets/tiled/levels` directory.**
- [ ] **Step 3: Implement recursive sorted `.tmj` discovery, call `check_level` for each, aggregate results, and return non-zero if any fail.**
- [ ] **Step 4: Support JSON output as `{ok, levels:[...]}` using the same per-level report schema as `check --json`.
- [ ] **Step 5: Run focused tests and commit.**

### Task 6: Consolidate CLI/docs and retire the workbench

**Files:**
- Modify: `README.md`
- Modify: `tools/level_kit.py`
- Delete: `tools/tiled_workbench.py`
- Delete: `tools/tests/test_tiled_workbench.py`

**Interfaces:**
- One public CLI: `python tools/level_kit.py ...`.

- [ ] **Step 1: Update README examples so every workbench command becomes the equivalent `level_kit.py` command.**
- [ ] **Step 2: Ensure `python tools/level_kit.py --help` lists old commands plus `check-all` and `stamp`.
- [ ] **Step 3: Search the repository for `tiled_workbench` and remove all executable/documentation references.
- [ ] **Step 4: Run `python -m unittest discover -s tools/tests -v` and confirm zero failures.**
- [ ] **Step 5: Commit the consolidation.**

### Task 7: Full verification and PR update

**Files:**
- Modify only if verification finds defects.

**Interfaces:**
- Final result is PR #30 updated to describe a unified Level Kit rather than a companion workbench.

- [ ] **Step 1: Run the full Python tooling suite.** `python -m unittest discover -s tools/tests -v`.
- [ ] **Step 2: Run Level Kit against both authored maps.** `python tools/level_kit.py check-all assets/tiled/levels`.
- [ ] **Step 3: Run/observe GitHub Actions for the exact head and require Python tooling, clean Godot/YATI import + GUT, Windows export, and artifact upload to succeed.
- [ ] **Step 4: Review the final PR diff for accidental map/asset changes and backward-compatibility regressions.
- [ ] **Step 5: Update PR #30 title/body with the final feature/debug list and verification evidence; leave merge decision to the user.
