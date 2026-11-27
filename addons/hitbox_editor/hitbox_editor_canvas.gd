@tool
extends Control

signal hitbox_selected(hitbox: HitboxData)
signal hitbox_context_requested(hitbox: HitboxData)

const BASE_SCALE := 0.75
const MIN_SCALE := 0.15
const MAX_SCALE := 3.0
const ZOOM_FACTOR := 1.12
const HANDLE_RADIUS := 7.0
const HANDLE_PICK_RADIUS := 12.0
const DRAG_THRESHOLD := 3.0

enum DragMode {
	NONE,
	MOVE,
	RESIZE_RECT,
	RESIZE_CIRCLE,
	RESIZE_CAPSULE_RADIUS,
	RESIZE_CAPSULE_HEIGHT,
	PAN
}

var action_data: CombatActionData
var selected_hitbox: HitboxData
var undo_redo: EditorUndoRedoManager
var hidden_instances: Dictionary = {}
var hidden_hitboxes: Dictionary = {}

var view_scale := BASE_SCALE
var view_pan := Vector2.ZERO
var actor_origin := Vector2.ZERO
var preview_time: float = 0.0
var preview_actor_offset: Vector2 = Vector2.ZERO

var drag_mode := DragMode.NONE
var drag_pending := false
var dragging := false
var drag_resource: HitboxData
var drag_start_mouse := Vector2.ZERO
var drag_start_offset := Vector2.ZERO
var drag_start_size := Vector2.ZERO
var drag_start_radius := 0.0
var drag_start_height := 0.0
var drag_anchor := Vector2.ZERO
var drag_handle_index := -1
var pan_start := Vector2.ZERO
var pan_start_offset := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func set_undo_redo(value: EditorUndoRedoManager) -> void:
	undo_redo = value

func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_hitbox = null
	_cancel_interaction()
	queue_redraw()

func set_selection(_instance: HitInstanceData, hitbox: HitboxData) -> void:
	selected_hitbox = hitbox
	queue_redraw()

func set_hidden_resources(instances: Dictionary, hitboxes: Dictionary) -> void:
	hidden_instances = instances.duplicate()
	hidden_hitboxes = hitboxes.duplicate()
	if selected_hitbox != null and not _is_hitbox_visible(selected_hitbox):
		selected_hitbox = null
	queue_redraw()

func _is_hitbox_visible(hitbox: HitboxData) -> bool:
	if hidden_hitboxes.has(hitbox.get_instance_id()):
		return false
	for instance in action_data.hit_instances:
		if instance != null and instance.hitboxes.has(hitbox):
			return not hidden_instances.has(instance.get_instance_id())
	return true

func refresh_view() -> void:
	queue_redraw()


func set_preview_time(value: float) -> void:
	preview_time = maxf(value, 0.0)
	preview_actor_offset = _get_preview_actor_offset()
	queue_redraw()


func _get_movement_track_module() -> MovementModule:
	if action_data == null:
		return null

	for module in action_data.modules:
		if module is MovementModule:
			var movement := module as MovementModule
			if movement.movement_mode == MovementModule.MovementMode.MOVEMENT_TRACK:
				return movement

	return null


func _get_preview_facing_direction() -> float:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return 1.0

	var player: Node = root
	if not root.is_in_group("player"):
		for candidate in root.find_children("*", "CharacterBody2D", true, false):
			if candidate.is_in_group("player"):
				player = candidate
				break

	var facing_value: Variant = player.get("facing_direction")
	if typeof(facing_value) == TYPE_FLOAT or typeof(facing_value) == TYPE_INT:
		if not is_zero_approx(float(facing_value)):
			return signf(float(facing_value))
	return 1.0


func _get_preview_actor_offset() -> Vector2:
	var movement := _get_movement_track_module()
	if movement == null:
		return Vector2.ZERO

	if movement.movement_track_x == null or movement.movement_track_y == null:
		return Vector2.ZERO

	var duration := maxf(movement.movement_track_duration, 0.01)
	var progress := clampf(preview_time / duration, 0.0, 1.0)
	# The editor preview faces right by default. Runtime X is mirrored
	# from the facing direction captured by the Action; Y is authored up-positive.
	var facing_direction := _get_preview_facing_direction()
	var start_offset := Vector2(
		movement.movement_track_x.sample_baked(0.0) * facing_direction,
		-movement.movement_track_y.sample_baked(0.0)
	)
	var current_offset := Vector2(
		movement.movement_track_x.sample_baked(progress) * facing_direction,
		-movement.movement_track_y.sample_baked(progress)
	)
	return current_offset - start_offset


