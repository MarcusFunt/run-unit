class_name RunUnitGame
extends Node2D

@export var initial_seed: int = 0
## A hands-off movie must close after exhausting its final-route retries instead
## of recording a static failure menu forever. Tests can disable this to inspect
## that menu without quitting the test process.
@export var auto_quit_failed_demo: bool = true

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
## A level may own its ending (the inter-level portals, Beacon 9's ignition
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
var _pending_checkpoint_recovery: bool = false
var _trace_sample_countdown: float = 0.0
var _run_elapsed_seconds: float = 0.0
var _full_route_attempt: bool = true
var _finished_metrics: Dictionary = {}
var _crouch_started_msec: int = 0
var _was_crouching: bool = false
## Deaths on the current route during a demo run. Scene-local, so it resets
## naturally when the demo moves on to the next route.
var _demo_failures: int = 0
var _selected_level_index: int = 0
var _trace: RunUnitTraversalTrace = RunUnitTraversalTrace.new()

## Swaps in the selected route's world before any child is ready, so the
## controllers' world_path and this node's @onready references all resolve to
## the level that is actually being played.
func _enter_tree() -> void:
	_selected_level_index = RunUnitSession.selected_level_index if RunUnitSession.is_route_unlocked(RunUnitSession.selected_level_index) else RunUnitCampaign.PLAYABLE_INDEX
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
	if not death_menu.retry_requested.is_connected(_on_retry_requested):
		death_menu.retry_requested.connect(_on_retry_requested)
	if RunUnitSession.demo_mode and RunUnitSession.demo_completed:
		print("DEMO_GAME_RESTART_GUARD route=%d" % _selected_level_index)
		get_tree().quit()
		return
	RunUnitSession.selected_level_index = _selected_level_index
	if RunUnitSession.demo_mode:
		RunUnitSession.record_demo_route_start(_selected_level_index)
	world.set_level_profile(_selected_level_index)
	var world_scene_path: String = RunUnitCampaign.get_world_scene(_selected_level_index)
	RunUnitSession.begin_run(_selected_level_index, 0, "authored", "static", world_scene_path.get_file())
	if not world.obstacle_triggered.is_connected(_on_obstacle_triggered):
		world.obstacle_triggered.connect(_on_obstacle_triggered)
	if not world.route_completed.is_connected(_on_route_completed):
		world.route_completed.connect(_on_route_completed)
	if not world.story_beat.is_connected(_on_story_beat):
		world.story_beat.connect(_on_story_beat)
	if not player_health.damaged.is_connected(_on_player_damaged):
		player_health.damaged.connect(_on_player_damaged)
	if not player_health.depleted.is_connected(_on_player_depleted):
		player_health.depleted.connect(_on_player_depleted)
	if not player.landed.is_connected(_on_player_landed):
		player.landed.connect(_on_player_landed)
	hud.set_level_length(world.get_traversal_length())
	hud.set_campaign_progress(_selected_level_index, RunUnitCampaign.route_count())
	hud.set_objective(RunUnitCampaign.get_objective(_selected_level_index))
	hud.show_system_message(RunUnitCampaign.get_briefing(_selected_level_index), 2.4)
	RunUnitAudio.set_ambience(_ambience_for_route(_selected_level_index))
	for node: Node in world.get_node("CheckpointStations").get_children():
		var station: RunUnitCheckpointStation = node as RunUnitCheckpointStation
		station.activated.connect(_on_checkpoint_activated)
	var module_cradle := world.get_node_or_null("ModuleCradle") as RunUnitModuleCradle
	if module_cradle != null and not module_cradle.module_acquired.is_connected(_on_module_acquired.bind(module_cradle)):
		module_cradle.module_acquired.connect(_on_module_acquired.bind(module_cradle))
	if route_exit is RunUnitBeaconIgnition:
		var beacon: RunUnitBeaconIgnition = route_exit as RunUnitBeaconIgnition
		if not beacon.interaction_completed.is_connected(_complete_run):
			beacon.interaction_completed.connect(_complete_run)
	reset_run(0)
	for hazard: RunUnitHazardArea in world.get_hazard_nodes():
		if not hazard.hazard_phase_changed.is_connected(_on_hazard_phase_changed.bind(hazard)):
			hazard.hazard_phase_changed.connect(_on_hazard_phase_changed.bind(hazard))
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
	_run_elapsed_seconds += delta
	var current_distance: float = score_manager.record_position(player.global_position.x)
	_update_crouch_metrics()
	RunUnitSession.record_best_distance(score_manager.best_distance)
	_trace_sample_countdown -= delta
	if _trace_sample_countdown <= 0.0:
		_trace_sample_countdown = TRACE_SAMPLE_INTERVAL
		var current_platform: Dictionary = world.get_platform_below_position(player.global_position)
		_trace.record_sample(player.global_position, player.velocity, int(current_platform.get("platform_id", -1)))
	world.set_progress(current_distance)
	hud.set_scores(current_distance, score_manager.best_distance)
	_update_debug(current_distance)
	if player.global_position.y > world.death_y:
		_fail_run("fell_below_route")

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
	if RunUnitSession.last_run_outcome == "failed":
		RunUnitSession.begin_retry_attempt()
	elif RunUnitSession.last_run_outcome in ["completed", "incomplete"]:
		RunUnitSession.begin_redeployment_attempt()
	if RunUnitSession.has_checkpoint(_selected_level_index):
		RunUnitSession.record_respawn()
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
	_full_route_attempt = not RunUnitSession.has_checkpoint(_selected_level_index)
	score_manager.reset(spawn_position.x, RunUnitSession.best_distance)
	_last_reward_distance = 0.0
	_terminal_penalty_paid = false
	_trace_sample_countdown = 0.0
	_run_elapsed_seconds = 0.0
	_finished_metrics.clear()
	_was_crouching = false
	if not world.world_metrics_updated.is_connected(_on_world_metrics_updated):
		world.world_metrics_updated.connect(_on_world_metrics_updated)
	world.reset(run_seed)
	var resumed_distance: float = score_manager.record_position(resume_position.x)
	world.set_progress(resumed_distance)
	RunUnitSession.run_seed = run_seed
	RunUnitSession.set_run_outcome("active")
	_trace.begin(run_seed)
	player.global_position = resume_position
	for node: Node in world.get_node("CheckpointStations").get_children():
		var station: RunUnitCheckpointStation = node as RunUnitCheckpointStation
		if RunUnitSession.has_checkpoint(_selected_level_index) and station.checkpoint_position.x <= resume_position.x:
			var is_resume_station: bool = station.checkpoint_position.is_equal_approx(resume_position)
			station.restore_active(_pending_checkpoint_recovery and is_resume_station)
	player.reset_motor()
	(player.get_node("Camera2D") as RunUnitFollowCamera).snap_to_player()
	player_health.reset_health()
	player.set_physics_process(true)
	death_menu.close()
	hud.show()
	if route_exit != null:
		route_exit.reset_transition()
	hud.set_campaign_progress(_selected_level_index, RunUnitCampaign.route_count())
	hud.set_scores(resumed_distance, score_manager.best_distance)
	hud.set_health(player_health.current_health, player_health.max_health)
	hud.set_objective(RunUnitCampaign.get_objective(_selected_level_index))
	if _pending_checkpoint_recovery:
		hud.show_system_message("Recovered at the last service marker.", 2.4)
		_pending_checkpoint_recovery = false

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

func _on_retry_requested() -> void:
	if not is_terminal():
		return
	reset_run(initial_seed)

func _fail_run(reason: String = "unknown") -> void:
	_pending_checkpoint_recovery = reason == "fell_below_route" and RunUnitSession.has_checkpoint(_selected_level_index)
	RunUnitSession.record_playtest_event("death", {
		"reason": reason,
		"position": [player.global_position.x, player.global_position.y],
		"distance": score_manager.distance,
	})
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
	RunUnitSession.record_playtest_event("run_end_position", {
		"position": [player.global_position.x, player.global_position.y],
		"distance": current_distance,
	})
	hud.set_scores(current_distance, score_manager.best_distance)
	var outcome: String = "failed" if result == RunState.FAILED else "completed"
	var campaign_completion_recorded: bool = true
	if result == RunState.COMPLETED:
		# The route is done; a redeploy starts it from the beginning again.
		RunUnitSession.clear_checkpoint()
		campaign_completion_recorded = RunUnitSession.record_route_completion(_selected_level_index, _run_elapsed_seconds if _full_route_attempt else 0.0)
		if _selected_level_index == 2 and not campaign_completion_recorded and not RunUnitSession.demo_mode and not RunUnitSession.debug_unlock_routes:
			outcome = "incomplete"
	if result == RunState.FAILED:
		player_feedback.play_game_over_feedback()
	_finished_metrics = RunUnitSession.finish_run_metrics(outcome)
	_trace.record("metrics:%s" % outcome, player.global_position, player.velocity)
	_trace.record(outcome, player.global_position, player.velocity)
	RunUnitSession.set_traversal_trace(_trace.export_data())
	RunUnitSession.set_run_outcome(outcome)
	if result == RunState.FAILED and RunUnitSession.demo_mode:
		_demo_recover_from_failure()
	elif result == RunState.FAILED:
		death_menu.open_with_scores(score_manager.distance, score_manager.best_distance, _finished_metrics)
	elif outcome == "incomplete":
		death_menu.open_missing_module()
	elif route_exit != null:
		if not route_exit.transition_finished.is_connected(_on_route_exit_finished):
			route_exit.transition_finished.connect(_on_route_exit_finished)
		route_exit.begin_transition()
	elif RunUnitSession.demo_mode and _has_next_route():
		# Routes without their own ending normally stop on the results menu,
		# which would end the recording partway through the campaign.
		_load_next_route()
	else:
		death_menu.open_completed_with_scores(score_manager.distance, score_manager.best_distance, _finished_metrics)

