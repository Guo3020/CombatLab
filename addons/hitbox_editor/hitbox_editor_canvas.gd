@tool
extends Control

signal hitbox_selected(hitbox: HitboxData)

const VIEW_SCALE := 0.75
const HANDLE_RADIUS := 7.0
var action_data: CombatActionData
var selected_hitbox: HitboxData
var undo_redo: EditorUndoRedoManager
var dragging := false
var drag_resource: HitboxData
var drag_origin := Vector2.ZERO
var drag_mouse := Vector2.ZERO
var actor_origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func set_undo_redo(value: EditorUndoRedoManager) -> void:
	undo_redo = value

func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_hitbox = null
	queue_redraw()

func set_selection(_instance: HitInstanceData, hitbox: HitboxData) -> void:
	selected_hitbox = hitbox
	queue_redraw()

func _draw() -> void:
	actor_origin = size * 0.5 + Vector2(-80, 0)
	_draw_grid()
	_draw_actor()
	_draw_origin()
	if action_data == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "Select a CombatActionData resource in FileSystem.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.LIGHT_GRAY)
		return
	for instance in action_data.hit_instances:
		if instance == null:
			continue
		for hitbox in instance.hitboxes:
			if hitbox != null:
				_draw_hitbox(hitbox, hitbox == selected_hitbox)

func _draw_grid() -> void:
	var c := Color(0.38, 0.42, 0.48, 0.22)
	var step := 40.0
	var x := fposmod(actor_origin.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1)
		x += step
	var y := fposmod(actor_origin.y, step)
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
	var body := player.find_child("CollisionShape2D", true, false)
	if not body is CollisionShape2D or body.shape == null:
		return
	var center := actor_origin + body.position * VIEW_SCALE
	if body.shape is RectangleShape2D:
		var s: Vector2 = body.shape.size * VIEW_SCALE
		var rect := Rect2(center - s * 0.5, s)
		draw_rect(rect, Color(0.3, 0.7, 0.95, 0.08), true)
		draw_rect(rect, Color(0.3, 0.7, 0.95, 0.7), false, 1.5)
	elif body.shape is CircleShape2D:
		draw_circle(center, body.shape.radius * VIEW_SCALE, Color(0.3, 0.7, 0.95, 0.08))
		draw_arc(center, body.shape.radius * VIEW_SCALE, 0, TAU, 48, Color(0.3, 0.7, 0.95, 0.7), 1.5)
	draw_string(ThemeDB.fallback_font, actor_origin + Vector2(-25, 58), "Player1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.76, 0.86))

func _draw_origin() -> void:
	var c := Color(1, 0.82, 0.25, 0.95)
	draw_line(actor_origin + Vector2(-18, 0), actor_origin + Vector2(18, 0), c, 1.5)
	draw_line(actor_origin + Vector2(0, -18), actor_origin + Vector2(0, 18), c, 1.5)
	draw_circle(actor_origin, 3, c)
	draw_string(ThemeDB.fallback_font, actor_origin + Vector2(10, -10), "Actor Origin", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)

func _draw_hitbox(hitbox: HitboxData, selected: bool) -> void:
	var center := actor_origin + hitbox.offset * VIEW_SCALE
	draw_set_transform(center, deg_to_rad(hitbox.rotation_degrees), Vector2.ONE * VIEW_SCALE)
	var fill := Color(1, 0.2, 0.16, 0.22 if selected else 0.10)
	var line := Color(1, 0.35, 0.27, 1.0 if selected else 0.55)
	match hitbox.shape_type:
		HitboxData.ShapeType.RECTANGLE:
			var rect := Rect2(-hitbox.rectangle_size * 0.5, hitbox.rectangle_size)
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, 2.0 / VIEW_SCALE)
			if selected:
				var h := hitbox.rectangle_size * 0.5
				for p in [Vector2(-h.x,-h.y), Vector2(h.x,-h.y), Vector2(h.x,h.y), Vector2(-h.x,h.y)]:
					draw_circle(p, HANDLE_RADIUS / VIEW_SCALE, Color.WHITE)
		HitboxData.ShapeType.CIRCLE:
			draw_circle(Vector2.ZERO, hitbox.circle_radius, fill)
			draw_arc(Vector2.ZERO, hitbox.circle_radius, 0, TAU, 64, line, 2.0 / VIEW_SCALE)
		HitboxData.ShapeType.CAPSULE:
			var r := hitbox.capsule_radius
			var half := maxf((hitbox.capsule_height - r * 2) * 0.5, 0)
			draw_rect(Rect2(Vector2(-r,-half), Vector2(r*2,half*2)), fill, true)
			draw_circle(Vector2(0,-half), r, fill)
			draw_circle(Vector2(0,half), r, fill)
			draw_line(Vector2(-r,-half), Vector2(-r,half), line, 2.0 / VIEW_SCALE)
			draw_line(Vector2(r,-half), Vector2(r,half), line, 2.0 / VIEW_SCALE)
			draw_arc(Vector2(0,-half), r, PI, TAU, 32, line, 2.0 / VIEW_SCALE)
			draw_arc(Vector2(0,half), r, 0, PI, 32, line, 2.0 / VIEW_SCALE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if selected:
		draw_circle(center, HANDLE_RADIUS, Color(1,0.88,0.3))
		draw_circle(center, 3, Color(0.12,0.12,0.12))

func _gui_input(event: InputEvent) -> void:
	if action_data == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hitbox := _pick(event.position)
			if hitbox != null:
				hitbox_selected.emit(hitbox)
				selected_hitbox = hitbox
				dragging = true
				drag_resource = hitbox
				drag_origin = hitbox.offset
				drag_mouse = event.position
				accept_event()
		elif dragging:
			_finish_drag()
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		drag_resource.offset = drag_origin + (event.position - drag_mouse) / VIEW_SCALE
		drag_resource.emit_changed()
		queue_redraw()
		accept_event()

func _finish_drag() -> void:
	dragging = false
	var final_value := drag_resource.offset
	if not final_value.is_equal_approx(drag_origin) and undo_redo != null:
		undo_redo.create_action("Move Hitbox")
		undo_redo.add_do_property(drag_resource, "offset", final_value)
		undo_redo.add_undo_property(drag_resource, "offset", drag_origin)
		undo_redo.commit_action()
		drag_resource.emit_changed()
	drag_resource = null
	queue_redraw()

func _pick(mouse: Vector2) -> HitboxData:
	var candidates: Array[HitboxData] = []
	for instance in action_data.hit_instances:
		if instance != null:
			for hitbox in instance.hitboxes:
				if hitbox != null:
					candidates.append(hitbox)
	for i in range(candidates.size() - 1, -1, -1):
		var h := candidates[i]
		var p := ((mouse - actor_origin - h.offset * VIEW_SCALE) / VIEW_SCALE).rotated(-deg_to_rad(h.rotation_degrees))
		match h.shape_type:
			HitboxData.ShapeType.RECTANGLE:
				if Rect2(-h.rectangle_size * 0.5, h.rectangle_size).has_point(p): return h
			HitboxData.ShapeType.CIRCLE:
				if p.length() <= h.circle_radius: return h
			HitboxData.ShapeType.CAPSULE:
				var half := maxf((h.capsule_height - h.capsule_radius * 2) * 0.5, 0)
				var nearest := clampf(p.y, -half, half)
				if Vector2(p.x, p.y - nearest).length() <= h.capsule_radius: return h
	return null
