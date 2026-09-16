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


func test_visual_time_advances_only_by_supplied_delta() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.advance_visual_time_for_test(0.25)
	visual.advance_visual_time_for_test(0.50)

	assert_almost_eq(visual.get_visual_time_for_test(), 0.75, 0.0001)


func test_idle_suspension_moves_body_without_moving_wheel_anchor() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	_ground_player(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(player.is_on_floor())

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	player.velocity.x = 0.0

	visual.run_process_for_test(0.05)
	var mount_a: Vector2 = visual.get_body_mount_position_for_test()
	var wheel_a: Vector2 = visual.get_wheel_local_position_for_test()

	for frame: int in range(20):
		visual.run_process_for_test(0.05)

	var mount_b: Vector2 = visual.get_body_mount_position_for_test()
	var wheel_b: Vector2 = visual.get_wheel_local_position_for_test()

	assert_gt(mount_a.distance_to(mount_b), 0.5, "Idle suspension should be visibly alive")
	assert_almost_eq(wheel_a.distance_to(wheel_b), 0.0, 0.1, "The cosmetic wheel must not skate while idling")


func test_idle_and_drive_motion_are_suppressed_while_airborne() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	assert_false(player.is_on_floor())

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	assert_false(visual.is_idle_eligible_for_test())
	assert_false(visual.is_drive_eligible_for_test())


func test_idle_and_drive_motion_are_suppressed_while_charging() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	_ground_player(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var charge_action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	charge_action.jump_held = true
	player.set_action(charge_action)
	await get_tree().physics_frame
	assert_true(player.is_charging())

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	assert_false(visual.is_idle_eligible_for_test())
	assert_false(visual.is_drive_eligible_for_test())


func test_idle_and_drive_motion_are_suppressed_while_crouching() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	_ground_player(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var crouch_action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	crouch_action.crouch_held = true
	player.set_action(crouch_action)
	for frame: int in range(6):
		await get_tree().physics_frame
	assert_true(player.is_crouching())

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	assert_false(visual.is_idle_eligible_for_test())
	assert_false(visual.is_drive_eligible_for_test())


func test_travel_phase_does_not_advance_at_zero_speed() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	player.velocity.x = 0.0
	visual.update_travel_phase_for_test(0.5)

	assert_almost_eq(visual.get_travel_phase_for_test(), 0.0, 0.0001)


func test_travel_phase_advances_faster_at_higher_speed() -> void:
	var slow_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var fast_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(slow_player)
	add_child_autofree(fast_player)
	var slow_visual: RunUnitRobotVisual = slow_player.get_node("RobotVisual") as RunUnitRobotVisual
	var fast_visual: RunUnitRobotVisual = fast_player.get_node("RobotVisual") as RunUnitRobotVisual

	slow_player.velocity.x = -80.0
	fast_player.velocity.x = -260.0

	slow_visual.update_travel_phase_for_test(0.1)
	fast_visual.update_travel_phase_for_test(0.1)

	assert_gt(fast_visual.get_travel_phase_for_test(), slow_visual.get_travel_phase_for_test())


func test_body_lean_ramps_smoothly_toward_target_speed_lean() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	_ground_player(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual
	player.velocity.x = -400.0

	visual.run_process_for_test(0.016)
	var body: Node2D = visual.get_node("BodyPivot") as Node2D
	var first_lean: float = absf(body.rotation)

	for frame: int in range(40):
		visual.run_process_for_test(0.016)
	var settled_lean: float = absf(body.rotation)

	assert_lt(first_lean, settled_lean, "Body lean should ramp in gradually rather than snapping to the target")
	assert_almost_eq(settled_lean, deg_to_rad(5.5), 0.05)


func test_antenna_deflects_backward_under_forward_acceleration() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.set_facing_left_for_test(true)
	visual.set_previous_velocity_for_test(0.0)
	player.velocity.x = -400.0

	visual.update_antenna_motion_for_test(0.05)

	assert_gt(visual.antenna_pivot.rotation, 0.0)


func test_antenna_deflects_forward_under_braking() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.set_facing_left_for_test(true)
	visual.set_previous_velocity_for_test(-400.0)
	player.velocity.x = -50.0

	visual.update_antenna_motion_for_test(0.05)

	assert_lt(visual.antenna_pivot.rotation, 0.0)


func test_antenna_returns_toward_rest_with_zero_acceleration() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.set_facing_left_for_test(true)
	visual.set_previous_velocity_for_test(0.0)
	player.velocity.x = -400.0
	visual.update_antenna_motion_for_test(0.05)
	assert_gt(absf(visual.antenna_pivot.rotation), 0.0)

	for frame: int in range(60):
		visual.update_antenna_motion_for_test(0.016)

	assert_almost_eq(visual.antenna_pivot.rotation, 0.0, 0.02)


func test_jump_impulse_kicks_antenna_backward() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.apply_jump_impulse_for_test()
	visual.update_antenna_motion_for_test(0.016)

	assert_lt(visual.antenna_pivot.rotation, 0.0)


func test_landing_impulse_scales_with_landing_speed() -> void:
	var soft_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var hard_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(soft_player)
	add_child_autofree(hard_player)
	var soft_visual: RunUnitRobotVisual = soft_player.get_node("RobotVisual") as RunUnitRobotVisual
	var hard_visual: RunUnitRobotVisual = hard_player.get_node("RobotVisual") as RunUnitRobotVisual

	soft_player.last_landing_speed = soft_player.max_fall_speed * 0.1
	hard_player.last_landing_speed = hard_player.max_fall_speed * 0.9

	soft_visual.apply_landing_impulse_for_test()
	hard_visual.apply_landing_impulse_for_test()

	soft_visual.update_antenna_motion_for_test(0.032)
	hard_visual.update_antenna_motion_for_test(0.032)

	assert_gt(absf(hard_visual.antenna_pivot.rotation), absf(soft_visual.antenna_pivot.rotation))


func test_antenna_never_exceeds_configured_limit() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.set_facing_left_for_test(true)
	visual.set_previous_velocity_for_test(0.0)
	player.velocity.x = -5000.0

	var limit: float = deg_to_rad(visual.antenna_max_lag_deg) + 0.001
	for frame: int in range(20):
		visual.update_antenna_motion_for_test(0.016)
		assert_lte(absf(visual.antenna_pivot.rotation), limit)


func test_eye_pulse_is_deterministic_function_of_visual_time() -> void:
	var player_a: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var player_b: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player_a)
	add_child_autofree(player_b)
	var visual_a: RunUnitRobotVisual = player_a.get_node("RobotVisual") as RunUnitRobotVisual
	var visual_b: RunUnitRobotVisual = player_b.get_node("RobotVisual") as RunUnitRobotVisual

	for frame: int in range(15):
		visual_a.run_process_for_test(0.03)
	for frame: int in range(30):
		visual_b.run_process_for_test(0.015)

	assert_almost_eq(visual_a.eye.modulate.a, visual_b.eye.modulate.a, 0.001)


func test_eye_pulse_gains_a_charge_boost() -> void:
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(player)
	var visual: RunUnitRobotVisual = player.get_node("RobotVisual") as RunUnitRobotVisual

	visual.run_process_for_test(0.35)
	var base_alpha: float = visual.eye.modulate.a

	player._is_charging = true
	player.charge_ratio = 0.6
	visual.run_process_for_test(0.0)

	assert_gt(visual.eye.modulate.a, base_alpha)


func test_mirrored_facing_produces_mechanically_equivalent_motion() -> void:
	var left_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var right_player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	_ground_player(left_player, 0.0)
	_ground_player(right_player, 1000.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var left_visual: RunUnitRobotVisual = left_player.get_node("RobotVisual") as RunUnitRobotVisual
	var right_visual: RunUnitRobotVisual = right_player.get_node("RobotVisual") as RunUnitRobotVisual

	left_player.velocity.x = -200.0
	right_player.velocity.x = 200.0

	for frame: int in range(30):
		left_visual.run_process_for_test(0.016)
		right_visual.run_process_for_test(0.016)

	var left_upper: Node2D = left_visual.get_node("UpperLinkPivot") as Node2D
	var right_upper: Node2D = right_visual.get_node("UpperLinkPivot") as Node2D
	assert_almost_eq(left_upper.rotation, right_upper.rotation, 0.001, "Suspension pose is authored facing-agnostic")

	var left_body: Node2D = left_visual.get_node("BodyPivot") as Node2D
	var right_body: Node2D = right_visual.get_node("BodyPivot") as Node2D
	assert_almost_eq(absf(left_body.rotation), absf(right_body.rotation), 0.001, "Body lean magnitude must match")

	assert_almost_eq(
		absf(left_visual.antenna_pivot.rotation),
		absf(right_visual.antenna_pivot.rotation),
		0.01,
		"Antenna lag magnitude must match"
	)

	assert_eq(left_visual.scale.x, 1.0)
	assert_eq(right_visual.scale.x, -1.0)


func _create_static_body(body_position: Vector2, body_size: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = body_position
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = body_size
	collision_shape.shape = rectangle
	body.add_child(collision_shape)
	return body


func _ground_player(player: RunUnitPlayerMotor, x_offset: float = 0.0) -> StaticBody2D:
	var ground: StaticBody2D = _create_static_body(Vector2(200.0 + x_offset, 432.0), Vector2(500.0, 32.0))
	add_child_autofree(ground)
	add_child_autofree(player)
	player.global_position = Vector2(200.0 + x_offset, 401.0)
	return ground