## A demo retries from its last checkpoint the way a player would, but it has to
## give up eventually: without a cap, a corner the bot cannot solve would loop
## forever and the recording would never reach the end of the campaign.
func _demo_recover_from_failure() -> void:
	RunUnitSession.record_demo_failure()
	_demo_failures += 1
	if _demo_failures <= DEMO_RETRY_LIMIT:
		reset_run.call_deferred(0)
		return
	if _has_next_route():
		push_warning("Demo: giving up on route %d after %d attempts; skipping ahead." % [_selected_level_index, _demo_failures])
		_load_next_route()
		return
	death_menu.open_with_scores(score_manager.distance, score_manager.best_distance)
	if auto_quit_failed_demo:
		push_error("Demo: final route failed after %d attempts; stopping the capture." % _demo_failures)
		get_tree().call_deferred("quit", 1)

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
		death_menu.open_completed_with_scores(score_manager.distance, score_manager.best_distance, _finished_metrics)
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
	RunUnitSession.record_demo_damage()
	RunUnitSession.record_damage()
	RunUnitSession.record_playtest_event("health_changed", {"current": current_health, "maximum": max_health})
	hud.set_health(current_health, max_health)
	player_feedback.play_damage_feedback()

func _on_player_depleted() -> void:
	_fail_run("health_depleted")

func _on_obstacle_triggered(obstacle_type: String, platform_id: int) -> void:
	if is_terminal():
		return
	_trace.record("obstacle:%s" % obstacle_type, player.global_position, player.velocity, platform_id)
	_fail_run("obstacle:%s" % obstacle_type)

## A checkpoint only registers when the player actually touches its node.
func _on_checkpoint_activated(checkpoint_position: Vector2) -> void:
	RunUnitSession.record_checkpoint(_selected_level_index, checkpoint_position)
	RunUnitAudio.play_event("checkpoint", -14.0)

func _on_player_landed() -> void:
	var platform: Dictionary = world.get_platform_below_position(player.global_position)
	RunUnitSession.record_playtest_event("landing", {
		"position": [player.global_position.x, player.global_position.y],
		"platform_id": int(platform.get("platform_id", -1)),
		"landing_speed": player.last_landing_speed,
	})

