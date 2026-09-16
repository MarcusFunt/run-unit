class_name RunUnitTutorialElevatorExit
extends Node2D

signal transition_finished

@export_file("*.tscn") var next_scene_path: String = ""
@export var jammed_leaf_y: float = -143.75
@export var closed_leaf_y: float = -87.75
@export_range(0.05, 0.5, 0.01) var close_duration: float = 0.12
@export_range(0.0, 0.3, 0.01) var blackout_delay: float = 0.06
@export_range(0.05, 0.5, 0.01) var fade_duration: float = 0.18

@onready var door_leaf: Sprite2D = $DoorLeaf
@onready var closed_door: Sprite2D = $ClosedDoor
@onready var blackout: ColorRect = $BlackoutLayer/Blackout

var transition_started: bool = false
var door_slammed: bool = false
var _transition_tween: Tween

func _ready() -> void:
	reset_transition()

func reset_transition() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	transition_started = false
	door_slammed = false
	door_leaf.position.y = jammed_leaf_y
	door_leaf.visible = true
	closed_door.visible = false
	var blackout_color: Color = blackout.color
	blackout_color.a = 0.0
	blackout.color = blackout_color

func begin_transition() -> void:
	if transition_started:
		return
	transition_started = true
	_transition_tween = create_tween()
	_transition_tween.tween_property(door_leaf, "position:y", closed_leaf_y, close_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_transition_tween.tween_callback(_on_door_slammed)
	_transition_tween.tween_interval(blackout_delay)
	_transition_tween.tween_property(blackout, "color:a", 1.0, fade_duration)
	_transition_tween.tween_callback(_on_transition_finished)

func _on_door_slammed() -> void:
	door_slammed = true
	door_leaf.visible = false
	closed_door.visible = true

func _on_transition_finished() -> void:
	transition_finished.emit()
	if next_scene_path.is_empty():
		return
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	if scene_loader != null and scene_loader.has_method("load_scene"):
		scene_loader.call("load_scene", next_scene_path)
	else:
		get_tree().change_scene_to_file(next_scene_path)
