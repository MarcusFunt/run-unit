# RUN//UNIT contributor guide

## Stack

- Godot 4.7, GDScript, and text-based `.tscn` / `.tres` resources.
- GUT is bundled under `addons/gut` for automated tests.

## Local commands

```sh
# Open or run in Godot
godot --editor --path .
godot --path .

# Run all GUT tests
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

## Repository boundaries

- Commit gameplay source, scenes, themes, assets, add-ons, test scripts, test
  scenarios, and useful project documentation.
- Do not commit Godot's `.godot/` cache, staged add-on/template folders,
  exports, local settings, secrets, logs, or rendered QA/validation artefacts.
- Keep `.uid` files next to GDScript source when Godot creates them; they are
  source identifiers, not editor cache files.
- Keep Godot scene/resource files as text and preserve their LF line endings.

## Change discipline

- Keep feature, test, and repository-hygiene changes easy to review.
- Run the relevant GUT suite before committing gameplay changes.
- Never force-push shared branches or commit credentials.
