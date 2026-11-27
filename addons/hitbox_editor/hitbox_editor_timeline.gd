@tool
extends Control

signal hit_instance_selected(instance: HitInstanceData)
signal preview_time_changed(time_seconds: float)

const LEFT := 92.0
const TOP := 42.0
const MIN_SCALE := 60.0
const MAX_SCALE := 1200.0
const DEFAULT_SCALE := 240.0
const ZOOM_FACTOR := 1.12
const ROW_HEIGHT := 19.0
const PHASE_ROW_HEIGHT := 20.0
const TRACK_ROW_Y := TOP + 29.0
const HIT_ROW_START_Y := TOP + 55.0
const TICK_STEP_FRAMES := 6

var action_data: CombatActionData
var selected_instance: HitInstanceData
var time_scale := DEFAULT_SCALE
var time_offset := 0.0
var preview_time := 0.0
var middle_dragging := false
var drag_start_x := 0.0
var drag_start_offset := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 150.0
	queue_redraw()


func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_instance = null
	time_offset = 0.0
	time_scale = DEFAULT_SCALE
	preview_time = 0.0
	middle_dragging = false
	preview_time_changed.emit(preview_time)
	queue_redraw()


func set_selected_instance(value: HitInstanceData) -> void:
	selected_instance = value
	queue_redraw()


func set_preview_time(value: float) -> void:
	preview_time = _clamp_preview_time(value)
	queue_redraw()


func _get_total_duration() -> float:
	if action_data == null:
		return 0.0
	return maxf(
		action_data.startup + action_data.active + action_data.recovery,
		0.01
	)


func _clamp_preview_time(value: float) -> float:
	return clampf(value, 0.0, _get_total_duration())


func _time_to_x(time_value: float) -> float:
	return LEFT + (time_value - time_offset) * time_scale


func _get_movement_track_module() -> MovementModule:
	if action_data == null:
		return null

	for module in action_data.modules:
		if module is MovementModule:
			var movement := module as MovementModule
			if movement.movement_mode == MovementModule.MovementMode.MOVEMENT_TRACK:
				return movement

	return null


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.105, 0.115, 0.135), true)
	draw_string(ThemeDB.fallback_font, Vector2(12, 18), "ACTION 时间轴  |  帧数基准：%d FPS" % CombatTimebase.PHYSICS_TICK_RATE, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.88, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 250, 18), "左键：预览 / 选择    中键：平移    滚轮：缩放", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.62, 0.68, 0.76))

	if action_data == null:
		draw_string(ThemeDB.fallback_font, Vector2(12, 52), "尚未选择 Action", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.GRAY)
		return

	_draw_frame_ruler()
	_draw_phase_lane()
	_draw_movement_track_lane()
	_draw_hit_instance_lanes()
	_draw_playhead()


func _draw_frame_ruler() -> void:
	var visible_start := time_offset
	var visible_end := time_offset + maxf((size.x - LEFT - 12.0) / time_scale, 0.01)
	var fps := CombatTimebase.PHYSICS_TICK_RATE
	var first_frame := maxi(int(floor(visible_start * fps / TICK_STEP_FRAMES)) * TICK_STEP_FRAMES, 0)
	var last_frame := int(ceil(visible_end * fps / TICK_STEP_FRAMES)) * TICK_STEP_FRAMES

	for frame in range(first_frame, last_frame + 1, TICK_STEP_FRAMES):
		var time_value := CombatTimebase.frames_to_seconds(frame)
		var x := _time_to_x(time_value)
		if x < LEFT - 2.0 or x > size.x - 4.0:
			continue

		var major_tick := frame % 30 == 0
		var color := Color(0.58, 0.62, 0.68, 0.65) if major_tick else Color(0.42, 0.46, 0.52, 0.38)
		draw_line(Vector2(x, TOP - 5.0), Vector2(x, size.y - 5.0), color, 1.0)

		if major_tick:
			draw_string(ThemeDB.fallback_font, Vector2(x + 2.0, TOP - 9.0), str(frame), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.81, 0.86))


