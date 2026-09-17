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


func test_the_ending_thanks_the_player() -> void:
	var ending: RunUnitEnding = _instantiate_ending()

	assert_eq(ending.thanks_label.text, "THANK YOU FOR PLAYING")
	assert_true(ending.status_label.text.contains("BEACON 9 ONLINE"), "The ending states what UNIT-07 achieved")
	assert_eq(ending.sector_button.text, "SECTOR SELECT")
	assert_eq(ending.menu_button.text, "MAIN MENU")


func test_the_ending_shows_the_restored_city() -> void:
	var ending: RunUnitEnding = _instantiate_ending()

	assert_not_null(ending.vista.texture, "The ending screen shows the restored city")
	assert_eq(ending.vista.texture.resource_path, "res://assets/images/ending_beacon_vista.png")
	assert_eq(ending.vista.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "The vista fills the screen at any window size")


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


func test_the_vista_pushes_in_slowly() -> void:
	var ending: RunUnitEnding = _instantiate_ending()
	var before: float = ending.vista.scale.x

	await wait_seconds(0.4)

	assert_gt(ending.vista.scale.x, before, "The vista keeps moving under the ending copy")
	assert_lt(ending.vista.scale.x, ending.push_in_scale + 0.001, "The push in never overshoots its authored limit")
