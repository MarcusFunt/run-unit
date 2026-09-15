extends Node2D

## Drawn-in-world dressing for the authored Maintenance Shaft tutorial.
## The collision route remains in world.tscn; this layer only makes the route
## legible as a service shaft and gives each lesson a distinct visual identity.

@export var foreground: bool = false
@export var route_length: float = 4864.0

const WALL_SHADOW: Color = Color(0.012, 0.040, 0.060, 0.92)
const WALL_PANEL: Color = Color(0.030, 0.110, 0.145, 0.72)
const WALL_EDGE: Color = Color(0.090, 0.310, 0.360, 0.42)
const STEEL_DARK: Color = Color(0.045, 0.140, 0.175, 0.92)
const STEEL_MID: Color = Color(0.110, 0.290, 0.330, 0.95)
const SIGNAL_TEAL: Color = Color(0.300, 0.930, 0.900, 0.88)
const SIGNAL_AMBER: Color = Color(1.000, 0.620, 0.180, 0.96)
const PANEL_INSET: Color = Color(0.020, 0.080, 0.105, 0.70)

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

	var cable_y: float = 74.0
	while cable_y <= 126.0:
		draw_line(Vector2(-256.0, cable_y), Vector2(route_length + 256.0, cable_y), Color(0.100, 0.360, 0.390, 0.42), 2.0)
		cable_y += 18.0

	var cable_x: int = 0
	while cable_x <= int(route_length):
		draw_line(Vector2(float(cable_x), 72.0), Vector2(float(cable_x) + 22.0, 146.0), Color(0.120, 0.390, 0.420, 0.42), 1.0)
		draw_circle(Vector2(float(cable_x) + 22.0, 146.0), 3.0, Color(0.180, 0.570, 0.600, 0.52))
		cable_x += 384

func _draw_foreground() -> void:
	_draw_tutorial_marker(Vector2(360.0, 238.0), SIGNAL_TEAL)
	_draw_tutorial_marker(Vector2(900.0, 238.0), SIGNAL_AMBER)
	_draw_tutorial_marker(Vector2(1230.0, 206.0), SIGNAL_AMBER)
	_draw_tutorial_marker(Vector2(1770.0, 206.0), SIGNAL_TEAL)

	_draw_platform_surface(0.0, 448.0, 736.0, SIGNAL_TEAL)
	_draw_platform_surface(832.0, 448.0, 448.0, SIGNAL_TEAL)
	_draw_platform_surface(1504.0, 416.0, 640.0, SIGNAL_AMBER)
	_draw_platform_surface(2144.0, 416.0, 896.0, SIGNAL_TEAL)
	_draw_platform_surface(3136.0, 384.0, 320.0, SIGNAL_AMBER)
	_draw_platform_surface(3584.0, 416.0, 1024.0, SIGNAL_TEAL)

	_draw_gap_marker(736.0, 832.0, 448.0, SIGNAL_TEAL)
	_draw_gap_marker(1280.0, 1504.0, 448.0, SIGNAL_AMBER)
	_draw_gap_marker(3040.0, 3136.0, 416.0, SIGNAL_AMBER)
	_draw_gap_marker(3456.0, 3584.0, 416.0, SIGNAL_TEAL)

	_draw_gate_frame()
	_draw_completion_beacon()

func _draw_tutorial_marker(anchor: Vector2, accent: Color) -> void:
	var rail_x: float = anchor.x - 174.0

	draw_line(Vector2(rail_x, anchor.y - 46.0), Vector2(rail_x, anchor.y + 24.0), Color(accent, 0.9), 2.0)

func _draw_platform_surface(surface_x: float, surface_y: float, surface_width: float, accent: Color) -> void:
	draw_rect(Rect2(surface_x, surface_y, surface_width, 8.0), STEEL_DARK)
	draw_rect(Rect2(surface_x, surface_y, surface_width, 3.0), accent)
	draw_line(Vector2(surface_x, surface_y + 10.0), Vector2(surface_x + surface_width, surface_y + 10.0), STEEL_MID, 1.0)
	draw_rect(Rect2(surface_x + 14.0, surface_y + 28.0, surface_width - 28.0, 76.0), PANEL_INSET)

	var marker_x: float = surface_x + 38.0
	while marker_x < surface_x + surface_width - 28.0:
		draw_rect(Rect2(marker_x, surface_y + 16.0, 28.0, 4.0), accent)
		draw_line(Vector2(marker_x, surface_y + 29.0), Vector2(marker_x, surface_y + 98.0), Color(0.180, 0.430, 0.460, 0.38), 1.0)
		marker_x += 88.0

	draw_line(Vector2(surface_x + 18.0, surface_y + 120.0), Vector2(surface_x + surface_width - 18.0, surface_y + 120.0), Color(0.100, 0.300, 0.340, 0.48), 2.0)

func _draw_gap_marker(start_x: float, end_x: float, surface_y: float, accent: Color) -> void:
	var midpoint: float = (start_x + end_x) * 0.5
	draw_line(Vector2(start_x + 10.0, surface_y - 12.0), Vector2(midpoint - 8.0, surface_y - 12.0), Color(accent, 0.66), 2.0)
	draw_line(Vector2(midpoint + 8.0, surface_y - 12.0), Vector2(end_x - 10.0, surface_y - 12.0), Color(accent, 0.66), 2.0)
	draw_line(Vector2(midpoint - 8.0, surface_y - 20.0), Vector2(midpoint, surface_y - 12.0), accent, 2.0)
	draw_line(Vector2(midpoint, surface_y - 12.0), Vector2(midpoint + 8.0, surface_y - 20.0), accent, 2.0)

func _draw_gate_frame() -> void:
	draw_line(Vector2(1890.0, 356.0), Vector2(1890.0, 416.0), SIGNAL_AMBER, 3.0)
	draw_line(Vector2(2006.0, 356.0), Vector2(2006.0, 416.0), SIGNAL_AMBER, 3.0)
	draw_circle(Vector2(1890.0, 350.0), 5.0, SIGNAL_AMBER)
	draw_circle(Vector2(2006.0, 350.0), 5.0, SIGNAL_AMBER)
	draw_line(Vector2(1908.0, 405.0), Vector2(1940.0, 405.0), SIGNAL_TEAL, 2.0)
	draw_line(Vector2(1956.0, 405.0), Vector2(1988.0, 405.0), SIGNAL_TEAL, 2.0)

func _draw_completion_beacon() -> void:
	draw_rect(Rect2(4232.0, 196.0, 210.0, 112.0), Color(0.008, 0.040, 0.055, 0.82))
	draw_rect(Rect2(4232.0, 196.0, 210.0, 112.0), Color(SIGNAL_TEAL, 0.62), false, 2.0)
	draw_circle(Vector2(4337.0, 236.0), 14.0, Color(0.120, 0.800, 0.740, 0.34))
	draw_circle(Vector2(4337.0, 236.0), 6.0, SIGNAL_TEAL)
	draw_line(Vector2(4270.0, 276.0), Vector2(4404.0, 276.0), SIGNAL_TEAL, 2.0)
