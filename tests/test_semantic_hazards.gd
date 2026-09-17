extends GutTest

const WORLD_SCENE: PackedScene = preload("res://tests/fixtures/hazard_semantic_world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _instantiate_world() -> RunUnitStaticWorld:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	return world

func test_adjacent_semantic_hazard_cells_merge_into_one_non_solid_lethal_area() -> void:
	var world: RunUnitStaticWorld = _instantiate_world()
	var hazards: Node = world.get_node_or_null("SemanticHazards")
	assert_not_null(hazards, "Semantic value 3 should generate a hazard container")
	if hazards == null:
		return

	assert_eq(hazards.get_child_count(), 1, "Three adjacent hazard cells should merge into one detector")
	if hazards.get_child_count() != 1:
		return
	var hazard: RunUnitHazardArea = hazards.get_child(0) as RunUnitHazardArea
	assert_not_null(hazard, "Generated semantic hazards should use the common hazard behavior")
	if hazard == null:
		return

	assert_eq(hazard.collision_layer, 0, "Semantic hazards must not become solid collision bodies")
	assert_eq(hazard.collision_mask, 1, "Semantic hazards should detect the player collision layer")
	assert_true(hazard.lethal, "Semantic hazard cells are lethal by default")

	var collision: CollisionShape2D = hazard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_not_null(collision)
	if collision == null:
		return
	var rectangle: RectangleShape2D = collision.shape as RectangleShape2D
	assert_not_null(rectangle)
	if rectangle != null:
		assert_eq(rectangle.size, Vector2(96.0, 32.0), "The merged detector should span exactly three 32px cells")

	assert_eq(world.get_current_plan().size(), 1, "Hazard cells must remain outside solid/one-way route extraction")

func test_semantic_hazard_contact_is_lethal_to_player() -> void:
	var world: RunUnitStaticWorld = _instantiate_world()
	var hazards: Node = world.get_node_or_null("SemanticHazards")
	assert_not_null(hazards)
	if hazards == null or hazards.get_child_count() == 0:
		return
	var hazard: Area2D = hazards.get_child(0) as Area2D
	assert_not_null(hazard)
	if hazard == null:
		return

	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = hazard.global_position
	for frame: int in range(3):
		await get_tree().physics_frame

	var health: RunUnitPlayerHealth = player.get_node("Health") as RunUnitPlayerHealth
	assert_eq(health.current_health, 0, "Touching a semantic hazard should immediately deplete player health")
