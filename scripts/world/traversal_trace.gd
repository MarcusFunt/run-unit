class_name RunUnitTraversalTrace
extends RefCounted

var seed_value: int = 0
var events: Array[Dictionary] = []
var started_at_msec: int = 0

func begin(trace_seed: int) -> void:
	seed_value = trace_seed
	started_at_msec = Time.get_ticks_msec()
	events.clear()

func record(event_name: String, position: Vector2, velocity: Vector2, platform_id: int = -1) -> void:
	events.append({
		"event": event_name,
		"time_msec": Time.get_ticks_msec() - started_at_msec,
		"position": {"x": position.x, "y": position.y},
		"velocity": {"x": velocity.x, "y": velocity.y},
		"platform_id": platform_id,
	})

func export_data() -> Dictionary:
	return {"seed": seed_value, "started_at_msec": started_at_msec, "events": events.duplicate(true)}
