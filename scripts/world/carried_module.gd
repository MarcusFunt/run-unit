class_name RunUnitCarriedModule
extends Node2D

## The replacement ignition module UNIT-07 recovered in Level 2.
##
## Level 3 opens with it already mounted, so this node puts it back on the
## robot whenever a run starts and takes it off again when it is installed into
## Beacon 9. It carries no behaviour of its own: the module is a mission
## object, not a tool.

@onready var module_template: Node2D = $ModuleTemplate

var _mounted_module: Node2D = null

func _ready() -> void:
	module_template.visible = false
	reset_level_state()

## Called by RunUnitStaticWorld.reset() whenever a run (re)starts.
func reset_level_state() -> void:
	RunUnitModuleMount.clear(_mounted_module)
	_mounted_module = null
	var player: RunUnitPlayerMotor = _find_player()
	if player != null:
		_mounted_module = RunUnitModuleMount.mount(player, module_template)

func get_mounted_module() -> Node2D:
	return _mounted_module if is_instance_valid(_mounted_module) else null

func is_carried() -> bool:
	return get_mounted_module() != null

## Takes the module off the robot, for the moment it is installed.
func stow() -> void:
	RunUnitModuleMount.clear(_mounted_module)
	_mounted_module = null

## The player is a sibling of the world rather than a child of it, so walk up
## from here until a robot turns up. A level opened on its own has none, and
## simply shows no carried module.
func _find_player() -> RunUnitPlayerMotor:
	var host: Node = get_parent()
	while host != null:
		for child: Node in host.get_children():
			if child is RunUnitPlayerMotor:
				return child as RunUnitPlayerMotor
		host = host.get_parent()
	return null
