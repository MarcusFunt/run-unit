class_name RunUnitMainMenu
extends MainMenu

const THIN_TERMINAL_THEME: Theme = preload("res://theme/thin_terminal_button_theme.tres")
const TERMINAL_BUTTON_SIZE := Vector2(280.0, 50.0)
const TERMINAL_BUTTON_ANCHOR_X := 0.45
const PRESSED_SCALE := Vector2(0.985, 0.985)

func _ready() -> void:
	super._ready()
	var menu_buttons: Array[Button] = [new_game_button, options_button, credits_button, exit_button]
	for button: Button in menu_buttons:
		_configure_terminal_button(button)
	var button_box: BoxContainer = new_game_button.get_parent() as BoxContainer
	if button_box != null:
		button_box.add_theme_constant_override("separation", 10)
		button_box.anchor_left = TERMINAL_BUTTON_ANCHOR_X
		button_box.anchor_right = TERMINAL_BUTTON_ANCHOR_X
	new_game_button.text = "START NEW RUN"
	options_button.text = "SYSTEM SETTINGS"
	credits_button.text = "CREDITS / INTEL"
	exit_button.text = "SHUT DOWN"

func _configure_terminal_button(button: Button) -> void:
	button.theme = THIN_TERMINAL_THEME
	button.custom_minimum_size = TERMINAL_BUTTON_SIZE
	button.resized.connect(_center_terminal_button_pivot.bind(button))
	button.button_down.connect(_press_terminal_button.bind(button))
	button.button_up.connect(_release_terminal_button.bind(button))
	button.mouse_exited.connect(_release_terminal_button.bind(button))
	button.focus_exited.connect(_release_terminal_button.bind(button))
	_center_terminal_button_pivot(button)

func _center_terminal_button_pivot(button: Button) -> void:
	button.pivot_offset = button.size * 0.5

func _press_terminal_button(button: Button) -> void:
	_animate_terminal_button(button, PRESSED_SCALE, 0.05)

func _release_terminal_button(button: Button) -> void:
	_animate_terminal_button(button, Vector2.ONE, 0.08)

func _animate_terminal_button(button: Button, target_scale: Vector2, duration: float) -> void:
	var tween: Tween = button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, duration)

func new_game() -> void:
	SceneLoader.load_scene("res://scenes/level_selector.tscn")
