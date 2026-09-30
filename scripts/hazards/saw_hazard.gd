class_name RunUnitSawHazard
extends RunUnitHazardArea

@export_range(-20.0, 20.0, 0.1) var spin_speed: float = 7.5

var _blade: Node2D = null
var _motor_audio: AudioStreamPlayer2D = null

func _ready() -> void:
	_blade = get_node_or_null("ActiveVisual") as Node2D
	super._ready()
	if DisplayServer.get_name() == "headless":
		return
	var motor_stream := load("res://assets/audio/kenney/engineCircular_000.ogg") as AudioStreamOggVorbis
	if motor_stream == null:
		return
	motor_stream = motor_stream.duplicate() as AudioStreamOggVorbis
	motor_stream.loop = true
	_motor_audio = AudioStreamPlayer2D.new()
	_motor_audio.name = "SawMotorAudio"
	_motor_audio.stream = motor_stream
	_motor_audio.volume_db = -23.0
	_motor_audio.max_distance = 560.0
	add_child(_motor_audio)
	if active:
		_motor_audio.play()

func _physics_process(delta: float) -> void:
	if _blade != null:
		_blade.rotation += spin_speed * delta
	if _motor_audio != null and active and not _motor_audio.playing:
		_motor_audio.play()
	elif _motor_audio != null and not active and _motor_audio.playing:
		_motor_audio.stop()
