import sys
import unittest
from pathlib import Path

from PIL import Image

TOOLS_DIR = Path(__file__).resolve().parents[1]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import compile_run_unit_assets as compiler


class MenuMegastructureTests(unittest.TestCase):
    def test_draw_menu_megastructure_creates_tall_landmark(self) -> None:
        self.assertTrue(
            hasattr(compiler, "draw_menu_megastructure"),
            "asset compiler should expose deterministic menu megastructure drawing",
        )
        canvas = Image.new("RGBA", (480, 270))
        bounds = compiler.draw_menu_megastructure(canvas, center_x=352, base_y=250)

        self.assertIsNotNone(canvas.getbbox())
        self.assertEqual(len(bounds), 4)
        self.assertGreater(bounds[3] - bounds[1], 100)
        self.assertGreater(bounds[2] - bounds[0], 60)
        self.assertLessEqual(bounds[2], canvas.width)
        self.assertLessEqual(bounds[3], canvas.height)


class PixelizeSourceTests(unittest.TestCase):
    def _source(self, tmp: Path, size: tuple[int, int]) -> Path:
        image = Image.new("RGBA", size)
        for x in range(size[0]):
            for y in range(size[1]):
                image.putpixel((x, y), (x % 256, y % 256, 128, 255))
        path = tmp / "source.png"
        image.save(path)
        return path

    def test_pixelize_source_writes_the_requested_resolution(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            source = self._source(tmp, (640, 360))
            target = tmp / "out" / "vista.png"

            record = compiler.pixelize_source(source, target, (320, 180))

            self.assertTrue(target.is_file())
            self.assertEqual(Image.open(target).size, (320, 180))
            self.assertEqual(record["size"], [320, 180])
            self.assertEqual(record["source_size"], [640, 360])

    def test_pixelize_source_crops_to_the_target_aspect(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            # 2:1 source into a 16:9 target: the extra width is cropped away,
            # never squashed.
            source = self._source(tmp, (800, 400))
            target = tmp / "vista.png"

            compiler.pixelize_source(source, target, (320, 180))

            self.assertEqual(Image.open(target).size, (320, 180))

    def test_pixelize_source_is_deterministic(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as raw:
            tmp = Path(raw)
            source = self._source(tmp, (640, 360))
            first = tmp / "first.png"
            second = tmp / "second.png"

            compiler.pixelize_source(source, first, (320, 180))
            compiler.pixelize_source(source, second, (320, 180))

            self.assertEqual(first.read_bytes(), second.read_bytes())

