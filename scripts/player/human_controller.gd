class_name RunUnitHumanController
extends Node

@export var player_path: NodePath
var active: bool = true
var _motor: RunUnitPlayerMotor = null

func _ready() -> void:
	_motor = get_node(player_path) as RunUnitPlayerMotor

func _physics_process(_delta: float) -> void:
	if not active or _motor == null:
		return
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = Input.get_axis("move_left", "move_right")
	action.jump_pressed = Input.is_action_just_pressed("jump")
	action.jump_held = Input.is_action_pressed("jump")
	action.jump_released = Input.is_action_just_released("jump")
	action.crouch_held = Input.is_action_pressed("crouch")
	_motor.set_action(action)
