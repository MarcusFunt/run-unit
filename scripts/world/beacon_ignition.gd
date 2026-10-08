class_name RunUnitBeaconIgnition
extends RunUnitRouteExit

signal module_installed
signal interaction_completed

@export var carried_module_path: NodePath
@export var stage_paths: Array[NodePath] = []
@export_range(0.0, 3.0, 0.05) var install_delay: float = 0.45
@export_range(0.1, 2.0, 0.05) var transfer_duration: float = 0.65
@export_range(0.05, 1.0, 0.05) var lock_duration: float = 0.25
@export_range(0.1, 2.0, 0.05) var stage_interval: float = 0.38
@export_range(0.0, 5.0, 0.1) var hold_after_activation: float = 2.6
@export_range(0.1, 3.0, 0.05) var fade_duration: float = 1.1

@onready var seated_module: Node2D = $SeatedModule
@onready var transfer_module: Sprite2D = $TransferModule
@onready var socket_burst: CPUParticles2D = $SocketBurst
@onready var shockwave: Polygon2D = $Shockwave
@onready var blackout: ColorRect = $BlackoutLayer/Blackout
@onready var sequence_ui: CanvasLayer = $SequenceUI
@onready var world_flash: ColorRect = %WorldFlash
@onready var activation_label: Label = %ActivationLabel
@onready var activation_progress: ProgressBar = %ActivationProgress
@onready var completion_banner: Label = %CompletionBanner
@onready var coupler_console: Node2D = $CouplerConsole
@onready var coupler_prompt: Label = $CouplerConsole/Prompt
@onready var coupler_fill: Line2D = $CouplerConsole/GaugeFill

var installed: bool = false
var lit_stages: int = 0
var _sequence: Tween = null
var _camera_tween: Tween = null
var _camera: Camera2D = null
var _camera_zoom_start: Vector2 = Vector2.ONE
var _camera_offset_start: Vector2 = Vector2.ZERO
var _interaction_player: RunUnitPlayerMotor = null
var _interaction_active: bool = false
var _interaction_charge_seconds: float = 0.0
var _interaction_jump_was_held: bool = false

const STAGE_COPY: Array[String] = [
	"The socket clamps take hold.",
	"Current climbs through the floor.",
	"The rotor begins to turn.",
	"Light returns to the lens.",
	"Beacon 9 shines above the roofline.",
	"Lights return across the city.",
]
const OBJECTIVE_COLOR := Color(1.0, 0.88, 0.38, 1.0)
const SYSTEM_COLOR := Color(0.72, 1.0, 0.96, 1.0)

func reset_transition() -> void:
	super()
	if _sequence != null and _sequence.is_valid():
		_sequence.kill()
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_restore_camera()
	installed = false
	_interaction_active = false
	_interaction_charge_seconds = 0.0
	_interaction_jump_was_held = false
	_interaction_player = null
	lit_stages = 0
	seated_module.visible = false
	transfer_module.visible = false
	socket_burst.emitting = false
	shockwave.visible = false
	sequence_ui.visible = false
	coupler_console.visible = true
	completion_banner.visible = false
	activation_progress.value = 0.0
	_sync_coupler_gauge()
	coupler_prompt.text = "The coupler is dark."
	coupler_prompt.add_theme_color_override("font_color", OBJECTIVE_COLOR)
	_configure_coupler_signifier()
	for path: NodePath in stage_paths:
		var stage: CanvasItem = get_node_or_null(path) as CanvasItem
		if stage != null:
			stage.visible = false
			stage.modulate.a = 0.0
	var blackout_color: Color = blackout.color
	blackout_color.a = 0.0
	blackout.color = blackout_color
	var flash_color: Color = world_flash.color
	flash_color.a = 0.0
	world_flash.color = flash_color

func begin_player_interaction(player: RunUnitPlayerMotor) -> void:
	if transition_started:
		return
	transition_started = true
	_interaction_active = true
	_interaction_player = player
	_interaction_charge_seconds = 0.0
	_interaction_jump_was_held = false
	if player != null:
		player.set_interaction_charge(0.0, false)
	sequence_ui.visible = true
	coupler_console.visible = true
	_configure_coupler_signifier()
	completion_banner.visible = false
	activation_label.text = "The coupler is open. Build pressure, then release."
	coupler_prompt.text = "Hold to build pressure; release to seat."
	coupler_prompt.add_theme_color_override("font_color", SYSTEM_COLOR)
	activation_progress.value = 0.0
	_sync_coupler_gauge()
	_focus_camera()

func is_interaction_active() -> bool:
	return _interaction_active

