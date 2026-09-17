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
			# Parallax2D already multiplies scroll_offset by scroll_scale when
			# rendering, so drive all layers by the same base offset here and
			# let the engine apply each layer's own scroll_scale for depth.
			layer.scroll_offset.x -= drift_pixels_per_second * delta
