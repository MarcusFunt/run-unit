class_name RunUnitPlayerAction
extends RefCounted

## Discrete, controller-neutral command passed to RunUnitPlayerMotor.
## The values are intentionally stable for future NEAT/DQN integrations.
enum DiscreteAction {
	NOTHING = 0,
	LEFT = 1,
	RIGHT = 2,
	JUMP = 3,
	LEFT_JUMP = 4,
	RIGHT_JUMP = 5,
}

var movement: float = 0.0
var jump_pressed: bool = false
var jump_held: bool = false
var jump_released: bool = false
var crouch_held: bool = false

static func from_discrete(action: int, was_jump_held: bool = false) -> RunUnitPlayerAction:
	var result: RunUnitPlayerAction = RunUnitPlayerAction.new()
	match action:
		DiscreteAction.LEFT:
			result.movement = -1.0
		DiscreteAction.RIGHT:
			result.movement = 1.0
		DiscreteAction.JUMP:
			result.jump_held = true
		DiscreteAction.LEFT_JUMP:
			result.movement = -1.0
			result.jump_held = true
		DiscreteAction.RIGHT_JUMP:
			result.movement = 1.0
			result.jump_held = true
	result.jump_pressed = result.jump_held and not was_jump_held
	result.jump_released = not result.jump_held and was_jump_held
	return result

func duplicate_action() -> RunUnitPlayerAction:
	var result: RunUnitPlayerAction = RunUnitPlayerAction.new()
	result.movement = movement
	result.jump_pressed = jump_pressed
	result.jump_held = jump_held
	result.jump_released = jump_released
	result.crouch_held = crouch_held
	return result
