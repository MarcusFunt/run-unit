extends SceneTree

# Temporary showcase capture: positions the real player on authored support and
# renders actual Godot frames. No screenshots are checked into the repository.
const SHOTS := [
	{"route": 0, "name": "01-calibration-spring", "center": Vector2(1180, 315)},
	{"route": 1, "name": "02-factory-storage", "center": Vector2(3850, 525)},
	{"route": 1, "name": "03-factory-exterior", "center": Vector2(7300, 575)},
	{"route": 2, "name": "04-recovery-depot", "center": Vector2(3730, 520)},
	{"route": 2, "name": "05-recovery-reserve-module", "center": Vector2(7920, 525)},
	{"route": 3, "name": "06-beacon-rooftops", "center": Vector2(1650, 450)},
	{"route": 3, "name": "07-beacon-service-ascent", "center": Vector2(12200, 390)},
	{"route": 3, "name": "08-beacon-ignition", "center": Vector2(15520, 185)},
]

func _initialize() -> void:
	call_deferred("_capture_all")

func _capture_all() -> void:
	var session: Node = root.get_node_or_null("RunUnitSession")
	if session == null:
		push_error("RunUnitSession autoload missing")
		quit(1)
		return
	session.set("debug_unlock_routes", true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/highlights"))
	var failures: int = 0
	for shot: Dictionary in SHOTS:
		session.set("selected_level_index", int(shot["route"]))
		var game: Node2D = load("res://scenes/game.tscn").instantiate() as Node2D
		root.add_child(game)
		current_scene = game
		await process_frame
		await process_frame
		var world: Node2D = game.get_node("World") as Node2D
		var player: CharacterBody2D = game.get_node("Player") as CharacterBody2D
		var camera: Camera2D = player.get_node("Camera2D") as Camera2D
		game.get_node("HumanController").set_physics_process(false)
		game.get_node("ScriptedController").set_physics_process(false)
		player.set_physics_process(false)
		camera.set_physics_process(false)
		var target: Vector2 = shot["center"]
		var player_x: float = target.x - 270.0
		var platform: Dictionary = {}
		for step: int in range(8):
			platform = world.call("get_platform_below_position", Vector2(player_x, target.y - 120.0))
			if not platform.is_empty():
				break
			player_x += 32.0
		if not platform.is_empty():
			var surface: float = world.to_global(Vector2(0.0, float(platform.get("height", 15)) * float(world.get("tile_size")))).y
			player.global_position = Vector2(player_x, surface - 31.0)
		else:
			player.global_position = Vector2(player_x, target.y + 110.0)
		camera.global_position = target
		camera.force_update_scroll()
		for frame: int in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		var filepath: String = "res://build/highlights/%s.png" % str(shot["name"])
		var err: Error = screenshot.save_png(filepath)
		if err != OK:
			push_error("Screenshot failed: %s / %s" % [filepath, str(err)])
			failures += 1
		else:
			print("HIGHLIGHT_CAPTURED %s (%d x %d)" % [filepath, screenshot.get_width(), screenshot.get_height()])
		current_scene = null
		root.remove_child(game)
		game.queue_free()
		await process_frame
	print("HIGHLIGHT_FINISHED: %d images, %d failures" % [SHOTS.size(), failures])
	quit(1 if failures > 0 else 0)
