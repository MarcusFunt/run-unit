class_name RunUnitEnvironmentBackdrop
extends Node2D

## Low-contrast, non-colliding environmental storytelling behind authored
## gameplay geometry. Everything is snapped to chunky pixel-art dimensions so
## the extra depth reads as part of RUN//UNIT rather than smooth vector art.
@export_enum("tutorial", "factory", "recovery", "beacon") var theme: String = "tutorial"

const INK := Color(0.008, 0.025, 0.036, 0.92)
const PANEL := Color(0.025, 0.075, 0.09, 0.78)
const PANEL_LIFT := Color(0.045, 0.13, 0.15, 0.62)
const STEEL := Color(0.075, 0.18, 0.20, 0.72)
const CYAN := Color(0.28, 0.82, 0.84, 0.42)
const CYAN_DIM := Color(0.14, 0.45, 0.50, 0.30)
const AMBER := Color(1.0, 0.48, 0.15, 0.46)
const WINDOW := Color(0.18, 0.52, 0.58, 0.30)

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	match theme:
		"tutorial":
			_draw_tutorial()
		"factory":
			_draw_factory()
		"recovery":
			_draw_recovery()
		"beacon":
			_draw_beacon()
func _draw_tutorial() -> void:
	# Calibration should feel like a purpose-built test tunnel, not a flat wall.
	_draw_pipe(Vector2(-100, 110), Vector2(2300, 110), 10.0, STEEL)
	_draw_pipe(Vector2(-100, 142), Vector2(2300, 142), 5.0, CYAN_DIM)
	for x: float in range(-64, 2305, 320):
		_draw_bay(x, 78, 272, 286, false)
		_draw_rib(x, 58, 430)
		_draw_light(Vector2(x + 44, 186), CYAN)
		if posmod(int(x / 320.0), 3) == 1:
			_draw_light(Vector2(x + 76, 186), AMBER)
	# A recessed service trench gives the lower half a second plane of depth.
	draw_rect(Rect2(-128, 356, 2460, 150), INK, true)
	for x: float in range(-96, 2305, 160):
		draw_rect(Rect2(x, 374, 112, 58), PANEL, true)
		draw_line(Vector2(x, 438), Vector2(x + 112, 438), CYAN_DIM, 3.0)
	# One oversized calibration fan breaks the otherwise regular bay rhythm and
	# gives the tutorial a recognisable landmark in B-roll.
	_draw_fan(Vector2(1110, 255), 72.0, Color(0.07, 0.19, 0.21, 0.54))
	_draw_pipe(Vector2(1110, 175), Vector2(1110, 110), 7.0, STEEL)
	# Heavier framing toward the elevator makes the route endpoint read early.
	_draw_rib(1870, 42, 470, 18.0)
	_draw_rib(2040, 42, 470, 18.0)
	draw_rect(Rect2(1870, 66, 170, 12), AMBER, true)

func _draw_factory() -> void:
	# Transfer hall: long overhead services and deep machinery silhouettes.
	_draw_pipe(Vector2(-80, 96), Vector2(2700, 96), 12.0, STEEL)
	_draw_pipe(Vector2(-80, 130), Vector2(2700, 130), 5.0, CYAN_DIM)
	for x: float in range(0, 2700, 384):
		_draw_bay(x + 24, 150, 304, 300, true)
		_draw_rib(x, 70, 510)
		_draw_light(Vector2(x + 54, 214), CYAN)
	# Warehouse: make the stored units read as shelves extending into a vast bay.
	draw_rect(Rect2(2860, 136, 3240, 500), Color(0.012, 0.04, 0.05, 0.74), true)
	for y: float in [260.0, 420.0, 580.0]:
		draw_rect(Rect2(2920, y, 3130, 7), STEEL, true)
		draw_rect(Rect2(2920, y + 8, 3130, 3), CYAN_DIM, true)
	for x: float in range(2920, 6080, 256):
		draw_rect(Rect2(x, 188, 9, 410), STEEL, true)
		if posmod(int(x / 256.0), 4) == 0:
			_draw_light(Vector2(x + 22, 210), AMBER)
	# Overhead crane rail breaks the repeating robot grid with a large landmark.
	draw_rect(Rect2(3030, 92, 2780, 18), Color(0.08, 0.20, 0.22, 0.80), true)
	draw_rect(Rect2(4100, 110, 230, 34), Color(0.13, 0.28, 0.29, 0.74), true)
	draw_line(Vector2(4215, 144), Vector2(4215, 222), AMBER, 4.0)
	# The warehouse is long enough that a second recognisable shape is useful:
	# a pair of extraction fans reads immediately even under voice-over cuts.
	_draw_fan(Vector2(3490, 360), 92.0, Color(0.055, 0.15, 0.17, 0.52))
	_draw_fan(Vector2(5350, 360), 70.0, Color(0.055, 0.15, 0.17, 0.42))
	# Exterior breach: sparse lights and power lines make leaving the factory
	# feel like a real spatial transition rather than merely a palette change.
	for x: float in range(6260, 7700, 170):
		var h: float = 120.0 + float(posmod(int(x / 10.0), 5)) * 26.0
		draw_rect(Rect2(x, 650 - h, 96, h + 530), Color(0.012, 0.045, 0.055, 0.62), true)
		for yy: float in range(680 - int(h), 690, 36):
			if posmod(int(x + yy), 3) != 0:
				draw_rect(Rect2(x + 18, yy, 8, 4), WINDOW, true)
	_draw_pipe(Vector2(6200, 286), Vector2(7700, 238), 4.0, Color(0.12, 0.34, 0.36, 0.42))

