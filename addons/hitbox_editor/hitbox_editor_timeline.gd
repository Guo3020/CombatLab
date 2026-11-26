@tool
extends Control

signal hit_instance_selected(instance: HitInstanceData)

const LEFT := 86.0
const TOP := 34.0
const MIN_SCALE := 60.0
const MAX_SCALE := 900.0
const DEFAULT_SCALE := 180.0
const ZOOM_FACTOR := 1.12
const ROW_HEIGHT := 19.0

var action_data: CombatActionData
var selected_instance: HitInstanceData
var time_scale := DEFAULT_SCALE
var time_offset := 0.0
var middle_dragging := false
var drag_start_x := 0.0
var drag_start_offset := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_instance = null
	time_offset = 0.0
	time_scale = DEFAULT_SCALE
	middle_dragging = false
	queue_redraw()

func set_selected_instance(value: HitInstanceData) -> void:
	selected_instance = value
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.105, 0.115, 0.135), true)
	draw_string(ThemeDB.fallback_font, Vector2(12, 17), "ACTIVE 时间轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.88, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 240, 17), "中键拖动：平移    滚轮：缩放", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.62, 0.68, 0.76))

	if action_data == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 48), "尚未选择 Action", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.GRAY)
		return

	var visible_start := time_offset
	var visible_end := time_offset + maxf((size.x - LEFT - 12) / time_scale, 0.01)
	var first_tick := int(floor(visible_start / 0.1))
	var last_tick := int(ceil(visible_end / 0.1))

	for tick in range(first_tick, last_tick + 1):
		var time_value := float(tick) * 0.1
		var x := LEFT + (time_value - time_offset) * time_scale
		if x < LEFT - 2 or x > size.x - 4:
			continue
		draw_line(Vector2(x, TOP), Vector2(x, size.y - 5), Color(0.45, 0.48, 0.52, 0.42), 1)
		draw_string(ThemeDB.fallback_font, Vector2(x + 2, TOP - 5), "%.1f" % time_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.78, 0.82))

	var active_start_x := LEFT - time_offset * time_scale
	var active_end_x := LEFT + (action_data.active - time_offset) * time_scale
	var active_left := maxf(active_start_x, LEFT)
	var active_right := minf(active_end_x, size.x)
	if active_right > active_left:
		draw_rect(Rect2(Vector2(active_left, TOP), Vector2(active_right - active_left, size.y - TOP - 5)), Color(0.18, 0.42, 0.56, 0.13), true)

	for i in range(action_data.hit_instances.size()):
		var item: HitInstanceData = action_data.hit_instances[i]
		if item == null:
			continue
		var y := TOP + 14 + float(i) * ROW_HEIGHT
		if y > size.y - 4:
			continue
		var x1 := LEFT + (item.start_time - time_offset) * time_scale
		var x2 := LEFT + (item.end_time - time_offset) * time_scale
		var clipped_left := maxf(x1, LEFT)
		var clipped_right := minf(x2, size.x - 5)
		var rect := Rect2(Vector2(clipped_left, y), Vector2(maxf(clipped_right - clipped_left, 0.0), 12))
		var chosen := item == selected_instance
		if rect.size.x > 0:
			draw_rect(rect, Color(1, 0.48, 0.2, 0.95 if chosen else 0.62), true)
			draw_rect(rect, Color(1, 0.82, 0.55, 1 if chosen else 0.5), false, 1)
		var name_color := Color(1.0, 0.83, 0.62) if chosen else Color(0.86, 0.88, 0.92)
		draw_string(ThemeDB.fallback_font, Vector2(8, y + 10), "命中 %02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, name_color)

func _gui_input(event: InputEvent) -> void:
	if action_data == null:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = button.pressed
			if button.pressed:
				drag_start_x = button.position.x
				drag_start_offset = time_offset
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position.x, ZOOM_FACTOR)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position.x, 1.0 / ZOOM_FACTOR)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_select_instance_at(button.position)
	elif event is InputEventMouseMotion and middle_dragging:
		var motion := event as InputEventMouseMotion
		time_offset = maxf(drag_start_offset - (motion.position.x - drag_start_x) / time_scale, 0.0)
		queue_redraw()
		accept_event()

func _select_instance_at(position: Vector2) -> void:
	if position.y < TOP + 8:
		return
	var index := int(floor((position.y - TOP - 14.0) / ROW_HEIGHT))
	if index < 0 or index >= action_data.hit_instances.size():
		return
	var item: HitInstanceData = action_data.hit_instances[index]
	if item == null:
		return

	# The full row (label and hit bar) is selectable, including when
	# the hit interval is currently outside the visible horizontal range.
	selected_instance = item
	hit_instance_selected.emit(item)
	queue_redraw()
	accept_event()

func _zoom_at(mouse_x: float, factor: float) -> void:
	var old_scale := time_scale
	var new_scale := clampf(old_scale * factor, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(old_scale, new_scale):
		return
	var time_under_mouse := time_offset + (mouse_x - LEFT) / old_scale
	time_scale = new_scale
	time_offset = maxf(time_under_mouse - (mouse_x - LEFT) / new_scale, 0.0)
	queue_redraw()
