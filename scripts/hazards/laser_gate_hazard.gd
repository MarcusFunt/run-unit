class_name RunUnitLaserGateHazard
extends RunUnitTimedHazard

@export_range(0.05, 1.0, 0.05) var warning_seconds: float = 0.35

const WARNING_SOUND: AudioStream = preload("res://assets/audio/run_unit/laser_warning.ogg")
const FIRE_SOUND: AudioStream = preload("res://assets/audio/run_unit/laser_fire.ogg")

var _warning_visual: CanvasItem = null
var _audio_was_warning: bool = false
var _audio_was_active: bool = false

func _ready() -> void:
	_warning_visual = get_node_or_null("WarningVisual") as CanvasItem
	super._ready()
	_update_warning_visual()
	_audio_was_active = active
	_audio_was_warning = _is_warning_phase()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_warning_visual()
	_update_audio_cues()

func reset_level_state() -> void:
	super.reset_level_state()
	if is_inside_tree():
		_update_warning_visual()

func _is_warning_phase() -> bool:
	var safe_cycle: float = maxf(cycle_seconds, 0.05)
	var safe_active: float = clampf(active_seconds, 0.0, safe_cycle)
	var phase: float = get_cycle_phase_seconds()
	var warning_start: float = maxf(safe_cycle - warning_seconds, safe_active)
	return phase >= warning_start and phase >= safe_active


func _update_warning_visual() -> void:
	if _warning_visual == null:
		return
	_warning_visual.visible = _is_warning_phase()


func _update_audio_cues() -> void:
	var warning_now := _is_warning_phase()
	if warning_now and not _audio_was_warning:
		_play_positional(WARNING_SOUND, -12.0, 1.0)
	if active and not _audio_was_active:
		_play_positional(FIRE_SOUND, -8.0, 0.98)
	_audio_was_warning = warning_now
	_audio_was_active = active


func _play_positional(stream: AudioStream, volume_db: float, pitch_scale: float) -> void:
	if stream == null or DisplayServer.get_name() == "headless":
		return
	var voice := AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch_scale
	voice.bus = &"SFX"
	voice.max_distance = 720.0
	voice.attenuation = 1.4
	add_child(voice)
	voice.finished.connect(voice.queue_free, CONNECT_ONE_SHOT)
	voice.play()
