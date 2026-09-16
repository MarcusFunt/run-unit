class_name RunUnitStaticWorld
extends Node2D

signal world_metrics_updated(metrics: Dictionary)
@warning_ignore("unused_signal")
signal obstacle_triggered(obstacle_type: String, platform_id: int)
signal route_completed

const TILE_SIZE: float = 32.0

@export var death_y: float = 900.0

var tile_size: float = TILE_SIZE
var _platforms: Array[Dictionary] = []
var _difficulty: float = 0.0
var _metrics: Dictionary = {}
var _completion_triggered: bool = false
@onready var _completion_trigger: Area2D = get_node_or_null("CompletionTrigger") as Area2D

func _ready() -> void:
	_load_authored_platforms()
	_update_metrics()
	if _completion_trigger != null and not _completion_trigger.body_entered.is_connected(_on_completion_trigger_body_entered):
		_completion_trigger.body_entered.connect(_on_completion_trigger_body_entered)

func set_level_profile(_level_index: int) -> void:
	pass

func reset(_run_seed: int = 0, _mode: String = "campaign") -> void:
	_difficulty = 0.0
	_completion_triggered = false
	_update_metrics()

func set_progress(max_distance: float) -> void:
	_difficulty = clampf(max_distance / get_route_length(), 0.0, 1.0)
	_metrics["difficulty"] = _difficulty
	world_metrics_updated.emit(_metrics.duplicate(true))

func get_platform_below(world_x: float) -> Dictionary:
	var tile_x: int = floori(world_x / tile_size)
	for platform: Dictionary in _platforms:
		if tile_x >= int(platform.get("start_x", 0)) and tile_x <= int(platform.get("end_x", 0)):
			return platform.duplicate()
	return {}

func get_upcoming_platforms(world_x: float, count: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tile_x: int = floori(world_x / tile_size)
	for platform: Dictionary in _platforms:
		if int(platform.get("end_x", 0)) >= tile_x:
			result.append(platform.duplicate())
			if result.size() >= count:
				break
	return result

func get_seed() -> int:
	return 0

func get_difficulty() -> float:
	return _difficulty

func get_route_digest() -> String:
	return JSON.stringify(_platforms)

func get_current_plan() -> Array[Dictionary]:
	return _platforms.duplicate(true)

func get_world_metrics() -> Dictionary:
	return _metrics.duplicate(true)

func is_route_valid() -> bool:
	return not _platforms.is_empty()

func get_tile_size() -> float:
	return tile_size

func get_route_length() -> float:
	var route_end: float = 0.0
	for platform: Dictionary in _platforms:
		var platform_end: float = (float(platform.get("end_x", 0)) + 1.0) * tile_size
		route_end = maxf(route_end, platform_end)
	return route_end / tile_size

func is_completion_triggered() -> bool:
	return _completion_triggered

func _load_authored_platforms() -> void:
	_platforms.clear()
	var platform_id: int = 1
	for child: Node in get_children():
		var platform_body: StaticBody2D = child as StaticBody2D
		if platform_body == null:
			continue
		var width_pixels: float = float(platform_body.get_meta("width_pixels", 0.0))
		if width_pixels <= 0.0:
			continue
		var start_x: int = roundi(platform_body.position.x / tile_size)
		var surface_y: int = roundi(platform_body.position.y / tile_size)
		_platforms.append({
			"platform_id": platform_id,
			"start_x": start_x,
			"end_x": start_x + roundi(width_pixels / tile_size) - 1,
			"height": surface_y,
			"width": roundi(width_pixels / tile_size),
			"challenge_type": "Authored",
			"gap_before": 0,
			"obstacle_x": -1,
			"obstacle_type": "",
			"hazard_x": -1,
			"collectible": false
		})
		platform_id += 1

func _update_metrics() -> void:
	_metrics = {
		"level_type": "authored",
		"platform_count": _platforms.size(),
		"route_ready": not _platforms.is_empty(),
		"difficulty": _difficulty
	}
	world_metrics_updated.emit(_metrics.duplicate(true))

func _on_completion_trigger_body_entered(body: Node2D) -> void:
	if _completion_triggered or not body is RunUnitPlayerMotor:
		return
	_completion_triggered = true
	route_completed.emit()
