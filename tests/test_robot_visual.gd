extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")


func test_robot_visual_preserves_rigid_link_lengths() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	var knee: Node2D = visual.get_node("UpperLinkPivot/KneePivot") as Node2D
	var wheel: Node2D = visual.get_node("UpperLinkPivot/KneePivot/WheelPivot") as Node2D

	assert_eq(knee.position, Vector2(110.0, 0.0))
	assert_eq(wheel.position, Vector2(145.0, 0.0))


func test_linkage_pose_keeps_wheel_anchor_fixed() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.apply_pose_for_test(25.0, 105.0, 0.0, 0.0)
	var first_anchor: Vector2 = visual.get_visual_wheel_anchor()

	visual.apply_pose_for_test(15.0, 140.0, 0.0, 0.0)
	var second_anchor: Vector2 = visual.get_visual_wheel_anchor()

	assert_eq(first_anchor, second_anchor)


func test_antenna_uses_svg_defined_base_pivot() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	var pivot: Node2D = visual.get_node("BodyPivot/AntennaPivot") as Node2D
	var antenna: Sprite2D = pivot.get_node("Antenna") as Sprite2D

	assert_eq(pivot.position, Vector2(83.0, -76.0))
	assert_eq(antenna.position, Vector2(-20.0, -70.0))


func test_wheel_radius_comes_from_source_geometry() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	assert_almost_eq(visual.get_wheel_radius_world(), 25.2, 0.001)


func test_wheel_spin_matches_linear_travel() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	player.velocity.x = -252.0
	visual.set_facing_left_for_test(true)
	visual.update_wheel_for_test(0.1)

	assert_almost_eq(absf(visual.get_wheel_spin_for_test()), 1.0, 0.02)


func test_wheel_spin_is_symmetric_between_facing_directions() -> void:
	var left_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var right_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(left_player)
	add_child_autofree(right_player)

	var left_visual: RunUnitRobotVisual = left_player.get_node("RobotVisual") as RunUnitRobotVisual
	var right_visual: RunUnitRobotVisual = right_player.get_node("RobotVisual") as RunUnitRobotVisual

	left_player.velocity.x = -200.0
	left_visual.set_facing_left_for_test(true)
	left_visual.update_wheel_for_test(0.1)

	right_player.velocity.x = 200.0
	right_visual.set_facing_left_for_test(false)
	right_visual.update_wheel_for_test(0.1)

	assert_almost_eq(
		absf(left_visual.get_wheel_spin_for_test()),
		absf(right_visual.get_wheel_spin_for_test()),
		0.0001
	)
