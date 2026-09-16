#!/usr/bin/env python3
"""Run RUN//UNIT's Godot tests from a deterministic import state."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def discover_tiled_import_cache(project_root: Path) -> list[Path]:
    """Return generated Godot cache files for YATI-imported .tmj levels."""
    imported = project_root / ".godot" / "imported"
    if not imported.is_dir():
        return []
    return sorted(path for path in imported.glob("*.tmj-*") if path.is_file())


def purge_tiled_import_cache(project_root: Path) -> list[Path]:
    """Remove stale .tmj cache entries so external .tsj edits are re-read."""
    removed = discover_tiled_import_cache(project_root)
    for path in removed:
        path.unlink()
    return removed


def snapshot_import_sidecars(project_root: Path) -> dict[Path, bytes]:
    """Snapshot existing source-side .import files that Godot may rewrite."""
    snapshot: dict[Path, bytes] = {}
    for path in project_root.rglob("*.import"):
        if ".godot" in path.parts or not path.is_file():
            continue
        snapshot[path] = path.read_bytes()
    return snapshot


def restore_import_sidecars(snapshot: dict[Path, bytes]) -> None:
    """Restore pre-run sidecar bytes without touching newly generated ignored files."""
    for path, content in snapshot.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)


def _existing_executable(value: str | None) -> str | None:
    if not value:
        return None
    resolved = shutil.which(value)
    if resolved:
        return resolved
    path = Path(value).expanduser()
    if path.is_file():
        return str(path)
    return None


def resolve_godot(explicit: str | None = None) -> str:
    candidates = [
        explicit,
        os.environ.get("RUN_UNIT_GODOT"),
        os.environ.get("GODOT_BIN"),
    ]
    if os.name == "nt":
        candidates.append(str(Path.home() / "Documents" / "GODOT" / "Godot_v4.7.1-stable_win64.exe"))
    candidates.extend(["godot", "godot4"])
    for candidate in candidates:
        found = _existing_executable(candidate)
        if found:
            return found
    raise FileNotFoundError(
        "Godot executable not found. Pass --godot PATH or set RUN_UNIT_GODOT/GODOT_BIN."
    )


def run_checked(command: list[str], project_root: Path) -> int:
    print("+", " ".join(command), flush=True)
    return subprocess.run(command, cwd=project_root, check=False).returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot executable path/name")
    parser.add_argument(
        "--keep-tiled-cache",
        action="store_true",
        help="Do not purge generated .tmj import cache before importing.",
    )
    args = parser.parse_args(argv)

    project_root = PROJECT_ROOT
    godot = resolve_godot(args.godot)
    sidecar_snapshot = snapshot_import_sidecars(project_root)
    try:
        if not args.keep_tiled_cache:
            removed = purge_tiled_import_cache(project_root)
            print(f"Purged {len(removed)} cached Tiled import file(s).", flush=True)

        import_exit = run_checked(
            [godot, "--headless", "--path", str(project_root), "--import", "--quit"],
            project_root,
        )
        if import_exit != 0:
            return import_exit

        return run_checked(
            [
                godot,
                "--headless",
                "--path",
                str(project_root),
                "-s",
                "res://addons/gut/gut_cmdln.gd",
                "-gdir=res://tests",
                "-ginclude_subdirs",
                "-gexit",
            ],
            project_root,
        )
    finally:
        restore_import_sidecars(sidecar_snapshot)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc
