class_name RunUnitGame
extends Node2D

@export var initial_seed: int = 0

@onready var world: RunUnitStaticWorld = $World
@onready var player: RunUnitPlayerMotor = $Player
@onready var player_health: RunUnitPlayerHealth = $Player/Health
@onready var player_feedback: RunUnitPlayerFeedback = $Player/Feedback
@onready var human_controller: RunUnitHumanController = $HumanController
@onready var scripted_controller: RunUnitScriptedController = $ScriptedController
@onready var score_manager: RunUnitScoreManager = $ScoreManager
@onready var hud: RunUnitHud = $HUD
@onready var debug_overlay: RunUnitDebugOverlay = $DebugOverlay
@onready var death_menu: RunUnitDeathMenu = $DeathMenu
## A level may own its ending (the tutorial's lift, Beacon 9's ignition
## chamber). Routes without one finish on the results menu.
@onready var route_exit: RunUnitRouteExit = _find_route_exit()

## The traversal trace exists to explain a run afterwards, not to replay it
## frame by frame, so it is sampled on a fixed wall-clock cadence instead of
## once per physics frame.
const TRACE_SAMPLE_INTERVAL: float = 0.1

## How many deaths a demo run absorbs on one route before skipping past it.
const DEMO_RETRY_LIMIT: int = 3

enum RunState { ACTIVE, FAILED, COMPLETED }

var _run_state: int = RunState.ACTIVE
var _run_started: bool = false
var _bot_enabled: bool = false
var _external_control: bool = false
var _last_reward_distance: float = 0.0
var _terminal_penalty_paid: bool = false
var _trace_sample_countdown: float = 0.0
## Deaths on the current route during a demo run. Scene-local, so it resets
## naturally when the demo moves on to the next route.
var _demo_failures: int = 0
var _selected_level_index: int = 0
var _trace: RunUnitTraversalTrace = RunUnitTraversalTrace.new()
## Authored respawn points, in route order, and the next one still ahead.
var _checkpoints: Array[Vector2] = []
var _next_checkpoint: int = 0

## Swaps in the selected route's world before any child is ready, so the
## controllers' world_path and this node's @onready references all resolve to
## the level that is actually being played.
func _enter_tree() -> void:
	_selected_level_index = RunUnitSession.selected_level_index if RunUnitCampaign.is_available(RunUnitSession.selected_level_index) else 0
	var world_scene_path: String = RunUnitCampaign.get_world_scene(_selected_level_index)
	var current_world: Node = get_node_or_null("World")
	if current_world == null or current_world.scene_file_path == world_scene_path:
		return
	var selected_world: Node = (load(world_scene_path) as PackedScene).instantiate()
	selected_world.name = "World"
	var world_index: int = current_world.get_index()
	remove_child(current_world)
	current_world.free()
	add_child(selected_world)
	move_child(selected_world, world_index)

func _ready() -> void:
	_ensure_input_map()
	RunUnitSession.selected_level_index = _selected_level_index
	world.set_level_profile(_selected_level_index)
	var world_scene_path: String = RunUnitCampaign.get_world_scene(_selected_level_index)
	RunUnitSession.begin_run(_selected_level_index, 0, "authored", "static", world_scene_path.get_file())
	if not world.obstacle_triggered.is_connected(_on_obstacle_triggered):
		world.obstacle_triggered.connect(_on_obstacle_triggered)
	if not world.route_completed.is_connected(_on_route_completed):
		world.route_completed.connect(_on_route_completed)
	if not player_health.damaged.is_connected(_on_player_damaged):
		player_health.damaged.connect(_on_player_damaged)
	if not player_health.depleted.is_connected(_on_player_depleted):
		player_health.depleted.connect(_on_player_depleted)
	hud.set_level_length(world.get_traversal_length())
	_checkpoints = world.get_checkpoint_positions()
	reset_run(0)
	_run_started = true

func _physics_process(delta: float) -> void:
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
	_record_passed_checkpoints()
	_trace_sample_countdown -= delta
	if _trace_sample_countdown <= 0.0:
		_trace_sample_countdown = TRACE_SAMPLE_INTERVAL
		var current_platform: Dictionary = world.get_platform_below_position(player.global_position)
		_trace.record_sample(player.global_position, player.velocity, int(current_platform.get("platform_id", -1)))
	world.set_progress(current_distance)
	hud.set_scores(current_distance, score_manager.best_distance)
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
	# A demo run is driven by the scripted controller from the first frame, and
	# stays that way across the retries it takes on the way through.
	_bot_enabled = RunUnitSession.demo_mode
	human_controller.active = not _bot_enabled
	scripted_controller.active = _bot_enabled
	scripted_controller.reset_controller()
	var spawn_position: Vector2 = world.get_spawn_position()
	# Distance is always measured from the route's spawn, even when a retry
	# resumes at a checkpoint, so progress reads the same either way.
	var resume_position: Vector2 = RunUnitSession.get_resume_position(_selected_level_index, spawn_position)
	score_manager.reset(spawn_position.x, RunUnitSession.best_distance)
	_last_reward_distance = 0.0
	_terminal_penalty_paid = false
	_trace_sample_countdown = 0.0
	if not world.world_metrics_updated.is_connected(_on_world_metrics_updated):
		world.world_metrics_updated.connect(_on_world_metrics_updated)
	world.reset(run_seed)
	RunUnitSession.run_seed = run_seed
	RunUnitSession.set_run_outcome("active")
	_trace.begin(run_seed)
	player.global_position = resume_position
	_next_checkpoint = 0
	_record_passed_checkpoints()
	player.reset_motor()
	player_health.reset_health()
	player.set_physics_process(true)
	death_menu.close()
	if route_exit != null:
		route_exit.reset_transition()
	hud.set_scores(0.0, score_manager.best_distance)
	hud.set_health(player_health.current_health, player_health.max_health)

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
			var surface: Vector2 = world.get_platform_surface_position(platform)
			values.append(clampf((surface.x - player.global_position.x) / 640.0, -1.0, 1.0))
			values.append(clampf((surface.y - player.global_position.y) / 320.0, -1.0, 1.0))
			values.append(clampf(float(platform.get("width", 0)) / 14.0, 0.0, 1.0))
		else:
			values.append(0.0)
			values.append(0.0)
			values.append(0.0)
	return {"values": values}

