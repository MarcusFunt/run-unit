class_name RunUnitBeaconIgnition
extends RunUnitRouteExit

## Beacon 9's ignition chamber, and the module's first and only use.
##
## Reaching the interface completes the route, so this exit plays the ending:
## UNIT-07 seats the module it has carried since Level 2, and after a beat the
## activation propagates outward one stage at a time -- interface, conduits,
## chamber machinery, the beacon's internal systems, its exterior structure,
## and finally the city through the chamber window -- before the fade to the
## credits. The module is consumed here; nothing about it is reusable.

signal module_installed

## The Level 3 node holding the module while it rides on the robot.
@export var carried_module_path: NodePath
## Activation stages, in the order they light up.
@export var stage_paths: Array[NodePath] = []
@export_range(0.1, 3.0, 0.05) var install_delay: float = 0.8
@export_range(0.1, 2.0, 0.05) var stage_interval: float = 0.5
@export_range(0.0, 5.0, 0.1) var hold_after_activation: float = 2.0
@export_range(0.1, 3.0, 0.05) var fade_duration: float = 1.1

@onready var seated_module: Node2D = $SeatedModule
@onready var blackout: ColorRect = $BlackoutLayer/Blackout

var installed: bool = false
## How many activation stages have lit so far, so the ending can be asserted on.
var lit_stages: int = 0

var _sequence: Tween

func reset_transition() -> void:
	super()
	if _sequence != null and _sequence.is_valid():
		_sequence.kill()
	installed = false
	lit_stages = 0
	seated_module.visible = false
	for path: NodePath in stage_paths:
		var stage: CanvasItem = get_node_or_null(path) as CanvasItem
		if stage != null:
			stage.visible = false
			stage.modulate.a = 0.0
	var blackout_color: Color = blackout.color
	blackout_color.a = 0.0
	blackout.color = blackout_color

func begin_transition() -> void:
	if transition_started:
		return
	transition_started = true
	_sequence = create_tween()
	_sequence.tween_interval(install_delay)
	_sequence.tween_callback(_install_module)
	for index: int in stage_paths.size():
		_sequence.tween_interval(stage_interval)
		_sequence.tween_callback(_light_stage.bind(index))
	_sequence.tween_interval(hold_after_activation)
	_sequence.tween_property(blackout, "color:a", 1.0, fade_duration)
	_sequence.tween_callback(finish_transition)

## The module leaves UNIT-07 for good and seats into the interface.
func _install_module() -> void:
	var carried: RunUnitCarriedModule = get_node_or_null(carried_module_path) as RunUnitCarriedModule
	if carried != null:
		carried.stow()
	seated_module.visible = true
	installed = true
	module_installed.emit()

func _light_stage(index: int) -> void:
	if index < 0 or index >= stage_paths.size():
		return
	var stage: CanvasItem = get_node_or_null(stage_paths[index]) as CanvasItem
	if stage == null:
		return
	stage.visible = true
	stage.modulate.a = 0.0
	create_tween().tween_property(stage, "modulate:a", 1.0, stage_interval)
	lit_stages += 1
