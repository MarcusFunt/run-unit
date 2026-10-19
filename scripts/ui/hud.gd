class_name RunUnitHud
extends CanvasLayer

@onready var distance_label: Label = %DistanceLabel
@onready var best_label: Label = %BestLabel
@onready var score_progress_bar: ProgressBar = %ScoreProgressBar
@onready var _health_cells: Array[CanvasItem] = [
	$HealthDisplay/HealthCell1,
	$HealthDisplay/HealthCell2,
	$HealthDisplay/HealthCell3,
]

@onready var _health_frame: Panel = $HealthFrame
var _level_length: float = 1.0
var _last_health: int = 3
var _damage_flash: float = 0.0
var _objective_frame: PanelContainer
var _objective_label: Label
var _message_label: Label
var _journey_label: Label
var _message_tween: Tween

func _process(delta: float) -> void:
	_damage_flash = maxf(_damage_flash - delta, 0.0)
	_health_frame.modulate = Color(1.0, 0.38, 0.28) if _damage_flash > 0.0 else Color.WHITE

func _ready() -> void:
	score_progress_bar.max_value = _level_length
	_build_mission_display()
	_adjust_integrity_layout()

func _build_mission_display() -> void:
	var header: HBoxContainer = distance_label.get_parent() as HBoxContainer
	_journey_label = Label.new()
	_journey_label.name = "JourneyLabel"
	_journey_label.visible = false
	_journey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_journey_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_journey_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_journey_label.add_theme_color_override("font_color", Color(0.58, 0.88, 0.86, 0.96))
	_journey_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_journey_label)
	set_campaign_progress(0, RunUnitCampaign.route_count())

	# Keep the mission line between the sector meter and integrity panel.
	var frame := PanelContainer.new()
	frame.name = "ObjectiveFrame"
	frame.visible = false
	frame.set_anchors_preset(Control.PRESET_TOP_WIDE)
	frame.anchor_left = 0.40
	frame.anchor_right = 0.765
	frame.offset_left = 0.0
	frame.offset_right = 0.0
	frame.offset_top = 12.0
	frame.offset_bottom = 48.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.055, 0.075, 0.9)
	style.border_color = Color(0.18, 0.83, 0.88, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	frame.add_theme_stylebox_override("panel", style)
	_objective_label = Label.new()
	_objective_label.name = "ObjectiveLabel"
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	_objective_label.add_theme_font_size_override("font_size", 18)
	frame.add_child(_objective_label)
	add_child(frame)
	_objective_frame = frame
	_message_label = Label.new()
	_message_label.name = "SystemMessage"
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.anchor_left = 0.2
	_message_label.anchor_right = 0.8
	_message_label.offset_top = 60.0
	_message_label.offset_bottom = 92.0
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color(0.82, 0.96, 0.95))
	_message_label.add_theme_font_size_override("font_size", 18)
	message_label_visible(false)
	add_child(_message_label)

func message_label_visible(value: bool) -> void:
	if _message_label != null:
		_message_label.visible = value

func set_objective(text: String) -> void:
	if _objective_label != null:
		_objective_label.text = text

func set_campaign_progress(route_index: int, route_count: int) -> void:
	if _journey_label == null:
		return
	var safe_count: int = maxi(route_count, 1)
	var safe_index: int = clampi(route_index, 0, safe_count - 1)
	_journey_label.text = "SECTOR %02d / %02d" % [safe_index + 1, safe_count]

func show_system_message(text: String, duration: float = 2.0) -> void:
	if _message_label == null:
		return
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_label.text = text
	_message_label.modulate.a = 1.0
	_message_label.visible = true
	_message_tween = create_tween()
	_message_tween.tween_interval(maxf(duration, 0.1))
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.5)
	_message_tween.tween_callback(_message_label.hide)

func set_scores(distance: float, best: float) -> void:
	var safe_distance: float = maxf(distance, 0.0)
	distance_label.text = "%dm" % int(safe_distance)
	score_progress_bar.value = clampf(safe_distance, 0.0, _level_length)
	best_label.text = "RECORD  %04dm" % int(best)

func set_level_length(length: float) -> void:
	_level_length = maxf(length, 1.0)
	score_progress_bar.max_value = _level_length

func set_health(current_health: int, maximum_health: int) -> void:
	var safe_maximum: int = maxi(maximum_health, 0)
	var safe_current: int = clampi(current_health, 0, safe_maximum)
	if safe_current < _last_health:
		_damage_flash = 0.58
	_last_health = safe_current
	for index: int in range(_health_cells.size()):
		var heart: TextureRect = _health_cells[index] as TextureRect
		heart.visible = true
		heart.modulate = Color(1.0, 0.39, 0.36, 1.0) if index < safe_current else Color(0.18, 0.28, 0.32, 0.86)

func _adjust_integrity_layout() -> void:
	_health_frame.position = Vector2(798.0, 14.0)
	_health_frame.size = Vector2(150.0, 51.0)
	var display: HBoxContainer = $HealthDisplay as HBoxContainer
	display.position = Vector2(808.0, 20.0)
	display.size = Vector2(138.0, 38.0)
	display.add_theme_constant_override("separation", 8)
	for cell_item: CanvasItem in _health_cells:
		var heart: TextureRect = cell_item as TextureRect
		heart.custom_minimum_size = Vector2(38.0, 38.0)
