extends Node

## True when the game was launched as a hands-off demo (`--demo`): the scripted
## controller drives, routes advance into each other without stopping on a
## results menu, and a death retries instead of waiting for input. Recording a
## playthrough is the point of it, so it pairs with Godot's movie writer:
##     godot --path . --write-movie run.avi --fixed-fps 60 -- --demo
var demo_mode: bool = false
## A completed hands-off run is terminal for the lifetime of the process. This
## prevents any fallback to the main menu from auto-starting route 0 again.
var demo_completed: bool = false
var demo_completion_count: int = 0
var demo_route_starts: Array[int] = []
var demo_damage_events: int = 0
var demo_failure_events: int = 0
var run_elapsed_seconds: float = 0.0
var damage_taken: int = 0
var checkpoint_activations: int = 0
var checkpoint_recoveries: int = 0
var best_time_seconds: float:
	get:
		return float(_best_times_by_level.get(selected_level_index, 0.0))

## Campaign progress is intentionally a single, inspectable save. The menu
## template stores audio/video settings and remaps separately in player_config.cfg.
var save_path: String = "user://run_unit_campaign.cfg"
var debug_unlock_routes: bool = false
var calibration_complete: bool = false
var factory_complete: bool = false
var recovery_complete: bool = false
var ignition_module_acquired: bool = false
var beacon_complete: bool = false
var highest_unlocked_route: int = 0
var _best_times_by_level: Dictionary = {}

var selected_level_index: int = 0
var run_seed: int = 0
var world_version: String = "static"
var world_mode: String = "authored"
var configuration_hash: String = ""
var last_world_metrics: Dictionary = {}
var traversal_trace: Dictionary = {}
var last_run_outcome: String = "active"
var run_attempt_index: int = 0

## Keyed by route index. Routes differ wildly in length, so a single shared
## best-distance value would carry a meaningless number over when the player
## switches routes; each route remembers its own record instead.
var _best_distances_by_level: Dictionary = {}
var _run_started_msec: int = 0
var _prior_attempt_seconds: float = 0.0
var _previous_route_index: int = -1
var _playtest_enabled: bool = false
var _playtest_events: Array[Dictionary] = []
var _playtest_path: String = ""
var _playtest_file: FileAccess = null
var _fresh_save_enabled: bool = false

var best_distance: float:
	get:
		return float(_best_distances_by_level.get(selected_level_index, 0.0))
	set(value):
		_best_distances_by_level[selected_level_index] = maxf(value, 0.0)

## Furthest checkpoint the player reached on the route they are running. It
## lives here rather than in RunUnitGame because retrying reloads the game
## scene, and a long route should not be replayed from the start after one
## mistake. Deploying a route from the selector and finishing it both clear it.
var checkpoint_level_index: int = -1
var checkpoint_position: Vector2 = Vector2.ZERO

## Godot only routes arguments after a bare `--` into get_cmdline_user_args(),
## but passing `--demo` straight through works too, so both are accepted.
func _ready() -> void:
	demo_mode = OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_args().has("--demo")
	debug_unlock_routes = OS.is_debug_build() and (OS.get_cmdline_user_args().has("--unlock-routes") or OS.get_cmdline_args().has("--unlock-routes"))
	load_campaign()
	_playtest_enabled = OS.get_cmdline_user_args().has("--playtest") or OS.get_cmdline_args().has("--playtest")
	_fresh_save_enabled = OS.get_cmdline_user_args().has("--fresh-save") or OS.get_cmdline_args().has("--fresh-save")
	_load_progress()
	reset_demo_lifecycle()

## Invalid fields cannot create progress. The derived unlock index wins over a
## stale or edited index in the save, so Beacon always needs the full chain.
func load_campaign() -> void:
	_clear_campaign_state()
	selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	var save: ConfigFile = ConfigFile.new()
	if save.load(save_path) != OK:
		return
	var version_value: Variant = save.get_value("campaign", "version", 0)
	if not (version_value is int):
		return
	if int(version_value) != 1:
		return
	calibration_complete = _saved_flag(save, "calibration_complete")
	factory_complete = calibration_complete and _saved_flag(save, "factory_complete")
	ignition_module_acquired = factory_complete and _saved_flag(save, "ignition_module_acquired")
	recovery_complete = factory_complete and ignition_module_acquired and _saved_flag(save, "recovery_complete")
	beacon_complete = recovery_complete and _saved_flag(save, "beacon_complete")
	_recompute_unlocked_route()
	for route_index: int in RunUnitCampaign.route_count():
		var time_value: Variant = save.get_value("best_times", "route_%d" % route_index, 0.0)
		if (time_value is float or time_value is int) and float(time_value) > 0.0 and not is_nan(float(time_value)) and not is_inf(float(time_value)):
			_best_times_by_level[route_index] = float(time_value)
	selected_level_index = highest_unlocked_route