func _process(delta: float) -> void:
	if not _interaction_active:
		return
	var player_holding_jump: bool = Input.is_action_pressed("jump") or (
		_interaction_player != null and _interaction_player.is_jump_held()
	)
	if player_holding_jump:
		_interaction_jump_was_held = true
		coupler_prompt.add_theme_color_override("font_color", SYSTEM_COLOR)
		_interaction_charge_seconds = minf(_interaction_charge_seconds + delta, _interaction_player.max_charge_time if _interaction_player != null else 0.36)
		var maximum: float = _interaction_player.max_charge_time if _interaction_player != null else 0.36
		var ratio: float = clampf(_interaction_charge_seconds / maxf(maximum, 0.01), 0.0, 1.0)
		activation_progress.value = ratio * 100.0
		activation_label.text = "Spring pressure  %d%%" % int(round(ratio * 100.0))
		coupler_prompt.text = "Pressure  %d%%" % int(round(ratio * 100.0))
		_sync_coupler_gauge()
		if _interaction_player != null:
			_interaction_player.set_interaction_charge(ratio, true)
	elif _interaction_jump_was_held:
		_interaction_jump_was_held = false
		var maximum: float = _interaction_player.max_charge_time if _interaction_player != null else 0.36
		var ratio: float = clampf(_interaction_charge_seconds / maxf(maximum, 0.01), 0.0, 1.0)
		if _interaction_player != null:
			_interaction_player.set_interaction_charge(0.0, false)
		_interaction_active = false
		RunUnitSession.record_playtest_event("beacon_charge_released", {
			"charge_ratio": ratio,
			"position": [global_position.x, global_position.y],
		})
		if ratio >= 0.98:
			interaction_completed.emit()
			RunUnitAudio.play_event("beacon_online", -5.0)
			_start_activation_sequence()
		else:
			_interaction_charge_seconds = 0.0
			activation_progress.value = 0.0
			activation_label.text = "Pressure too low. The coupler stays open."
			coupler_prompt.text = "Not enough pressure. Try again."
			coupler_prompt.add_theme_color_override("font_color", OBJECTIVE_COLOR)
			_sync_coupler_gauge()
			_interaction_active = true

func begin_transition() -> void:
	if transition_started and _interaction_charge_seconds <= 0.0 and not _interaction_active:
		# Beacon's full-charge release already claimed the interaction; the game
		# now records the completed route while the staged installation begins.
		return
	if transition_started:
		return
	transition_started = true
	sequence_ui.visible = true
	coupler_console.visible = true
	_configure_coupler_signifier()
	completion_banner.visible = false
	activation_label.text = "The coupler is aligning."
	activation_progress.value = 4.0
	coupler_prompt.text = "Build pressure to seat the cell."
	coupler_prompt.add_theme_color_override("font_color", SYSTEM_COLOR)
	_sync_coupler_gauge()
	_focus_camera()
	_start_activation_sequence()

func _configure_coupler_signifier() -> void:
	coupler_console.scale = Vector2.ONE * 1.08
	var panel: Polygon2D = coupler_console.get_node("ConsolePanel") as Polygon2D
	panel.polygon = PackedVector2Array([
		Vector2(-144.0, -40.0), Vector2(144.0, -40.0),
		Vector2(144.0, 40.0), Vector2(-144.0, 40.0),
	])
	coupler_prompt.position = Vector2(-140.0, -32.0)
	coupler_prompt.size = Vector2(280.0, 34.0)
	coupler_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coupler_prompt.add_theme_font_size_override("font_size", 17)
	var track: Line2D = coupler_console.get_node("GaugeTrack") as Line2D
	track.points = PackedVector2Array([Vector2(-120.0, 0.0), Vector2(120.0, 0.0)])

