class_name MenuParallaxBackground
extends Node2D

@export var drift_pixels_per_second: float = 6.0

@onready var city_parallax: Node2D = $CityParallax

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	for child: Node in city_parallax.get_children():
		var layer: Parallax2D = child as Parallax2D
		if layer != null:
			layer.scroll_offset.x -= drift_pixels_per_second * layer.scroll_scale.x * delta
