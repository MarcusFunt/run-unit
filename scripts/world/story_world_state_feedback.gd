extends Node2D

## Spatial signals that make authored story changes visible in the level.
## Every element is draw-only; Tiled remains the sole owner of route collision.

var _world_root: Node2D = null
var _visuals_by_zone: Dictionary = {}

func bind_world(world_root: Node2D) -> void:
	_world_root = world_root
	z_index = 2

func register_zone(zone_name: String, world_change: String, zone: Area2D) -> void:
	if _world_root == null:
		return
	var shape_node: CollisionShape2D = null
	for child: Node in zone.get_children():
		if child is CollisionShape2D:
			shape_node = child as CollisionShape2D
			break
	if shape_node == null:
		return
	var zone_shape: RectangleShape2D = shape_node.shape as RectangleShape2D
	if zone_shape == null:
		return
	var center_global: Vector2 = shape_node.global_position
	var center_local: Vector2 = _world_root.to_local(center_global)
	var left_global: Vector2 = Vector2(center_global.x - zone_shape.size.x * 0.5, center_global.y)
	var left_local: Vector2 = _world_root.to_local(left_global)
	var visual: Node2D = Node2D.new()
	visual.name = zone_name
	add_child(visual)
	_visuals_by_zone[zone_name] = {"state": world_change, "visual": visual}

	match world_change:
		"structure_shift":
			_build_structure_shift(visual, center_local + Vector2(-48.0, 24.0))
		"route_open":
			_build_route_gate(visual, Vector2(left_local.x + 48.0, center_local.y + 80.0))
		"hazard_field_cleared":
			_build_beacon_field(visual, Vector2(left_local.x + 128.0, center_local.y))

func apply_world_change(zone_name: String) -> void:
	var entry: Dictionary = _visuals_by_zone.get(zone_name, {})
	var visual: Node2D = entry.get("visual") as Node2D
	if visual == null or visual.get_meta("activated", false):
		return
	visual.set_meta("activated", true)
	var world_change: String = str(entry.get("state", ""))
	match world_change:
		"structure_shift":
			_animate_structure_shift(visual)
		"route_open":
			_animate_route_open(visual)
		"hazard_field_cleared":
			_animate_field_clear(visual)

func _build_structure_shift(visual: Node2D, world_position: Vector2) -> void:
	visual.position = world_position
	_add_box(visual, "LeftSupport", Vector2(-92.0, -6.0), Vector2(14.0, 108.0), Color(0.11, 0.20, 0.23, 1.0))
	_add_box(visual, "RightSupport", Vector2(92.0, -6.0), Vector2(14.0, 108.0), Color(0.11, 0.20, 0.23, 1.0))
	var beam: Polygon2D = _add_box(visual, "FallingBeam", Vector2(0.0, -48.0), Vector2(236.0, 24.0), Color(0.20, 0.31, 0.33, 1.0))
	_add_box(beam, "WarningStripe", Vector2(0.0, 6.0), Vector2(216.0, 5.0), Color(1.0, 0.57, 0.14, 1.0))
	_add_box(visual, "ShiftLamp", Vector2(0.0, -72.0), Vector2(42.0, 9.0), Color(1.0, 0.47, 0.10, 1.0))

func _build_route_gate(visual: Node2D, world_position: Vector2) -> void:
	visual.position = world_position
	_add_box(visual, "LeftFrame", Vector2(-48.0, -4.0), Vector2(10.0, 176.0), Color(0.22, 0.37, 0.39, 1.0))
	_add_box(visual, "RightFrame", Vector2(48.0, -4.0), Vector2(10.0, 176.0), Color(0.22, 0.37, 0.39, 1.0))
	_add_box(visual, "LeftShutter", Vector2(-28.0, -4.0), Vector2(48.0, 154.0), Color(0.14, 0.23, 0.26, 1.0))
	_add_box(visual, "RightShutter", Vector2(28.0, -4.0), Vector2(48.0, 154.0), Color(0.14, 0.23, 0.26, 1.0))
	_add_box(visual, "OpenIndicator", Vector2(0.0, -94.0), Vector2(120.0, 10.0), Color(0.22, 0.34, 0.39, 0.92))

