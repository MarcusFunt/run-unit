extends GutTest

const FACTORY_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const RECOVERY_SCENE: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")
const BEACON_SCENE: PackedScene = preload("res://scenes/levels/level_03_beacon.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _find_story_zone(root: Node, wanted_name: String) -> Area2D:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Area2D and str(node.get_meta("story_zone_name", "")) == wanted_name:
			return node as Area2D
	return null

func _activate_story_zone(world: RunUnitStaticWorld, zone_name: String) -> Node2D:
	var director: Node = world.get_node("StoryZoneDirector")
	var zone: Area2D = _find_story_zone(world, zone_name)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	assert_not_null(zone, "%s is an authored world-state trigger" % zone_name)
	if zone != null:
		director.call("_on_zone_body_entered", player, zone)
	return director.get_node_or_null("WorldStateVisuals/%s" % zone_name) as Node2D

func test_structure_shift_moves_a_visible_beam_in_the_world() -> void:
	var world: RunUnitStaticWorld = FACTORY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var visual: Node2D = world.get_node_or_null("StoryZoneDirector/WorldStateVisuals/Collapse") as Node2D
	assert_not_null(visual, "The collapse warning has an in-world structural set piece")
	if visual == null:
		return
	var beam: Polygon2D = visual.get_node("FallingBeam") as Polygon2D
	var original_y: float = beam.position.y
	var activated: Node2D = _activate_story_zone(world, "Collapse")
	assert_eq(activated, visual)
	await get_tree().create_timer(0.7).timeout
	assert_gt(beam.position.y, original_y + 32.0, "The beam visibly drops when the structure shifts")
	assert_gt(absf(beam.rotation), 0.05, "The fallen beam settles at an angle")

func test_exterior_breach_retracts_the_physical_route_gate() -> void:
	var world: RunUnitStaticWorld = FACTORY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var visual: Node2D = world.get_node_or_null("StoryZoneDirector/WorldStateVisuals/ExteriorBreach") as Node2D
	assert_not_null(visual, "The route opening is visible before its story message")
	if visual == null:
		return
	var left_shutter: Polygon2D = visual.get_node("LeftShutter") as Polygon2D
	var start_x: float = left_shutter.position.x
	_activate_story_zone(world, "ExteriorBreach")
	await get_tree().create_timer(0.6).timeout
	assert_lt(left_shutter.position.x, start_x - 24.0, "The route shutter retracts away from the opening")

func test_beacon_hazard_field_disappears_after_clearance() -> void:
	var world: RunUnitStaticWorld = BEACON_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var visual: Node2D = world.get_node_or_null("StoryZoneDirector/WorldStateVisuals/BeaconInterior") as Node2D
	assert_not_null(visual, "The Beacon entrance shows the active hazard field before clearance")
	if visual == null:
		return
	var field: Line2D = visual.get_node("FieldBeam") as Line2D
	assert_true(field.visible, "The field is visibly active before crossing the threshold")
	_activate_story_zone(world, "BeaconInterior")
	await get_tree().create_timer(0.6).timeout
	assert_lt(field.modulate.a, 0.1, "The field visibly powers down in the world")

func test_registered_checkpoint_keeps_a_strong_physical_light() -> void:
	var world: RunUnitStaticWorld = RECOVERY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var station: RunUnitCheckpointStation = world.get_node("CheckpointStations/Station1") as RunUnitCheckpointStation
	var glow: Polygon2D = station.get_node("MaintenanceStation/WorkGlow") as Polygon2D
	var lamp: Polygon2D = station.get_node("MaintenanceStation/WorkLight") as Polygon2D
	station.reset_level_state()
	var offline_color: Color = lamp.color
	assert_lt(offline_color.r, 0.5, "An offline service station uses a neutral color instead of a danger signal")
	station.restore_active()
	assert_gte(glow.color.a, 0.3, "A restored node remains bright after its HUD confirmation fades")
	assert_true(lamp.color.g > lamp.color.r and lamp.color.b > lamp.color.r, "An active station uses the safe cyan system color")
	assert_gt(lamp.polygon.size(), 4, "The checkpoint has a clear physical status beacon")
