class_name RunUnitDeathMenu
extends CanvasLayer

const FAILURE_ACCENT := Color(1.0, 0.28, 0.16, 1.0)
const FAILURE_DIMMER := Color(0.08, 0.005, 0.01, 0.94)
const FAILURE_PANEL := Color(0.055, 0.012, 0.018, 0.985)
const SUCCESS_ACCENT := Color(0.28, 1.0, 0.78, 1.0)
const SUCCESS_DIMMER := Color(0.0, 0.045, 0.055, 0.90)
const SUCCESS_PANEL := Color(0.008, 0.07, 0.075, 0.985)

@onready var overlay: Control = %Overlay
@onready var dimmer: ColorRect = %Dimmer
@onready var result_panel: PanelContainer = %ResultPanel
@onready var accent_bar: ColorRect = %AccentBar
@onready var outcome_glyph: Label = %OutcomeGlyph
@onready var outcome_eyebrow: Label = %OutcomeEyebrow
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var hint_label: Label = %HintLabel
@onready var restart_button: Button = %RestartButton
@onready var main_menu_button: Button = %MainMenuButton

var _owns_pause: bool = false
var _entrance: Tween = null

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not InputMap.has_action(&"restart"):
		return
	if event.is_action_pressed(&"restart"):
		get_viewport().set_input_as_handled()
		_on_restart_pressed()

func open_with_scores(distance: float, best: float) -> void:
	_apply_failure_presentation()
	title_label.text = "UNIT OFFLINE"
	description_label.text = "%s TERMINATED\n\nRUN DISTANCE  %05dm\nBEST DISTANCE  %05dm\n\nRecovery point preserved. Re-enter when ready." % [_get_route_title(), int(distance), int(best)]
	restart_button.text = "RETRY FROM CHECKPOINT"
	main_menu_button.text = "ABORT TO SECTOR SELECT"
	hint_label.text = "SYSTEM HALTED  //  R TO RETRY"
	_open(false)

func open_completed_with_scores(distance: float, best: float) -> void:
	_apply_success_presentation()
	title_label.text = "ROUTE COMPLETE"
	description_label.text = "%s CERTIFIED\n\nRUN DISTANCE  %05dm\nBEST DISTANCE  %05dm\n\n%s" % [_get_route_title(), int(distance), int(best), RunUnitCampaign.get_completion(RunUnitSession.selected_level_index)]
	restart_button.text = "REDEPLOY ROUTE"
	main_menu_button.text = "CONTINUE TO SECTOR SELECT"
	hint_label.text = "OBJECTIVE VERIFIED  //  ROUTE CERTIFIED"
	_open(true)

func _apply_failure_presentation() -> void:
	outcome_glyph.text = "FAIL"
	outcome_glyph.add_theme_color_override("font_color", FAILURE_ACCENT)
	outcome_eyebrow.text = "RUN TERMINATED"
	outcome_eyebrow.add_theme_color_override("font_color", FAILURE_ACCENT)
	accent_bar.color = FAILURE_ACCENT
	dimmer.color = FAILURE_DIMMER
	_set_panel_style(FAILURE_PANEL, FAILURE_ACCENT)

func _apply_success_presentation() -> void:
	outcome_glyph.text = "CLEAR"
	outcome_glyph.add_theme_color_override("font_color", SUCCESS_ACCENT)
	outcome_eyebrow.text = "MISSION SUCCESS"
	outcome_eyebrow.add_theme_color_override("font_color", SUCCESS_ACCENT)
	accent_bar.color = SUCCESS_ACCENT
	dimmer.color = SUCCESS_DIMMER
	_set_panel_style(SUCCESS_PANEL, SUCCESS_ACCENT)

func _set_panel_style(background: Color, border: Color) -> void:
	var base_style: StyleBox = result_panel.get_theme_stylebox("panel")
	var panel_style: StyleBoxFlat = base_style.duplicate() as StyleBoxFlat
	panel_style.bg_color = background
	panel_style.border_color = border
	result_panel.add_theme_stylebox_override("panel", panel_style)

func close() -> void:
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	hide()
	_release_pause()

func _open(success: bool) -> void:
	show()
	if not get_tree().paused:
		_owns_pause = true
	get_tree().paused = true
	_play_entrance(success)
	restart_button.grab_focus()

func _play_entrance(success: bool) -> void:
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	overlay.modulate.a = 0.0
	result_panel.modulate.a = 0.0
	result_panel.scale = Vector2.ONE * (0.94 if success else 1.025)
	outcome_glyph.modulate.a = 0.0
	_entrance = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var reveal_time: float = 0.28 if success else 0.11
	_entrance.tween_property(overlay, "modulate:a", 1.0, reveal_time)
	_entrance.parallel().tween_property(result_panel, "modulate:a", 1.0, reveal_time)
	_entrance.parallel().tween_property(result_panel, "scale", Vector2.ONE, reveal_time).set_trans(Tween.TRANS_BACK if success else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_entrance.tween_property(outcome_glyph, "modulate:a", 1.0, 0.16)
	if success:
		_entrance.tween_property(accent_bar, "modulate:a", 0.45, 0.16)
		_entrance.tween_property(accent_bar, "modulate:a", 1.0, 0.22)

func _release_pause() -> void:
	if not _owns_pause:
		return
	_owns_pause = false
	get_tree().paused = false

func _get_route_title() -> String:
	return RunUnitCampaign.get_title(RunUnitSession.selected_level_index)

func _on_restart_pressed() -> void:
	_release_pause()
	get_tree().paused = false
	SceneLoader.reload_current_scene()

func _on_main_menu_pressed() -> void:
	_release_pause()
	get_tree().paused = false
	SceneLoader.load_scene("res://scenes/level_selector.tscn")
