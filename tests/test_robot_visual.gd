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
