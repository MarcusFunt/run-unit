class_name RunUnitScriptedController
extends Node

## A deliberately modest bot that proves non-human actions share the motor.
@export var player_path: NodePath
@export var world_path: NodePath
var active: bool = false
var _motor: RunUnitPlayerMotor = null
var _world: RunUnitStaticWorld = null
var _jump_held_last_frame: bool = false

func _ready() -> void:
	_motor = get_node(player_path) as RunUnitPlayerMotor
	_world = get_node(world_path) as RunUnitStaticWorld

func reset_controller() -> void:
	_jump_held_last_frame = false

func _physics_process(_delta: float) -> void:
	if not active or _motor == null or _world == null:
		return
	var should_charge: bool = _should_charge()
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = 1.0
	action.jump_held = should_charge
	action.jump_pressed = should_charge and not _jump_held_last_frame
	action.jump_released = not should_charge and _jump_held_last_frame
	_jump_held_last_frame = should_charge
	_motor.set_action(action)

func _should_charge() -> bool:
	if not _motor.is_on_floor():
		return false
	var platform: Dictionary = _world.get_platform_below(_motor.global_position.x)
	if platform.is_empty():
		return false
	var end_world_x: float = (float(platform.get("end_x", 0)) + 0.5) * _world.tile_size
	if not _jump_held_last_frame:
		return _motor.global_position.x > end_world_x - 125.0
	return _motor.global_position.x < end_world_x - 45.0 and _motor.charge_ratio < 0.70
