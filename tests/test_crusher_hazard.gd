extends GutTest

const CRUSHER_SCENE: PackedScene = preload("res://scenes/hazards/crusher.tscn")
const FACTORY_SCENE: PackedScene = preload("res://scenes/levels/level_01_factory.tscn")
const RECOVERY_SCENE: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")
const BEACON_SCENE: PackedScene = preload("res://scenes/levels/level_03_beacon.tscn")

func test_crusher_telegraphs_then_strikes() -> void:
	var crusher: RunUnitCrusherHazard = CRUSHER_SCENE.instantiate() as RunUnitCrusherHazard
	add_child_autofree(crusher)
	assert_not_null(crusher)
	assert_true(crusher.lethal)
	assert_not_null(crusher.get_node_or_null("PistonAssembly"))
	assert_not_null(crusher.get_node_or_null("WarningVisual"))

	crusher.cycle_seconds = 3.0
	crusher.active_seconds = 0.6
	crusher.warning_seconds = 0.5
	crusher.phase_offset_seconds = 2.75
	crusher.reset_level_state()
	var warning: CanvasItem = crusher.get_node("WarningVisual") as CanvasItem
	assert_true(warning.visible, "The orange lamp should telegraph the next strike")
	assert_false(crusher.active, "The warning phase itself must still be safe")

func test_campaign_routes_use_crushers_as_sparse_setpieces() -> void:
	var scenes: Array[PackedScene] = [FACTORY_SCENE, RECOVERY_SCENE, BEACON_SCENE]
	var names: Array[String] = ["TransferPress", "DepotPress", "ServicePress"]
	for index: int in range(scenes.size()):
		var world: RunUnitStaticWorld = scenes[index].instantiate() as RunUnitStaticWorld
		add_child_autofree(world)
		var container: Node = world.get_node_or_null("MechanicalHazards")
		assert_not_null(container, "Each post-tutorial route should have a mechanical setpiece")
		if container == null:
			continue
		assert_eq(container.get_child_count(), 1, "Crushers stay memorable by remaining sparse")
		var crusher: RunUnitCrusherHazard = container.get_child(0) as RunUnitCrusherHazard
		assert_not_null(crusher)
		if crusher != null:
			assert_eq(String(crusher.name), names[index])
