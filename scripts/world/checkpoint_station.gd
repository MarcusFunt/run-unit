class_name RunUnitCheckpointStation
extends Area2D

signal activated(position: Vector2)

const DISPLAY_SCENE: PackedScene = preload("res://scenes/props/maintenance_station.tscn")
const CONFIRM_SOUND: AudioStream = preload("res://assets/audio/kenney/land_metal.ogg")
const OFFLINE := Color(0.9, 0.44, 0.13, 0.8)
const ONLINE := Color(0.28, 0.96, 0.92, 1.0)

var checkpoint_position: Vector2
var is_active: bool = false
var _display: Node2D
var _confirmation: Label
var _confirmation_time: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, 100)
	collider.position = Vector2(0, -12)
	collider.shape = shape
	add_child(collider)
	_display = DISPLAY_SCENE.instantiate() as Node2D
	_display.position = Vector2(0, 32)
	add_child(_display)
	_confirmation = Label.new()
	_confirmation.text = "RECOVERY NODE REGISTERED"
	_confirmation.position = Vector2(-122, -126)
	_confirmation.add_theme_color_override("font_color", ONLINE)
	_confirmation.add_theme_font_size_override("font_size", 14)
	add_child(_confirmation)
	body_entered.connect(_on_body_entered)
	reset_level_state()

func reset_level_state() -> void:
	is_active = false
	_confirmation_time = 0.0
	_update_display()

func restore_active() -> void:
	is_active = true
	_confirmation_time = 0.0
	_update_display()

func activate_for(player: RunUnitPlayerMotor) -> void:
	if is_active or player == null:
		return
	is_active = true
	_confirmation_time = 2.0
	_update_display()
	activated.emit(checkpoint_position)
	if DisplayServer.get_name() != "headless":
		var sound := AudioStreamPlayer2D.new()
		sound.stream = CONFIRM_SOUND
		sound.volume_db = -7.0
		sound.pitch_scale = 1.35
		add_child(sound)
		sound.finished.connect(sound.queue_free, CONNECT_ONE_SHOT)
		sound.play()

func _process(delta: float) -> void:
	if _confirmation_time > 0.0:
		_confirmation_time = maxf(_confirmation_time - delta, 0.0)
		_confirmation.visible = _confirmation_time > 0.0

func _update_display() -> void:
	if _display == null:
		return
	(_display.get_node("WorkLight") as Polygon2D).color = ONLINE if is_active else OFFLINE
	(_display.get_node("WorkGlow") as Polygon2D).color = Color(0.20, 0.85, 0.82, 0.18) if is_active else Color(0.9, 0.36, 0.08, 0.08)
	(_display.get_node("StatusScreen") as CanvasItem).modulate = ONLINE if is_active else OFFLINE
	_confirmation.visible = _confirmation_time > 0.0

func _on_body_entered(body: Node2D) -> void:
	if body is RunUnitPlayerMotor:
		activate_for(body as RunUnitPlayerMotor)
