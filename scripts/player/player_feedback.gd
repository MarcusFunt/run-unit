class_name RunUnitPlayerFeedback
extends Node2D

const SAMPLE_RATE: float = 22050.0
const BUFFER_LENGTH: float = 0.18
## Frames of silence kept queued while nothing is playing. Topping the
## generator buffer right up every frame meant a newly started tone sat behind
## a full buffer of already-queued silence, so jump and landing sounds arrived
## up to BUFFER_LENGTH (180 ms) after the event that caused them. A short idle
## cushion still protects against underruns without that lag.
const IDLE_BUFFER_FRAMES: int = 256

@onready var player: RunUnitPlayerMotor = get_parent() as RunUnitPlayerMotor

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _audio_player: AudioStreamPlayer = null
var _audio_playback: AudioStreamGeneratorPlayback = null
var _tone_remaining: float = 0.0
var _tone_duration: float = 0.0
var _tone_start_frequency: float = 0.0
var _tone_end_frequency: float = 0.0
var _tone_volume: float = 0.0
var _tone_noise: float = 0.0
var _tone_phase: float = 0.0

func _ready() -> void:
	_rng.randomize()
	# Sparks are emitted into the world, not carried by the robot. Without
	# this the node's transform follows the player and a landing burst slides
	# along with the body instead of staying where the wheel touched down.
	top_level = true
	transform = Transform2D.IDENTITY
	if DisplayServer.get_name() != "headless":
		_setup_audio()
	if player != null:
		player.jumped.connect(_on_player_jumped)
		player.landed.connect(_on_player_landed)

func _exit_tree() -> void:
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream = null
	_audio_playback = null
	_audio_player = null

func _process(delta: float) -> void:
	_update_particles(delta)
	_fill_audio_buffer()

func play_damage_feedback() -> void:
	_spawn_burst(_emitter_position(Vector2(0.0, -2.0)), 16, Color(1.0, 0.64, 0.24, 1.0), 90.0, 220.0, -80.0)
	_play_tone(310.0, 150.0, 0.12, 0.16, 0.18)

func play_game_over_feedback() -> void:
	_spawn_burst(_emitter_position(Vector2(0.0, -4.0)), 28, Color(1.0, 0.52, 0.2, 1.0), 120.0, 280.0, -130.0)
	_play_tone(240.0, 72.0, 0.42, 0.20, 0.32)

func _setup_audio() -> void:
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = int(SAMPLE_RATE)
	generator.buffer_length = BUFFER_LENGTH
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = generator
	# Routed to the project's SFX bus so the options menu's SFX slider actually
	# reaches these tones; on Master they could only be ducked by turning the
	# music down with them.
	_audio_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(_audio_player)
	_audio_player.play()
	_audio_playback = _audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _on_player_jumped() -> void:
	_spawn_burst(_emitter_position(Vector2(0.0, 13.0)), 12, Color(0.28, 0.85, 1.0, 1.0), 70.0, 150.0, 75.0)
	_play_tone(360.0, 720.0, 0.11, 0.15, 0.04)

func _on_player_landed() -> void:
	var impact_ratio: float = 0.35
	if player != null:
		impact_ratio = clampf(player.last_landing_speed / player.max_fall_speed, 0.35, 1.0)
	var spark_count: int = roundi(lerpf(8.0, 18.0, impact_ratio))
	_spawn_burst(_emitter_position(Vector2(0.0, 14.0)), spark_count, Color(0.96, 0.72, 0.28, 1.0), 80.0, 230.0, -110.0)
	_play_tone(150.0, 82.0, 0.12, lerpf(0.09, 0.18, impact_ratio), 0.24)

## World-space point an effect is emitted from, given an offset relative to
## the player body.
func _emitter_position(body_offset: Vector2) -> Vector2:
	if player == null:
		return body_offset
	return player.global_position + body_offset

func _spawn_burst(origin: Vector2, count: int, color: Color, minimum_speed: float, maximum_speed: float, vertical_bias: float) -> void:
	for index: int in range(count):
		var direction: Vector2 = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.7, 0.7)).normalized()
		var speed: float = _rng.randf_range(minimum_speed, maximum_speed)
		var particle: Dictionary = {
			"position": origin + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-2.0, 2.0)),
			"velocity": direction * speed + Vector2(0.0, vertical_bias),
			"color": color,
			"age": 0.0,
			"lifetime": _rng.randf_range(0.22, 0.48),
			"size": _rng.randf_range(1.6, 3.4),
		}
		_particles.append(particle)
	queue_redraw()

func _update_particles(delta: float) -> void:
	if _particles.is_empty():
		return
	for index: int in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		var age: float = float(particle["age"]) + delta
		var lifetime: float = float(particle["lifetime"])
		if age >= lifetime:
			_particles.remove_at(index)
			continue
		var velocity: Vector2 = particle["velocity"] as Vector2
		velocity.y += 520.0 * delta
		particle["age"] = age
		particle["velocity"] = velocity
		particle["position"] = particle["position"] as Vector2 + velocity * delta
		_particles[index] = particle
	queue_redraw()

func _draw() -> void:
	for particle: Dictionary in _particles:
		var age: float = float(particle["age"])
		var lifetime: float = float(particle["lifetime"])
		var fade: float = 1.0 - age / lifetime
		var color: Color = particle["color"] as Color
		var tint: Color = Color(color.r, color.g, color.b, color.a * fade)
		var position_value: Vector2 = particle["position"] as Vector2
		var velocity: Vector2 = particle["velocity"] as Vector2
		var size: float = float(particle["size"]) * fade
		draw_line(position_value - velocity.normalized() * size * 2.5, position_value, tint, maxf(size, 1.0))

func _play_tone(start_frequency: float, end_frequency: float, duration: float, volume: float, noise: float) -> void:
	_tone_remaining = duration
	_tone_duration = duration
	_tone_start_frequency = start_frequency
	_tone_end_frequency = end_frequency
	_tone_volume = volume
	_tone_noise = noise
	_tone_phase = 0.0

func _fill_audio_buffer() -> void:
	if _audio_playback == null:
		return
	var available_frames: int = _audio_playback.get_frames_available()
	var frames_to_push: int = available_frames
	if _tone_remaining <= 0.0:
		var queued_frames: int = int(SAMPLE_RATE * BUFFER_LENGTH) - available_frames
		frames_to_push = clampi(IDLE_BUFFER_FRAMES - queued_frames, 0, available_frames)
	for index: int in range(frames_to_push):
		var sample: float = 0.0
		if _tone_remaining > 0.0:
			var progress: float = 1.0 - _tone_remaining / _tone_duration
			var frequency: float = lerpf(_tone_start_frequency, _tone_end_frequency, progress)
			var envelope: float = _tone_volume * pow(1.0 - progress, 1.8)
			sample = sin(_tone_phase) * envelope
			sample += _rng.randf_range(-1.0, 1.0) * envelope * _tone_noise
			_tone_phase = fmod(_tone_phase + TAU * frequency / SAMPLE_RATE, TAU)
			_tone_remaining = maxf(_tone_remaining - 1.0 / SAMPLE_RATE, 0.0)
		_audio_playback.push_frame(Vector2(sample, sample))