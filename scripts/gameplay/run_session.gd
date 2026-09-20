extends Node

## True when the game was launched as a hands-off demo (`--demo`): the scripted
## controller drives, routes advance into each other without stopping on a
## results menu, and a death retries instead of waiting for input. Recording a
## playthrough is the point of it, so it pairs with Godot's movie writer:
##     godot --path . --write-movie run.avi --fixed-fps 60 -- --demo
var demo_mode: bool = false
## A completed hands-off run is terminal for the lifetime of the process. This
## prevents any fallback to the main menu from auto-starting route 0 again.
var demo_completed: bool = false
var demo_completion_count: int = 0
var demo_route_starts: Array[int] = []
var demo_damage_events: int = 0
var demo_failure_events: int = 0

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

## Godot only routes arguments after a bare `--` into get_cmdline_user_args(),
## but passing `--demo` straight through works too, so both are accepted.
func _ready() -> void:
	demo_mode = OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_args().has("--demo")
	reset_demo_lifecycle()

func reset_demo_lifecycle() -> void:
	demo_completed = false
	demo_completion_count = 0
	demo_route_starts.clear()
	demo_damage_events = 0
	demo_failure_events = 0

func should_start_demo() -> bool:
	return demo_mode and not demo_completed

func record_demo_route_start(level_index: int) -> void:
	if not demo_mode or demo_completed:
		return
	demo_route_starts.append(level_index)
	print("DEMO_ROUTE_START index=%d ordinal=%d" % [level_index, demo_route_starts.size()])

func record_demo_damage() -> void:
	if demo_mode and not demo_completed:
		demo_damage_events += 1

func record_demo_failure() -> void:
	if demo_mode and not demo_completed:
		demo_failure_events += 1

## Marks the campaign terminal exactly once. Returning false means some later
## scene tried to finish an already-finished demo and must not restart it.
func mark_demo_completed() -> bool:
	if not demo_mode or demo_completed:
		return false
	demo_completed = true
	demo_completion_count += 1
	print("DEMO_CAMPAIGN_COMPLETE completions=%d routes=%s damage=%d failures=%d" % [demo_completion_count, str(demo_route_starts), demo_damage_events, demo_failure_events])
	return true

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
