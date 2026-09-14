class_name RunUnitEnvironment
extends Node

## Thin simulation interface for future NEAT/DQN clients. It owns no input code.
@export var game_path: NodePath
var _game: RunUnitGame = null
var _previous_jump_held: bool = false

func _ready() -> void:
	_game = get_node(game_path) as RunUnitGame

func reset(run_seed: int) -> Dictionary:
	_previous_jump_held = false
	if _game != null:
		_game.reset_run(run_seed)
	return get_observation()

func apply_action(action: int) -> void:
	if _game == null:
		return
	var player_action: RunUnitPlayerAction = RunUnitPlayerAction.from_discrete(action, _previous_jump_held)
	_previous_jump_held = player_action.jump_held
	_game.apply_external_action(player_action)

func get_observation() -> Dictionary:
	if _game == null:
		return {"values": PackedFloat32Array()}
	return _game.get_observation()

func get_reward() -> float:
	return 0.0 if _game == null else _game.consume_reward()

func is_terminal() -> bool:
	return false if _game == null else _game.is_terminal()
