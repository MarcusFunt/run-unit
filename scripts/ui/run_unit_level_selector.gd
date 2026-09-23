class_name RunUnitLevelSelector
extends Control
## Campaign route selector.
##
## Routes remain inspectable while campaign progress controls deployment.

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"

@onready var sector_grid: GridContainer = %SectorGrid
@onready var selected_sector: Label = %SelectedSector
@onready var description: Label = %Description
@onready var campaign_state: Label = %CampaignState
@onready var length_label: Label = %LengthLabel
@onready var deploy_button: Button = %DeployButton
@onready var back_button: Button = %BackButton
var _selected_index: int = RunUnitCampaign.PLAYABLE_INDEX
var _sector_buttons: Array[Button] = []

func _ready() -> void:
	for level_index: int in RunUnitCampaign.route_count():
		var sector_button: Button = Button.new()
		sector_button.text = _get_route_button_text(level_index)
		sector_button.custom_minimum_size = Vector2(0.0, 46.0)
		sector_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sector_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sector_button.focus_mode = Control.FOCUS_ALL
		sector_button.toggle_mode = true
		sector_button.tooltip_text = _get_route_tooltip(level_index)
		if not _is_route_available(level_index):
			sector_button.add_theme_color_override("font_color", Color(0.48, 0.63, 0.66))
		sector_button.pressed.connect(_on_sector_pressed.bind(level_index))
		sector_button.focus_entered.connect(_on_sector_focused.bind(level_index))
		sector_grid.add_child(sector_button)
		_sector_buttons.append(sector_button)
	back_button.pressed.connect(_on_back_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed)
	var initial_index: int = RunUnitSession.selected_level_index if _is_route_available(RunUnitSession.selected_level_index) else RunUnitCampaign.PLAYABLE_INDEX
	_select_sector(initial_index)
	call_deferred("_focus_selected_sector")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_deploy_pressed()
		return
	var columns: int = maxi(sector_grid.columns, 1)
	var next_index: int = -1
	if event.is_action_pressed("ui_down"):
		next_index = _selected_index + columns
	elif event.is_action_pressed("ui_up"):
		next_index = _selected_index - columns
	elif event.is_action_pressed("ui_right"):
		next_index = _selected_index + 1
	elif event.is_action_pressed("ui_left"):
		next_index = _selected_index - 1
	if next_index >= 0 and next_index < _sector_buttons.size():
		_select_sector(next_index)
		_sector_buttons[next_index].grab_focus()
		get_viewport().set_input_as_handled()

## Opens on the route the session last selected, so returning from a run lands
## on the route that was just played rather than always on the tutorial.
func _focus_selected_sector() -> void:
	if _selected_index < _sector_buttons.size():
		_sector_buttons[_selected_index].grab_focus()

func _on_sector_focused(level_index: int) -> void:
	_select_sector(level_index)

func _on_sector_hovered(level_index: int) -> void:
	pass

func _on_sector_unhovered() -> void:
	pass

func _on_sector_pressed(level_index: int) -> void:
	_select_sector(level_index)

func _select_sector(level_index: int) -> void:
	if not RunUnitCampaign.has_route(level_index):
		return
	_selected_index = level_index
	if _is_route_available(level_index):
		RunUnitSession.selected_level_index = _selected_index
	for index: int in _sector_buttons.size():
		_sector_buttons[index].button_pressed = index == _selected_index
	_show_route_briefing(_selected_index)
	deploy_button.disabled = not _is_route_available(_selected_index)

func _show_route_briefing(level_index: int) -> void:
	if not RunUnitCampaign.has_route(level_index):
		return
	selected_sector.text = RunUnitCampaign.get_title(level_index)
	var lock_reason: String = RunUnitSession.get_route_lock_reason(level_index)
	description.text = RunUnitCampaign.get_summary(level_index)
	if not lock_reason.is_empty():
		description.text += "\n\n%s" % lock_reason
	var best_time: float = RunUnitSession.get_best_time(level_index)
	length_label.text = "ROUTE LENGTH  //  %s" % RunUnitCampaign.get_runtime(level_index)
	if RunUnitSession.is_route_completed(level_index):
		campaign_state.text = "COMPLETE  //  BEST %d:%02d" % [floori(best_time / 60.0), int(best_time) % 60] if best_time > 0.0 else "COMPLETE  //  REPLAY AVAILABLE"
	elif not lock_reason.is_empty():
		campaign_state.text = "LOCKED  //  PREREQUISITE REQUIRED"
	else:
		campaign_state.text = "READY  //  AVAILABLE TO DEPLOY"

func _on_deploy_pressed() -> void:
	if not _is_route_available(_selected_index):
		return
	RunUnitSession.selected_level_index = _selected_index
	# Deploying is always a fresh attempt, never a resume.
	RunUnitSession.clear_checkpoint()
	SceneLoader.load_scene(game_scene_path)

func _on_back_pressed() -> void:
	SceneLoader.load_scene("res://scenes/main_menu.tscn")

func _is_route_available(level_index: int) -> bool:
	return RunUnitSession.is_route_unlocked(level_index)

func _get_route_button_text(level_index: int) -> String:
	if RunUnitSession.is_route_completed(level_index):
		return "%s  //  COMPLETE" % RunUnitCampaign.get_title(level_index)
	if _is_route_available(level_index):
		return "%s  //  READY" % RunUnitCampaign.get_title(level_index)
	return "%s  //  LOCKED" % RunUnitCampaign.get_title(level_index)

func _get_route_tooltip(level_index: int) -> String:
	var summary: String = RunUnitCampaign.get_summary(level_index)
	if _is_route_available(level_index):
		return summary
	return "%s\n%s" % [summary, RunUnitSession.get_route_lock_reason(level_index)]
