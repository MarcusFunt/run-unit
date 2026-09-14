# RUN//UNIT debugger validation

## Findings

- GUT had no configured test directories, so its CLI exited with an error before running tests.
- Headless editor runs produced plugin teardown noise and a Maaack editor-only scene-save call attempted to process a null thumbnail texture.

## Fixes

- Added `.gutconfig.json` and four smoke tests in `tests/test_project_smoke.gd`.
- Marked installer/staging and non-mono C# sample directories as editor-ignored.

## Verification

- GUT: 4/4 tests passed, exit code 0.
- Project scenes: 11/11 loaded and instantiated with 0 errors/warnings.
- Active Maaack window scenes: 4/4 loaded and instantiated with 0 errors/warnings.
- Project scripts: 18/18 parsed with 0 errors/warnings.
- Runtime boot: 0 errors, 0 parse errors, 0 warnings.
