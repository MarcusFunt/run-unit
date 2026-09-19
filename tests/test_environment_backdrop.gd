extends GutTest

const ROUTES: Array[Dictionary] = [
	{"scene": preload("res://scenes/world.tscn"), "theme": "tutorial"},
	{"scene": preload("res://scenes/levels/level_01_factory.tscn"), "theme": "factory"},
	{"scene": preload("res://scenes/levels/level_02_recovery.tscn"), "theme": "recovery"},
	{"scene": preload("res://scenes/levels/level_03_beacon.tscn"), "theme": "beacon"},
]

func test_every_campaign_route_has_non_colliding_environment_depth() -> void:
	for route: Dictionary in ROUTES:
		var world: RunUnitStaticWorld = (route["scene"] as PackedScene).instantiate() as RunUnitStaticWorld
		add_child_autofree(world)
		var backdrop: RunUnitEnvironmentBackdrop = world.get_node_or_null("EnvironmentDepth") as RunUnitEnvironmentBackdrop
		assert_not_null(backdrop, "%s route should ship its background depth pass" % route["theme"])
		if backdrop == null:
			continue
		assert_eq(backdrop.theme, route["theme"], "Route should select the intended visual theme")
		assert_lt(backdrop.z_index, 0, "Environmental storytelling must remain behind gameplay")

func test_background_landmarks_do_not_add_gameplay_collision() -> void:
	var backdrop := RunUnitEnvironmentBackdrop.new()
	add_child_autofree(backdrop)
	assert_eq(backdrop.get_child_count(), 0, "Procedural backdrop should draw pixels only, not spawn gameplay nodes")
	assert_null(backdrop.get_node_or_null("CollisionShape2D"), "Background landmarks must never add collision")
