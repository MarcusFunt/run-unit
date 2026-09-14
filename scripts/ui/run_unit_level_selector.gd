class_name RunUnitLevelSelector
extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"
var level_names: PackedStringArray = PackedStringArray(["MAINTENANCE SHAFT", "MANUFACTURING DISTRICT", "THERMAL SECTOR", "FREIGHT NETWORK", "HABITATION GARDENS", "POWER SPINE", "BEACON APPROACH", "BEACON 9"])
var level_descriptions: PackedStringArray = PackedStringArray(["Service tunnels beneath the municipal core. Expect tight routing and unstable lift shafts.", "A production artery threaded with moving platforms, cargo lifts, and blind corners.", "Heat exchange infrastructure. The shortest route is rarely the safest route.", "A long-haul logistics lane with aggressive timing windows and sparse recovery points.", "Overgrown residential biodomes. Vertical traversal is mandatory.", "The city's main power conduit. Surges can turn a clean run into a blackout.", "An exposed approach through the upper relay district. Wind shear is severe.", "Final beacon access. No support systems. No second chances."])
var level_difficulties: PackedStringArray = PackedStringArray(["LOW", "LOW", "MEDIUM", "MEDIUM", "MEDIUM", "HIGH", "HIGH", "CRITICAL"])

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
	for level_index: int in level_names.size():
		var sector_button: Button = Button.new()
		sector_button.text = "%02d  %s" % [level_index + 1, level_names[level_index]]
		sector_button.custom_minimum_size = Vector2(0.0, 46.0)
		sector_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sector_button.focus_mode = Control.FOCUS_ALL
		sector_button.toggle_mode = true
		sector_button.tooltip_text = "Inspect %s" % level_names[level_index]
		sector_button.pressed.connect(_on_sector_pressed.bind(level_index))
		sector_button.focus_entered.connect(_on_sector_focused.bind(level_index))
		sector_grid.add_child(sector_button)
		_sector_buttons.append(sector_button)
	back_button.pressed.connect(_on_back_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed)
	_select_sector(0)
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
	if next_index >= 0 and next_index < _sector_buttons.size():
		_select_sector(next_index)
		_sector_buttons[next_index].grab_focus()
		get_viewport().set_input_as_handled()

func _focus_first_sector() -> void:
	if not _sector_buttons.is_empty():
		_sector_buttons[0].grab_focus()

func _on_sector_focused(level_index: int) -> void:
	_select_sector(level_index)

func _on_sector_pressed(level_index: int) -> void:
	_select_sector(level_index)
	deploy_button.grab_focus()

func _select_sector(level_index: int) -> void:
	_selected_index = clampi(level_index, 0, level_names.size() - 1)
	RunUnitSession.selected_level_index = _selected_index
	for index: int in _sector_buttons.size():
		_sector_buttons[index].button_pressed = index == _selected_index
	selected_sector.text = "%02d  %s" % [_selected_index + 1, level_names[_selected_index]]
	description.text = level_descriptions[_selected_index]
	seed_label.text = "AUTHORED ROUTE  %02d" % (_selected_index + 1)
	difficulty_label.text = "THREAT  %s" % level_difficulties[_selected_index]
	route_status.text = "ROUTE %02d READY" % (_selected_index + 1)

func _on_deploy_pressed() -> void:
	RunUnitSession.selected_level_index = _selected_index
	SceneLoader.load_scene(game_scene_path)

func _on_back_pressed() -> void:
	SceneLoader.load_scene("res://scenes/main_menu.tscn")
