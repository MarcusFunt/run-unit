extends Node2D

## Drawn-in-world dressing for the authored Maintenance Shaft tutorial.
## Gameplay geometry and collision come from the Tiled-authored level
## (assets/tiled/levels/maintenance_shaft.tmj); this layer is level-specific
## presentation only, making the route legible as a service shaft and giving
## each lesson a distinct visual identity.

@export var foreground: bool = false
@export var route_length: float = 4864.0

const WALL_SHADOW: Color = Color(0.012, 0.040, 0.060, 0.92)
const WALL_PANEL: Color = Color(0.030, 0.110, 0.145, 0.72)
const WALL_EDGE: Color = Color(0.090, 0.310, 0.360, 0.42)
const SIGNAL_TEAL: Color = Color(0.300, 0.930, 0.900, 0.88)
const SIGNAL_AMBER: Color = Color(1.000, 0.620, 0.180, 0.96)
const GATE_UNDERSIDE: Color = Color(0.129, 0.255, 0.353, 1.0)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	if foreground:
		_draw_foreground()
		return
	_draw_background()

func _draw_background() -> void:
	draw_rect(Rect2(-256.0, -360.0, route_length + 512.0, 780.0), WALL_SHADOW)
	draw_rect(Rect2(-256.0, 308.0, route_length + 512.0, 118.0), Color(0.035, 0.180, 0.205, 0.32))

	var rib_x: int = -128
	while rib_x <= int(route_length) + 128:
		draw_rect(Rect2(float(rib_x), -300.0, 148.0, 570.0), WALL_PANEL)
		draw_line(Vector2(float(rib_x), -300.0), Vector2(float(rib_x), 306.0), WALL_EDGE, 2.0)
		draw_line(Vector2(float(rib_x) + 148.0, -300.0), Vector2(float(rib_x) + 148.0, 306.0), WALL_EDGE, 1.0)
		draw_rect(Rect2(float(rib_x) + 18.0, -152.0, 112.0, 54.0), Color(0.015, 0.065, 0.087, 0.78))
		draw_line(Vector2(float(rib_x) + 26.0, -125.0), Vector2(float(rib_x) + 122.0, -125.0), Color(0.140, 0.420, 0.440, 0.28), 1.0)
		draw_circle(Vector2(float(rib_x) + 30.0, -125.0), 2.0, SIGNAL_TEAL)
		rib_x += 256

	# Kept well above the highest point the (now 64px-tall) robot's antenna
	# reaches at the peak of a full charged jump (~world y=125 from the lowest
	# deck) -- at the old y=74-146 these purely decorative, non-collidable
	# cables sat right in the jump arc and looked like a low ceiling the
	# player was clipping through.
	var cable_y: float = -76.0
	while cable_y <= -24.0:
		draw_line(Vector2(-256.0, cable_y), Vector2(route_length + 256.0, cable_y), Color(0.100, 0.360, 0.390, 0.42), 2.0)
		cable_y += 18.0

	var cable_x: int = 0
	while cable_x <= int(route_length):
		draw_line(Vector2(float(cable_x), -78.0), Vector2(float(cable_x) + 22.0, -4.0), Color(0.120, 0.390, 0.420, 0.42), 1.0)
		draw_circle(Vector2(float(cable_x) + 22.0, -4.0), 3.0, Color(0.180, 0.570, 0.600, 0.52))
		cable_x += 384

func _draw_foreground() -> void:
	_draw_tutorial_marker(Vector2(360.0, 238.0), SIGNAL_TEAL)
	_draw_tutorial_marker(Vector2(900.0, 238.0), SIGNAL_AMBER)
	_draw_tutorial_marker(Vector2(1230.0, 206.0), SIGNAL_AMBER)
	_draw_tutorial_marker(Vector2(1770.0, 206.0), SIGNAL_TEAL)

	_draw_gap_marker(736.0, 832.0, 448.0, SIGNAL_TEAL)
	_draw_gap_marker(1280.0, 1504.0, 448.0, SIGNAL_AMBER)
	_draw_gap_marker(3040.0, 3136.0, 416.0, SIGNAL_AMBER)
	_draw_gap_marker(3456.0, 3584.0, 416.0, SIGNAL_TEAL)

	_draw_gate_frame()
	_draw_completion_beacon()

func _draw_tutorial_marker(anchor: Vector2, accent: Color) -> void:
	var rail_x: float = anchor.x - 174.0

	draw_line(Vector2(rail_x, anchor.y - 46.0), Vector2(rail_x, anchor.y + 24.0), Color(accent, 0.9), 2.0)

func _draw_gap_marker(start_x: float, end_x: float, surface_y: float, accent: Color) -> void:
	var midpoint: float = (start_x + end_x) * 0.5
	draw_line(Vector2(start_x + 10.0, surface_y - 12.0), Vector2(midpoint - 8.0, surface_y - 12.0), Color(accent, 0.66), 2.0)
	draw_line(Vector2(midpoint + 8.0, surface_y - 12.0), Vector2(end_x - 10.0, surface_y - 12.0), Color(accent, 0.66), 2.0)
	draw_line(Vector2(midpoint - 8.0, surface_y - 20.0), Vector2(midpoint, surface_y - 12.0), accent, 2.0)
	draw_line(Vector2(midpoint, surface_y - 12.0), Vector2(midpoint + 8.0, surface_y - 20.0), accent, 2.0)

## Posts bracket the gate cells at tiles 59-61 (x 1888-1984); the gate's
## underside sits at y=358, 58px above the deck, so a standing (64px) player
## must crouch (36px) to pass. Only the underside (drawn here) is visible --
## the tile's actual collider (semantic_layer.tsj, "low_clearance_overhang")
## extends far above the cell, all the way past the top of a full charged
## jump's arc. The Semantic layer is wide open above this column, so a
## collider confined to the 32px cell let a player jump clean over the gate
## and land standing on top of it; the tall collider makes it a true
## impassable ceiling instead of a floating landable platform.
func _draw_gate_frame() -> void:
	draw_rect(Rect2(1888.0, 352.0, 96.0, 6.0), GATE_UNDERSIDE)
	draw_rect(Rect2(1888.0, 356.0, 96.0, 2.0), SIGNAL_AMBER)
	draw_line(Vector2(1878.0, 352.0), Vector2(1878.0, 416.0), SIGNAL_AMBER, 3.0)
	draw_line(Vector2(1994.0, 352.0), Vector2(1994.0, 416.0), SIGNAL_AMBER, 3.0)
	draw_circle(Vector2(1878.0, 346.0), 5.0, SIGNAL_AMBER)
	draw_circle(Vector2(1994.0, 346.0), 5.0, SIGNAL_AMBER)
	draw_line(Vector2(1896.0, 405.0), Vector2(1928.0, 405.0), SIGNAL_TEAL, 2.0)
	draw_line(Vector2(1944.0, 405.0), Vector2(1976.0, 405.0), SIGNAL_TEAL, 2.0)

func _draw_completion_beacon() -> void:
	draw_rect(Rect2(4232.0, 196.0, 210.0, 112.0), Color(0.008, 0.040, 0.055, 0.82))
	draw_rect(Rect2(4232.0, 196.0, 210.0, 112.0), Color(SIGNAL_TEAL, 0.62), false, 2.0)
	draw_circle(Vector2(4337.0, 236.0), 14.0, Color(0.120, 0.800, 0.740, 0.34))
	draw_circle(Vector2(4337.0, 236.0), 6.0, SIGNAL_TEAL)
	draw_line(Vector2(4270.0, 276.0), Vector2(4404.0, 276.0), SIGNAL_TEAL, 2.0)
