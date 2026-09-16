class_name RunUnitLevelSelector
extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"
const PLAYABLE_LEVEL_INDEX: int = 0
const ROUTE_SLOT_COUNT: int = 8
const PLAYABLE_ROUTE_NAME: String = "FINAL INSPECTION"
const PLAYABLE_ROUTE_DESCRIPTION: String = "CALIBRATION READY\nComplete mobility, spring, and clearance checks in Final Inspection.\n\nFour checks. One short route."

@onready var sector_grid: GridContainer = %SectorGrid
@onready var selected_sector: Label = %SelectedSector
@onready var description: Label = %Description
@onready var seed_label: Label = %SeedLabel
@onready var difficulty_label: Label = %DifficultyLabel
@onready var route_status: Label = %RouteStatus
@onready var deploy_button: Button = %DeployButton
@onready var back_button: Button = %BackButton
var _selected_index: int = 0
var _sector_buttons: Array[Button] = []

func _ready() -> void:
	for level_index: int in ROUTE_SLOT_COUNT:
		var sector_button: Button = Button.new()
		var route_available: bool = _is_route_available(level_index)
		sector_button.text = _get_route_button_text(level_index)
		sector_button.custom_minimum_size = Vector2(0.0, 46.0)
		sector_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sector_button.focus_mode = Control.FOCUS_ALL if route_available else Control.FOCUS_NONE
		sector_button.toggle_mode = true
		sector_button.disabled = not route_available
		sector_button.tooltip_text = "Review the playable route" if route_available else "This route is not available in the current build."
		sector_button.pressed.connect(_on_sector_pressed.bind(level_index))
		sector_button.focus_entered.connect(_on_sector_focused.bind(level_index))
		sector_grid.add_child(sector_button)
		_sector_buttons.append(sector_button)
	back_button.pressed.connect(_on_back_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed)
	_select_sector(PLAYABLE_LEVEL_INDEX)
	call_deferred("_focus_first_sector")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	var next_index: int = -1
	if event.is_action_pressed("ui_down"):
		next_index = _selected_index + 2
	elif event.is_action_pressed("ui_up"):
		next_index = _selected_index - 2
	elif event.is_action_pressed("ui_right"):
		next_index = _selected_index + 1
	elif event.is_action_pressed("ui_left"):
		next_index = _selected_index - 1
	if next_index >= 0 and next_index < _sector_buttons.size() and _is_route_available(next_index):
		_select_sector(next_index)
		_sector_buttons[next_index].grab_focus()
		get_viewport().set_input_as_handled()

func _focus_first_sector() -> void:
	if not _sector_buttons.is_empty():
		_sector_buttons[0].grab_focus()

func _on_sector_focused(level_index: int) -> void:
	if _is_route_available(level_index):
		_select_sector(level_index)

func _on_sector_pressed(level_index: int) -> void:
	if not _is_route_available(level_index):
		return
	_select_sector(level_index)
	_on_deploy_pressed()

func _select_sector(level_index: int) -> void:
	if not _is_route_available(level_index):
		return
	_selected_index = PLAYABLE_LEVEL_INDEX
	RunUnitSession.selected_level_index = _selected_index
	for index: int in _sector_buttons.size():
		_sector_buttons[index].button_pressed = index == _selected_index
	selected_sector.text = "%02d  %s" % [_selected_index + 1, PLAYABLE_ROUTE_NAME]
	description.text = PLAYABLE_ROUTE_DESCRIPTION
	seed_label.text = "AUTHORED ROUTE  //  AVAILABLE"
	difficulty_label.text = "THREAT  //  LOW"
	route_status.text = "ROUTE ONLINE  //  READY TO DEPLOY"

func _on_deploy_pressed() -> void:
	if not _is_route_available(_selected_index):
		return
	RunUnitSession.selected_level_index = _selected_index
	SceneLoader.load_scene(game_scene_path)

func _on_back_pressed() -> void:
	SceneLoader.load_scene("res://scenes/main_menu.tscn")

func _is_route_available(level_index: int) -> bool:
	return level_index == PLAYABLE_LEVEL_INDEX

func _get_route_button_text(level_index: int) -> String:
	if _is_route_available(level_index):
		return "%02d  %s" % [level_index + 1, PLAYABLE_ROUTE_NAME]
	return "ROUTE %02d  //  OFFLINE" % (level_index + 1)