func _draw() -> void:
	actor_origin = size * 0.5 + Vector2(-80, 0) + view_pan
	preview_actor_offset = _get_preview_actor_offset()
	_draw_grid()
	_draw_movement_track_path()
	_draw_actor()
	_draw_origin()

	if action_data == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "请在文件系统中选择 CombatActionData 资源。", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.LIGHT_GRAY)
		return

	for instance_index in range(action_data.hit_instances.size()):
		var instance: HitInstanceData = action_data.hit_instances[instance_index]
		if instance == null or hidden_instances.has(instance.get_instance_id()):
			continue
		for hitbox_index in range(instance.hitboxes.size()):
			var hitbox: HitboxData = instance.hitboxes[hitbox_index]
			if hitbox == null or hidden_hitboxes.has(hitbox.get_instance_id()):
				continue
			var hitbox_color := _get_hitbox_color(instance_index, hitbox_index)
			_draw_hitbox(hitbox, hitbox == selected_hitbox, hitbox_color)

	_draw_view_hint()

func _draw_grid() -> void:
	var c := Color(0.38, 0.42, 0.48, 0.22)
	var step := 40.0 * view_scale
	var start_x := fposmod(actor_origin.x, step)
	var start_y := fposmod(actor_origin.y, step)
	var x := start_x
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1)
		x += step
	var y := start_y
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), c, 1)
		y += step

func _draw_actor() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return

	var player: Node = root
	if not root.is_in_group("player"):
		for candidate in root.find_children("*", "CharacterBody2D", true, false):
			if candidate.is_in_group("player"):
				player = candidate
				break

	var body_node := player.find_child("CollisionShape2D", true, false)
	if not body_node is CollisionShape2D:
		return

	var body := body_node as CollisionShape2D
	if body.shape == null:
		return

	var center := actor_origin + (preview_actor_offset + body.position) * view_scale
	var shape := body.shape
	if shape is RectangleShape2D:
		var rectangle := shape as RectangleShape2D
		var s: Vector2 = rectangle.size * view_scale
		var rect := Rect2(center - s * 0.5, s)
		draw_rect(rect, Color(0.3, 0.7, 0.95, 0.08), true)
		draw_rect(rect, Color(0.3, 0.7, 0.95, 0.7), false, 1.5)
	elif shape is CircleShape2D:
		var circle := shape as CircleShape2D
		draw_circle(center, circle.radius * view_scale, Color(0.3, 0.7, 0.95, 0.08))
		draw_arc(center, circle.radius * view_scale, 0, TAU, 48, Color(0.3, 0.7, 0.95, 0.7), 1.5)

	draw_string(ThemeDB.fallback_font, actor_origin + Vector2(-25, 58) * view_scale, "Player1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.76, 0.86))

func _draw_movement_track_path() -> void:
	var movement := _get_movement_track_module()
	if movement == null:
		return

	if movement.movement_track_x == null or movement.movement_track_y == null:
		return

	var points := PackedVector2Array()
	var facing_direction := _get_preview_facing_direction()
	var start_offset := Vector2(
		movement.movement_track_x.sample_baked(0.0) * facing_direction,
		-movement.movement_track_y.sample_baked(0.0)
	)

	for index in range(21):
		var progress := float(index) / 20.0
		var displacement := Vector2(
			movement.movement_track_x.sample_baked(progress) * facing_direction,
			-movement.movement_track_y.sample_baked(progress)
		) - start_offset
		points.append(actor_origin + displacement * view_scale)

	if points.size() >= 2:
		draw_polyline(points, Color(0.28, 0.9, 0.7, 0.8), 2.0)

	var preview_position := actor_origin + preview_actor_offset * view_scale
	draw_circle(preview_position, 4.0, Color(0.35, 1.0, 0.8))
	draw_string(ThemeDB.fallback_font, preview_position + Vector2(8, -8), "%dF" % CombatTimebase.seconds_to_frames(preview_time), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 1.0, 0.82))


func _draw_origin() -> void:
	var c := Color(1, 0.82, 0.25, 0.95)
	var arm := 18.0 * view_scale
	draw_line(actor_origin + Vector2(-arm, 0), actor_origin + Vector2(arm, 0), c, 1.5)
	draw_line(actor_origin + Vector2(0, -arm), actor_origin + Vector2(0, arm), c, 1.5)
	draw_circle(actor_origin, 3, c)
	draw_string(ThemeDB.fallback_font, actor_origin + Vector2(10, -10), "角色原点", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)

