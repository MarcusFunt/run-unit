class_name RunUnitScriptedController
extends Node

## A deliberately modest bot that proves non-human actions share the motor.
@export var player_path: NodePath
@export var world_path: NodePath
## How far ahead of the player, in pixels, the bot checks for a crouch gate
## so it is already ducked by the time it arrives instead of walking into it.
const CROUCH_LOOKAHEAD_DISTANCE: float = 64.0

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
	var wants_to_crouch: bool = _should_crouch()
	var should_charge: bool = not wants_to_crouch and _should_charge()
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = 1.0
	action.crouch_held = wants_to_crouch
	action.jump_held = should_charge
	action.jump_pressed = should_charge and not _jump_held_last_frame
	action.jump_released = not should_charge and _jump_held_last_frame
	_jump_held_last_frame = should_charge
	_motor.set_action(action)

## Ducks a crouch gate before reaching it (lookahead probe) and stays ducked
## until clear of it (a zero-distance probe at the player's own position),
## rather than only reacting after the standing collision already stopped it.
func _should_crouch() -> bool:
	if not _motor.is_on_floor() or _motor.is_charging():
		return false
	return _motor.has_low_clearance_ahead(0.0) or _motor.has_low_clearance_ahead(CROUCH_LOOKAHEAD_DISTANCE)

func _should_charge() -> bool:
	if not _motor.is_on_floor():
		return false
	var platform: Dictionary = _world.get_platform_below(_motor.global_position.x)
	if platform.is_empty():
		return false
	var end_world_x: float = _world.to_global(Vector2((float(platform.get("end_x", 0)) + 0.5) * _world.tile_size, 0.0)).x
	if not _jump_held_last_frame:
		return _motor.global_position.x > end_world_x - 125.0
	return _motor.global_position.x < end_world_x - 45.0 and _motor.charge_ratio < 0.70
