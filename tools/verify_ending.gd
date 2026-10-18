extends SceneTree

# Integration smoke, not a unit test: boots the actual Game scene, triggers the
# authored completion zone, holds and releases jump, and waits for Ending.
const ENDING_PATH := "res://scenes/ending.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session: Node = root.get_node_or_null("RunUnitSession")
	if session == null:
		push_error("ENDING_SMOKE no RunUnitSession autoload")
		quit(1)
		return
	session.set("debug_unlock_routes", true)
	session.set("demo_mode", false)
	session.set("selected_level_index", 3)
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var world: Node = game.get_node("World")
	var player: Node2D = game.get_node("Player") as Node2D
	var ignition: Node = game.get_node("World/IgnitionChamber")
	if ignition == null:
		push_error("ENDING_SMOKE missing ignition chamber")
		quit(1)
		return
	player.global_position = world.call("get_goal_position")
	# The *physics* overlap must fire the authored Goal trigger; calling its
	# callback by hand would miss the exact regression we are checking.
	for step: int in range(8):
		await physics_frame
		if bool(ignition.call("is_interaction_active")):
			break
	if not bool(ignition.call("is_interaction_active")):
		push_error("ENDING_SMOKE goal did not open ignition interaction")
		quit(1)
		return
	print("ENDING_SMOKE physical Goal contact -> ignition interaction OK")
	Input.action_press("jump")
	await create_timer(0.65).timeout
	Input.action_release("jump")
	await create_timer(0.25).timeout
	if session.get("last_run_outcome") != "completed":
		push_error("ENDING_SMOKE full charge not accepted: %s" % str(session.get("last_run_outcome")))
		quit(1)
		return
	print("ENDING_SMOKE full charge -> route completed OK")
	var deadline: int = Time.get_ticks_msec() + 16000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.15).timeout
		if current_scene != null and current_scene.scene_file_path == ENDING_PATH:
			if current_scene.get_node_or_null("UI/Buttons") == null:
				push_error("ENDING_SMOKE ending scene missing controls")
				quit(1)
				return
			print("ENDING_SMOKE ending scene reached and controls loaded")
			await create_timer(4.0).timeout
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/ending-check"))
			await RenderingServer.frame_post_draw
			var screenshot: Image = root.get_texture().get_image()
			var err: Error = screenshot.save_png("res://build/ending-check/ending.png")
			if err != OK:
				push_error("ENDING_SMOKE screenshot save error %d" % err)
				quit(1)
				return
			print("ENDING_SMOKE PASSED")
			quit(0)
			return
	push_error("ENDING_SMOKE timed out waiting for ending screen: current=%s" % str(current_scene.scene_file_path if current_scene != null else "(none)"))
	quit(1)