func _start_activation_sequence() -> void:
	_interaction_active = false
	if _interaction_player != null:
		_interaction_player.set_interaction_charge(0.0, false)

	_sequence = create_tween()
	_sequence.tween_interval(install_delay)
	_sequence.tween_callback(_start_module_transfer)
	_sequence.tween_property(transfer_module, "global_position", seated_module.global_position, transfer_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_sequence.parallel().tween_property(transfer_module, "scale", Vector2.ONE * 1.7, transfer_duration)
	_sequence.parallel().tween_property(transfer_module, "rotation", 0.0, transfer_duration)
	_sequence.tween_callback(_lock_module)
	_sequence.tween_interval(lock_duration)
	for index: int in range(stage_paths.size()):
		_sequence.tween_interval(stage_interval)
		_sequence.tween_callback(_light_stage.bind(index))
	_sequence.tween_interval(stage_interval * 0.6)
	_sequence.tween_callback(_declare_success)
	_sequence.tween_interval(hold_after_activation)
	if not next_scene_path.is_empty():
		_sequence.tween_property(blackout, "color:a", 1.0, fade_duration)
	_sequence.tween_callback(finish_transition)

func _start_module_transfer() -> void:
	var carried: RunUnitCarriedModule = get_node_or_null(carried_module_path) as RunUnitCarriedModule
	var start_position: Vector2 = seated_module.global_position + Vector2(-150.0, -86.0)
	if carried != null:
		var mounted: Node2D = carried.get_mounted_module()
		if mounted != null:
			start_position = mounted.global_position
		carried.stow()
	transfer_module.global_position = start_position
	transfer_module.scale = Vector2.ONE * 1.35
	transfer_module.rotation = -0.18
	transfer_module.modulate = Color(1.0, 0.9, 0.48, 1.0)
	transfer_module.visible = true
	activation_label.text = "The cell rises into the socket."
	activation_progress.value = 12.0
	coupler_prompt.text = "The clamps draw it in."
	_sync_coupler_gauge()
func _lock_module() -> void:
	transfer_module.visible = false
	seated_module.visible = true
	installed = true
	module_installed.emit()
	activation_label.text = "The clamps close around the cell."
	activation_progress.value = 22.0
	coupler_prompt.text = "Current returns to the shaft."
	_sync_coupler_gauge()

	socket_burst.restart()
	socket_burst.emitting = true
	shockwave.visible = true
	shockwave.scale = Vector2.ONE * 0.18
	shockwave.modulate.a = 0.8
	var pulse: Tween = create_tween()
	pulse.tween_property(shockwave, "scale", Vector2.ONE * 2.7, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(shockwave, "modulate:a", 0.0, 0.55)
	pulse.tween_callback(shockwave.hide)

	var flash_color: Color = world_flash.color
	flash_color.a = 0.34
	world_flash.color = flash_color
	create_tween().tween_property(world_flash, "color:a", 0.0, 0.48)

func _light_stage(index: int) -> void:
	if index < 0 or index >= stage_paths.size():
		return
	var stage: CanvasItem = get_node_or_null(stage_paths[index]) as CanvasItem
	if stage == null:
		return
	stage.visible = true
	stage.modulate.a = 0.0
	var reveal: Tween = create_tween()
	reveal.tween_property(stage, "modulate:a", 1.0, stage_interval * 0.85).set_trans(Tween.TRANS_SINE)
	reveal.parallel().tween_property(stage, "scale", Vector2.ONE * 1.015, stage_interval * 0.4)
	reveal.tween_property(stage, "scale", Vector2.ONE, stage_interval * 0.35)
	lit_stages += 1
	activation_label.text = STAGE_COPY[index] if index < STAGE_COPY.size() else "CURRENT STAGE %02d // STABLE" % (index + 1)
	activation_progress.value = lerpf(24.0, 92.0, float(lit_stages) / maxf(float(stage_paths.size()), 1.0))
	coupler_prompt.text = STAGE_COPY[index] if index < STAGE_COPY.size() else "CURRENT STAGE %02d // STABLE" % (index + 1)
	_sync_coupler_gauge()
	RunUnitAudio.play_event("beacon_stage", -12.0)
func _declare_success() -> void:
	activation_label.text = "Beacon 9 shines again."
	activation_progress.value = 100.0
	coupler_prompt.text = "The city lights return."
	_sync_coupler_gauge()
	completion_banner.visible = true
	completion_banner.modulate.a = 0.0
	completion_banner.scale = Vector2.ONE * 0.88
	var reveal: Tween = create_tween()
	reveal.tween_property(completion_banner, "modulate:a", 1.0, 0.35)
	reveal.parallel().tween_property(completion_banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(completion_banner, "modulate:a", 0.82, 0.22)
	reveal.tween_property(completion_banner, "modulate:a", 1.0, 0.28)

func _focus_camera() -> void:
	_camera = get_viewport().get_camera_2d()
	if _camera == null:
		return
	_camera_zoom_start = _camera.zoom
	_camera_offset_start = _camera.offset
	_camera_tween = create_tween()
	_camera_tween.tween_property(_camera, "zoom", _camera_zoom_start * 1.055, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.parallel().tween_property(_camera, "offset", _camera_offset_start + Vector2(46.0, -18.0), 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _restore_camera() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.zoom = _camera_zoom_start
	_camera.offset = _camera_offset_start
	_camera = null

func _sync_coupler_gauge() -> void:
	if coupler_fill == null or activation_progress == null:
		return
	var ratio: float = clampf(activation_progress.value / 100.0, 0.0, 1.0)
	var end_x: float = lerpf(-118.0, 118.0, ratio)
	coupler_fill.points = PackedVector2Array([Vector2(-118.0, 0.0), Vector2(end_x, 0.0)])