func _saved_flag(save: ConfigFile, key: String) -> bool:
	var value: Variant = save.get_value("campaign", key, false)
	return value is bool and value

func reset_campaign() -> void:
	_clear_campaign_state()
	selected_level_index = RunUnitCampaign.PLAYABLE_INDEX
	clear_checkpoint()
	_save_campaign()

func _clear_campaign_state() -> void:
	calibration_complete = false
	factory_complete = false
	recovery_complete = false
	ignition_module_acquired = false
	beacon_complete = false
	highest_unlocked_route = 0
	_best_times_by_level.clear()

func _recompute_unlocked_route() -> void:
	if recovery_complete and ignition_module_acquired:
		highest_unlocked_route = 3
	elif factory_complete:
		highest_unlocked_route = 2
	elif calibration_complete:
		highest_unlocked_route = 1
	else:
		highest_unlocked_route = 0

func _save_campaign() -> void:
	var save: ConfigFile = ConfigFile.new()
	save.set_value("campaign", "version", 1)
	save.set_value("campaign", "calibration_complete", calibration_complete)
	save.set_value("campaign", "factory_complete", factory_complete)
	save.set_value("campaign", "recovery_complete", recovery_complete)
	save.set_value("campaign", "ignition_module_acquired", ignition_module_acquired)
	save.set_value("campaign", "beacon_complete", beacon_complete)
	save.set_value("campaign", "highest_unlocked_route", highest_unlocked_route)
	for route_index: int in _best_times_by_level:
		save.set_value("best_times", "route_%d" % route_index, _best_times_by_level[route_index])
	var error: Error = save.save(save_path)
	if error != OK:
		push_warning("Campaign save failed: %s" % error_string(error))

func is_route_unlocked(route_index: int) -> bool:
	if not RunUnitCampaign.is_available(route_index):
		return false
	if demo_mode or debug_unlock_routes:
		return true
	return route_index <= highest_unlocked_route and (route_index != 3 or (recovery_complete and ignition_module_acquired))

func get_route_lock_reason(route_index: int) -> String:
	if not RunUnitCampaign.is_available(route_index):
		return "Route unavailable in this build."
	if is_route_unlocked(route_index):
		return ""
	match route_index:
		1:
			return "Complete Calibration to unlock Factory Escape."
		2:
			return "Complete Factory Escape to unlock Recovery."
		3:
			return "Complete Recovery and recover the ignition module to unlock Beacon 9."
	return "Complete the preceding route to unlock this route."

func get_best_time(route_index: int) -> float:
	return float(_best_times_by_level.get(route_index, 0.0))

func is_route_completed(route_index: int) -> bool:
	match route_index:
		0:
			return calibration_complete
		1:
			return factory_complete
		2:
			return recovery_complete
		3:
			return beacon_complete
	return false

func record_module_acquired() -> void:
	if demo_mode or debug_unlock_routes or ignition_module_acquired:
		return
	ignition_module_acquired = true
	_save_campaign()

## Called only after an actual route finish. Demo/debug routes do not bypass
## campaign prerequisites when recording permanent progress.
func record_route_completion(route_index: int, elapsed_seconds: float) -> bool:
	if demo_mode or debug_unlock_routes or not is_route_unlocked(route_index):
		return false
	match route_index:
		0:
			calibration_complete = true
		1:
			factory_complete = calibration_complete
		2:
			if not ignition_module_acquired:
				return false
			recovery_complete = factory_complete
		3:
			beacon_complete = recovery_complete and ignition_module_acquired
		_:
			return false
	_recompute_unlocked_route()
	if elapsed_seconds > 0.0 and not is_nan(elapsed_seconds) and not is_inf(elapsed_seconds):
		var previous: float = get_best_time(route_index)
		if previous == 0.0 or elapsed_seconds < previous:
			_best_times_by_level[route_index] = elapsed_seconds
	_save_campaign()
	return true

