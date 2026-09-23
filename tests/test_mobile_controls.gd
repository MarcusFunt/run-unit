extends GutTest

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const CONTROLS_SCENE: PackedScene = preload("res://scenes/mobile_controls.tscn")


func test_game_has_multitouch_controls_for_every_movement_action() -> void:
	var game: Node = autofree(GAME_SCENE.instantiate()) as Node
	var controls: CanvasLayer = game.get_node_or_null("MobileControls") as CanvasLayer
	assert_not_null(controls, "Every route needs the same touch controls")
	if controls == null:
		return
	var expected: Dictionary = {
		"Left": &"move_left", "Right": &"move_right",
		"Jump": &"jump", "Crouch": &"crouch",
	}
	for button_name: String in expected:
		var button: TouchScreenButton = controls.get_node_or_null("Area/" + button_name) as TouchScreenButton
		assert_not_null(button, button_name + " needs a separate multitouch target")
		if button != null:
			assert_eq(button.action, expected[button_name])
			assert_eq(button.visibility_mode, TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY)
	var pause: TouchScreenButton = controls.get_node_or_null("Area/Pause") as TouchScreenButton
	assert_not_null(pause, "A phone needs a way to open the pause menu")


func test_touch_targets_stay_inside_a_landscape_viewport() -> void:
	var controls: CanvasLayer = CONTROLS_SCENE.instantiate() as CanvasLayer
	add_child_autofree(controls)
	for viewport_size: Vector2 in [Vector2(960, 540), Vector2(640, 360)]:
		controls.layout_for_viewport(viewport_size)
		var left: TouchScreenButton = controls.get_node("Area/Left") as TouchScreenButton
		var right: TouchScreenButton = controls.get_node("Area/Right") as TouchScreenButton
		var crouch: TouchScreenButton = controls.get_node("Area/Crouch") as TouchScreenButton
		var jump: TouchScreenButton = controls.get_node("Area/Jump") as TouchScreenButton
		var width: float = 88.0 * left.scale.x
		assert_gt(left.position.x, 0.0)
		assert_gt(right.position.x - (left.position.x + width), 8.0)
		assert_gt(crouch.position.x - (right.position.x + width), 8.0)
		assert_gt(jump.position.x - (crouch.position.x + width), 8.0)
		assert_lt(jump.position.x + width, viewport_size.x)
		assert_lt(jump.position.y + width, viewport_size.y)
		assert_gt(jump.position.y, viewport_size.y * 0.65)


func test_movement_and_jump_can_be_held_by_two_fingers() -> void:
	var controls: CanvasLayer = CONTROLS_SCENE.instantiate() as CanvasLayer
	add_child_autofree(controls)
	var left: TouchScreenButton = controls.get_node("Area/Left") as TouchScreenButton
	var jump: TouchScreenButton = controls.get_node("Area/Jump") as TouchScreenButton
	left.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	jump.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var left_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	left_touch.index = 0
	left_touch.position = left.global_position + Vector2.ONE * (44.0 * left.scale.x)
	left_touch.pressed = true
	var jump_touch: InputEventScreenTouch = InputEventScreenTouch.new()
	jump_touch.index = 1
	jump_touch.position = jump.global_position + Vector2.ONE * (44.0 * jump.scale.x)
	jump_touch.pressed = true
	Input.parse_input_event(left_touch)
	Input.parse_input_event(jump_touch)
	await get_tree().physics_frame
	assert_true(Input.is_action_pressed(&"move_left"))
	assert_true(Input.is_action_pressed(&"jump"))
	left_touch.pressed = false
	jump_touch.pressed = false
	Input.parse_input_event(left_touch)
	Input.parse_input_event(jump_touch)
	await get_tree().physics_frame
	assert_false(Input.is_action_pressed(&"move_left"))
	assert_false(Input.is_action_pressed(&"jump"))
