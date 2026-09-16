extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const SCORE_MANAGER_SCRIPT: GDScript = preload("res://scripts/gameplay/score_manager.gd")
const WORLD_SCENE: PackedScene = preload("res://scenes/world.tscn")


func test_distance_is_measured_in_metres_from_the_start_pad() -> void:
	var score_manager: RunUnitScoreManager = SCORE_MANAGER_SCRIPT.new() as RunUnitScoreManager
	score_manager.call("reset", 128.0, 18.0)

	var distance: float = score_manager.record_position(160.0)

	assert_eq(distance, 1.0, "32 world pixels should equal one metre from the start pad")
	assert_eq(score_manager.best_distance, 18.0, "A retry should retain the session's existing best distance")


func test_session_keeps_the_best_distance_between_retries() -> void:
	var previous_best: Variant = RunUnitSession.get("best_distance")
	RunUnitSession.set("best_distance", 0.0)
	RunUnitSession.call("record_best_distance", 42.0)

	assert_eq(float(RunUnitSession.get("best_distance")), 42.0)

	RunUnitSession.set("best_distance", previous_best)


func test_maintenance_shaft_exposes_a_completion_trigger_and_signal() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)

	assert_true(world.has_signal(&"route_completed"))
	var completion_trigger: Area2D = world.get_node_or_null("CompletionTrigger") as Area2D
	assert_not_null(completion_trigger)
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	var completion_events: Array[int] = [0]
	world.route_completed.connect(func() -> void: completion_events[0] += 1)

	completion_trigger.body_entered.emit(player)
	completion_trigger.body_entered.emit(player)

	assert_true(world.is_completion_triggered())
	assert_eq(completion_events[0], 1, "The finish area should complete each run only once")


func test_player_crossing_the_maintenance_shaft_finish_area_completes_the_world() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(world)
	add_child_autofree(player)
	player.global_position = Vector2(4544.0, 401.0)

	for frame: int in range(8):
		await get_tree().physics_frame

	assert_true(world.is_completion_triggered())


func test_game_enters_completed_state_when_the_route_trigger_fires() -> void:
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	game.world.route_completed.emit()

	assert_true(game.is_terminal())
	assert_eq(RunUnitSession.last_run_outcome, "completed")
	assert_true(game.death_menu.visible)
	assert_eq(game.death_menu.title_label.text, "ROUTE COMPLETE")

	get_tree().paused = false


func test_player_stays_crouched_when_releasing_under_a_low_ceiling() -> void:
	var ground: StaticBody2D = _create_static_body(Vector2(200.0, 432.0), Vector2(500.0, 32.0))
	var ceiling: StaticBody2D = _create_static_body(Vector2(200.0, 374.0), Vector2(96.0, 32.0))
	var player: RunUnitPlayerMotor = PLAYER_SCENE.instantiate() as RunUnitPlayerMotor
	add_child_autofree(ground)
	add_child_autofree(ceiling)
	add_child_autofree(player)
	player.global_position = Vector2(200.0, 401.0)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var crouch_action: RunUnitPlayerAction = RunUnitPlayerAction.new()
	crouch_action.crouch_held = true
	player.set_action(crouch_action)
	for frame: int in range(30):
		await get_tree().physics_frame
	assert_gt(player.crouch_ratio, 0.95)

	player.set_action(RunUnitPlayerAction.new())
	for frame: int in range(30):
		await get_tree().physics_frame
	assert_gt(player.crouch_ratio, 0.20, "The motor must keep a collision height that fits beneath the low ceiling")


func _create_static_body(body_position: Vector2, body_size: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = body_position
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = body_size
	collision_shape.shape = rectangle
	body.add_child(collision_shape)
	return body
