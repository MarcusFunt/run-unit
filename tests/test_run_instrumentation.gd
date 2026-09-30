extends GutTest

## Regression coverage for the run's bookkeeping seams: the traversal trace,
## the reward the AI facade reads, world-metrics broadcasting, and the
## world-space contract of the platform queries.

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const WORLD_SCENE: PackedScene = preload("res://scenes/world.tscn")
const TRACE_SCRIPT: GDScript = preload("res://scripts/world/traversal_trace.gd")
const RUN_SESSION_SCRIPT: GDScript = preload("res://scripts/gameplay/run_session.gd")
const TILE: float = 32.0


func _make_game() -> RunUnitGame:
	var game: RunUnitGame = GAME_SCENE.instantiate() as RunUnitGame
	var pause_menu_controller: Node = game.get_node_or_null("PauseMenuController")
	if pause_menu_controller != null:
		pause_menu_controller.free()
	add_child_autofree(game)
	return game


func test_traversal_trace_caps_its_positional_sample_stream() -> void:
	var trace: RunUnitTraversalTrace = TRACE_SCRIPT.new() as RunUnitTraversalTrace
	trace.begin(0)

	var over_budget: int = RunUnitTraversalTrace.MAX_SAMPLE_EVENTS + 250
	for index: int in range(over_budget):
		trace.record_sample(Vector2(float(index), 0.0), Vector2.ZERO, 1)

	assert_eq(trace.events.size(), RunUnitTraversalTrace.MAX_SAMPLE_EVENTS, "A long run must not grow the trace without bound")
	assert_eq(trace.dropped_samples, 250, "Dropped samples should be reported rather than silently lost")


func test_traversal_trace_always_keeps_named_events() -> void:
	var trace: RunUnitTraversalTrace = TRACE_SCRIPT.new() as RunUnitTraversalTrace
	trace.begin(0)
	for index: int in range(RunUnitTraversalTrace.MAX_SAMPLE_EVENTS + 10):
		trace.record_sample(Vector2.ZERO, Vector2.ZERO)

	trace.record("failed", Vector2(9.0, 9.0), Vector2.ZERO)

	var exported: Dictionary = trace.export_data()
	var events: Array = exported.get("events", [])
	assert_eq(str((events[events.size() - 1] as Dictionary).get("event", "")), "failed", "The terminal event must survive a spent sample budget")
	assert_eq(int(exported.get("dropped_samples", -1)), 10)


func test_traversal_trace_resets_its_budget_between_runs() -> void:
	var trace: RunUnitTraversalTrace = TRACE_SCRIPT.new() as RunUnitTraversalTrace
	trace.begin(0)
	for index: int in range(RunUnitTraversalTrace.MAX_SAMPLE_EVENTS + 5):
		trace.record_sample(Vector2.ZERO, Vector2.ZERO)

	trace.begin(1)
	trace.record_sample(Vector2.ZERO, Vector2.ZERO)

	assert_eq(trace.events.size(), 1)
	assert_eq(trace.dropped_samples, 0)


func test_failure_penalty_is_charged_once_per_run() -> void:
	var game: RunUnitGame = _make_game()
	game.world.obstacle_triggered.emit("test", 1)
	assert_true(game.is_terminal(), "The obstacle should have ended the run")

	var first_reward: float = game.consume_reward()
	var second_reward: float = game.consume_reward()
	get_tree().paused = false

	assert_almost_eq(second_reward - first_reward, 1.0, 0.001, "Polling reward after a failure must not re-charge the -1 terminal penalty")
	assert_almost_eq(second_reward, 0.0, 0.001, "A finished, already-settled run yields no further reward")


func test_resetting_a_run_rearms_the_failure_penalty() -> void:
	var game: RunUnitGame = _make_game()
	var attempt_before_failure: int = RunUnitSession.run_attempt_index
	game.world.obstacle_triggered.emit("test", 1)
	var _settle: float = game.consume_reward()

	game.reset_run(0)
	assert_eq(RunUnitSession.run_attempt_index, attempt_before_failure + 1, "Restarting a failed route should begin a separately recorded attempt")
	assert_false(get_tree().paused, "Restarting should release the pause the results menu took")
	game.world.obstacle_triggered.emit("test", 1)
	var reward: float = game.consume_reward()
	get_tree().paused = false

	assert_almost_eq(reward, -1.0, 0.001, "A fresh run should charge its own terminal penalty")


func test_world_metrics_are_not_republished_on_every_progress_sample() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	world.reset(0)
	var emissions: Array[int] = [0]
	world.world_metrics_updated.connect(func(_metrics: Dictionary) -> void: emissions[0] += 1)

	for step: int in range(120):
		world.set_progress(0.25)

	assert_eq(emissions[0], 1, "Re-reporting an unchanged progress value should not re-emit metrics")
	assert_almost_eq(world.get_difficulty(), 0.25 / world.get_traversal_length(), 0.0001, "Throttling must not change the reported progress")


func test_world_metrics_still_report_meaningful_progress_changes() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	world.reset(0)
	var emissions: Array[int] = [0]
	world.world_metrics_updated.connect(func(_metrics: Dictionary) -> void: emissions[0] += 1)

	world.set_progress(0.0)
	world.set_progress(world.get_traversal_length() * 0.5)
	world.set_progress(world.get_traversal_length())

	assert_eq(emissions[0], 3, "Real progress steps, including the finish, must still be broadcast")
	assert_almost_eq(world.get_difficulty(), 1.0, 0.0001)


