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