func _draw_recovery() -> void:
	# Street: broad silhouettes between the tiled route and far parallax stop the
	# skyline from reading as one repeating wallpaper strip.
	for x: float in range(-160, 4800, 720):
		_draw_city_pylon(x, 176, 530)
		if posmod(int(x / 720.0), 2) == 0:
			draw_rect(Rect2(x + 84, 286, 390, 14), Color(0.035, 0.11, 0.13, 0.55), true)
			draw_rect(Rect2(x + 110, 306, 338, 5), CYAN_DIM, true)
	# Reserve Depot 03 is the longest visually flat passage in the recording.
	# Give it numbered-looking service bays, pipes and pools of work light.
	draw_rect(Rect2(4820, 108, 5200, 760), Color(0.008, 0.025, 0.034, 0.70), true)
	_draw_pipe(Vector2(4840, 136), Vector2(10010, 136), 13.0, STEEL)
	_draw_pipe(Vector2(4840, 172), Vector2(10010, 172), 5.0, CYAN_DIM)
	for x: float in range(4920, 9960, 480):
		_draw_bay(x, 210, 388, 520, true)
		_draw_rib(x - 28, 178, 810, 14.0)
		_draw_light(Vector2(x + 34, 246), CYAN)
		# Three bars read like bay-number plaques without introducing tiny text.
		for bar: int in range(3):
			draw_rect(Rect2(x + 70 + bar * 14, 238, 8, 3 + bar * 2), AMBER, true)
	# Break the five-screen-long depot repetition with two large mechanical
	# landmarks. They remain deliberately dimmer than hazards and pickups.
	_draw_fan(Vector2(6420, 430), 112.0, Color(0.055, 0.16, 0.18, 0.54))
	_draw_tank(Rect2(7540, 300, 230, 430))
	_draw_pipe(Vector2(7655, 300), Vector2(7655, 174), 9.0, STEEL)
	# The module vault gets a clear cyan focal corridor before the pickup.
	draw_rect(Rect2(8710, 190, 760, 540), Color(0.03, 0.12, 0.14, 0.35), true)
	for x: float in range(8780, 9450, 112):
		draw_line(Vector2(x, 226), Vector2(x - 40, 700), Color(0.20, 0.68, 0.72, 0.16), 4.0)
	_draw_light(Vector2(9184, 226), Color(0.40, 0.95, 0.94, 0.58), 26.0)
	# Re-emerge into the city after the depot.
	for x: float in range(10060, 11200, 420):
		_draw_city_pylon(x, 220, 550)
func _draw_beacon() -> void:
	# Exterior city approach: occasional massive infrastructure silhouettes
	# provide scale while leaving the existing multi-layer skyline readable.
	for x: float in range(-120, 9300, 1120):
		var height: float = 330.0 + float(posmod(int(x / 40.0), 4)) * 70.0
		draw_rect(Rect2(x, 620 - height, 140, height + 420), Color(0.012, 0.045, 0.055, 0.42), true)
		draw_rect(Rect2(x + 18, 620 - height + 36, 8, height - 40), Color(0.09, 0.25, 0.27, 0.34), true)
		for yy: float in range(int(650 - height), 590, 54):
			draw_rect(Rect2(x + 52, yy, 12, 4), WINDOW, true)
	# Elevated utility routes repeatedly cross the skyline, but at a deliberately
	# irregular cadence so the background does not reveal a 960 px texture loop.
	for x: float in [980.0, 2860.0, 5120.0, 7480.0]:
		draw_rect(Rect2(x, 248, 620, 18), Color(0.035, 0.105, 0.12, 0.42), true)
		draw_line(Vector2(x + 60, 266), Vector2(x + 10, 470), STEEL, 7.0)
		draw_line(Vector2(x + 560, 266), Vector2(x + 610, 470), STEEL, 7.0)
	# Unique infrastructure beats prevent the approach from feeling like the
	# same skyline tile sliding forever.
	_draw_fan(Vector2(3880, 370), 108.0, Color(0.04, 0.12, 0.14, 0.42))
	_draw_tank(Rect2(6550, 286, 260, 390))
	_draw_pipe(Vector2(6680, 286), Vector2(6680, 176), 8.0, Color(0.10, 0.30, 0.32, 0.42))
	# The final megastructure should engulf the frame before the ignition room.
	draw_rect(Rect2(11300, -420, 3000, 1510), Color(0.008, 0.026, 0.035, 0.76), true)
	for x: float in range(11420, 14120, 360):
		_draw_rib(x, -160, 1000, 20.0)
		draw_rect(Rect2(x + 42, 86, 220, 10), Color(0.09, 0.25, 0.27, 0.52), true)
		if posmod(int(x / 360.0), 2) == 0:
			_draw_light(Vector2(x + 72, 128), AMBER)
	# Ignition interior: vertical scale, dark ribs, and restrained energized strips.
	for x: float in range(14220, 16320, 300):
		draw_rect(Rect2(x, -520, 22, 1580), Color(0.08, 0.18, 0.20, 0.64), true)
		draw_rect(Rect2(x + 22, -520, 4, 1580), CYAN_DIM, true)
	for y: float in range(-260, 900, 220):
		draw_rect(Rect2(14160, y, 2100, 8), Color(0.055, 0.14, 0.16, 0.42), true)

