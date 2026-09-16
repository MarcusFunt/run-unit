import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from tools import run_gut


class TiledCacheTests(unittest.TestCase):
    def test_resolve_godot_prefers_real_windows_install_over_path_wrapper(self) -> None:
        fake_home = Path("/fake-home")
        local_exe = str(fake_home / "Documents" / "GODOT" / "Godot_v4.7.1-stable_win64.exe")

        def fake_existing(value: str | None) -> str | None:
            if value == local_exe:
                return "LOCAL_EXE"
            if value == "godot":
                return "PATH_WRAPPER"
            return None

        with patch.object(run_gut.os, "name", "nt"), patch.object(run_gut.Path, "home", return_value=fake_home), patch.object(run_gut, "_existing_executable", side_effect=fake_existing):
            self.assertEqual(run_gut.resolve_godot(), "LOCAL_EXE")

    def test_discover_tiled_import_cache_only_returns_tmj_cache_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            imported = root / ".godot" / "imported"
            imported.mkdir(parents=True)
            wanted = [
                imported / "maintenance_shaft.tmj-abc.tscn",
                imported / "maintenance_shaft.tmj-abc.md5",
            ]
            for path in wanted:
                path.write_text("cache", encoding="utf-8")
            (imported / "robot.png-abc.ctex").write_text("image", encoding="utf-8")

            found = run_gut.discover_tiled_import_cache(root)

            self.assertEqual(found, sorted(wanted))

    def test_restore_import_sidecars_restores_existing_tracked_content(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sidecar = root / "assets" / "sprite.png.import"
            sidecar.parent.mkdir(parents=True)
            sidecar.write_bytes(b"original")
            snapshot = run_gut.snapshot_import_sidecars(root)
            sidecar.write_bytes(b"rewritten by Godot")

            run_gut.restore_import_sidecars(snapshot)

            self.assertEqual(sidecar.read_bytes(), b"original")

    def test_purge_tiled_import_cache_removes_only_tmj_cache_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            imported = root / ".godot" / "imported"
            imported.mkdir(parents=True)
            stale = imported / "maintenance_shaft.tmj-def.tscn"
            keep = imported / "robot.png-def.ctex"
            stale.write_text("stale", encoding="utf-8")
            keep.write_text("keep", encoding="utf-8")

            removed = run_gut.purge_tiled_import_cache(root)

            self.assertEqual(removed, [stale])
            self.assertFalse(stale.exists())
            self.assertTrue(keep.exists())


if __name__ == "__main__":
    unittest.main()
