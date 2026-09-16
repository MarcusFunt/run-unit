class_name RunUnitGame
extends Node2D

@export var initial_seed: int = 0

@onready var world: RunUnitStaticWorld = $World
@onready var player: RunUnitPlayerMotor = $Player
@onready var player_feedback: RunUnitPlayerFeedback = $Player/Feedback
@onready var human_controller: RunUnitHumanController = $HumanController
@onready var scripted_controller: RunUnitScriptedController = $ScriptedController
@onready var score_manager: RunUnitScoreManager = $ScoreManager
@onready var hud: RunUnitHud = $HUD
@onready var debug_overlay: RunUnitDebugOverlay = $DebugOverlay
@onready var death_menu: RunUnitDeathMenu = $DeathMenu

const PLAYABLE_LEVEL_INDEX: int = 0

enum RunState { ACTIVE, FAILED, COMPLETED }

var _run_state: int = RunState.ACTIVE
var _run_started: bool = false
var _bot_enabled: bool = false
var _external_control: bool = false
var _last_reward_distance: float = 0.0
var _selected_level_index: int = 0
var _trace: RunUnitTraversalTrace = RunUnitTraversalTrace.new()

func _ready() -> void:
	_ensure_input_map()
	_selected_level_index = PLAYABLE_LEVEL_INDEX
	RunUnitSession.selected_level_index = PLAYABLE_LEVEL_INDEX
	world.set_level_profile(_selected_level_index)
	RunUnitSession.begin_run(_selected_level_index, 0, "authored", "static", "world.tscn")
	if not world.obstacle_triggered.is_connected(_on_obstacle_triggered):
		world.obstacle_triggered.connect(_on_obstacle_triggered)
	if not world.route_completed.is_connected(_on_route_completed):
		world.route_completed.connect(_on_route_completed)
	hud.set_level_length(world.get_traversal_length())
	reset_run(0)
	_run_started = true

func _physics_process(_delta: float) -> void:
	if not _run_started:
		return
	if is_terminal():
		if Input.is_action_just_pressed("restart"):
			reset_run(0)
		return
	if Input.is_action_just_pressed("restart"):
		reset_run(0)
		return
	var current_distance: float = score_manager.record_position(player.global_position.x)
	RunUnitSession.record_best_distance(score_manager.best_distance)
	var current_platform: Dictionary = world.get_platform_below_position(player.global_position)
	_trace.record("sample", player.global_position, player.velocity, int(current_platform.get("platform_id", -1)))
	world.set_progress(current_distance)
	hud.set_scores(current_distance, score_manager.best_distance)
	var controller_name: String = "BOT" if _bot_enabled else ("AI" if _external_control else "HUMAN")
	hud.set_status("%s  //  A/D MOVE  //  SPACE JUMP  //  R RESTART" % controller_name)
	_update_debug(current_distance)
	if player.global_position.y > world.death_y:
		_fail_run()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if OS.is_debug_build() and event.is_action_pressed("toggle_debug"):
		debug_overlay.set_open(not debug_overlay.visible)
	elif OS.is_debug_build() and event.keycode == KEY_B and not is_terminal():
		_bot_enabled = not _bot_enabled
		_external_control = false
		human_controller.active = not _bot_enabled
		scripted_controller.active = _bot_enabled
		scripted_controller.reset_controller()

func reset_run(run_seed: int) -> void:
	initial_seed = run_seed
	_run_state = RunState.ACTIVE
	_external_control = false
	_bot_enabled = false
	human_controller.active = true
	scripted_controller.active = false
	scripted_controller.reset_controller()
	var spawn_position: Vector2 = world.get_spawn_position()
	score_manager.reset(spawn_position.x, RunUnitSession.best_distance)
	_last_reward_distance = 0.0
	if not world.world_metrics_updated.is_connected(_on_world_metrics_updated):
		world.world_metrics_updated.connect(_on_world_metrics_updated)
	world.reset(run_seed)
	RunUnitSession.run_seed = run_seed
	RunUnitSession.set_run_outcome("active")
	_trace.begin(run_seed)
	player.global_position = spawn_position
	player.reset_motor()
	player.set_physics_process(true)
	death_menu.close()
	hud.set_scores(0.0, score_manager.best_distance)

func apply_external_action(action: RunUnitPlayerAction) -> void:
	if is_terminal():
		return
	_external_control = true
	_bot_enabled = false
	human_controller.active = false
	scripted_controller.active = false
	player.set_action(action)