func _draw_bay(x: float, y: float, width: float, height: float, lit: bool) -> void:
	draw_rect(Rect2(x, y, width, height), PANEL, true)
	draw_rect(Rect2(x + 14, y + 16, width - 28, height - 32), INK, true)
	draw_rect(Rect2(x + 24, y + 30, width - 48, 8), STEEL, true)
	if lit:
		draw_rect(Rect2(x + 24, y + 46, width * 0.42, 4), CYAN_DIM, true)
func _draw_rib(x: float, top: float, bottom: float, width: float = 11.0) -> void:
	draw_rect(Rect2(x, top, width, bottom - top), STEEL, true)
	draw_line(Vector2(x + width, top), Vector2(x + width, bottom), Color(0.12, 0.30, 0.31, 0.42), 2.0)
	# Small diagonal foot suggests a structural brace without masking gameplay.
	draw_line(Vector2(x + width, bottom - 82), Vector2(x + 48, bottom), Color(0.06, 0.16, 0.18, 0.56), 6.0)

func _draw_pipe(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, color, width)
	draw_circle(a, width * 0.62, color)
	draw_circle(b, width * 0.62, color)

func _draw_light(position: Vector2, color: Color, size: float = 14.0) -> void:
	draw_rect(Rect2(position - Vector2(size * 0.8, size * 0.28), Vector2(size * 1.6, size * 0.56)), color, true)
	draw_rect(Rect2(position - Vector2(size * 1.8, size * 0.55), Vector2(size * 3.6, size * 1.1)), Color(color.r, color.g, color.b, color.a * 0.12), true)

func _draw_fan(center: Vector2, radius: float, color: Color) -> void:
	# A chunky ring and four thick radial blades stay legible at 540p without
	# introducing smooth high-detail art that would clash with the tileset.
	draw_circle(center, radius, Color(color.r, color.g, color.b, color.a * 0.24))
	draw_arc(center, radius, 0.0, TAU, 24, color, maxf(radius * 0.07, 5.0))
	draw_arc(center, radius * 0.72, 0.0, TAU, 20, Color(color.r, color.g, color.b, color.a * 0.72), maxf(radius * 0.04, 3.0))
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * radius * 0.18, center + direction * radius * 0.62, color, maxf(radius * 0.14, 6.0))
	draw_circle(center, radius * 0.13, color)

func _draw_tank(rect: Rect2) -> void:
	var body := Color(0.035, 0.11, 0.13, 0.48)
	var edge := Color(0.09, 0.25, 0.27, 0.44)
	draw_rect(rect, body, true)
	draw_rect(Rect2(rect.position + Vector2(12, 16), Vector2(rect.size.x - 24, 8)), edge, true)
	draw_rect(Rect2(rect.position + Vector2(18, 42), Vector2(8, rect.size.y - 64)), edge, true)
	for y: float in [rect.position.y + rect.size.y * 0.35, rect.position.y + rect.size.y * 0.68]:
		draw_rect(Rect2(rect.position.x - 8, y, rect.size.x + 16, 7), edge, true)
	_draw_light(rect.position + Vector2(rect.size.x * 0.5, 58), AMBER, 10.0)

func _draw_city_pylon(x: float, top: float, bottom: float) -> void:
	var silhouette := Color(0.014, 0.055, 0.066, 0.48)
	draw_rect(Rect2(x, top, 48, bottom - top), silhouette, true)
	draw_line(Vector2(x + 24, top), Vector2(x - 74, bottom), silhouette, 11.0)
	draw_line(Vector2(x + 24, top), Vector2(x + 122, bottom), silhouette, 11.0)
	draw_rect(Rect2(x - 76, top + 64, 200, 9), Color(0.07, 0.20, 0.22, 0.34), true)
	_draw_light(Vector2(x + 24, top + 48), CYAN_DIM, 10.0)
