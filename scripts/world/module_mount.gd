class_name RunUnitModuleMount
extends RefCounted

## Where the replacement ignition module rides on UNIT-07.
##
## Level 2 mounts it when the module is taken out of its cradle and Level 3
## starts with it already mounted, so both levels place it the same way: on the
## robot's back, behind the body, in BodyPivot space (source-art pixels,
## authored facing left, so +x is behind the robot).

const MOUNT_PARENT: String = "RobotVisual/BodyPivot"
const MOUNT_NAME: StringName = &"MountedModule"
const MOUNT_OFFSET: Vector2 = Vector2(165.0, -30.0)
const MOUNT_SCALE: float = 4.4
## Used when the robot has no visual rig to hang the module on.
const FALLBACK_OFFSET: Vector2 = Vector2(0.0, -40.0)

## Copies `template` onto the player and returns the mounted copy.
static func mount(player: RunUnitPlayerMotor, template: Node2D) -> Node2D:
	if player == null or template == null:
		return null
	var module: Node2D = template.duplicate() as Node2D
	module.name = MOUNT_NAME
	module.visible = true
	# Behind the body, so the robot reads as carrying it rather than wearing it.
	module.z_index = -1
	var mount_parent: Node2D = player.get_node_or_null(MOUNT_PARENT) as Node2D
	if mount_parent == null:
		mount_parent = player
		module.position = FALLBACK_OFFSET
		module.scale = Vector2.ONE
	else:
		module.position = MOUNT_OFFSET
		module.scale = Vector2.ONE * MOUNT_SCALE
	mount_parent.add_child(module)
	return module

## Takes a mounted module back off the robot.
static func clear(module: Node2D) -> void:
	if not is_instance_valid(module):
		return
	module.get_parent().remove_child(module)
	module.free()
