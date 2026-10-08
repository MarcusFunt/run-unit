extends GutTest

const ROUTES: Array[Dictionary] = [
	{"scene": preload("res://scenes/world.tscn"), "theme": "tutorial"},
	{"scene": preload("res://scenes/levels/level_01_factory.tscn"), "theme": "factory"},
	{"scene": preload("res://scenes/levels/level_02_recovery.tscn"), "theme": "recovery"},
	{"scene": preload("res://scenes/levels/level_03_beacon.tscn"), "theme": "beacon"},
]
const TILED_MAP_PATHS: Array[String] = [
	"res://assets/tiled/levels/maintenance_shaft.tmj",
	"res://assets/tiled/levels/level_01_factory.tmj",
	"res://assets/tiled/levels/level_02_recovery.tmj",
	"res://assets/tiled/levels/level_03_beacon.tmj",
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

func test_tiled_depth_layers_stay_visibly_quieter_than_walkable_art() -> void:
	for map_path: String in TILED_MAP_PATHS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_path))
		assert_true(parsed is Dictionary, "%s should remain readable Tiled JSON" % map_path)
		if not parsed is Dictionary:
			continue
		var map_data: Dictionary = parsed as Dictionary
		for layer_variant: Variant in map_data.get("layers", []):
			if not layer_variant is Dictionary:
				continue
			var layer: Dictionary = layer_variant as Dictionary
			var layer_name: String = str(layer.get("name", ""))
			var opacity: float = float(layer.get("opacity", 1.0))
			if layer_name == "ArtBackground":
				assert_lte(opacity, 0.4, "%s background texture should stay subdued" % map_path)
			elif layer_name == "ArtStructure":
				assert_lte(opacity, 0.65, "%s architecture should read behind the route" % map_path)
			elif layer_name == "ArtForeground":
				assert_lte(opacity, 0.72, "%s foreground decoration should not compete with platforms" % map_path)