func reset_demo_lifecycle() -> void:
	demo_completed = false
	demo_completion_count = 0
	demo_route_starts.clear()
	demo_damage_events = 0
	demo_failure_events = 0

func should_start_demo() -> bool:
	return demo_mode and not demo_completed

func record_demo_route_start(level_index: int) -> void:
	if not demo_mode or demo_completed:
		return
	demo_route_starts.append(level_index)
	print("DEMO_ROUTE_START index=%d ordinal=%d" % [level_index, demo_route_starts.size()])

func record_demo_damage() -> void:
	if demo_mode and not demo_completed:
		demo_damage_events += 1

func record_demo_failure() -> void:
	if demo_mode and not demo_completed:
		demo_failure_events += 1

## Marks the campaign terminal exactly once. Returning false means some later
## scene tried to finish an already-finished demo and must not restart it.
func mark_demo_completed() -> bool:
	if not demo_mode or demo_completed:
		return false
	demo_completed = true
	demo_completion_count += 1
	print("DEMO_CAMPAIGN_COMPLETE completions=%d routes=%s damage=%d failures=%d" % [demo_completion_count, str(demo_route_starts), demo_damage_events, demo_failure_events])
	return true

func begin_run(level_index: int, seed_value: int, mode: String, version: String, config_hash: String) -> void:
	var retrying_route: bool = _previous_route_index == level_index and last_run_outcome == "failed"
	if retrying_route:
		_prior_attempt_seconds = run_elapsed_seconds
		run_attempt_index += 1
	else:
		_prior_attempt_seconds = 0.0
		run_attempt_index = 1
		damage_taken = 0
		checkpoint_activations = 0
		checkpoint_recoveries = 0
	selected_level_index = level_index
	run_seed = seed_value
	world_mode = mode
	world_version = version
	configuration_hash = config_hash
	last_world_metrics = {}
	traversal_trace = {}
	last_run_outcome = "active"
	run_elapsed_seconds = _prior_attempt_seconds
	_run_started_msec = Time.get_ticks_msec()
	_previous_route_index = level_index
	_open_playtest_attempt(false)

## Starts a new telemetry segment for a retry without resetting route-wide
## measures such as elapsed time, damage or checkpoint activity.
func begin_retry_attempt() -> void:
	_prior_attempt_seconds = run_elapsed_seconds
	run_elapsed_seconds = _prior_attempt_seconds
	run_attempt_index += 1
	_run_started_msec = Time.get_ticks_msec()
	last_run_outcome = "active"
	_open_playtest_attempt(true)

## Redeploying from a completed result starts a separate route attempt, rather
## than adding its time and damage to the route that was just certified.
func begin_redeployment_attempt() -> void:
	_prior_attempt_seconds = 0.0
	run_elapsed_seconds = 0.0
	damage_taken = 0
	checkpoint_activations = 0
	checkpoint_recoveries = 0
	run_attempt_index += 1
	_run_started_msec = Time.get_ticks_msec()
	last_run_outcome = "active"
	_open_playtest_attempt(true)

func _open_playtest_attempt(is_retry: bool) -> void:
	_flush_playtest_events()
	_playtest_events.clear()
	if not _playtest_enabled:
		return
	var directory := "user://run_unit_playtests"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_playtest_path = "%s/route_%02d_%d_attempt_%02d.jsonl" % [directory, selected_level_index, _run_started_msec, run_attempt_index]
	_playtest_file = FileAccess.open(_playtest_path, FileAccess.WRITE)
	record_playtest_event("run_started", {
		"route": selected_level_index,
		"mode": world_mode,
		"world": configuration_hash,
		"attempt": run_attempt_index,
		"retry": is_retry,
	})

func set_world_metrics(metrics: Dictionary) -> void:
	last_world_metrics = metrics.duplicate(true)

func set_traversal_trace(trace: Dictionary) -> void:
	traversal_trace = trace.duplicate(true)

func record_best_distance(distance_value: float) -> void:
	best_distance = maxf(best_distance, maxf(distance_value, 0.0))

func record_damage(amount: int = 1) -> void:
	damage_taken += maxi(amount, 0)
	record_playtest_event("damage", {"amount": amount, "total": damage_taken})

