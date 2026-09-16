class_name RunUnitStaticWorld
extends Node2D

## Route geometry comes from the Tiled-authored, YATI-imported TileMapLayers
## under this node (assets/tiled/levels/maintenance_shaft.tmj):
##   "Semantic"  - route floor; owns collision and is scanned for platforms
##   "Obstacles" - collidable obstacle geometry (the crouch gate); never a platform
##   "Art"       - decoration only, carries no collision at all
## Collision is the tiles' own, so it stays independent of the artwork drawn
## over it (metadata/semantic_tile_contract.json).

signal world_metrics_updated(metrics: Dictionary)
@warning_ignore("unused_signal")
signal obstacle_triggered(obstacle_type: String, platform_id: int)
signal route_completed

const TILE_SIZE: float = 32.0
const SEMANTIC_EMPTY: int = 0
const SEMANTIC_SOLID: int = 1
const SEMANTIC_ONE_WAY: int = 2

@export var death_y: float = 900.0

var tile_size: float = TILE_SIZE
var _platforms: Array[Dictionary] = []
var _difficulty: float = 0.0
var _metrics: Dictionary = {}
var _completion_triggered: bool = false
var _semantic_layer: TileMapLayer = null
@onready var _completion_trigger: Area2D = get_node_or_null("CompletionTrigger") as Area2D

func _ready() -> void:
	_semantic_layer = _find_layer(&"Semantic")
	_load_platforms_from_tilemap()
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

## Raw semantic value (0-5, see metadata/semantic_tile_contract.json) of the
## cell at a world position, whether or not it forms a walkable platform.
func get_semantic_value(world_x: float, world_y: float) -> int:
	if _semantic_layer == null:
		return SEMANTIC_EMPTY
	var cell: Vector2i = Vector2i(floori(world_x / tile_size), floori(world_y / tile_size))
	var data: TileData = _semantic_layer.get_cell_tile_data(cell)
	if data == null:
		return SEMANTIC_EMPTY
	return int(data.get_custom_data("semantic"))

func _find_layer(layer_name: StringName) -> TileMapLayer:
	return _find_layer_recursive(self, layer_name)

func _find_layer_recursive(node: Node, layer_name: StringName) -> TileMapLayer:
	for child: Node in node.get_children():
		if child.name == layer_name and child is TileMapLayer:
			return child as TileMapLayer
		var found: TileMapLayer = _find_layer_recursive(child, layer_name)
		if found != null:
			return found
	return null

func _cell_semantic(cell: Vector2i) -> int:
	var data: TileData = _semantic_layer.get_cell_tile_data(cell)
	if data == null:
		return SEMANTIC_EMPTY
	return int(data.get_custom_data("semantic"))

## Walks the "Semantic" layer and turns every exposed horizontal run of
## standable tiles into one platform. A solid cell only counts as a surface
## when nothing standable sits directly above it, so a platform painted as a
## deep block of tiles still reports a single walkable ledge rather than one
## platform per buried row.
func _load_platforms_from_tilemap() -> void:
	_platforms.clear()
	if _semantic_layer == null:
		return

	var rows: Dictionary = {}
	for cell: Vector2i in _semantic_layer.get_used_cells():
		var value: int = _cell_semantic(cell)
		if value != SEMANTIC_SOLID and value != SEMANTIC_ONE_WAY:
			continue
		var above: int = _cell_semantic(Vector2i(cell.x, cell.y - 1))
		if above == SEMANTIC_SOLID or above == SEMANTIC_ONE_WAY:
			continue
		if not rows.has(cell.y):
			rows[cell.y] = [] as Array[Dictionary]
		(rows[cell.y] as Array[Dictionary]).append({"x": cell.x, "value": value})

	var found: Array[Dictionary] = []
	var row_keys: Array = rows.keys()
	row_keys.sort()
	for y: int in row_keys:
		var entries: Array[Dictionary] = rows[y]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x"]) < int(b["x"]))
		var i: int = 0
		while i < entries.size():
			var start_x: int = int(entries[i]["x"])
			var value: int = int(entries[i]["value"])
			var end_x: int = start_x
			var j: int = i + 1
			while j < entries.size() and int(entries[j]["x"]) == end_x + 1 and int(entries[j]["value"]) == value:
				end_x = int(entries[j]["x"])
				j += 1
			found.append({
				"platform_id": 0,
				"start_x": start_x,
				"end_x": end_x,
				"height": y,
				"width": end_x - start_x + 1,
				"challenge_type": "Authored",
				"surface_type": "solid" if value == SEMANTIC_SOLID else "one_way",
				"gap_before": 0,
				"obstacle_x": -1,
				"obstacle_type": "",
				"hazard_x": -1,
				"collectible": false,
			})
			i = j

	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start_x"]) < int(b["start_x"]))
	for index: int in range(found.size()):
		found[index]["platform_id"] = index + 1
	_platforms = found

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