func _draw_phase_lane() -> void:
	var y := TOP
	var h := PHASE_ROW_HEIGHT - 3.0
	var phases := [
		{"name": "Startup", "start": 0.0, "duration": action_data.startup, "color": Color(0.88, 0.66, 0.18)},
		{"name": "Active", "start": action_data.startup, "duration": action_data.active, "color": Color(0.82, 0.25, 0.23)},
		{"name": "Recovery", "start": action_data.startup + action_data.active, "duration": action_data.recovery, "color": Color(0.24, 0.48, 0.82)}
	]

	draw_string(ThemeDB.fallback_font, Vector2(8, y + 13.0), "阶段", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.86, 0.89, 0.94))

	for phase in phases:
		var duration: float = phase["duration"]
		if duration <= 0.0:
			continue
		var x1 := _time_to_x(float(phase["start"]))
		var x2 := _time_to_x(float(phase["start"]) + duration)
		var left := maxf(x1, LEFT)
		var right := minf(x2, size.x - 5.0)
		if right <= left:
			continue
		draw_rect(Rect2(Vector2(left, y), Vector2(right - left, h)), phase["color"], true)
		if right - left > 45.0:
			draw_string(ThemeDB.fallback_font, Vector2(left + 4.0, y + 13.0), str(phase["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _draw_movement_track_lane() -> void:
	var y := TRACK_ROW_Y
	draw_string(ThemeDB.fallback_font, Vector2(8, y + 12.0), "Movement", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.88, 0.98))

	var movement := _get_movement_track_module()
	if movement == null:
		draw_string(ThemeDB.fallback_font, Vector2(LEFT + 4.0, y + 12.0), "未配置 MovementTrack", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.48, 0.53, 0.6))
		return

	var x1 := _time_to_x(0.0)
	var x2 := _time_to_x(movement.movement_track_duration)
	var left := maxf(x1, LEFT)
	var right := minf(x2, size.x - 5.0)
	if right > left:
		var color := Color(0.18, 0.68, 0.55, 0.9)
		draw_rect(Rect2(Vector2(left, y), Vector2(right - left, 13.0)), color, true)
		draw_rect(Rect2(Vector2(left, y), Vector2(right - left, 13.0)), Color(0.55, 1.0, 0.82), false, 1.0)
		if right - left > 90.0:
			var strategy := "IGNORE_WORLD" if movement.movement_track_collision_strategy == MovementModule.MovementCollisionStrategy.IGNORE_WORLD else "BLOCK"
			draw_string(ThemeDB.fallback_font, Vector2(left + 4.0, y + 10.0), "Track  |  %s" % strategy, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)


func _draw_hit_instance_lanes() -> void:
	for i in range(action_data.hit_instances.size()):
		var item: HitInstanceData = action_data.hit_instances[i]
		if item == null:
			continue

		var y := HIT_ROW_START_Y + float(i) * ROW_HEIGHT
		if y > size.y - 4.0:
			continue

		var x1 := _time_to_x(action_data.startup + item.start_time)
		var x2 := _time_to_x(action_data.startup + item.end_time)
		var clipped_left := maxf(x1, LEFT)
		var clipped_right := minf(x2, size.x - 5.0)
		var rect := Rect2(Vector2(clipped_left, y), Vector2(maxf(clipped_right - clipped_left, 0.0), 12.0))
		var chosen := item == selected_instance
		var active_now := (
			preview_time >= action_data.startup + item.start_time
			and preview_time < action_data.startup + item.end_time
		)

		if rect.size.x > 0.0:
			var fill := Color(1.0, 0.48, 0.2, 0.95 if chosen else (0.78 if active_now else 0.45))
			draw_rect(rect, fill, true)
			draw_rect(rect, Color(1.0, 0.82, 0.55, 1.0 if chosen or active_now else 0.5), false, 1.0)

		var name_color := Color(1.0, 0.83, 0.62) if chosen else Color(0.86, 0.88, 0.92)
		draw_string(ThemeDB.fallback_font, Vector2(8, y + 10.0), "命中 %02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, name_color)


func _draw_playhead() -> void:
	var x := _time_to_x(preview_time)
	if x < LEFT or x > size.x - 4.0:
		return

	draw_line(Vector2(x, TOP - 7.0), Vector2(x, size.y - 4.0), Color(1.0, 0.95, 0.55), 2.0)
	draw_circle(Vector2(x, TOP - 7.0), 3.5, Color(1.0, 0.95, 0.55))

	var frame := CombatTimebase.seconds_to_frames(preview_time)
	draw_string(ThemeDB.fallback_font, Vector2(x + 6.0, size.y - 7.0), "%dF  %.3fs" % [frame, preview_time], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.95, 0.65))


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
			_scrub_and_select(button.position)
	elif event is InputEventMouseMotion and middle_dragging:
		var motion := event as InputEventMouseMotion
		time_offset = maxf(drag_start_offset - (motion.position.x - drag_start_x) / time_scale, 0.0)
		queue_redraw()
		accept_event()


func _scrub_and_select(position: Vector2) -> void:
	preview_time = _clamp_preview_time(time_offset + (position.x - LEFT) / time_scale)
	preview_time_changed.emit(preview_time)

	if position.y >= HIT_ROW_START_Y:
		var index := int(floor((position.y - HIT_ROW_START_Y) / ROW_HEIGHT))
		if index >= 0 and index < action_data.hit_instances.size():
			var item: HitInstanceData = action_data.hit_instances[index]
			if item != null:
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
