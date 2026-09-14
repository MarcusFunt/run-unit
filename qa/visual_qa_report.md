# RUN//UNIT visual QA report

## Pass 1 findings

- The main menu action buttons were too narrow for their role and the screen had little operational context.
- The level selector header and footer overflowed at the project viewport (960x540), and the briefing copy consumed too much vertical space.
- Gameplay used a very bright, flat terrain slab that dominated the lower half of the frame.
- The robot silhouette was too small relative to the playfield.
- Gameplay instructions were a single crowded line drawn directly over the world.
- Pause labels were generic and did not match RUN//UNIT terminology.
- The death screen did not include the route number and its Sector Select action returned to the main menu instead of the selector.

## Implemented

- Main menu buttons now use wider action targets and RUN//UNIT-specific labels, with system status and navigation hints.
- Level selector now uses a viewport-safe two-column grid, compact mission briefing, explicit status data, and a dedicated Deploy action.
- Sector selector arrow navigation is handled explicitly, and selecting a sector moves focus to Deploy.
- Terrain colors were muted, the robot art scale increased, and the HUD instructions moved into a framed status bar.
- Pause labels now identify the run, route restart, and desktop exit actions.
- Death results now identify the route and return to the level selector.

## Pass 2 result

- Main menu, level selector, selector focus movement, gameplay, and death state were visually rechecked after a clean restart.
- Level selector UI report: zero zero-size, offscreen, and overlap findings at 960x540.
- Gameplay HUD UI report: zero zero-size, offscreen, and overlap findings.
- Pause scene UI report: zero zero-size, offscreen, and overlap findings.
- Main menu background-underlay overlap reports are intentional decorative layering, not visible layout collisions.
