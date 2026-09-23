class_name RunUnitMobileControls
extends CanvasLayer

const BUTTON_SIZE: float = 88.0

@onready var _area: Control = $Area
@onready var _left: TouchScreenButton = $Area/Left
@onready var _right: TouchScreenButton = $Area/Right
@onready var _crouch: TouchScreenButton = $Area/Crouch
@onready var _jump: TouchScreenButton = $Area/Jump
@onready var _pause: TouchScreenButton = $Area/Pause


func _ready() -> void:
	_area.resized.connect(_on_area_resized)
	_pause.pressed.connect(_on_pause_pressed)
	layout_for_viewport(_area.size)
	_update_visibility()


func _process(_delta: float) -> void:
	# The pause and results menus need the whole screen for their touch targets.
	_update_visibility()


func layout_for_viewport(viewport_size: Vector2) -> void:
	var scale_factor: float = minf(clampf(minf(viewport_size.x / 960.0, viewport_size.y / 540.0), 0.5, 1.0), viewport_size.x / 440.0)
	var button_size: float = BUTTON_SIZE * scale_factor
	var margin: float = 24.0 * scale_factor
	var gap: float = 16.0 * scale_factor
	var bottom: float = viewport_size.y - margin - button_size
	for button: TouchScreenButton in [_left, _right, _crouch, _jump]:
		button.scale = Vector2.ONE * scale_factor
	_left.position = Vector2(margin, bottom)
	_right.position = Vector2(margin + button_size + gap, bottom)
	_jump.position = Vector2(viewport_size.x - margin - button_size, bottom)
	_crouch.position = Vector2(_jump.position.x - gap - button_size, bottom)
	_pause.scale = Vector2.ONE * (scale_factor * 0.62)
	_pause.position = Vector2((viewport_size.x - BUTTON_SIZE * _pause.scale.x) * 0.5, 16.0 * scale_factor)


func _on_area_resized() -> void:
	layout_for_viewport(_area.size)


func _update_visibility() -> void:
	var game: RunUnitGame = get_parent() as RunUnitGame
	_area.visible = not get_tree().paused and (game == null or not game.is_terminal())


func _on_pause_pressed() -> void:
	var game: RunUnitGame = get_parent() as RunUnitGame
	if game == null or game.is_terminal():
		return
	_area.hide()
	game.get_node("PauseMenuController").pause()
