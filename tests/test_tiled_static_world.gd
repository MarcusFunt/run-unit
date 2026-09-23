extends GutTest

## Pins the Tiled -> YATI -> TileMapLayer invariants that RunUnitStaticWorld
## relies on, using a small purpose-built fixture level
## (scenes/poc/tiled_level_poc.tmj) rather than the shipping maintenance shaft:
## platforms are derived from the "Semantic" layer, semantic values stay
## queryable independently of collision, one-way tiles are enterable from
## below, and decorative "Art" layer tiles never create collision.

const WORLD_SCENE: PackedScene = preload("res://scenes/poc/tiled_world_poc.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const TILE: float = 32.0


func test_platforms_are_derived_from_the_semantic_tilemap_layer() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_true(world.is_route_valid(), "Four solid/one-way tile runs should produce a valid route")
	assert_eq(world.get_current_plan().size(), 4)

	var platform_a: Dictionary = world.get_platform_below(2 * TILE)
	assert_eq(int(platform_a.get("start_x", -1)), 0)
	assert_eq(int(platform_a.get("end_x", -1)), 5)
	assert_eq(int(platform_a.get("height", -1)), 7)
	assert_eq(str(platform_a.get("surface_type", "")), "solid")

	var platform_b: Dictionary = world.get_platform_below(9 * TILE)
	assert_eq(int(platform_b.get("start_x", -1)), 8)
	assert_eq(int(platform_b.get("end_x", -1)), 11)
	assert_eq(int(platform_b.get("height", -1)), 6)

	var one_way: Dictionary = world.get_platform_below(14 * TILE)
	assert_eq(int(one_way.get("start_x", -1)), 13)
	assert_eq(int(one_way.get("end_x", -1)), 15)
	assert_eq(int(one_way.get("height", -1)), 5)
	assert_eq(str(one_way.get("surface_type", "")), "one_way")

	var platform_c: Dictionary = world.get_platform_below(19 * TILE)
	assert_eq(int(platform_c.get("start_x", -1)), 17)
	assert_eq(int(platform_c.get("end_x", -1)), 21)

	assert_true(world.get_platform_below(6 * TILE).is_empty(), "The authored gap should report no platform")
	assert_eq(world.get_upcoming_platforms(0.0, 10).size(), 4)
	assert_eq(world.get_route_length(), 22.0, "Route length should reach the far edge of the last platform (x=21)")


func test_position_aware_platform_query_prefers_nearest_surface_below_player() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var overlapping_platforms: Array[Dictionary] = [
		{"platform_id": 1, "start_x": 0, "end_x": 10, "height": 5},
		{"platform_id": 2, "start_x": 0, "end_x": 10, "height": 10},
	]
	world.set("_platforms", overlapping_platforms)

	var above_both: Dictionary = world.get_platform_below_position(Vector2(5 * TILE, 100.0))
	assert_eq(int(above_both.get("platform_id", -1)), 1, "Nearest lower surface should win when platforms overlap in X")
	var between_surfaces: Dictionary = world.get_platform_below_position(Vector2(5 * TILE, 200.0))
	assert_eq(int(between_surfaces.get("platform_id", -1)), 2, "A platform already above the player must not be reported as below")


func test_position_aware_platform_query_handles_world_transform() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	world.position = Vector2(320.0, 96.0)
	add_child_autofree(world)
	var platforms: Array[Dictionary] = [
		{"platform_id": 7, "start_x": 0, "end_x": 10, "height": 5},
	]
	world.set("_platforms", platforms)
	var query_position: Vector2 = world.to_global(Vector2(5 * TILE, 100.0))

	var platform: Dictionary = world.get_platform_below_position(query_position)

	assert_eq(int(platform.get("platform_id", -1)), 7, "World-space queries should respect the StaticWorld transform")


func test_semantic_values_are_queryable_independent_of_collision() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_eq(world.get_semantic_value(2 * TILE + 16, 3 * TILE + 16), 4, "conveyor sample cell")
	assert_eq(world.get_semantic_value(3 * TILE + 16, 3 * TILE + 16), 5, "foreground sample cell")
	assert_eq(world.get_semantic_value(14 * TILE + 16, 8 * TILE + 16), 3, "hazard strip beneath the one-way platform")
	assert_eq(world.get_semantic_value(6 * TILE + 16, 7 * TILE + 16), 0, "the authored gap has no semantic tile")


func test_player_lands_on_a_solid_platform_derived_from_tiles() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	var surface_y: float = 7 * TILE  # Platform A's top edge
	player.global_position = Vector2(2 * TILE + 16, surface_y - 60.0)

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "The player should land on collision generated from the Semantic TileMapLayer")
	assert_almost_eq(player.global_position.y, surface_y - 32.0, 6.0, "Player should settle on top of the tile surface")


func test_gap_is_open_and_approximately_the_width_of_the_player() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	var art_layer: TileMapLayer = world.find_child("Art", true, false) as TileMapLayer
	assert_not_null(art_layer, "The fixture should keep its decorative layer")
	assert_eq(art_layer.get_cell_source_id(Vector2i(22, 6)), -1, "The unsupported art tile should be removed")
	assert_eq(art_layer.get_cell_source_id(Vector2i(23, 6)), -1, "The unsupported art tile should be removed")

	var player_shape: RectangleShape2D = player.get_node("CollisionShape2D").shape as RectangleShape2D
	var gap_width: float = (24.0 - 22.0) * TILE
	assert_almost_eq(gap_width, player_shape.size.x, TILE * 0.5, "The open gap should be about one robot wide")

	var gap_surface_y: float = 6 * TILE
	player.global_position = Vector2(23 * TILE, gap_surface_y - 60.0)
	for frame: int in range(60):
		await get_tree().physics_frame

	assert_false(player.is_on_floor(), "The open gap must not stop the player")
	assert_true(player.global_position.y > gap_surface_y + 50.0, "The player should fall through the open gap")

func test_one_way_platform_can_be_entered_from_below() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	var one_way_surface_y: float = 5 * TILE
	player.global_position = Vector2(14 * TILE + 16, one_way_surface_y + 40.0)
	player.velocity = Vector2(0.0, -420.0)

	for frame: int in range(20):
		await get_tree().physics_frame

	assert_true(player.global_position.y < one_way_surface_y, "Rising from below, the player should pass through the one-way tile instead of being blocked by it")


func test_holding_jump_drops_through_same_height_one_way_platform() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	var surface_y: float = 5 * TILE
	player.global_position = Vector2(14 * TILE + 16, surface_y - 32.0)
	for frame: int in range(3):
		await get_tree().physics_frame
	assert_true(player.is_on_floor(), "The player should start on the one-way platform")

	var held_jump: RunUnitPlayerAction = RunUnitPlayerAction.new()
	held_jump.jump_held = true
	player.set_action(held_jump)
	for frame: int in range(30):
		await get_tree().physics_frame

	var release_jump: RunUnitPlayerAction = RunUnitPlayerAction.new()
	release_jump.jump_released = true
	player.set_action(release_jump)
	await get_tree().physics_frame

	player.set_action(held_jump)
	for frame: int in range(100):
		await get_tree().physics_frame

	assert_true(player.global_position.y > surface_y + 50.0, "Holding jump on descent should let the player pass through the takeoff platform")
	assert_false(player.is_on_floor(), "The player should not land on the one-way platform they jumped from")
