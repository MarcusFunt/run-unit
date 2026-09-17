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
