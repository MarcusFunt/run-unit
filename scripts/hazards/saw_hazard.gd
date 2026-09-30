class_name RunUnitSawHazard
extends RunUnitHazardArea

@export_range(-20.0, 20.0, 0.1) var spin_speed: float = 7.5

var _blade: Node2D = null

func _ready() -> void:
	_blade = get_node_or_null("ActiveVisual") as Node2D
	super._ready()

func _physics_process(delta: float) -> void:
	if _blade != null:
		_blade.rotation += spin_speed * delta
