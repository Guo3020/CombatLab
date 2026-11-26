@tool
extends EditorPlugin

var current_hitbox_data: Resource = null


func _enter_tree() -> void:
	set_force_draw_over_forwarding_enabled()
	update_overlays()


func _exit_tree() -> void:
	current_hitbox_data = null
	update_overlays()


func _handles(object: Object) -> bool:
	if not object is Resource:
		return false

	return _has_property(object, &"shape_type") and _has_property(object, &"offset")


func _edit(object: Object) -> void:
	if object is Resource and _has_property(object, &"shape_type") and _has_property(object, &"offset"):
		current_hitbox_data = object
	else:
		current_hitbox_data = null

	update_overlays()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(current_hitbox_data):
		return

	var anchor := _get_preview_anchor()
	if anchor == null:
		return

	var editor_viewport := get_editor_interface().get_editor_viewport_2d()
	if editor_viewport == null:
		return

	var canvas_transform: Transform2D = editor_viewport.get_canvas_transform()
	var zoom: float = maxf(canvas_transform.get_scale().x, 0.001)
	var local_to_screen: Transform2D = canvas_transform * anchor.get_global_transform()

	overlay.draw_set_transform_matrix(local_to_screen)
	_draw_origin(overlay, zoom)
	_draw_hitbox(overlay, zoom, local_to_screen)
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)


func _get_preview_anchor() -> Node2D:
	var edited_root := get_editor_interface().get_edited_scene_root()
	if edited_root == null:
		return null

	if edited_root is Node2D and edited_root.is_in_group("player"):
		return edited_root

	var player_nodes := edited_root.find_children("*", "Node2D", true, false)
	for node in player_nodes:
		if node is Node2D and node.is_in_group("player"):
			return node as Node2D

	# 编辑 Player1 场景时，根节点本身就是角色；若没有 player 分组则退回根节点。
	if edited_root is Node2D:
		return edited_root as Node2D

	return null


func _draw_origin(overlay: Control, zoom: float) -> void:
	var axis_length: float = 24.0 / zoom
	var line_width: float = 1.5 / zoom
	var axis_color := Color(0.35, 0.9, 1.0, 0.9)
	var origin_color := Color(1.0, 0.85, 0.25, 1.0)

	overlay.draw_line(Vector2(-axis_length, 0.0), Vector2(axis_length, 0.0), axis_color, line_width)
	overlay.draw_line(Vector2(0.0, -axis_length), Vector2(0.0, axis_length), axis_color, line_width)
	overlay.draw_circle(Vector2.ZERO, 3.5 / zoom, origin_color)


func _draw_hitbox(overlay: Control, zoom: float, local_to_screen: Transform2D) -> void:
	var shape_type: int = int(current_hitbox_data.get("shape_type"))
	var offset: Vector2 = current_hitbox_data.get("offset")
	var rotation_degrees: float = float(current_hitbox_data.get("rotation_degrees"))
	var line_width: float = 2.0 / zoom
	var fill_color := Color(1.0, 0.2, 0.16, 0.22)
	var outline_color := Color(1.0, 0.32, 0.26, 0.95)
	var hitbox_transform := local_to_screen * Transform2D(deg_to_rad(rotation_degrees), offset)

	overlay.draw_set_transform_matrix(hitbox_transform)

	match shape_type:
		0:
			var rectangle_size: Vector2 = current_hitbox_data.get("rectangle_size")
			var rectangle := Rect2(-rectangle_size * 0.5, rectangle_size)
			overlay.draw_rect(rectangle, fill_color, true)
			overlay.draw_rect(rectangle, outline_color, false, line_width)
		1:
			var circle_radius: float = float(current_hitbox_data.get("circle_radius"))
			overlay.draw_circle(Vector2.ZERO, circle_radius, fill_color)
			overlay.draw_arc(Vector2.ZERO, circle_radius, 0.0, TAU, 64, outline_color, line_width)
		2:
			var capsule_radius: float = float(current_hitbox_data.get("capsule_radius"))
			var capsule_height: float = maxf(float(current_hitbox_data.get("capsule_height")), capsule_radius * 2.0)
			var capsule_points := _get_capsule_points(capsule_radius, capsule_height)
			overlay.draw_colored_polygon(capsule_points, fill_color)
			overlay.draw_polyline(_close_polygon(capsule_points), outline_color, line_width, true)

	overlay.draw_circle(Vector2.ZERO, 3.0 / zoom, outline_color)


func _get_capsule_points(radius: float, height: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half_segment: float = maxf((height - radius * 2.0) * 0.5, 0.0)
	var steps: int = 16

	for index in range(steps + 1):
		var angle: float = PI + PI * float(index) / float(steps)
		points.append(Vector2(cos(angle) * radius, -half_segment + sin(angle) * radius))

	for index in range(steps + 1):
		var angle: float = PI * float(index) / float(steps)
		points.append(Vector2(cos(angle) * radius, half_segment + sin(angle) * radius))

	return points


func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var closed_points := points.duplicate()
	if not closed_points.is_empty():
		closed_points.append(closed_points[0])
	return closed_points


func _has_property(object: Object, property_name: StringName) -> bool:
	for property_info in object.get_property_list():
		if StringName(property_info.name) == property_name:
			return true
	return false
