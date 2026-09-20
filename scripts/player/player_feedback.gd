class_name RunUnitPlayerFeedback
extends Node2D

const JUMP_SOUND: AudioStream = preload("res://assets/audio/kenney/jump_zap.ogg")
const LAND_SOUND: AudioStream = preload("res://assets/audio/kenney/land_metal.ogg")
const DAMAGE_SOUND: AudioStream = preload("res://assets/audio/kenney/damage_metal.ogg")
const GAME_OVER_SOUND: AudioStream = preload("res://assets/audio/kenney/game_over_crunch.ogg")

const JUMP_FX: SpriteFrames = preload("res://assets/generated/godot/spriteframes/fx/part_2/fx_77.tres")
const LAND_FX: SpriteFrames = preload("res://assets/generated/godot/spriteframes/fx/part_2/fx_78.tres")
const DAMAGE_FX: SpriteFrames = preload("res://assets/generated/godot/spriteframes/fx/part_2/fx_79.tres")
const GAME_OVER_FX: SpriteFrames = preload("res://assets/generated/godot/spriteframes/fx/part_2/fx_71.tres")

const CYAN_FX: StringName = &"palette_2"
const AMBER_FX: StringName = &"palette_4"

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor


func _ready() -> void:
	top_level = true
	transform = Transform2D.IDENTITY
	if player != null:
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)


func play_damage_feedback() -> void:
	_spawn_effect(_emitter_position(Vector2(0.0, -2.0)), DAMAGE_FX, AMBER_FX, 0.78)
	_play_sound(DAMAGE_SOUND, -2.0, 0.96)


func play_game_over_feedback() -> void:
	_spawn_effect(_emitter_position(Vector2(0.0, -4.0)), GAME_OVER_FX, AMBER_FX, 1.05)
	_play_sound(GAME_OVER_SOUND, -1.0, 0.92)


func _on_player_jumped() -> void:
	_spawn_effect(_emitter_position(Vector2(0.0, 14.0)), JUMP_FX, CYAN_FX, 0.48)
	_play_sound(JUMP_SOUND, -8.0, 1.16)


func _on_player_landed() -> void:
	var impact_ratio: float = 0.35
	if player != null:
		impact_ratio = clampf(player.last_landing_speed / player.max_fall_speed, 0.35, 1.0)

	var effect_scale: float = lerpf(0.45, 0.72, impact_ratio)
	_spawn_effect(_emitter_position(Vector2(0.0, 15.0)), LAND_FX, AMBER_FX, effect_scale)
	_play_sound(LAND_SOUND, lerpf(-10.0, -4.0, impact_ratio), lerpf(1.08, 0.92, impact_ratio))


func _emitter_position(body_offset: Vector2) -> Vector2:
	if player == null:
		return body_offset
	return player.global_position + body_offset


# The old FX pack already has proper one-shot bursts, so there is no reason to draw fake particles here.
func _spawn_effect(origin: Vector2, frames: SpriteFrames, animation: StringName, effect_scale: float) -> void:
	if frames == null or not frames.has_animation(animation):
		return

	var one_shot_frames: SpriteFrames = frames.duplicate(true) as SpriteFrames
	one_shot_frames.set_animation_loop(animation, false)

	var effect: AnimatedSprite2D = AnimatedSprite2D.new()
	effect.sprite_frames = one_shot_frames
	effect.z_index = 20
	effect.scale = Vector2.ONE * effect_scale
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(effect)

	effect.global_position = origin
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.play(animation)


# Actual asset sounds now. No generated tones.
func _play_sound(stream: AudioStream, volume_db: float, pitch_scale: float) -> void:
	if stream == null or DisplayServer.get_name() == "headless":
		return

	var voice: AudioStreamPlayer = AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch_scale
	voice.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(voice)

	voice.finished.connect(voice.queue_free, CONNECT_ONE_SHOT)
	voice.play()
