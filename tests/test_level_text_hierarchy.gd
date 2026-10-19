extends GutTest

const CALIBRATION: PackedScene = preload("res://scenes/world.tscn")
const RECOVERY: PackedScene = preload("res://scenes/levels/level_02_recovery.tscn")
const BEACON: PackedScene = preload("res://scenes/levels/level_03_beacon.tscn")
const HUD: PackedScene = preload("res://scenes/hud.tscn")


func test_tutorial_controls_are_present_but_behind_unit() -> void:
	var world: RunUnitStaticWorld = CALIBRATION.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var signs: CanvasItem = world.get_node("TutorialSigns") as CanvasItem
	assert_lt(signs.z_index, 0, "Tutorial tips cannot be foreground billboards")
	for name: String in ["MovementPrompt", "JumpPrompt", "CrouchPrompt"]:
		assert_true((signs.get_node(name) as CanvasItem).visible, "%s remains discoverable" % name)
	assert_false((signs.get_node("ChargePrompt") as CanvasItem).visible)
	assert_false((signs.get_node("FullChargePrompt") as CanvasItem).visible)


func test_recovery_and_beacon_have_no_location_billboards() -> void:
	var recovery: RunUnitStaticWorld = RECOVERY.instantiate() as RunUnitStaticWorld
	add_child_autofree(recovery)
	assert_null(recovery.get_node_or_null("RecoverySigns"), "No opaque depot sign intersects the player lane")
	var cradle: RunUnitModuleCradle = recovery.get_node("ModuleCradle") as RunUnitModuleCradle
	assert_null(cradle.get_node_or_null("ModuleName"))
	assert_null(cradle.get_node_or_null("AcquisitionReadout"))
	var beacon: RunUnitStaticWorld = BEACON.instantiate() as RunUnitStaticWorld
	add_child_autofree(beacon)
	assert_null(beacon.get_node_or_null("BeaconSigns"), "Beacon landmark is conveyed by the scenery")
	var console: CanvasItem = beacon.get_node("IgnitionChamber/CouplerConsole") as CanvasItem
	assert_lt(console.z_index, 0, "Even the final physical signifier draws behind UNIT")


func test_ingame_hud_keeps_progress_and_health_without_extra_text() -> void:
	var hud: RunUnitHud = HUD.instantiate() as RunUnitHud
	add_child_autofree(hud)
	hud.set_campaign_progress(2, 4)
	hud.set_objective("Beacon 9 needs its reserve cell.")
	hud.set_scores(103.0, 120.0)
	assert_eq(hud.distance_label.text, "103m")
	assert_true(hud.score_progress_bar.visible, "Progress is always measurable")
	assert_false(hud.get_node("ObjectiveFrame").visible, "Objective lives in the route briefing")
	assert_false(hud.get_node("ScoreBar/Margin/Rows/Header/JourneyLabel").visible, "No duplicate sector label")
	assert_false(hud.best_label.visible, "Record is not gameplay-critical")
	assert_true(hud.get_node("HealthFrame").visible, "Integrity remains visible")