func record_respawn() -> void:
	checkpoint_recoveries += 1
	record_playtest_event("checkpoint_respawn", {"position": [checkpoint_position.x, checkpoint_position.y]})

func record_playtest_event(event_name: String, payload: Dictionary = {}) -> void:
	if not _playtest_enabled:
		return
	var event: Dictionary = {"t": maxf((Time.get_ticks_msec() - _run_started_msec) / 1000.0, 0.0), "event": event_name, "data": payload.duplicate(true)}
	_playtest_events.append(event)
	if _playtest_file != null:
		_playtest_file.store_line(JSON.stringify(event))
		_playtest_file.flush()

func finish_run_metrics(outcome: String) -> Dictionary:
	var attempt_elapsed_seconds: float = maxf((Time.get_ticks_msec() - _run_started_msec) / 1000.0, 0.0)
	run_elapsed_seconds = _prior_attempt_seconds + attempt_elapsed_seconds
	if outcome == "completed":
		var old_time := float(_best_times_by_level.get(selected_level_index, 0.0))
		if old_time <= 0.0 or run_elapsed_seconds < old_time:
			_best_times_by_level[selected_level_index] = run_elapsed_seconds
	record_playtest_event("run_finished", {"outcome": outcome, "attempt": run_attempt_index, "attempt_time_s": attempt_elapsed_seconds, "time_s": run_elapsed_seconds, "distance_m": best_distance, "damage": damage_taken, "checkpoint_activations": checkpoint_activations, "checkpoint_recoveries": checkpoint_recoveries})
	_save_progress()
	_flush_playtest_events()
	return {"time_s": run_elapsed_seconds, "best_time_s": best_time_seconds, "damage": damage_taken, "checkpoint_activations": checkpoint_activations, "checkpoint_recoveries": checkpoint_recoveries}

func set_run_outcome(outcome: String) -> void:
	last_run_outcome = outcome

func record_checkpoint(level_index: int, position: Vector2) -> void:
	if not has_checkpoint(level_index) or position.x > checkpoint_position.x + 1.0:
		checkpoint_activations += 1
		record_playtest_event("checkpoint_activated", {"position": [position.x, position.y]})
	checkpoint_level_index = level_index
	checkpoint_position = position

func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(_progress_path()) != OK:
		return
	var distances: Variant = config.get_value("progress", "best_distances", {})
	var times: Variant = config.get_value("progress", "best_times", {})
	if distances is Dictionary:
		_best_distances_by_level = distances
	if times is Dictionary:
		for route_key: Variant in times:
			var time_value: Variant = times[route_key]
			if not (time_value is int or time_value is float):
				continue
			var elapsed: float = float(time_value)
			if elapsed <= 0.0 or is_nan(elapsed) or is_inf(elapsed):
				continue
			var route_index: int = int(route_key)
			var campaign_time: float = float(_best_times_by_level.get(route_index, 0.0))
			if campaign_time <= 0.0 or elapsed < campaign_time:
				_best_times_by_level[route_index] = elapsed

func _save_progress() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(_progress_path())
	config.set_value("progress", "best_distances", _best_distances_by_level)
	config.set_value("progress", "best_times", _best_times_by_level)
	config.set_value("metrics", "last_route", selected_level_index)
	config.set_value("metrics", "last_time_s", run_elapsed_seconds)
	config.set_value("metrics", "last_distance_m", best_distance)
	config.set_value("metrics", "last_damage", damage_taken)
	config.set_value("metrics", "last_checkpoint_activations", checkpoint_activations)
	config.set_value("metrics", "last_checkpoint_recoveries", checkpoint_recoveries)
	config.save(_progress_path())

func _progress_path() -> String:
	return "user://run_unit_fresh_progress.cfg" if _fresh_save_enabled else "user://run_unit_progress.cfg"

func _flush_playtest_events() -> void:
	if _playtest_file == null:
		return
	_playtest_file.flush()
	_playtest_file.close()
	_playtest_file = null

func has_checkpoint(level_index: int) -> bool:
	return checkpoint_level_index == level_index

## The position a retry should resume from: the reached checkpoint, or the
## route's own spawn when the player has not passed one yet.
func get_resume_position(level_index: int, spawn_position: Vector2) -> Vector2:
	return checkpoint_position if has_checkpoint(level_index) else spawn_position

func clear_checkpoint() -> void:
	checkpoint_level_index = -1
	checkpoint_position = Vector2.ZERO
