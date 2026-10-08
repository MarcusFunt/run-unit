extends GutTest

const SAW_SCENE: PackedScene = preload("res://scenes/hazards/saw.tscn")
const LASER_SCENE: PackedScene = preload("res://scenes/hazards/laser_gate.tscn")
const FLOOR_ARC_SCENE: PackedScene = preload("res://scenes/hazards/electric_floor_arc.tscn")
const CRUSHER_SCENE: PackedScene = preload("res://scenes/hazards/crusher.tscn")
const FACTORY_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const RECOVERY_SCENE: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")
const BEACON_SCENE: PackedScene = preload("res://scenes/levels/level_03_beacon.tscn")

func test_saw_is_spinning_lethal_and_visible_to_world_queries() -> void:
	var saw: RunUnitSawHazard = SAW_SCENE.instantiate() as RunUnitSawHazard
	add_child_autofree(saw)
	assert_not_null(saw)
	assert_true(saw.lethal)
	var blade: Node2D = saw.get_node("ActiveVisual") as Node2D
	var before: float = blade.rotation
	saw._physics_process(0.1)
	assert_gt(blade.rotation, before, "Saw artwork should visibly rotate")

	var world: RunUnitStaticWorld = FACTORY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var hazard: Dictionary = world.get_nearest_hazard_ahead(Vector2(1640.0, 352.0), 240.0)
	assert_false(hazard.is_empty(), "The bot must perceive circular saw collision")
	assert_eq(String((hazard.get("node") as Node).name), "AssemblySaw")
func test_laser_gate_has_safe_warning_and_active_beam_phases() -> void:
	var laser: RunUnitLaserGateHazard = LASER_SCENE.instantiate() as RunUnitLaserGateHazard
	add_child_autofree(laser)
	assert_not_null(laser)
	assert_not_null(laser.get_node_or_null("WarningVisual"))
	assert_not_null(laser.get_node_or_null("ActiveVisual"))

	laser.cycle_seconds = 3.0
	laser.active_seconds = 1.0
	laser.warning_seconds = 0.4
	laser.phase_offset_seconds = 2.8
	laser.reset_level_state()
	var warning: CanvasItem = laser.get_node("WarningVisual") as CanvasItem
	assert_false(laser.active, "Amber warning phase should remain safe")
	assert_true(warning.visible, "Gate should telegraph immediately before energizing")

	laser.phase_offset_seconds = 0.2
	laser.reset_level_state()
	assert_true(laser.active, "Beam phase should be damaging")
	assert_false(warning.visible, "Warning lamps hand over to the energized beam")
	var beam_core: Polygon2D = laser.get_node("ActiveVisual/BeamCore") as Polygon2D
	assert_gt(beam_core.color.r, beam_core.color.b, "A damaging beam uses the danger palette instead of safe-platform cyan")
	assert_gt(beam_core.color.r, beam_core.color.g, "The energized beam reads as hot danger before contact")
func test_later_routes_gain_distinct_hazard_setpieces() -> void:
	var factory: RunUnitStaticWorld = FACTORY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(factory)
	assert_not_null(factory.get_node_or_null("RotaryHazards/AssemblySaw"))

	var recovery: RunUnitStaticWorld = RECOVERY_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(recovery)
	assert_not_null(recovery.get_node_or_null("RotaryHazards/DepotSaw"))
	assert_not_null(recovery.get_node_or_null("TimingHazards/VaultLaser"))

	var beacon: RunUnitStaticWorld = BEACON_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(beacon)
	assert_not_null(beacon.get_node_or_null("RotaryHazards/RooftopSaw"))
	assert_not_null(beacon.get_node_or_null("TimingHazards/BeaconLaser"))
	var ascent_saw: RunUnitSawHazard = beacon.get_node_or_null("RotaryHazards/AscentSaw") as RunUnitSawHazard
	assert_not_null(ascent_saw, "The final ascent combines a taught saw with the existing timed hazards")
	if ascent_saw != null:
		assert_true(ascent_saw.lethal)
		assert_eq(ascent_saw.position, Vector2(14600.0, 156.0))
	var ascent_press: RunUnitCrusherHazard = beacon.get_node_or_null("MechanicalHazards/AscentPress") as RunUnitCrusherHazard
	assert_not_null(ascent_press)
	if ascent_press != null:
		assert_gte(ascent_press.cycle_seconds, 4.0, "The final press uses a slower, more deliberate rhythm")
		assert_gte(ascent_press.warning_seconds, 0.9, "The last climb leaves time to read the press warning")
	assert_eq(beacon.death_y, 900.0, "The fall warning band sits just above the void recovery boundary")

func test_floor_arc_and_crusher_share_a_bold_danger_band() -> void:
	var floor_arc: RunUnitTimedHazard = FLOOR_ARC_SCENE.instantiate() as RunUnitTimedHazard
	add_child_autofree(floor_arc)
	var plate: Polygon2D = floor_arc.get_node_or_null("WarningPlate") as Polygon2D
	assert_not_null(plate, "The floor arc keeps a persistent warning plate while inactive")
	assert_not_null(floor_arc.get_node_or_null("DangerBand"), "Floor arcs use the shared high-contrast hazard marking")
	if plate != null:
		assert_gt(plate.polygon.size(), 4, "The plate silhouette reads as a hazard rather than thin trim")

	var crusher: RunUnitTimedHazard = CRUSHER_SCENE.instantiate() as RunUnitTimedHazard
	add_child_autofree(crusher)
	assert_not_null(crusher.get_node_or_null("PistonAssembly/DangerBand"), "The crusher face carries a broad hazard marking")
	assert_not_null(crusher.get_node_or_null("WarningVisual/Lamp"), "The crusher keeps a visible amber approach warning")
	assert_not_null(crusher.get_node_or_null("RestLimit"), "A fixed mark shows where the ram waits")
	assert_not_null(crusher.get_node_or_null("StrikeLimit"), "A fixed mark shows the bottom of its sweep")
	assert_not_null(crusher.get_node_or_null("SweptChannel"), "The full danger travel path remains visible before movement")
	var channel: Polygon2D = crusher.get_node("SweptChannel") as Polygon2D
	var top: float = 0.0
	var bottom: float = 0.0
	for point: Vector2 in channel.polygon:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	assert_lte(top, -118.0, "The channel reaches the ram's raised position")
	assert_gte(bottom, 44.0, "The channel reaches the strike surface")
	var marks: Node2D = crusher.get_node_or_null("TravelWarningMarks") as Node2D
	assert_not_null(marks, "The marked channel gives a visible swept boundary")
	if marks != null:
		assert_eq(marks.get_child_count(), 12)

func test_final_coupler_prompt_and_carried_cell_have_enough_presence() -> void:
	var beacon: RunUnitStaticWorld = BEACON_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(beacon)
	var ignition: RunUnitBeaconIgnition = beacon.get_node("IgnitionChamber") as RunUnitBeaconIgnition
	var prompt: Label = ignition.get_node("CouplerConsole/Prompt") as Label
	assert_gte(prompt.get_theme_font_size("font_size"), 17, "The physical coupler explains the pressure interaction at play size")
	assert_gte(RunUnitModuleMount.MOUNT_SCALE, 5.0, "The recovered cell stays visible on UNIT-07 throughout the journey")
