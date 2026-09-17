class_name RunUnitRouteExit
extends Node2D

## A level-owned ending.
##
## When a run completes, RunUnitGame hands control to the route's exit instead
## of opening the results menu: the tutorial closes its transfer door, Beacon 9
## installs the module and lights up. The exit reports back through
## `transition_finished`, then loads `next_scene_path`; an exit that leaves that
## path empty falls back to the results menu, so a level can own its ending
## without owning what comes after it.

signal transition_finished

@export_file("*.tscn") var next_scene_path: String = ""

var transition_started: bool = false

func _ready() -> void:
	reset_transition()

## Called whenever a run (re)starts, so an ending that was already played does
## not stay played on the retry.
func reset_transition() -> void:
	transition_started = false

## Overridden per level. The base ending is instant.
func begin_transition() -> void:
	if transition_started:
		return
	transition_started = true
	finish_transition()

## Ends the transition and hands off to the next scene, if this exit names one.
func finish_transition() -> void:
	transition_finished.emit()
	if next_scene_path.is_empty():
		return
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	if scene_loader != null and scene_loader.has_method("load_scene"):
		scene_loader.call("load_scene", next_scene_path)
	else:
		get_tree().change_scene_to_file(next_scene_path)