func _get_hitbox_color(instance_index: int, hitbox_index: int) -> Color:
	var hue := fposmod(0.02 + float(instance_index) * 0.19 + float(hitbox_index) * 0.035, 1.0)
	var value := 0.96 - float(hitbox_index % 3) * 0.07
	return Color.from_hsv(hue, 0.72, value)

func _draw_hitbox(hitbox: HitboxData, selected: bool, base_color: Color) -> void:
	var center := actor_origin + (preview_actor_offset + hitbox.offset) * view_scale
	draw_set_transform(center, deg_to_rad(hitbox.rotation_degrees), Vector2.ONE * view_scale)

	var fill := Color(base_color.r, base_color.g, base_color.b, 0.24 if selected else 0.11)
	var line := Color(base_color.r, base_color.g, base_color.b, 1.0 if selected else 0.72)

	match hitbox.shape_type:
		HitboxData.ShapeType.RECTANGLE:
			var rect := Rect2(-hitbox.rectangle_size * 0.5, hitbox.rectangle_size)
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, 2.0 / view_scale)
			if selected:
				var half := hitbox.rectangle_size * 0.5
				for p in _rect_handle_points(half):
					draw_rect(Rect2(p - Vector2.ONE * HANDLE_RADIUS / view_scale, Vector2.ONE * HANDLE_RADIUS * 2.0 / view_scale), Color(1, 0.88, 0.3), true)
		HitboxData.ShapeType.CIRCLE:
			draw_circle(Vector2.ZERO, hitbox.circle_radius, fill)
			draw_arc(Vector2.ZERO, hitbox.circle_radius, 0, TAU, 64, line, 2.0 / view_scale)
			if selected:
				draw_circle(Vector2(hitbox.circle_radius, 0), HANDLE_RADIUS / view_scale, Color(1, 0.88, 0.3))
		HitboxData.ShapeType.CAPSULE:
			var radius := hitbox.capsule_radius
			var half := maxf((hitbox.capsule_height - radius * 2.0) * 0.5, 0.0)
			draw_rect(Rect2(Vector2(-radius, -half), Vector2(radius * 2.0, half * 2.0)), fill, true)
			draw_circle(Vector2(0, -half), radius, fill)
			draw_circle(Vector2(0, half), radius, fill)
			draw_line(Vector2(-radius, -half), Vector2(-radius, half), line, 2.0 / view_scale)
			draw_line(Vector2(radius, -half), Vector2(radius, half), line, 2.0 / view_scale)
			draw_arc(Vector2(0, -half), radius, PI, TAU, 32, line, 2.0 / view_scale)
			draw_arc(Vector2(0, half), radius, 0, PI, 32, line, 2.0 / view_scale)
			if selected:
				draw_circle(Vector2(radius, 0), HANDLE_RADIUS / view_scale, Color(1, 0.88, 0.3))
				draw_circle(Vector2(0, half + radius), HANDLE_RADIUS / view_scale, Color(1, 0.88, 0.3))

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _rect_handle_points(half: Vector2) -> Array[Vector2]:
	return [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	]

func _draw_view_hint() -> void:
	var hint := "滚轮：缩放    中键拖动：平移    左键拖动：移动 / 调整尺寸    缩放 %.0f%%" % (view_scale / BASE_SCALE * 100.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, size.y - 12), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.75, 0.8, 0.85))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, ZOOM_FACTOR)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 1.0 / ZOOM_FACTOR)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				drag_mode = DragMode.PAN
				pan_start = button.position
				pan_start_offset = view_pan
			else:
				if drag_mode == DragMode.PAN:
					drag_mode = DragMode.NONE
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and action_data != null:
			var hitbox := _pick(button.position)
			if hitbox != null:
				hitbox_context_requested.emit(hitbox)
				accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed and action_data != null:
			_begin_left_drag(button.position)
			accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if drag_mode == DragMode.NONE:
			return
		var local_event := make_input_local(event) as InputEventMouseMotion
		var mouse := local_event.position
		if drag_mode == DragMode.PAN:
			view_pan = pan_start_offset + mouse - pan_start
			queue_redraw()
			return

		if drag_pending and not dragging and mouse.distance_to(drag_start_mouse) < DRAG_THRESHOLD:
			return
		dragging = true
		_apply_drag(mouse)
		queue_redraw()

	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and drag_mode != DragMode.NONE and drag_mode != DragMode.PAN:
			_finish_edit()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and drag_mode == DragMode.PAN:
			drag_mode = DragMode.NONE

