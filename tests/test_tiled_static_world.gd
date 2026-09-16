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


func test_player_falls_through_a_decorative_only_tile_with_no_semantic_collision() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	# x=22..23,y=6 only has an Art-layer tile (no Semantic cell underneath) --
	# it must look identical to Platform C but never stop the player. Centered
	# in the middle of the two-tile decorative strip (x=704..768) so the wider
	# player body clears the real collision edges on both sides.
	var decorative_surface_y: float = 6 * TILE
	player.global_position = Vector2(23 * TILE, decorative_surface_y - 60.0)

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_false(player.is_on_floor(), "Decorative-only art tiles must never create collision")
	assert_true(player.global_position.y > decorative_surface_y + 50.0, "The player should have fallen straight through")


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