func test_platform_queries_take_world_space_under_a_moved_world() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	world.position = Vector2(640.0, 128.0)
	add_child_autofree(world)
	var platforms: Array[Dictionary] = [
		{"platform_id": 3, "start_x": 4, "end_x": 9, "width": 6, "height": 12},
	]
	world.set("_platforms", platforms)

	var inside: Dictionary = world.get_platform_below(world.to_global(Vector2(6.0 * TILE, 0.0)).x)
	assert_eq(int(inside.get("platform_id", -1)), 3, "get_platform_below should read world-space X")

	var upcoming: Array[Dictionary] = world.get_upcoming_platforms(world.to_global(Vector2(5.0 * TILE, 0.0)).x, 3)
	assert_eq(upcoming.size(), 1, "get_upcoming_platforms should read world-space X")

	var behind: Array[Dictionary] = world.get_upcoming_platforms(world.to_global(Vector2(40.0 * TILE, 0.0)).x, 3)
	assert_eq(behind.size(), 0, "Platforms already passed must not be reported as upcoming")


func test_platform_surface_position_is_reported_in_world_space() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	world.position = Vector2(640.0, 128.0)
	add_child_autofree(world)

	var surface: Vector2 = world.get_platform_surface_position({"start_x": 4, "width": 6, "height": 12})

	assert_eq(surface, Vector2(640.0 + 7.0 * TILE, 128.0 + 12.0 * TILE), "Observation geometry must be comparable with the player's global position")


func test_retry_attempt_records_completion_and_keeps_cumulative_metrics() -> void:
	var session: Variant = RUN_SESSION_SCRIPT.new()
	assert_true(session.has_method("begin_retry_attempt"), "A retry needs a telemetry boundary so its events are not lost when the failed attempt closes")
	if not session.has_method("begin_retry_attempt"):
		session.free()
		return

	session.set("_playtest_enabled", true)
	session.begin_run(2, 0, "authored", "static", "level_02_recovery.tscn")
	var first_attempt_path: String = str(session.get("_playtest_path"))
	session.record_damage()
	session.record_checkpoint(2, Vector2(128.0, 64.0))
	session.set("_run_started_msec", Time.get_ticks_msec() - 2000)
	var failed_metrics: Dictionary = session.finish_run_metrics("failed")
	session.set_run_outcome("failed")

	session.begin_retry_attempt()
	var retry_attempt_path: String = str(session.get("_playtest_path"))
	session.record_respawn()
	session.set("_run_started_msec", Time.get_ticks_msec() - 3000)
	var completed_metrics: Dictionary = session.finish_run_metrics("completed")

	assert_ne(first_attempt_path, retry_attempt_path, "Retries should have a separate JSONL file so each attempt retains its terminal outcome")
	assert_eq(int(session.get("run_attempt_index")), 2)
	assert_eq(int(completed_metrics.get("damage", -1)), 1, "Retrying should retain damage across the route attempt")
	assert_eq(int(completed_metrics.get("checkpoint_activations", -1)), 1)
	assert_eq(int(completed_metrics.get("checkpoint_recoveries", -1)), 1)
	assert_gt(float(completed_metrics.get("time_s", 0.0)), float(failed_metrics.get("time_s", 0.0)) + 2.5, "The completed record should include both attempt durations")

	var first_lines: PackedStringArray = FileAccess.get_file_as_string(first_attempt_path).strip_edges().split("\n")
	var retry_lines: PackedStringArray = FileAccess.get_file_as_string(retry_attempt_path).strip_edges().split("\n")
	var first_end: Dictionary = JSON.parse_string(first_lines[-1])
	var retry_start: Dictionary = JSON.parse_string(retry_lines[0])
	var retry_end: Dictionary = JSON.parse_string(retry_lines[-1])
	var retry_events: Array[Dictionary] = []
	for line: String in retry_lines:
		var event: Variant = JSON.parse_string(line)
		if event is Dictionary:
			retry_events.append(event)
	var has_respawn_event: bool = false
	for event: Dictionary in retry_events:
		if str(event.get("event", "")) == "checkpoint_respawn":
			has_respawn_event = true
	assert_eq(str(first_end.get("event", "")), "run_finished")
	assert_eq(str((first_end.get("data", {}) as Dictionary).get("outcome", "")), "failed")
	assert_eq(int((retry_start.get("data", {}) as Dictionary).get("attempt", -1)), 2)
	assert_true(bool((retry_start.get("data", {}) as Dictionary).get("retry", false)))
	assert_true(has_respawn_event, "Checkpoint recovery should be present in the retry's telemetry file")
	assert_eq(str(retry_end.get("event", "")), "run_finished")
	assert_eq(str((retry_end.get("data", {}) as Dictionary).get("outcome", "")), "completed")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(first_attempt_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(retry_attempt_path))
	session.free()


func test_semantic_lookup_follows_the_world_transform() -> void:
	var world: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	add_child_autofree(world)
	var sample_x: float = 3.0 * TILE + 16.0
	var sample_y: float = 14.0 * TILE + 16.0
	var expected: int = world.get_semantic_value(sample_x, sample_y)
	assert_ne(expected, 0, "The sample cell must be an authored tile, or this test proves nothing")

	var moved: RunUnitStaticWorld = WORLD_SCENE.instantiate() as RunUnitStaticWorld
	moved.position = Vector2(640.0, 128.0)
	add_child_autofree(moved)

	assert_eq(moved.get_semantic_value(sample_x + 640.0, sample_y + 128.0), expected, "The same authored cell should answer the same under a moved world")
