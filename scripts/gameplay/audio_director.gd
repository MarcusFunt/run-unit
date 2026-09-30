extends Node
## Small centralized effects and route ambience using bundled CC0 Kenney audio.

const AMBIENCE := {
	"factory": "res://assets/audio/kenney/engineCircular_000.ogg",
	"factory_interior": "res://assets/audio/kenney/computerNoise_000.ogg",
	"exterior": "res://assets/audio/kenney/spaceEngineLow_000.ogg",
	"cooling": "res://assets/audio/kenney/forceField_000.ogg",
	"beacon_exterior": "res://assets/audio/kenney/spaceEngine_000.ogg",
	"beacon_interior": "res://assets/audio/kenney/computerNoise_000.ogg",
}
const EVENTS := {
	"hazard_warning": "res://assets/audio/kenney/computerNoise_000.ogg",
	"collapse_warning": "res://assets/audio/kenney/doorClose_000.ogg",
	"electrical_arc": "res://assets/audio/kenney/laserLarge_000.ogg",
	"crusher_strike": "res://assets/audio/kenney/impactMetal_000.ogg",
	"module_acquired": "res://assets/audio/kenney/forceField_000.ogg",
	"objective_cue": "res://assets/audio/kenney/forceField_000.ogg",
	"checkpoint": "res://assets/audio/kenney/impactMetal_000.ogg",
	"beacon_stage": "res://assets/audio/kenney/laserLarge_000.ogg",
	"beacon_online": "res://assets/audio/kenney/spaceEngine_000.ogg",
}

var _ambience_player: AudioStreamPlayer
var _current_ambience: String = ""

func _ready() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "RouteAmbience"
	_ambience_player.volume_db = -25.0
	add_child(_ambience_player)

func set_ambience(profile: String) -> void:
	if profile == _current_ambience or not AMBIENCE.has(profile):
		return
	_current_ambience = profile
	var stream := load(str(AMBIENCE[profile])) as AudioStreamOggVorbis
	if stream == null:
		return
	var loop_stream := stream.duplicate() as AudioStreamOggVorbis
	loop_stream.loop = true
	_ambience_player.stop()
	_ambience_player.stream = loop_stream
	_ambience_player.play()
	_ambience_player.volume_db = -25.0

func play_event(event_name: String, volume_db: float = -6.0) -> void:
	if not EVENTS.has(event_name):
		return
	var stream := load(str(EVENTS[event_name])) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func play_world_event(event_name: String, world_position: Vector2, volume_db: float = -10.0) -> void:
	if DisplayServer.get_name() == "headless" or not EVENTS.has(event_name):
		return
	var stream := load(str(EVENTS[event_name])) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 1050.0
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func play_hazard_phase(phase: int, hazard_name: String, world_position: Vector2) -> void:
	if phase == RunUnitHazardArea.HazardPhase.WARNING:
		play_world_event("hazard_warning", world_position, -15.0)
	elif phase == RunUnitHazardArea.HazardPhase.ACTIVE:
		if hazard_name.to_lower().contains("crusher"):
			play_world_event("crusher_strike", world_position, -9.0)
		else:
			play_world_event("electrical_arc", world_position, -13.0)
