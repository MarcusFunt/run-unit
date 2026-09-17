#!/usr/bin/env python3
"""One-time branch migration: install the internal Level Kit extension hook."""

from pathlib import Path

path = Path("tools/level_kit.py")
text = path.read_text(encoding="utf-8")
marker = "\nif __name__ == \"__main__\":\n    raise SystemExit(main())\n"
hook = (
    "\n# Internal implementation extensions keep this file as the stable public facade.\n"
    "from levelkit.api import install_into as _install_levelkit_extensions\n"
    "_install_levelkit_extensions(globals())\n"
)
if hook in text:
    raise SystemExit(0)
if marker not in text:
    raise SystemExit("level_kit.py footer changed; refusing to patch blindly")
path.write_text(text.replace(marker, hook + marker), encoding="utf-8", newline="\n")
