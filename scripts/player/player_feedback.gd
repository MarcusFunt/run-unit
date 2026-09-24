class_name RunUnitPlayerFeedback
extends Node2D

# The feedback layer intentionally stays quieter and smaller than the robot animation.
# Mechanical motion should read first; VFX and audio only confirm what happened.
const MECHANICAL_ACTION: AudioStream = preload("res://assets/audio/feedback/mechanical_action.wav")
const METAL_CLANK: AudioStream = preload("res://assets/audio/feedback/metal_clank.wav")
const METAL_CLINK: AudioStream = preload("res://assets/audio/feedback/metal_clink.wav")
const BODY_THUD_SOFT: AudioStream = preload("res://assets/audio/feedback/body_thud_soft.wav")
const BODY_THUD_HARD: AudioStream = preload("res://assets/audio/feedback/body_thud_hard.wav")

const JUMP_DUST_SCENE: PackedScene = preload("res://assets/vfx/godot_vfx_library/run_unit_jump_dust.tscn")
const METAL_SPARK_SCENE: PackedScene = preload("res://assets/vfx/godot_vfx_library/run_unit_metal_sparks.tscn")

const LANDING_TIER_SOFT: int = 0
const LANDING_TIER_MEDIUM: int = 1
const LANDING_TIER_HARD: int = 2
const MEDIUM_LANDING_RATIO: float = 0.48
const HARD_LANDING_RATIO: float = 0.72

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor

var _sound_variation_index: int = 0

func _ready() -> void:
	top_level = true
	transform = Transform2D.IDENTITY
	if player != null:
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)

func play_charge_stage(stage: int) -> void:
	var clamped_stage: int = clampi(stage, 1, 2)
	_play_sound(
		MECHANICAL_ACTION,
		-23.0 + float(clamped_stage - 1) * 2.5,
		0.98 + float(clamped_stage - 1) * 0.10,
		0.012
	)

func play_charge_ready() -> void:
	# Full charge already has a strong diegetic visual in RobotVisual. Keep this as a
	# precise mechanism lock rather than adding another cyan burst.
	_play_sound(MECHANICAL_ACTION, -18.0, 1.20, 0.010)
	_play_sound(METAL_CLINK, -24.0, 1.12, 0.018)

func play_damage_feedback() -> void:
	_spawn_particles(_emitter_position(Vector2(0.0, -2.0)), METAL_SPARK_SCENE, 0.62)
	_play_sound(METAL_CLANK, -7.0, 0.96, 0.018)
	_play_sound(BODY_THUD_HARD, -11.0, 0.90, 0.012)

func play_game_over_feedback() -> void:
	_spawn_particles(_emitter_position(Vector2(0.0, -2.0)), METAL_SPARK_SCENE, 0.78)
	_spawn_particles(_emitter_position(Vector2(0.0, 15.0)), JUMP_DUST_SCENE, 0.78)
	_play_sound(METAL_CLANK, -4.0, 0.84, 0.012)
	_play_sound(BODY_THUD_HARD, -8.0, 0.76, 0.010)
	_play_sound(MECHANICAL_ACTION, -17.0, 0.72, 0.008)

func landing_tier_for_ratio(impact_ratio: float) -> int:
	var ratio: float = clampf(impact_ratio, 0.0, 1.0)
	if ratio >= HARD_LANDING_RATIO:
		return LANDING_TIER_HARD
	if ratio >= MEDIUM_LANDING_RATIO:
		return LANDING_TIER_MEDIUM
	return LANDING_TIER_SOFT

func should_emit_landing_sparks_for_ratio(impact_ratio: float) -> bool:
	return landing_tier_for_ratio(impact_ratio) == LANDING_TIER_HARD

func _on_player_jumped() -> void:
	_spawn_particles(_emitter_position(Vector2(0.0, 15.0)), JUMP_DUST_SCENE, 0.56)
	_play_sound(MECHANICAL_ACTION, -14.0, 1.16, 0.016)
	_play_sound(METAL_CLINK, -25.0, 1.18, 0.020)

func _on_player_landed() -> void:
	var impact_ratio: float = 0.35
	if player != null:
		impact_ratio = clampf(player.last_landing_speed / player.max_fall_speed, 0.0, 1.0)

	var tier: int = landing_tier_for_ratio(impact_ratio)
	match tier:
		LANDING_TIER_HARD:
			_spawn_particles(_emitter_position(Vector2(0.0, 15.0)), JUMP_DUST_SCENE, 0.88)
			_spawn_particles(_emitter_position(Vector2(0.0, 14.0)), METAL_SPARK_SCENE, 0.54)
			_play_sound(BODY_THUD_HARD, -8.0, 0.92, 0.012)
			_play_sound(METAL_CLANK, -12.0, 1.00, 0.018)
			_play_sound(METAL_CLINK, -20.0, 0.94, 0.020)
		LANDING_TIER_MEDIUM:
			_spawn_particles(_emitter_position(Vector2(0.0, 15.0)), JUMP_DUST_SCENE, 0.70)
			_play_sound(BODY_THUD_SOFT, -13.0, 1.00, 0.016)
			_play_sound(METAL_CLINK, -19.0, 1.05, 0.020)
		_:
			_spawn_particles(_emitter_position(Vector2(0.0, 15.0)), JUMP_DUST_SCENE, 0.52)
			_play_sound(BODY_THUD_SOFT, -17.0, 1.08, 0.016)
			_play_sound(METAL_CLINK, -23.0, 1.14, 0.020)

func _emitter_position(body_offset: Vector2) -> Vector2:
	if player == null:
		return body_offset
	return player.global_position + body_offset

func _spawn_particles(origin: Vector2, scene: PackedScene, effect_scale: float) -> void:
	if scene == null:
		return
	var effect: CPUParticles2D = scene.instantiate() as CPUParticles2D
	if effect == null:
		return
	add_child(effect)
	effect.global_position = origin
	effect.scale = Vector2.ONE * effect_scale
	effect.emitting = true
	effect.restart()
	var cleanup_seconds: float = maxf(effect.lifetime + 0.15, 0.25)
	get_tree().create_timer(cleanup_seconds).timeout.connect(effect.queue_free, CONNECT_ONE_SHOT)

func _play_sound(stream: AudioStream, volume_db: float, base_pitch: float, pitch_spread: float = 0.0) -> void:
	if stream == null or DisplayServer.get_name() == "headless":
		return
	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = base_pitch * _next_pitch_multiplier(pitch_spread)
	voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(voice)
	voice.finished.connect(voice.queue_free, CONNECT_ONE_SHOT)
	voice.play()

func _next_pitch_multiplier(spread: float) -> float:
	if spread <= 0.0:
		return 1.0
	# A fixed sequence avoids the machine-gun effect without making tests nondeterministic.
	var step: int = (_sound_variation_index % 5) - 2
	_sound_variation_index += 1
	return 1.0 + float(step) * spread * 0.5