func consume_reward() -> float:
	var reward: float = score_manager.distance - _last_reward_distance
	_last_reward_distance = score_manager.distance
	# The failure penalty is part of the terminal transition, so it is paid
	# exactly once. Polling the reward after a run ended used to charge -1 on
	# every call, which silently skews any agent that reads past terminal.
	if _run_state == RunState.FAILED and not _terminal_penalty_paid:
		_terminal_penalty_paid = true
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
	if result == RunState.COMPLETED:
		# The route is done; a redeploy starts it from the beginning again.
		RunUnitSession.clear_checkpoint()
	if result == RunState.FAILED:
		player_feedback.play_game_over_feedback()
	_trace.record(outcome, player.global_position, player.velocity)
	RunUnitSession.set_traversal_trace(_trace.export_data())
	RunUnitSession.set_run_outcome(outcome)
	if result == RunState.FAILED and RunUnitSession.demo_mode:
		_demo_recover_from_failure()
	elif result == RunState.FAILED:
		death_menu.open_with_scores(score_manager.distance, score_manager.best_distance)
	elif route_exit != null:
		if not route_exit.transition_finished.is_connected(_on_route_exit_finished):
			route_exit.transition_finished.connect(_on_route_exit_finished)
		route_exit.begin_transition()
	elif RunUnitSession.demo_mode and _has_next_route():
		# Routes without their own ending normally stop on the results menu,
		# which would end the recording partway through the campaign.
		_load_next_route()
	else:
		death_menu.open_completed_with_scores(score_manager.distance, score_manager.best_distance)

## A demo retries from its last checkpoint the way a player would, but it has to
## give up eventually: without a cap, a corner the bot cannot solve would loop
## forever and the recording would never reach the end of the campaign.
func _demo_recover_from_failure() -> void:
	_demo_failures += 1
	if _demo_failures <= DEMO_RETRY_LIMIT:
		reset_run.call_deferred(0)
		return
	if _has_next_route():
		push_warning("Demo: giving up on route %d after %d attempts; skipping ahead." % [_selected_level_index, _demo_failures])
		_load_next_route()
		return
	death_menu.open_with_scores(score_manager.distance, score_manager.best_distance)

func _has_next_route() -> bool:
	return RunUnitCampaign.get_next_route_index(_selected_level_index) != _selected_level_index

func _load_next_route() -> void:
	RunUnitSession.clear_checkpoint()
	RunUnitSession.selected_level_index = RunUnitCampaign.get_next_route_index(_selected_level_index)
	# Route completion is emitted from an Area2D physics callback. Replacing the
	# scene immediately from that callback removes CollisionObject2D nodes while
	# the physics server is still iterating them, which can strand demo runs on
	# the old route. Defer the hand-off to the next idle turn instead.
	SceneLoader.call_deferred("load_scene", scene_file_path)

## The exit emits this just before it loads its own next scene. An exit that
## hands back into this same game scene means "play the next route", so the
## session has to point at that route before the load happens.
func _on_route_exit_finished() -> void:
	if route_exit.next_scene_path.is_empty():
		death_menu.open_completed_with_scores(score_manager.distance, score_manager.best_distance)
		return
	if route_exit.next_scene_path == scene_file_path:
		RunUnitSession.selected_level_index = RunUnitCampaign.get_next_route_index(_selected_level_index)

func _find_route_exit() -> RunUnitRouteExit:
	for child: Node in world.get_children():
		if child is RunUnitRouteExit:
			return child as RunUnitRouteExit
	return null

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

func _on_player_damaged(current_health: int, max_health: int) -> void:
	hud.set_health(current_health, max_health)
	player_feedback.play_damage_feedback()

func _on_player_depleted() -> void:
	_fail_run()

func _on_obstacle_triggered(obstacle_type: String, platform_id: int) -> void:
	if is_terminal():
		return
	_trace.record("obstacle:%s" % obstacle_type, player.global_position, player.velocity, platform_id)
	_fail_run()

## Remembers every checkpoint the player has already driven past, so a retry
## resumes from the furthest one instead of replaying the whole route.
func _record_passed_checkpoints() -> void:
	while _next_checkpoint < _checkpoints.size() and player.global_position.x >= _checkpoints[_next_checkpoint].x:
		RunUnitSession.record_checkpoint(_selected_level_index, _checkpoints[_next_checkpoint])
		_next_checkpoint += 1

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