func _on_module_acquired(module_cradle: RunUnitModuleCradle) -> void:
	RunUnitSession.record_module_acquired()
	RunUnitSession.record_playtest_event("module_acquired_progress", _module_acquisition_metrics(module_cradle.global_position.x))

func _module_acquisition_metrics(module_x: float) -> Dictionary:
	# Traversal length is expressed in tiles; pickup positions are world pixels.
	var route_length_pixels: float = maxf(world.get_traversal_length() * world.tile_size, 1.0)
	var distance_from_spawn: float = module_x - world.get_spawn_position().x
	return {
		"position_x": module_x,
		"route_progress": clampf(distance_from_spawn / route_length_pixels, 0.0, 1.0),
		"post_pickup_distance": maxf(route_length_pixels - distance_from_spawn, 0.0),
	}

func _on_route_completed() -> void:
	if route_exit is RunUnitBeaconIgnition:
		var beacon: RunUnitBeaconIgnition = route_exit as RunUnitBeaconIgnition
		hud.hide()
		beacon.begin_player_interaction(player)
		human_controller.active = false
		# The route ending uses the same hold/release input as a player. Keep the
		# scripted controller alive only for an automated campaign demonstration.
		scripted_controller.active = RunUnitSession.demo_mode
		if RunUnitSession.demo_mode:
			scripted_controller.reset_controller()
		player.set_physics_process(false)
		RunUnitSession.record_playtest_event("beacon_interaction_started", {"position": [player.global_position.x, player.global_position.y]})
		return
	_complete_run()

func _on_story_beat(zone_name: String, cue: Dictionary) -> void:
	var message := str(cue.get("message", ""))
	# Zone labels are part of the machinery, not subtitles. Only surface a
	# brief cue when the level also changes in a visible, persistent way.
	if not message.is_empty() and not str(cue.get("world_change", "")).is_empty():
		hud.show_system_message(message, 1.8)
	var ambience := str(cue.get("ambience", ""))
	if not ambience.is_empty():
		RunUnitAudio.set_ambience(ambience)
	var event_name := str(cue.get("event", ""))
	if not event_name.is_empty():
		RunUnitAudio.play_event(event_name)
	RunUnitSession.record_playtest_event("story_effect", {"zone": zone_name, "message": message, "ambience": ambience, "event": event_name})

func _on_hazard_phase_changed(phase: int, hazard: RunUnitHazardArea) -> void:
	if not is_instance_valid(hazard):
		return
	if hazard.global_position.distance_to(player.global_position) <= 1200.0:
		RunUnitAudio.play_hazard_phase(phase, String(hazard.name), hazard.global_position)
	RunUnitSession.record_playtest_event("hazard_phase", {"hazard": String(hazard.name), "phase": phase})

func _update_crouch_metrics() -> void:
	var crouching: bool = player.is_crouching()
	if crouching and not _was_crouching:
		_crouch_started_msec = Time.get_ticks_msec()
		RunUnitSession.record_playtest_event("crouch_started", {"position": [player.global_position.x, player.global_position.y]})
	elif _was_crouching and not crouching:
		RunUnitSession.record_playtest_event("crouch_ended", {"duration_s": maxf((Time.get_ticks_msec() - _crouch_started_msec) / 1000.0, 0.0)})
	_was_crouching = crouching

func _ambience_for_route(route_index: int) -> String:
	match route_index:
		0, 1: return "factory"
		2: return "exterior"
		3: return "beacon_exterior"
	return "factory"

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
	# The options menu loads saved bindings at startup. Do not restore a
	# removed default key when a player has already remapped this action.
	if not InputMap.action_get_events(action_name).is_empty():
		return
	var input_event: InputEventKey = InputEventKey.new()
	input_event.keycode = keycode
	if not InputMap.action_has_event(action_name, input_event):
		InputMap.action_add_event(action_name, input_event)
