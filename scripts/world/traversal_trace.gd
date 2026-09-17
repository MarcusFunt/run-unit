class_name RunUnitTraversalTrace
extends RefCounted

## A run has no time limit, so a per-physics-frame sample stream grows without
## bound (60 dictionaries per second, deep-copied again on export). Samples get
## a fixed budget and are dropped once it is spent; named events -- obstacle
## hits and the terminal record -- are always kept so an exported trace still
## explains how the run ended.
const MAX_SAMPLE_EVENTS: int = 2048

var seed_value: int = 0
var events: Array[Dictionary] = []
var started_at_msec: int = 0
var dropped_samples: int = 0

var _sample_count: int = 0

func begin(trace_seed: int) -> void:
	seed_value = trace_seed
	started_at_msec = Time.get_ticks_msec()
	events.clear()
	_sample_count = 0
	dropped_samples = 0

func record(event_name: String, position: Vector2, velocity: Vector2, platform_id: int = -1) -> void:
	events.append(_make_event(event_name, position, velocity, platform_id))

## Budgeted variant for the high-frequency positional stream.
func record_sample(position: Vector2, velocity: Vector2, platform_id: int = -1) -> void:
	if _sample_count >= MAX_SAMPLE_EVENTS:
		dropped_samples += 1
		return
	_sample_count += 1
	events.append(_make_event("sample", position, velocity, platform_id))

func export_data() -> Dictionary:
	return {
		"seed": seed_value,
		"started_at_msec": started_at_msec,
		"dropped_samples": dropped_samples,
		"events": events.duplicate(true),
	}

func _make_event(event_name: String, position: Vector2, velocity: Vector2, platform_id: int) -> Dictionary:
	return {
		"event": event_name,
		"time_msec": Time.get_ticks_msec() - started_at_msec,
		"position": {"x": position.x, "y": position.y},
		"velocity": {"x": velocity.x, "y": velocity.y},
		"platform_id": platform_id,
	}