func _begin_left_drag(mouse: Vector2) -> void:
	var handle_mode := _pick_handle(mouse)
	if handle_mode != DragMode.NONE and selected_hitbox != null:
		_start_edit(handle_mode, selected_hitbox, mouse)
		return

	var hitbox := _pick(mouse)
	if hitbox == null:
		selected_hitbox = null
		hitbox_selected.emit(null)
		queue_redraw()
		return

	selected_hitbox = hitbox
	hitbox_selected.emit(hitbox)
	_start_edit(DragMode.MOVE, hitbox, mouse)

func _start_edit(mode: DragMode, hitbox: HitboxData, mouse: Vector2) -> void:
	drag_mode = mode
	drag_pending = true
	dragging = false
	drag_resource = hitbox
	drag_start_mouse = mouse
	drag_start_offset = hitbox.offset
	drag_start_size = hitbox.rectangle_size
	drag_start_radius = hitbox.circle_radius if hitbox.shape_type == HitboxData.ShapeType.CIRCLE else hitbox.capsule_radius
	drag_start_height = hitbox.capsule_height

	if mode == DragMode.RESIZE_RECT:
		var local_mouse := _to_hitbox_local(mouse, hitbox)
		var half := drag_start_size * 0.5
		var points := _rect_handle_points(half)
		var nearest_index := 0
		var nearest_distance := INF
		for i in range(points.size()):
			var d := (local_mouse - points[i]).length()
			if d < nearest_distance:
				nearest_distance = d
				nearest_index = i
		drag_handle_index = nearest_index
		drag_anchor = -points[nearest_index]
	queue_redraw()

func _apply_drag(mouse: Vector2) -> void:
	if not is_instance_valid(drag_resource):
		return

	match drag_mode:
		DragMode.MOVE:
			drag_resource.offset = drag_start_offset + (mouse - drag_start_mouse) / view_scale
		DragMode.RESIZE_RECT:
			var local_mouse := _to_hitbox_local_at(mouse, drag_start_offset, drag_resource.rotation_degrees)
			var new_center := (drag_anchor + local_mouse) * 0.5
			var new_size := (local_mouse - drag_anchor).abs()
			drag_resource.rectangle_size = Vector2(maxf(new_size.x, 2.0), maxf(new_size.y, 2.0))
			drag_resource.offset = drag_start_offset + new_center.rotated(deg_to_rad(drag_resource.rotation_degrees))
		DragMode.RESIZE_CIRCLE:
			var local_mouse := _to_hitbox_local(mouse, drag_resource)
			drag_resource.circle_radius = maxf(local_mouse.length(), 2.0)
		DragMode.RESIZE_CAPSULE_RADIUS:
			var local_mouse := _to_hitbox_local(mouse, drag_resource)
			drag_resource.capsule_radius = maxf(absf(local_mouse.x), 2.0)
		DragMode.RESIZE_CAPSULE_HEIGHT:
			var local_mouse := _to_hitbox_local(mouse, drag_resource)
			drag_resource.capsule_height = maxf(absf(local_mouse.y) * 2.0, drag_resource.capsule_radius * 2.0)
	drag_resource.emit_changed()

func _to_hitbox_local(mouse: Vector2, hitbox: HitboxData) -> Vector2:
	return _to_hitbox_local_at(mouse, hitbox.offset, hitbox.rotation_degrees)

func _to_hitbox_local_at(mouse: Vector2, offset: Vector2, rotation_degrees: float) -> Vector2:
	var center := actor_origin + (preview_actor_offset + offset) * view_scale
	return ((mouse - center) / view_scale).rotated(-deg_to_rad(rotation_degrees))

func _pick_handle(mouse: Vector2) -> DragMode:
	if selected_hitbox == null:
		return DragMode.NONE
	var local_mouse := _to_hitbox_local(mouse, selected_hitbox)
	match selected_hitbox.shape_type:
		HitboxData.ShapeType.RECTANGLE:
			var half := selected_hitbox.rectangle_size * 0.5
			var points := _rect_handle_points(half)
			for point in points:
				if local_mouse.distance_to(point) * view_scale <= HANDLE_PICK_RADIUS:
					return DragMode.RESIZE_RECT
		HitboxData.ShapeType.CIRCLE:
			if absf(local_mouse.distance_to(Vector2(selected_hitbox.circle_radius, 0))) * view_scale <= HANDLE_PICK_RADIUS:
				return DragMode.RESIZE_CIRCLE
		HitboxData.ShapeType.CAPSULE:
			var half := maxf((selected_hitbox.capsule_height - selected_hitbox.capsule_radius * 2.0) * 0.5, 0.0)
			if local_mouse.distance_to(Vector2(selected_hitbox.capsule_radius, 0)) * view_scale <= HANDLE_PICK_RADIUS:
				return DragMode.RESIZE_CAPSULE_RADIUS
			if local_mouse.distance_to(Vector2(0, half + selected_hitbox.capsule_radius)) * view_scale <= HANDLE_PICK_RADIUS:
				return DragMode.RESIZE_CAPSULE_HEIGHT
	return DragMode.NONE

