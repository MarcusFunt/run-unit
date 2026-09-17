class_name RunUnitModuleCradle
extends Area2D

## The Reserve Depot 03 storage cradle in Level 2 (StorylineSketch.md, "Module
## acquisition"). Driving UNIT-07 into it moves the replacement ignition module
## from the cradle onto the robot, where it stays visible for the rest of the
## run, and switches the depot into its shutdown state. The module is a passive
## mission object: nothing here gives the player a new ability.

signal module_acquired

## Where the module sits on the robot's back, in BodyPivot space (source-art
## pixels, authored facing left, so +x is behind the robot).
@export var mount_offset: Vector2 = Vector2(165.0, -30.0)
@export var mount_scale: float = 4.4
## Nodes that only exist once the reserve component has been removed.
@export var shutdown_nodes: Array[NodePath] = []

@onready var cradle_module: Node2D = $CradleModule
@onready var acquisition_readout: Label = $AcquisitionReadout

var acquired: bool = false
var _mounted_module: Node2D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	reset_level_state()

## Called by RunUnitStaticWorld.reset() whenever a run (re)starts.
func reset_level_state() -> void:
	acquired = false
	if is_instance_valid(_mounted_module):
		_mounted_module.get_parent().remove_child(_mounted_module)
		_mounted_module.free()
	_mounted_module = null
	cradle_module.visible = true
	acquisition_readout.visible = false
	_set_shutdown(false)

func get_mounted_module() -> Node2D:
	return _mounted_module if is_instance_valid(_mounted_module) else null

func acquire_for(player: RunUnitPlayerMotor) -> void:
	if acquired or player == null:
		return
	acquired = true
	cradle_module.visible = false
	var module: Node2D = cradle_module.duplicate() as Node2D
	module.name = "MountedModule"
	module.visible = true
	# Behind the body so the robot reads as carrying it, not wearing it.
	module.z_index = -1
	var mount_parent: Node2D = player.get_node_or_null("RobotVisual/BodyPivot") as Node2D
	if mount_parent == null:
		mount_parent = player
		module.position = Vector2(0.0, -40.0)
		module.scale = Vector2.ONE
	else:
		module.position = mount_offset
		module.scale = Vector2.ONE * mount_scale
	mount_parent.add_child(module)
	_mounted_module = module
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
