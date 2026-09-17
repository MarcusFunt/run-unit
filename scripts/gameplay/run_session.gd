extends Node

var selected_level_index: int = 0
var run_seed: int = 0
var world_version: String = "static"
var world_mode: String = "authored"
var configuration_hash: String = ""
var last_world_metrics: Dictionary = {}
var traversal_trace: Dictionary = {}
var last_run_outcome: String = "active"

## Keyed by route index. Routes differ wildly in length, so a single shared
## best-distance value would carry a meaningless number over when the player
## switches routes; each route remembers its own record instead.
var _best_distances_by_level: Dictionary = {}

var best_distance: float:
	get:
		return float(_best_distances_by_level.get(selected_level_index, 0.0))
	set(value):
		_best_distances_by_level[selected_level_index] = maxf(value, 0.0)

## Furthest checkpoint the player reached on the route they are running. It
## lives here rather than in RunUnitGame because retrying reloads the game
## scene, and a long route should not be replayed from the start after one
## mistake. Deploying a route from the selector and finishing it both clear it.
var checkpoint_level_index: int = -1
var checkpoint_position: Vector2 = Vector2.ZERO

func begin_run(level_index: int, seed_value: int, mode: String, version: String, config_hash: String) -> void:
	selected_level_index = level_index
	run_seed = seed_value
	world_mode = mode
	world_version = version
	configuration_hash = config_hash
	last_world_metrics = {}
	traversal_trace = {}
	last_run_outcome = "active"

func set_world_metrics(metrics: Dictionary) -> void:
	last_world_metrics = metrics.duplicate(true)

func set_traversal_trace(trace: Dictionary) -> void:
	traversal_trace = trace.duplicate(true)

func record_best_distance(distance_value: float) -> void:
	best_distance = maxf(best_distance, maxf(distance_value, 0.0))

func set_run_outcome(outcome: String) -> void:
	last_run_outcome = outcome

func record_checkpoint(level_index: int, position: Vector2) -> void:
	checkpoint_level_index = level_index
	checkpoint_position = position

func has_checkpoint(level_index: int) -> bool:
	return checkpoint_level_index == level_index

## The position a retry should resume from: the reached checkpoint, or the
## route's own spawn when the player has not passed one yet.
func get_resume_position(level_index: int, spawn_position: Vector2) -> Vector2:
	return checkpoint_position if has_checkpoint(level_index) else spawn_position

func clear_checkpoint() -> void:
	checkpoint_level_index = -1
	checkpoint_position = Vector2.ZERO
