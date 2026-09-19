class_name RunUnitStaticWorld
extends Node2D

## Route geometry comes from the Tiled-authored, YATI-imported level under this
## node (assets/tiled/levels/maintenance_shaft.tmj):
##   "Semantic"  - route floor; owns collision and is scanned for platforms
##   "Obstacles" - collidable obstacle geometry (the crouch gate); never a platform
##   "ArtBackground" / "ArtStructure" / "ArtDeck" - decoration only; no collision
##   "Markers"   - Spawn/Goal points, so start and finish travel with the level
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
const SEMANTIC_HAZARD: int = 3

## Used only when a level ships without a Spawn marker, so a malformed map
## still starts somewhere sane instead of dropping the player at the origin.
const FALLBACK_SPAWN_POSITION: Vector2 = Vector2(128.0, 385.0)
const COMPLETION_TRIGGER_SIZE: Vector2 = Vector2(64.0, 128.0)
## Markers named like this are respawn points rather than route geometry.
const CHECKPOINT_PREFIX: String = "Checkpoint"
## Smallest route-progress change that is worth re-publishing to listeners.
const DIFFICULTY_PUBLISH_STEP: float = 0.005

@export var death_y: float = 900.0

var tile_size: float = TILE_SIZE
var _platforms: Array[Dictionary] = []
var _difficulty: float = 0.0
var _published_difficulty: float = -1.0
var _metrics: Dictionary = {}
var _completion_triggered: bool = false
var _semantic_layer: TileMapLayer = null
var _spawn_marker: Marker2D = null
var _goal_marker: Marker2D = null
var _completion_trigger: Area2D = null
var _checkpoints: Array[Vector2] = []
var _hazards: Array[RunUnitHazardArea] = []

func _ready() -> void:
	_semantic_layer = _find_layer(&"Semantic")
	if _semantic_layer == null:
		push_error("RunUnitStaticWorld: required 'Semantic' TileMapLayer is missing; the route will be empty.")
	_spawn_marker = _find_marker(&"Spawn")
	if _spawn_marker == null:
		push_warning("RunUnitStaticWorld: no 'Spawn' marker in the level; falling back to %s." % FALLBACK_SPAWN_POSITION)
	_goal_marker = _find_marker(&"Goal")
	_collect_checkpoints()
	_load_platforms_from_tilemap()
	_load_semantic_hazards_from_tilemap()
	_collect_hazards()
	_update_metrics()
	_ensure_completion_trigger()

func set_level_profile(_level_index: int) -> void:
	pass

func reset(_run_seed: int = 0, _mode: String = "campaign") -> void:
	_difficulty = 0.0
	_published_difficulty = -1.0
	_completion_triggered = false
	# Level-owned set pieces (e.g. Level 2's module cradle) return to their
	# pre-run state alongside the route itself.
	propagate_call(&"reset_level_state")
	_update_metrics()

## Called every physics frame with the run's furthest distance. Republishing
## the metrics dictionary on each of those frames deep-copied it twice a frame
## for a value nobody samples that finely, so progress is only broadcast once
## it has moved a visible step.
func set_progress(max_distance: float) -> void:
	var traversal_length: float = maxf(get_traversal_length(), 1.0)
	_difficulty = clampf(max_distance / traversal_length, 0.0, 1.0)
	_metrics["difficulty"] = _difficulty
	if absf(_difficulty - _published_difficulty) < DIFFICULTY_PUBLISH_STEP and not is_equal_approx(_difficulty, 1.0):
		return
	_published_difficulty = _difficulty
	world_metrics_updated.emit(_metrics.duplicate(true))

## Every public query takes world-space coordinates and converts them here, so
## a level instanced under a translated parent answers consistently instead of
## only working while the World node happens to sit at the origin.
func get_platform_below(world_x: float) -> Dictionary:
	var tile_x: int = floori(to_local(Vector2(world_x, 0.0)).x / tile_size)
	for platform: Dictionary in _platforms:
		if tile_x >= int(platform.get("start_x", 0)) and tile_x <= int(platform.get("end_x", 0)):
			return platform.duplicate()
	return {}

func get_platform_below_position(world_position: Vector2) -> Dictionary:
	var local_position: Vector2 = to_local(world_position)
	var tile_x: int = floori(local_position.x / tile_size)
	var nearest: Dictionary = {}
	var nearest_vertical_distance: float = INF
	for platform: Dictionary in _platforms:
		if tile_x < int(platform.get("start_x", 0)) or tile_x > int(platform.get("end_x", 0)):
			continue
		var surface_y: float = float(platform.get("height", 0)) * tile_size
		var vertical_distance: float = surface_y - local_position.y
		if vertical_distance < -0.001 or vertical_distance >= nearest_vertical_distance:
			continue
		nearest = platform
		nearest_vertical_distance = vertical_distance
	return nearest.duplicate()

