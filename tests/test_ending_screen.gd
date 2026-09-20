extends GutTest

## The ending screen the game finishes on (scenes/ending.tscn): the restored
## city with Beacon 9 lit, and the thank-you.

const ENDING_SCENE: PackedScene = preload("res://scenes/ending.tscn")


func _instantiate_ending() -> RunUnitEnding:
	var ending: RunUnitEnding = ENDING_SCENE.instantiate() as RunUnitEnding
	add_child_autofree(ending)
	return ending


func after_each() -> void:
	RunUnitSession.clear_checkpoint()
	RunUnitSession.demo_mode = false
	RunUnitSession.reset_demo_lifecycle()


func test_the_ending_thanks_the_player() -> void:
	var ending: RunUnitEnding = _instantiate_ending()

	assert_eq(ending.thanks_label.text, "THANK YOU FOR PLAYING")
	assert_true(ending.status_label.text.contains("BEACON 9 ONLINE"), "The ending states what UNIT-07 achieved")
	assert_eq(ending.sector_button.text, "SECTOR SELECT")
	assert_eq(ending.menu_button.text, "MAIN MENU")


func test_the_ending_shows_the_restored_city() -> void:
	var ending: RunUnitEnding = _instantiate_ending()

	assert_not_null(ending.vista.texture, "The ending screen shows the restored city")
	assert_eq(ending.vista.texture.resource_path, "res://assets/generated/converted/ending/ending_beacon_vista_320x180.png")
	assert_eq(ending.vista.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "The vista fills the screen at any window size")


## The illustration is drawn at the game's own pixel density and sampled the
## way the tile art is, so the ending does not read as a different game.
func test_the_vista_matches_the_games_pixel_density() -> void:
	var ending: RunUnitEnding = _instantiate_ending()

	assert_eq(ending.vista.texture.get_size(), Vector2(320.0, 180.0), "The vista is authored at a third of the viewport, then drawn up")
	assert_eq(ending.vista.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "Nearest sampling keeps the pixels square")


## A still frame reads as a screenshot, so the scene keeps moving: the beacon
## breathes, the refinery smokes, and UNIT-07 stands there watching it.
func test_the_ending_is_not_a_still_frame() -> void:
	var ending: RunUnitEnding = _instantiate_ending()
	var steam: CPUParticles2D = ending.get_node("%Steam") as CPUParticles2D
	var embers: CPUParticles2D = ending.get_node("%Embers") as CPUParticles2D

	assert_true(steam.emitting, "Steam drifts off the refinery")
	assert_true(embers.emitting, "Embers drift up through the foreground")
	assert_gt(ending.twinkles.get_child_count(), 0, "Windows blink across the city")
	assert_not_null(ending.unit_07, "UNIT-07 is in frame for the last shot of the game")
	assert_lt(ending.unit_07.scale.x, 0.0, "UNIT-07 faces the beacon it just restored")

	var column_alpha: float = ending.beacon_column.modulate.a
	var unit_y: float = ending.unit_07.position.y
	await wait_seconds(0.9)

	assert_ne(ending.beacon_column.modulate.a, column_alpha, "The ignition column keeps pulsing")
	assert_ne(ending.unit_07.position.y, unit_y, "UNIT-07 idles rather than freezing")


func test_the_ending_reveals_its_copy_and_then_its_buttons() -> void:
	var ending: RunUnitEnding = _instantiate_ending()
	ending.status_delay = 0.05
	ending.thanks_delay = 0.1
	ending.buttons_delay = 0.15
	ending.fade_duration = 0.05
	# _ready() already built the reveal from the authored timings, so run it again.
	ending._ready()
	assert_almost_eq(ending.thanks_label.modulate.a, 0.0, 0.01, "The thank-you fades in rather than popping")

	await wait_seconds(1.0)

	assert_almost_eq(ending.status_label.modulate.a, 1.0, 0.01)
	assert_almost_eq(ending.thanks_label.modulate.a, 1.0, 0.01)
	assert_almost_eq(ending.buttons.modulate.a, 1.0, 0.01, "The player is offered somewhere to go afterwards")


func test_reaching_the_ending_clears_any_route_checkpoint() -> void:
	RunUnitSession.record_checkpoint(3, Vector2(9000.0, 700.0))

	_instantiate_ending()

	assert_false(RunUnitSession.has_checkpoint(3), "Finishing the campaign should not leave a route mid-run")


func test_demo_ending_marks_the_campaign_terminal_exactly_once() -> void:
	RunUnitSession.demo_mode = true
	RunUnitSession.reset_demo_lifecycle()
	RunUnitSession.record_demo_route_start(0)
	RunUnitSession.record_demo_route_start(1)
	RunUnitSession.record_demo_route_start(2)
	RunUnitSession.record_demo_route_start(3)
	var ending: RunUnitEnding = ENDING_SCENE.instantiate() as RunUnitEnding
	ending.auto_quit_demo = false
	add_child_autofree(ending)

	assert_true(RunUnitSession.demo_completed, "Reaching the ending makes a hands-off run process-terminal")
	assert_eq(RunUnitSession.demo_completion_count, 1, "The campaign should be completed exactly once")
	assert_false(RunUnitSession.should_start_demo(), "A completed demo must never auto-start route 0 again")
	assert_false(RunUnitSession.mark_demo_completed(), "A duplicate ending cannot count as another completion")
	assert_eq(RunUnitSession.demo_completion_count, 1, "Duplicate completion requests stay idempotent")
	assert_eq(RunUnitSession.demo_route_starts, [0, 1, 2, 3], "One complete demo contains exactly the four campaign routes")


func test_the_vista_pushes_in_slowly() -> void:
	var ending: RunUnitEnding = _instantiate_ending()
	var before: float = ending.vista.scale.x

	await wait_seconds(0.4)

	assert_gt(ending.vista.scale.x, before, "The vista keeps moving under the ending copy")
	assert_lt(ending.vista.scale.x, ending.push_in_scale + 0.001, "The push in never overshoots its authored limit")