func get_observation() -> Dictionary:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.append(clampf(player.velocity.x / player.max_run_speed, -1.0, 1.0))
	values.append(clampf(player.velocity.y / player.max_fall_speed, -1.0, 1.0))
	values.append(1.0 if player.is_on_floor() else 0.0)
	var platforms: Array[Dictionary] = world.get_upcoming_platforms(player.global_position.x, 3)
	for index: int in range(0, 3):
		if index < platforms.size():
			var platform: Dictionary = platforms[index]
			var centre_x: float = (float(platform.get("start_x", 0)) + float(platform.get("width", 0)) * 0.5) * world.tile_size
			var surface_y: float = float(platform.get("height", 0)) * world.tile_size
			values.append(clampf((centre_x - player.global_position.x) / 640.0, -1.0, 1.0))
			values.append(clampf((surface_y - player.global_position.y) / 320.0, -1.0, 1.0))
			values.append(clampf(float(platform.get("width", 0)) / 14.0, 0.0, 1.0))
		else:
			values.append(0.0)
			values.append(0.0)
			values.append(0.0)
	return {"values": values}

func consume_reward() -> float:
	var reward: float = score_manager.distance - _last_reward_distance
	_last_reward_distance = score_manager.distance
	if _run_state == RunState.FAILED:
		reward -= 1.0
	return reward

func is_terminal() -> bool:
	return _run_state != RunState.ACTIVE

func _fail_run() -> void:
	_finish_run(RunState.FAILED)

func _complete_run() -> void:
	_finish_run(RunState.COMPLETED)

func _finish_run(result: int) -> void:
	if is_terminal():
		return
	_run_state = result
	human_controller.active = false
	scripted_controller.active = false
	player.set_physics_process(false)
	var current_distance: float = score_manager.record_position(player.global_position.x)
	RunUnitSession.record_best_distance(score_manager.best_distance)
	hud.set_scores(current_distance, score_manager.best_distance)
	var outcome: String = "failed" if result == RunState.FAILED else "completed"
	if result == RunState.FAILED:
		player_feedback.play_game_over_feedback()
	_trace.record(outcome, player.global_position, player.velocity)
	RunUnitSession.set_traversal_trace(_trace.export_data())
	RunUnitSession.set_run_outcome(outcome)
	if result == RunState.FAILED:
		death_menu.open_with_scores(score_manager.distance, score_manager.best_distance)
	else:
		death_menu.open_completed_with_scores(score_manager.distance, score_manager.best_distance)

func _update_debug(current_distance: float) -> void:
	if not debug_overlay.visible:
		return
	var current: Dictionary = world.get_platform_below_position(player.global_position)
	var upcoming: Array[Dictionary] = world.get_upcoming_platforms(player.global_position.x, 2)
	var current_id: Variant = current.get("platform_id", "-")
	var next_id: Variant = "-"
	if upcoming.size() > 1:
		next_id = upcoming[1].get("platform_id", "-")
	var challenge: Variant = current.get("challenge_type", "-")
	var metrics: Dictionary = world.get_world_metrics()
	debug_overlay.set_debug_text("AUTHORED WORLD\nDIST %dm  DIFF %.2f\nVEL (%.0f, %.0f)\nPLATFORM %s  NEXT %s\nPLATFORMS %s\n%s" % [int(current_distance), world.get_difficulty(), player.velocity.x, player.velocity.y, str(current_id), str(next_id), str(metrics.get("platform_count", "-")), str(challenge)])

func _on_world_metrics_updated(metrics: Dictionary) -> void:
	RunUnitSession.set_world_metrics(metrics)

func _on_obstacle_triggered(obstacle_type: String, platform_id: int) -> void:
	if is_terminal():
		return
	_trace.record("obstacle:%s" % obstacle_type, player.global_position, player.velocity, platform_id)
	_fail_run()

func _on_route_completed() -> void:
	_complete_run()

func _ensure_input_map() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_left", KEY_LEFT)
	_add_key_action("move_right", KEY_D)
	_add_key_action("move_right", KEY_RIGHT)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("jump", KEY_UP)
	_add_key_action("crouch", KEY_DOWN)
	_add_key_action("restart", KEY_R)

func _add_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var input_event: InputEventKey = InputEventKey.new()
	input_event.keycode = keycode
	if not InputMap.action_has_event(action_name, input_event):
		InputMap.action_add_event(action_name, input_event)
