class_name RunUnitEnding
extends Control

## The ending screen.
##
## Level 3 hands off here once UNIT-07 installs the module: the city it just
## crossed is lit again, Beacon 9 burns on the skyline, and the game thanks the
## player. The vista holds on screen with a slow push in, and the copy fades up
## over it a line at a time rather than arriving all at once.

@export_range(0.0, 3.0, 0.05) var status_delay: float = 0.8
@export_range(0.0, 4.0, 0.05) var thanks_delay: float = 1.8
@export_range(0.0, 5.0, 0.05) var buttons_delay: float = 3.0
@export_range(0.1, 3.0, 0.05) var fade_duration: float = 1.2
## A push this slow reads as the scene breathing, not as a camera move.
@export_range(1.0, 1.3, 0.005) var push_in_scale: float = 1.06
@export_range(5.0, 120.0, 1.0) var push_in_duration: float = 45.0

@onready var vista: TextureRect = %Vista
@onready var status_label: Label = %StatusLabel
@onready var thanks_label: Label = %ThanksLabel
@onready var buttons: Control = %Buttons
@onready var sector_button: Button = %SectorButton
@onready var menu_button: Button = %MenuButton

var _reveal: Tween
var _push: Tween

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
	_start_reveal()

func _start_push_in() -> void:
	if _push != null and _push.is_valid():
		_push.kill()
	vista.scale = Vector2.ONE
	_push = create_tween()
	_push.tween_property(vista, "scale", Vector2.ONE * push_in_scale, push_in_duration)

func _start_reveal() -> void:
	if _reveal != null and _reveal.is_valid():
		_reveal.kill()
	_reveal = create_tween()
	_reveal.tween_interval(status_delay)
	_reveal.tween_property(status_label, "modulate:a", 1.0, fade_duration)
	_reveal.tween_interval(maxf(thanks_delay - status_delay - fade_duration, 0.0))
	_reveal.tween_property(thanks_label, "modulate:a", 1.0, fade_duration)
	_reveal.tween_interval(maxf(buttons_delay - thanks_delay - fade_duration, 0.0))
	_reveal.tween_property(buttons, "modulate:a", 1.0, fade_duration)
	_reveal.tween_callback(sector_button.grab_focus)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_main_menu_pressed()
		get_viewport().set_input_as_handled()

func _on_sector_pressed() -> void:
	SceneLoader.load_scene("res://scenes/level_selector.tscn")

func _on_main_menu_pressed() -> void:
	SceneLoader.load_scene("res://scenes/main_menu.tscn")