func get_upcoming_platforms(world_x: float, count: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tile_x: int = floori(to_local(Vector2(world_x, 0.0)).x / tile_size)
	for platform: Dictionary in _platforms:
		if int(platform.get("end_x", 0)) >= tile_x:
			result.append(platform.duplicate())
			if result.size() >= count:
				break
	return result

## Returns the closest hazard on the same walkable surface in front of a world
## position. This includes both hand-authored hazards (electric arcs, saws,
## crushers) and semantic hazard tiles materialized at runtime.
func get_nearest_hazard_ahead(world_position: Vector2, max_distance: float = 240.0) -> Dictionary:
	var current_platform: Dictionary = get_platform_below_position(world_position)
	var surface_y: float = INF
	if not current_platform.is_empty():
		surface_y = to_global(Vector2(0.0, float(current_platform.get("height", 0)) * tile_size)).y
	var best: Dictionary = {}
	var best_distance: float = INF
	for hazard: RunUnitHazardArea in _hazards:
		if not is_instance_valid(hazard):
			continue
		var bounds: Rect2 = _hazard_bounds(hazard)
		if bounds.size == Vector2.ZERO:
			continue
		var front_x: float = bounds.position.x
		var back_x: float = bounds.end.x
		if back_x < world_position.x:
			continue
		if surface_y < INF and absf(bounds.end.y - surface_y) > tile_size * 1.25:
			continue
		var distance: float = maxf(front_x - world_position.x, 0.0)
		if distance > max_distance or distance >= best_distance:
			continue
		best_distance = distance
		best = {
			"node": hazard,
			"start_x": front_x,
			"end_x": back_x,
			"width": bounds.size.x,
			"active": hazard.active,
			"lethal": hazard.lethal,
		}
	return best

func _collect_hazards() -> void:
	_hazards.clear()
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is RunUnitHazardArea:
			_hazards.append(node as RunUnitHazardArea)

func _hazard_bounds(hazard: RunUnitHazardArea) -> Rect2:
	var collision: CollisionShape2D = hazard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return Rect2()
	# Timed hazards disable their detector during the safe phase, but their
	# warning plate is still an authored obstacle. Keep its geometry visible to
	# the bot so it never commits to walking across a floor arc that can switch
	# on before UNIT-07 has cleared it.
	var rectangle: RectangleShape2D = collision.shape as RectangleShape2D
	if rectangle == null:
		return Rect2()
	var half: Vector2 = rectangle.size * 0.5
	var corners: Array[Vector2] = [
		collision.to_global(Vector2(-half.x, -half.y)),
		collision.to_global(Vector2(half.x, -half.y)),
		collision.to_global(Vector2(-half.x, half.y)),
		collision.to_global(Vector2(half.x, half.y)),
	]
	var min_point: Vector2 = corners[0]
	var max_point: Vector2 = corners[0]
	for corner: Vector2 in corners:
		min_point.x = minf(min_point.x, corner.x)
		min_point.y = minf(min_point.y, corner.y)
		max_point.x = maxf(max_point.x, corner.x)
		max_point.y = maxf(max_point.y, corner.y)
	return Rect2(min_point, max_point - min_point)

## World-space centre of a platform's walkable surface, for callers that have
## to compare platform geometry against a player's global position.
func get_platform_surface_position(platform: Dictionary) -> Vector2:
	var centre_x: float = (float(platform.get("start_x", 0)) + float(platform.get("width", 0)) * 0.5) * tile_size
	var surface_y: float = float(platform.get("height", 0)) * tile_size
	return to_global(Vector2(centre_x, surface_y))

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

func get_traversal_length() -> float:
	# ScoreManager measures forward X travel from Spawn, so progress must use
	# the same authored interval rather than the map's world-space extent.
	if has_goal():
		return absf(get_goal_position().x - get_spawn_position().x) / tile_size
	# get_route_length() is measured in the level's own tile space, so the
	# spawn has to be converted out of world space before subtracting it.
	return maxf(get_route_length() - to_local(get_spawn_position()).x / tile_size, 0.0)

func is_completion_triggered() -> bool:
	return _completion_triggered

## Where a run starts. Authored as a "Spawn" point in the level's Markers
## layer so a generated map can move it without touching Godot scenes or code.
func get_spawn_position() -> Vector2:
	if _spawn_marker == null:
		return FALLBACK_SPAWN_POSITION
	return _spawn_marker.global_position

## Authored respawn points in route order. Levels short enough to replay from
## the start simply ship none.
func get_checkpoint_positions() -> Array[Vector2]:
	return _checkpoints.duplicate()

func _collect_checkpoints() -> void:
	_checkpoints.clear()
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Marker2D and String(node.name).begins_with(CHECKPOINT_PREFIX):
			_checkpoints.append((node as Marker2D).global_position)
	_checkpoints.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

func has_goal() -> bool:
	return _goal_marker != null

## Where a run finishes; the completion trigger is built around this point.
func get_goal_position() -> Vector2:
	if _goal_marker == null:
		return Vector2.ZERO
	return _goal_marker.global_position

## Builds the finish area from the level's Goal marker, so a level that moves
## its finish does not also need its trigger repositioned by hand. A trigger
## already present in the scene wins, which keeps hand-authored levels working.
func _ensure_completion_trigger() -> void:
	_completion_trigger = get_node_or_null("CompletionTrigger") as Area2D
	if _completion_trigger == null and has_goal():
		var trigger: Area2D = Area2D.new()
		trigger.name = "CompletionTrigger"
		trigger.position = to_local(get_goal_position())
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		var shape: CollisionShape2D = CollisionShape2D.new()
		var rectangle: RectangleShape2D = RectangleShape2D.new()
		rectangle.size = COMPLETION_TRIGGER_SIZE
		shape.shape = rectangle
		trigger.add_child(shape)
		add_child(trigger)
		_completion_trigger = trigger
	if _completion_trigger != null and not _completion_trigger.body_entered.is_connected(_on_completion_trigger_body_entered):
		_completion_trigger.body_entered.connect(_on_completion_trigger_body_entered)

## Raw semantic value (0-5, see metadata/semantic_tile_contract.json) of the
## cell at a world position, whether or not it forms a walkable platform.
func get_semantic_value(world_x: float, world_y: float) -> int:
	if _semantic_layer == null:
		return SEMANTIC_EMPTY
	# Resolved through the layer itself so the lookup honours every transform
	# between it and the viewport, not just this node's.
	var cell: Vector2i = _semantic_layer.local_to_map(_semantic_layer.to_local(Vector2(world_x, world_y)))
	var data: TileData = _semantic_layer.get_cell_tile_data(cell)
	if data == null:
		return SEMANTIC_EMPTY
	return int(data.get_custom_data("semantic"))

func _find_layer(layer_name: StringName) -> TileMapLayer:
	return _find_node_of_type(self, layer_name, "TileMapLayer") as TileMapLayer

func _find_marker(marker_name: StringName) -> Marker2D:
	return _find_node_of_type(self, marker_name, "Marker2D") as Marker2D

func _find_node_of_type(node: Node, wanted_name: StringName, wanted_class: String) -> Node:
	for child: Node in node.get_children():
		if child.name == wanted_name and child.is_class(wanted_class):
			return child
		var found: Node = _find_node_of_type(child, wanted_name, wanted_class)
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

## Semantic value 3 is gameplay-only danger, not route geometry. Materialize
## each horizontal run as one non-solid lethal Area2D while preserving the
## Semantic layer's transform so authored Tiled placement remains authoritative.
func _load_semantic_hazards_from_tilemap() -> void:
	if _semantic_layer == null:
		return

	var existing: Node = get_node_or_null("SemanticHazards")
	if existing != null:
		existing.free()

	var container: Node2D = Node2D.new()
	container.name = "SemanticHazards"
	add_child(container)
	container.global_transform = _semantic_layer.global_transform

	var rows: Dictionary = {}
	for cell: Vector2i in _semantic_layer.get_used_cells():
		if _cell_semantic(cell) != SEMANTIC_HAZARD:
			continue
		if not rows.has(cell.y):
			rows[cell.y] = []
		var x_values: Array = rows[cell.y]
		x_values.append(cell.x)

	var row_keys: Array = rows.keys()
	row_keys.sort()
	for y: int in row_keys:
		var x_values: Array = rows[y]
		x_values.sort()
		if x_values.is_empty():
			continue
		var start_x: int = int(x_values[0])
		var end_x: int = start_x
		for index: int in range(1, x_values.size()):
			var next_x: int = int(x_values[index])
			if next_x == end_x + 1:
				end_x = next_x
				continue
			_create_semantic_hazard_run(container, y, start_x, end_x)
			start_x = next_x
			end_x = next_x
		_create_semantic_hazard_run(container, y, start_x, end_x)

func _create_semantic_hazard_run(container: Node2D, y: int, start_x: int, end_x: int) -> void:
	var hazard: RunUnitHazardArea = RunUnitHazardArea.new()
	hazard.name = "Hazard_%d_%d_%d" % [y, start_x, end_x]
	hazard.lethal = true
	hazard.collision_layer = 0
	hazard.collision_mask = 1

	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	var layer_tile_size: Vector2i = _semantic_layer.tile_set.tile_size
	rectangle.size = Vector2(float((end_x - start_x + 1) * layer_tile_size.x), float(layer_tile_size.y))
	collision.shape = rectangle
	hazard.add_child(collision)

	var first_center: Vector2 = _semantic_layer.map_to_local(Vector2i(start_x, y))
	var last_center: Vector2 = _semantic_layer.map_to_local(Vector2i(end_x, y))
	hazard.position = (first_center + last_center) * 0.5
	container.add_child(hazard)

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
