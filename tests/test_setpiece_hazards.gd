extends GutTest

const SAW_SCENE: PackedScene = preload("res://scenes/hazards/saw.tscn")
const LASER_SCENE: PackedScene = preload("res://scenes/hazards/laser_gate.tscn")
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
	assert_false(warning.visible, "Warning lamps hand over to the cyan beam")
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
