class_name RunUnitDebugOverlay
extends CanvasLayer

@onready var info_label: Label = %InfoLabel

func set_debug_text(text_value: String) -> void:
	info_label.text = text_value

func set_open(value: bool) -> void:
	visible = value