func _build_beacon_field(visual: Node2D, world_position: Vector2) -> void:
	visual.position = world_position
	var left_emitter: Polygon2D = _add_box(visual, "LeftEmitter", Vector2(-116.0, 0.0), Vector2(22.0, 204.0), Color(0.12, 0.22, 0.25, 1.0))
	var right_emitter: Polygon2D = _add_box(visual, "RightEmitter", Vector2(116.0, 0.0), Vector2(22.0, 204.0), Color(0.12, 0.22, 0.25, 1.0))
	_add_box(left_emitter, "StatusLamp", Vector2(0.0, -82.0), Vector2(14.0, 18.0), Color(1.0, 0.50, 0.12, 1.0))
	_add_box(right_emitter, "StatusLamp", Vector2(0.0, -82.0), Vector2(14.0, 18.0), Color(1.0, 0.50, 0.12, 1.0))
	var glow: Line2D = Line2D.new()
	glow.name = "FieldGlow"
	glow.points = PackedVector2Array([Vector2(-104.0, 0.0), Vector2(104.0, 0.0)])
	glow.width = 18.0
	glow.default_color = Color(1.0, 0.23, 0.06, 0.24)
	visual.add_child(glow)
	var field: Line2D = Line2D.new()
	field.name = "FieldBeam"
	field.points = PackedVector2Array([Vector2(-104.0, 0.0), Vector2(104.0, 0.0)])
	field.width = 7.0
	field.default_color = Color(1.0, 0.63, 0.16, 1.0)
	visual.add_child(field)

func _animate_structure_shift(visual: Node2D) -> void:
	var beam: Polygon2D = visual.get_node("FallingBeam") as Polygon2D
	var lamp: Polygon2D = visual.get_node("ShiftLamp") as Polygon2D
	var tween: Tween = create_tween()
	tween.tween_property(beam, "position:y", beam.position.y + 74.0, 0.34).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(beam, "rotation", 0.14, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lamp, "color", Color(1.0, 0.22, 0.08, 0.2), 0.24)

func _animate_route_open(visual: Node2D) -> void:
	var left_shutter: Polygon2D = visual.get_node("LeftShutter") as Polygon2D
	var right_shutter: Polygon2D = visual.get_node("RightShutter") as Polygon2D
	var indicator: Polygon2D = visual.get_node("OpenIndicator") as Polygon2D
	var tween: Tween = create_tween()
	tween.tween_property(left_shutter, "position:x", -92.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(right_shutter, "position:x", 92.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(indicator, "color", Color(0.28, 0.96, 0.92, 1.0), 0.28)

func _animate_field_clear(visual: Node2D) -> void:
	var field: Line2D = visual.get_node("FieldBeam") as Line2D
	var glow: Line2D = visual.get_node("FieldGlow") as Line2D
	var tween: Tween = create_tween()
	tween.tween_property(field, "position:y", 92.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(field, "modulate:a", 0.0, 0.36)
	tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.36)
	tween.tween_callback(field.hide)
	for emitter_name: String in ["LeftEmitter", "RightEmitter"]:
		var emitter: Polygon2D = visual.get_node(emitter_name) as Polygon2D
		var lamp: Polygon2D = emitter.get_node("StatusLamp") as Polygon2D
		var emitter_tween: Tween = create_tween()
		emitter_tween.tween_property(lamp, "color", Color(0.28, 0.96, 0.92, 1.0), 0.3)

func _add_box(parent: Node, node_name: String, box_position: Vector2, box_size: Vector2, color: Color) -> Polygon2D:
	var box: Polygon2D = Polygon2D.new()
	box.name = node_name
	var half: Vector2 = box_size * 0.5
	box.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	box.position = box_position
	box.color = color
	parent.add_child(box)
	return box
