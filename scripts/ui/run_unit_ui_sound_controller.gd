extends "res://addons/maaacks_menus_template/base/nodes/autoloads/ui_sound_controller/ui_sound_controller.gd"

const HOVER_PATH := "res://assets/audio/run_unit/ui_hover.ogg"
const PRESS_PATH := "res://assets/audio/run_unit/ui_press.ogg"

func _ready() -> void:
	# Editor import creates autoloads before newly-added audio has been scanned.
	# Defer loading the custom sounds to actual game/test runtime.
	if not Engine.is_editor_hint():
		var hover := load(HOVER_PATH) as AudioStream
		var press := load(PRESS_PATH) as AudioStream
		button_hovered = hover
		button_focused = hover
		tab_hovered = hover
		slider_hovered = hover
		line_hovered = hover
		button_pressed = press
		tab_changed = press
		tab_selected = press
		slider_drag_started = press
		slider_drag_ended = press
		line_text_submitted = press
		item_list_selected = press
		item_list_activated = press
		tree_item_selected = press
		tree_item_activated = press
		tree_button_clicked = press
	super._ready()
