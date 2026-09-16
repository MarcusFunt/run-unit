extends GutTest

## Regression tests against the shipping level itself
## (scenes/world.tscn -> assets/tiled/levels/maintenance_shaft.tmj), rather
## than the small fixture map in test_tiled_static_world.gd. These catch a
## bad shipping map that still satisfies the generic tile invariants.

const WORLD_SCENE: PackedScene = preload("res://scenes/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const DECK_Y: float = 416.0          # Platform03/04 surface the gate sits over
const GATE_LEFT_X: float = 1888.0    # gate cells are tiles 59-61
const GATE_RIGHT_X: float = 1984.0


func _standing_action(movement: float, crouch: bool) -> RunUnitPlayerAction:
	var action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	action.movement = movement
	action.crouch_held = crouch
	return action


## Drives the player rightwards for a while and reports how far it got.
func _drive_through_gate(crouch: bool) -> float:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(GATE_LEFT_X - 120.0, DECK_Y - 32.0)

	for frame: int in range(150):
		player.set_action(_standing_action(1.0, crouch))
		await get_tree().physics_frame

	return player.global_position.x


func test_shipping_maintenance_shaft_has_the_expected_route() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_true(world.is_route_valid(), "The shipping level must produce a route from its Semantic layer")

	var plan: Array[Dictionary] = world.get_current_plan()
	assert_eq(plan.size(), 5, "Platform03 and Platform04 abut at the same height, so they read as one ledge")

	var first: Dictionary = plan[0]
	assert_eq(int(first.get("start_x", -1)), 0, "The starting deck begins at tile 0")
	assert_eq(int(first.get("end_x", -1)), 22, "The starting deck is 23 tiles wide")
	assert_eq(int(first.get("height", -1)), 14, "The starting deck surface is at tile row 14 (y=448)")

	var last: Dictionary = plan[plan.size() - 1]
	assert_eq(int(last.get("end_x", -1)), 143, "The final deck ends at tile 143 (x=4608)")
	assert_eq(world.get_route_length(), 144.0, "Route length spans to the far edge of the final deck")


func test_shipping_level_publishes_spawn_and_goal_markers() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_eq(world.get_spawn_position(), Vector2(128.0, 385.0), "Spawn comes from the level's Markers layer")
	assert_true(world.has_goal(), "The shipping level declares a Goal marker")
	assert_eq(world.get_goal_position(), Vector2(4544.0, 352.0))

	var trigger: Area2D = world.get_node_or_null("CompletionTrigger") as Area2D
	assert_not_null(trigger, "A completion trigger should be built from the Goal marker")
	assert_eq(trigger.position, world.get_goal_position(), "The trigger sits on the Goal marker")


func test_player_lands_on_the_shipping_starting_deck() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)

	player.global_position = world.get_spawn_position()

	for frame: int in range(60):
		await get_tree().physics_frame

	assert_true(player.is_on_floor(), "Spawning at the level's Spawn marker should land on the starting deck")
	assert_almost_eq(player.global_position.y, 448.0 - 32.0, 6.0, "The player settles on the tiled deck surface")


## The gate tile's collider is shorter than its 32px cell, leaving just enough
## clearance to force a crouch, which is the whole reason the crouch lesson
## survives being put on a 32px grid. These two tests pin that behaviour to
## the real tile rather than a synthetic ceiling.
func test_shipping_crouch_gate_blocks_a_standing_player() -> void:
	var reached_x: float = await _drive_through_gate(false)
	assert_true(reached_x < GATE_LEFT_X, "A standing player must be stopped by the gate, got x=%.1f" % reached_x)


func test_shipping_crouch_gate_lets_a_crouched_player_through() -> void:
	var reached_x: float = await _drive_through_gate(true)
	assert_true(reached_x > GATE_RIGHT_X, "A crouched player must clear the gate, got x=%.1f" % reached_x)