func _pick(mouse: Vector2) -> HitboxData:
	var candidates: Array[HitboxData] = []
	for instance in action_data.hit_instances:
		if instance == null or hidden_instances.has(instance.get_instance_id()):
			continue
		for hitbox in instance.hitboxes:
			if hitbox != null and not hidden_hitboxes.has(hitbox.get_instance_id()):
				candidates.append(hitbox)

	for i in range(candidates.size() - 1, -1, -1):
		var hitbox := candidates[i]
		var p := _to_hitbox_local(mouse, hitbox)
		match hitbox.shape_type:
			HitboxData.ShapeType.RECTANGLE:
				if Rect2(-hitbox.rectangle_size * 0.5, hitbox.rectangle_size).has_point(p):
					return hitbox
			HitboxData.ShapeType.CIRCLE:
				if p.length() <= hitbox.circle_radius:
					return hitbox
			HitboxData.ShapeType.CAPSULE:
				var half := maxf((hitbox.capsule_height - hitbox.capsule_radius * 2.0) * 0.5, 0.0)
				var nearest := clampf(p.y, -half, half)
				if Vector2(p.x, p.y - nearest).length() <= hitbox.capsule_radius:
					return hitbox
	return null

func _zoom_at(mouse: Vector2, factor: float) -> void:
	var old_scale := view_scale
	var new_scale := clampf(old_scale * factor, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(old_scale, new_scale):
		return
	var base_origin := size * 0.5 + Vector2(-80, 0)
	var world_under_mouse := (mouse - base_origin - view_pan) / old_scale
	view_scale = new_scale
	view_pan = mouse - base_origin - world_under_mouse * new_scale
	queue_redraw()

func _finish_edit() -> void:
	if not drag_pending and not dragging:
		_cancel_interaction()
		return

	var resource := drag_resource
	var final_offset := resource.offset if is_instance_valid(resource) else drag_start_offset
	var final_size := resource.rectangle_size if is_instance_valid(resource) else drag_start_size
	var final_radius := resource.circle_radius if is_instance_valid(resource) and resource.shape_type == HitboxData.ShapeType.CIRCLE else (resource.capsule_radius if is_instance_valid(resource) else drag_start_radius)
	var final_height := resource.capsule_height if is_instance_valid(resource) else drag_start_height

	drag_mode = DragMode.NONE
	drag_pending = false
	dragging = false
	drag_resource = null

	if not is_instance_valid(resource):
		queue_redraw()
		return

	var changes: Array[Dictionary] = []
	if not final_offset.is_equal_approx(drag_start_offset):
		changes.append({"property": "offset", "after": final_offset, "before": drag_start_offset})
	if resource.shape_type == HitboxData.ShapeType.RECTANGLE and not final_size.is_equal_approx(drag_start_size):
		changes.append({"property": "rectangle_size", "after": final_size, "before": drag_start_size})
	elif resource.shape_type == HitboxData.ShapeType.CIRCLE and not is_equal_approx(final_radius, drag_start_radius):
		changes.append({"property": "circle_radius", "after": final_radius, "before": drag_start_radius})
	elif resource.shape_type == HitboxData.ShapeType.CAPSULE:
		if not is_equal_approx(final_radius, drag_start_radius):
			changes.append({"property": "capsule_radius", "after": final_radius, "before": drag_start_radius})
		if not is_equal_approx(final_height, drag_start_height):
			changes.append({"property": "capsule_height", "after": final_height, "before": drag_start_height})

	if undo_redo != null and not changes.is_empty():
		undo_redo.create_action("编辑判定框")
		for change in changes:
			undo_redo.add_do_property(resource, change.property, change.after)
			undo_redo.add_undo_property(resource, change.property, change.before)
		undo_redo.commit_action()

	resource.emit_changed()
	queue_redraw()

func _cancel_interaction() -> void:
	drag_mode = DragMode.NONE
	drag_pending = false
	dragging = false
	drag_resource = null
