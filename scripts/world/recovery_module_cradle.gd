class_name RunUnitModuleCradle
extends Area2D

## The Reserve Depot 03 storage cradle in Level 2 (StorylineSketch.md, "Module
## acquisition"). Driving UNIT-07 into it moves the replacement ignition module
## from the cradle onto the robot, where it stays visible for the rest of the
## run, and switches the depot into its shutdown state. The module is a passive
## mission object: nothing here gives the player a new ability.

signal module_acquired

## Nodes that only exist once the reserve component has been removed.
@export var shutdown_nodes: Array[NodePath] = []

@onready var cradle_module: Node2D = $CradleModule
@onready var acquisition_readout: Label = $AcquisitionReadout

var acquired: bool = false
var _mounted_module: Node2D = null

func _process(delta: float) -> void:
	if acquired:
		return
	var halo: Polygon2D = get_node_or_null("ObjectiveHalo") as Polygon2D
	if halo != null:
		halo.modulate.a = 0.84 + 0.16 * sin(Time.get_ticks_msec() * 0.001 * 2.0)

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	reset_level_state()

## Called by RunUnitStaticWorld.reset() whenever a run (re)starts.
func reset_level_state() -> void:
	acquired = false
	RunUnitModuleMount.clear(_mounted_module)
	_mounted_module = null
	cradle_module.visible = true
	get_node("ObjectiveHalo").visible = true
	get_node("ModuleName").visible = true
	acquisition_readout.visible = false
	_set_shutdown(false)

func get_mounted_module() -> Node2D:
	return _mounted_module if is_instance_valid(_mounted_module) else null

func acquire_for(player: RunUnitPlayerMotor) -> void:
	if acquired or player == null:
		return
	acquired = true
	cradle_module.visible = false
	get_node("ObjectiveHalo").visible = false
	get_node("ModuleName").visible = false
	_mounted_module = RunUnitModuleMount.mount(player, cradle_module)
	acquisition_readout.visible = true
	_set_shutdown(true)
	module_acquired.emit()

func _set_shutdown(active: bool) -> void:
	for path: NodePath in shutdown_nodes:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = active

func _on_body_entered(body: Node2D) -> void:
	if body is RunUnitPlayerMotor:
		acquire_for(body as RunUnitPlayerMotor)
