class_name RunUnitEnding
extends Control

## The ending screen.
##
## Level 3 hands off here once UNIT-07 installs the module: the city it just
## crossed is lit again and Beacon 9 burns on the skyline. The vista is a still
## illustration, so everything that sells it as a living place is layered over
## it here -- the ignition column breathing, embers and steam drifting up off
## the refinery, windows blinking across the city, and UNIT-07 itself standing
## in the foreground watching the thing it just restored.

@export_range(0.0, 3.0, 0.05) var status_delay: float = 0.8
@export_range(0.0, 4.0, 0.05) var thanks_delay: float = 1.8
@export_range(0.0, 5.0, 0.05) var buttons_delay: float = 3.0
@export_range(0.1, 3.0, 0.05) var fade_duration: float = 1.2
## A push this slow reads as the scene breathing, not as a camera move.
@export_range(1.0, 1.3, 0.005) var push_in_scale: float = 1.05
@export_range(5.0, 120.0, 1.0) var push_in_duration: float = 60.0
## Seconds for one full dim-to-bright-to-dim of the ignition column.
@export_range(0.5, 8.0, 0.1) var pulse_period: float = 2.6

## Hands-off demo/movie runs linger long enough to show the completed ending,
## then exit cleanly so Godot's movie writer can finalize the capture.
const DEMO_END_HOLD_SECONDS: float = 2.0
## Tests can disable the process-level quit while still exercising the exact
## same completion bookkeeping as a real movie/demo run.
@export var auto_quit_demo: bool = true

@onready var vista: TextureRect = %Vista
@onready var beacon_halo: Polygon2D = %BeaconHalo
@onready var beacon_column: Polygon2D = %BeaconColumn
@onready var beacon_ring: Polygon2D = %BeaconRing
@onready var twinkles: Node2D = %Twinkles
@onready var unit_07: Node2D = %Unit07
@onready var status_label: Label = %StatusLabel
@onready var thanks_label: Label = %ThanksLabel
@onready var buttons: Control = %Buttons
@onready var sector_button: Button = %SectorButton
@onready var menu_button: Button = %MenuButton

var _reveal: Tween
var _push: Tween
var _loops: Array[Tween] = []

func _ready() -> void:
	if not sector_button.pressed.is_connected(_on_sector_pressed):
		sector_button.pressed.connect(_on_sector_pressed)
	if not menu_button.pressed.is_connected(_on_main_menu_pressed):
		menu_button.pressed.connect(_on_main_menu_pressed)
	status_label.modulate.a = 0.0
	thanks_label.modulate.a = 0.0
	buttons.modulate.a = 0.0
	# The player has finished the campaign; nothing should resume mid-route.
	RunUnitSession.clear_checkpoint()
	_start_push_in()
	_start_life()
	_start_reveal()
	if RunUnitSession.demo_mode:
		RunUnitSession.mark_demo_completed()
		if auto_quit_demo:
			_quit_demo_after_reveal()

func _start_push_in() -> void:
	if _push != null and _push.is_valid():
		_push.kill()
	vista.scale = Vector2.ONE
	_push = create_tween()
	_push.tween_property(vista, "scale", Vector2.ONE * push_in_scale, push_in_duration)

## The beacon breathes, the windows blink, and UNIT-07 idles. The three run on
## deliberately unrelated periods so the screen never visibly loops.
func _start_life() -> void:
	for loop: Tween in _loops:
		if loop != null and loop.is_valid():
			loop.kill()
	_loops.clear()
	_pulse(beacon_column, 0.16, 0.34, pulse_period)
	_pulse(beacon_halo, 0.05, 0.13, pulse_period * 1.45)
	_pulse(beacon_ring, 0.18, 0.4, pulse_period * 0.8)
	var index: int = 0
	for child: Node in twinkles.get_children():
		var light: CanvasItem = child as CanvasItem
		if light == null:
			continue
		index += 1
		_pulse(light, 0.1, 0.95, 1.3 + 0.37 * index)
	var bob: Tween = create_tween().set_loops()
	var resting_y: float = unit_07.position.y
	bob.tween_property(unit_07, "position:y", resting_y - 2.0, 1.7).set_trans(Tween.TRANS_SINE)
	bob.tween_property(unit_07, "position:y", resting_y, 1.7).set_trans(Tween.TRANS_SINE)
	_loops.append(bob)

func _pulse(item: CanvasItem, low: float, high: float, period: float) -> void:
	var loop: Tween = create_tween().set_loops()
	loop.tween_property(item, "modulate:a", high, period * 0.5).set_trans(Tween.TRANS_SINE)
	loop.tween_property(item, "modulate:a", low, period * 0.5).set_trans(Tween.TRANS_SINE)
	_loops.append(loop)

func _start_reveal() -> void:
	if _reveal != null and _reveal.is_valid():
		_reveal.kill()
	var thanks_rest: float = thanks_label.position.y
	thanks_label.position.y = thanks_rest + 16.0
	_reveal = create_tween()
	_reveal.tween_interval(status_delay)
	_reveal.tween_property(status_label, "modulate:a", 1.0, fade_duration)
	_reveal.tween_interval(maxf(thanks_delay - status_delay - fade_duration, 0.0))
	_reveal.tween_property(thanks_label, "modulate:a", 1.0, fade_duration)
	_reveal.parallel().tween_property(thanks_label, "position:y", thanks_rest, fade_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal.tween_interval(maxf(buttons_delay - thanks_delay - fade_duration, 0.0))
	_reveal.tween_property(buttons, "modulate:a", 1.0, fade_duration)
	_reveal.tween_callback(sector_button.grab_focus)

func _quit_demo_after_reveal() -> void:
	await get_tree().create_timer(buttons_delay + fade_duration + DEMO_END_HOLD_SECONDS).timeout
	if not RunUnitSession.demo_mode or not RunUnitSession.demo_completed:
		return
	print("DEMO_PROCESS_EXIT")
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_main_menu_pressed()
		get_viewport().set_input_as_handled()

func _on_sector_pressed() -> void:
	SceneLoader.load_scene("res://scenes/level_selector.tscn")

func _on_main_menu_pressed() -> void:
	SceneLoader.load_scene("res://scenes/main_menu.tscn")
