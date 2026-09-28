extends GutTest

const PORTAL_SCENE: PackedScene = preload("res://scenes/props/dimensional_portal_exit.tscn")
const GAME_SCENE: String = "res://scenes/game.tscn"
const INTER_LEVEL_ROUTES: Array[Dictionary] = [
	{"scene": "res://scenes/world.tscn", "goal": Vector2(2032, 352)},
	{"scene": "res://scenes/levels/level_01_factory.tscn", "goal": Vector2(8544, 576)},
	{"scene": "res://scenes/levels/level_02_recovery.tscn", "goal": Vector2(12512, 448)},
]

func test_portal_uses_the_uploaded_six_frame_sprite_sheet() -> void:
	var exit: RunUnitDimensionalPortalExit = PORTAL_SCENE.instantiate() as RunUnitDimensionalPortalExit
	add_child_autofree(exit)
	var sprite: Sprite2D = exit.get_node("Portal") as Sprite2D
	assert_not_null(sprite)
	if sprite == null:
		return
	assert_eq(sprite.hframes, 3)
	assert_eq(sprite.vframes, 2)
	assert_not_null(sprite.texture)
	if sprite.texture != null:
		assert_eq(sprite.texture.get_size(), Vector2(96, 64))

func test_every_intermediate_route_hands_off_through_the_portal() -> void:
	for route: Dictionary in INTER_LEVEL_ROUTES:
		var packed: PackedScene = load(str(route["scene"])) as PackedScene
		assert_not_null(packed)
		if packed == null:
			continue
		var world: Node = packed.instantiate()
		add_child_autofree(world)
		var exit: RunUnitDimensionalPortalExit = world.get_node_or_null("DimensionalPortalExit") as RunUnitDimensionalPortalExit
		assert_not_null(exit, "%s should end at the dimensional portal" % route["scene"])
		if exit == null:
			continue
		assert_eq(exit.position, route["goal"], "Portal should sit on the authored Goal marker")
		assert_eq(exit.next_scene_path, GAME_SCENE, "Intermediate portals should load the next campaign route")

func test_beacon_9_keeps_its_authored_finale() -> void:
	var packed: PackedScene = load("res://scenes/levels/level_03_beacon.tscn") as PackedScene
	var world: Node = packed.instantiate()
	add_child_autofree(world)
	assert_null(world.get_node_or_null("DimensionalPortalExit"))
	assert_true(world.get_node("IgnitionChamber") is RunUnitBeaconIgnition)
