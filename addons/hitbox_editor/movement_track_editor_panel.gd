@tool
extends PanelContainer

class_name MovementTrackEditorPanel

const PANEL_WIDTH := 320.0
const MIN_PANEL_WIDTH := 280.0
const MAX_PANEL_WIDTH := 900.0
const MIN_PANEL_HEIGHT := 300.0
const MAX_PANEL_HEIGHT := 1000.0
const DURATION_MIN := 0.01
const DURATION_MAX := 1000000000.0
const AXIS_RANGE_MIN := 1.0
const AXIS_RANGE_MAX := 1000000000.0

var movement: MovementModule
var scroll: ScrollContainer
var content: VBoxContainer
var empty_state: Label
var root_layout: VBoxContainer
var overlay: Control
var duration_axis_buttons: Array[Button] = []
var duration_spin: SpinBox
var collision_option: OptionButton
var x_graph: CurveGraph
var y_graph: CurveGraph
var header: HBoxContainer
var dragging := false
var resize_mode := ""
var user_positioned := false
var resize_mouse := Vector2.ZERO
var resize_size := Vector2.ZERO
var resize_position := Vector2.ZERO
var drag_origin := Vector2.ZERO
var panel_origin := Vector2.ZERO
var number_dialog: AcceptDialog
var number_spin: SpinBox
var number_callback: Callable


class CurveGraph extends Control:
	var curve: Curve
	var duration := 0.2
	var value_range := 100.0
	var selected_point := -1
	var dragging_point := -1
	var plot_left := 32.0
	var plot_right := 0.0
	var plot_top := 12.0
	var plot_bottom := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(0.0, 150.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.035, 0.05, 0.5), true)
		plot_left = 32.0
		plot_right = size.x - 10.0
		plot_top = 12.0
		plot_bottom = size.y - 24.0
		var graph_width := plot_right - plot_left
		var graph_height := plot_bottom - plot_top
		if graph_width <= 0.0 or graph_height <= 0.0:
			return

		for i in range(5):
			var x := plot_left + graph_width * float(i) / 4.0
			draw_line(Vector2(x, plot_top), Vector2(x, plot_bottom), Color(0.5, 0.58, 0.68, 0.16), 1.0)
		for i in range(5):
			var y := plot_top + graph_height * float(i) / 4.0
			draw_line(Vector2(plot_left, y), Vector2(plot_right, y), Color(0.5, 0.58, 0.68, 0.16), 1.0)

		var zero_y := _value_to_screen_y(0.0)
		draw_line(Vector2(plot_left, zero_y), Vector2(plot_right, zero_y), Color(0.8, 0.84, 0.9, 0.6), 1.2)
		draw_line(Vector2(plot_left, plot_top), Vector2(plot_left, plot_bottom), Color(0.8, 0.84, 0.9, 0.6), 1.2)
		draw_string(ThemeDB.fallback_font, Vector2(2, plot_top + 4), "%+.0f" % value_range, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.78, 0.84, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(2, plot_bottom), "%+.0f" % -value_range, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.78, 0.84, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(plot_left, size.y - 5), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.78, 0.84, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(plot_right - 42, size.y - 5), "%.2fs" % duration, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.78, 0.84, 0.92))

		if curve == null:
			return
		var line_points := PackedVector2Array()
		for i in range(257):
			var progress := float(i) / 256.0
			line_points.append(_curve_to_screen(Vector2(progress, curve.sample_baked(progress))))
		if line_points.size() > 1:
			draw_polyline(line_points, Color(0.3, 0.92, 0.74, 0.95), 2.0, true)
		for i in range(curve.get_point_count()):
			var point_position := _curve_to_screen(curve.get_point_position(i))
			var point_color := Color(1.0, 0.78, 0.28, 1.0) if i == selected_point else Color(0.88, 0.95, 1.0, 1.0)
			draw_circle(point_position, 5.0 if i == selected_point else 4.0, point_color)
			draw_arc(point_position, 5.5, 0.0, TAU, 16, Color(0.04, 0.06, 0.08, 1.0), 1.0)

	func set_curve(value: Curve, track_duration: float, axis_range: float) -> void:
		var curve_changed := curve != value
		curve = value
		duration = maxf(track_duration, 0.01)
		value_range = maxf(axis_range, 1.0)
		if curve_changed:
			selected_point = -1
			dragging_point = -1
		queue_redraw()

	func set_value_range(value: float) -> void:
		value_range = clampf(value, 1.0, 1000000000.0)
		queue_redraw()

	func _curve_to_screen(point: Vector2) -> Vector2:
		return Vector2(plot_left + clampf(point.x, 0.0, 1.0) * (plot_right - plot_left), _value_to_screen_y(point.y))

	func _value_to_screen_y(value: float) -> float:
		var graph_height := plot_bottom - plot_top
		return plot_top + graph_height * 0.5 - clampf(value / maxf(value_range, 0.01), -1.0, 1.0) * graph_height * 0.5

	func _screen_to_curve(screen_position: Vector2) -> Vector2:
		var graph_width := maxf(plot_right - plot_left, 1.0)
		var graph_height := maxf(plot_bottom - plot_top, 1.0)
		var x := clampf((screen_position.x - plot_left) / graph_width, 0.0, 1.0)
		var y := (plot_top + graph_height * 0.5 - screen_position.y) / (graph_height * 0.5) * value_range
		return Vector2(x, clampf(y, -value_range, value_range))

	func _find_nearest_point(screen_position: Vector2) -> int:
		if curve == null:
			return -1
		var nearest_index := -1
		var nearest_distance := 12.0
		for i in range(curve.get_point_count()):
			var distance := _curve_to_screen(curve.get_point_position(i)).distance_to(screen_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = i
		return nearest_index

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
				grab_focus()
				if button.double_click:
					_add_point_at(button.position)
					accept_event()
					return
				selected_point = _find_nearest_point(button.position)
				queue_redraw()
				if selected_point >= 0:
					dragging_point = selected_point
					accept_event()
			elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
				dragging_point = -1
			elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
				selected_point = _find_nearest_point(button.position)
				_delete_selected_point()
				accept_event()
		elif event is InputEventMouseMotion and dragging_point >= 0:
			_move_selected_point((event as InputEventMouseMotion).position)
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo:
			var key := event as InputEventKey
			if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
				_delete_selected_point()
				accept_event()

	func _add_point_at(screen_position: Vector2) -> void:
		if curve == null:
			return
		var point := _screen_to_curve(screen_position)
		if point.x <= 0.005 or point.x >= 0.995:
			return
		curve.add_point(point)
		selected_point = _find_nearest_point(_curve_to_screen(point))
		queue_redraw()

	func _move_selected_point(screen_position: Vector2) -> void:
		if curve == null or dragging_point < 0 or dragging_point >= curve.get_point_count():
			return
		var point := _screen_to_curve(screen_position)
		var old_point := curve.get_point_position(dragging_point)
		if dragging_point == 0:
			point.x = 0.0
		elif dragging_point == curve.get_point_count() - 1:
			point.x = 1.0
		else:
			var min_x := curve.get_point_position(dragging_point - 1).x + 0.001
			var max_x := curve.get_point_position(dragging_point + 1).x - 0.001
			point.x = clampf(point.x, min_x, max_x)
		if old_point.distance_squared_to(point) > 0.000001:
			curve.set_point_position(dragging_point, point)
			queue_redraw()

	func _delete_selected_point() -> void:
		if curve == null or selected_point <= 0 or selected_point >= curve.get_point_count() - 1:
			return
		curve.remove_point(selected_point)
		selected_point = -1
		dragging_point = -1
		queue_redraw()


func _ready() -> void:
	visible = movement != null
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280.0, 300.0)
	size = Vector2(PANEL_WIDTH, 430)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.085, 0.78)
	style.border_color = Color(0.48, 0.56, 0.68, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	root_layout = VBoxContainer.new()
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.add_theme_constant_override("separation", 4)
	overlay.add_child(root_layout)
	header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_header_input)
	root_layout.add_child(header)

	empty_state = Label.new()
	empty_state.text = "当前 Action 没有启用 MovementTrack。"
	empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_layout.add_child(empty_state)

	var title := Label.new()
	title.text = "MovementTrack"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := Label.new()
	hint.text = "拖动"
	hint.add_theme_font_size_override("font_size", 10)
	header.add_child(hint)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_layout.add_child(scroll)
	scroll.visible = false
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.x = 0.0
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var duration_row := HBoxContainer.new()
	content.add_child(duration_row)
	duration_row.add_child(_make_label("持续时间"))
	duration_row.add_theme_constant_override("separation", 4)
	duration_spin = SpinBox.new()
	duration_spin.min_value = 0.01
	duration_spin.max_value = DURATION_MAX
	duration_spin.step = 0.01
	duration_spin.custom_minimum_size.x = 0.0
	duration_spin.value = 0.2
	duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_spin.value_changed.connect(_on_duration_changed)
	duration_row.add_child(duration_spin)

	var collision_row := HBoxContainer.new()
	content.add_child(collision_row)
	collision_row.add_child(_make_label("碰撞策略"))
	collision_row.add_theme_constant_override("separation", 4)
	collision_option = OptionButton.new()
	collision_option.add_item("BLOCK", MovementModule.MovementCollisionStrategy.BLOCK)
	collision_option.add_item("IGNORE_WORLD", MovementModule.MovementCollisionStrategy.IGNORE_WORLD)
	collision_option.custom_minimum_size.x = 0.0
	collision_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collision_option.item_selected.connect(_on_collision_changed)
	collision_row.add_child(collision_option)

	x_graph = CurveGraph.new()
	content.add_child(_make_graph_section("Track_X（面向方向为正）", x_graph, true))
	y_graph = CurveGraph.new()
	content.add_child(_make_graph_section("Track_Y（向上为正）", y_graph, false))

	number_dialog = AcceptDialog.new()
	number_dialog.title = "输入数值"
	get_parent().add_child(number_dialog)

	number_spin = SpinBox.new()
	number_spin.min_value = 0.01
	number_spin.max_value = DURATION_MAX
	number_spin.step = 0.01
	number_spin.custom_minimum_size.x = 0.0
	number_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number_dialog.add_child(number_spin)
	number_dialog.confirmed.connect(_on_number_confirmed)

	_create_resize_grips()
	_refresh()


func _make_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = 68.0
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label


func _make_graph_section(title_text: String, graph: CurveGraph, _is_x: bool) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.custom_minimum_size.x = 0.0
	var heading := HBoxContainer.new()
	section.add_child(heading)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var range_button := Button.new()
	range_button.flat = true
	range_button.text = "+100"
	range_button.custom_minimum_size.x = 42.0
	heading.add_child(range_button)
	section.add_child(graph)
	var footer := HBoxContainer.new()
	section.add_child(footer)
	var lower_range_button := Button.new()
	lower_range_button.flat = true
	lower_range_button.text = "-100"
	lower_range_button.custom_minimum_size.x = 42.0
	range_button.pressed.connect(_on_range_button_pressed.bind(graph, range_button, lower_range_button))
	lower_range_button.pressed.connect(_on_range_button_pressed.bind(graph, range_button, lower_range_button))
	footer.add_child(lower_range_button)
	var start_label := Label.new()
	start_label.text = "双击添加 · 拖动调整 · 右键/删除移除"
	start_label.add_theme_font_size_override("font_size", 9)
	start_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(start_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var end_button := Button.new()
	end_button.flat = true
	end_button.text = "0.20s"
	end_button.custom_minimum_size.x = 54.0
	end_button.pressed.connect(_on_duration_axis_pressed)
	footer.add_child(end_button)
	duration_axis_buttons.append(end_button)
	return section


func set_movement(value: MovementModule) -> void:
	if movement != value:
		if movement != null:
			if movement.changed.is_connected(_refresh):
				movement.changed.disconnect(_refresh)
			for old_curve in [movement.movement_track_x, movement.movement_track_y]:
				if old_curve != null and old_curve.changed.is_connected(_refresh):
					old_curve.changed.disconnect(_refresh)
		movement = value

	visible = movement != null
	if not is_node_ready():
		return
	_connect_movement_signals()
	_refresh()


func _connect_movement_signals() -> void:
	if movement == null:
		return
	# Assign inspector filter names before connecting changed signals.
	if movement.movement_track_x != null:
		if movement.movement_track_x.resource_name != "MovementTrack X Curve":
			movement.movement_track_x.resource_name = "MovementTrack X Curve"
		if not movement.movement_track_x.changed.is_connected(_refresh):
			movement.movement_track_x.changed.connect(_refresh)
	if movement.movement_track_y != null:
		if movement.movement_track_y.resource_name != "MovementTrack Y Curve":
			movement.movement_track_y.resource_name = "MovementTrack Y Curve"
		if not movement.movement_track_y.changed.is_connected(_refresh):
			movement.movement_track_y.changed.connect(_refresh)
	if not movement.changed.is_connected(_refresh):
		movement.changed.connect(_refresh)


func _refresh() -> void:
	var has_movement := movement != null
	empty_state.visible = not has_movement
	scroll.visible = has_movement
	if not has_movement:
		return
	duration_spin.set_value_no_signal(movement.movement_track_duration)
	for axis_button in duration_axis_buttons:
		axis_button.text = "%.2fs" % movement.movement_track_duration
	collision_option.select(int(movement.movement_track_collision_strategy))
	x_graph.set_curve(movement.movement_track_x, movement.movement_track_duration, x_graph.value_range)
	y_graph.set_curve(movement.movement_track_y, movement.movement_track_duration, y_graph.value_range)


func _on_duration_changed(value: float) -> void:
	if movement == null:
		return
	movement.movement_track_duration = value
	movement.emit_changed()
	_refresh()


func _on_collision_changed(index: int) -> void:
	if movement == null:
		return
	movement.movement_track_collision_strategy = collision_option.get_item_id(index)
	movement.emit_changed()


func _on_range_button_pressed(graph: CurveGraph, button: Button, opposite_button: Button) -> void:
	_open_number_dialog("纵轴最大位移绝对值", graph.value_range, AXIS_RANGE_MIN, AXIS_RANGE_MAX, func(value: float) -> void:
		graph.value_range = value
		button.text = "+%.0f" % value
		opposite_button.text = "-%.0f" % value
		graph.queue_redraw()
	)


func _on_duration_axis_pressed() -> void:
	if movement == null:
		return
	_open_number_dialog("时间范围（秒）", movement.movement_track_duration, DURATION_MIN, DURATION_MAX, func(value: float) -> void:
		duration_spin.set_value_no_signal(value)
		_on_duration_changed(value)
	)


func _open_number_dialog(title_text: String, current_value: float, min_value: float, max_value: float, callback: Callable) -> void:
	number_dialog.title = title_text
	number_spin.min_value = min_value
	number_spin.max_value = max_value
	number_spin.step = 0.01
	number_spin.set_value_no_signal(current_value)
	number_callback = callback
	number_dialog.popup_centered(Vector2i(300, 100))


func _on_number_confirmed() -> void:
	if number_callback.is_valid():
		number_callback.call(number_spin.value)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_origin = get_global_mouse_position()
			panel_origin = position
			header.accept_event()
		else:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		header.accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		resize_mode = ""


func _process(_delta: float) -> void:
	if dragging:
		position = panel_origin + get_global_mouse_position() - drag_origin
		user_positioned = true
	if not resize_mode.is_empty():
		var mouse_delta := get_global_mouse_position() - resize_mouse
		var next_width := resize_size.x
		var next_height := resize_size.y
		if resize_mode == "left":
			next_width = clampf(resize_size.x - mouse_delta.x, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
			position.x = resize_position.x + resize_size.x - next_width
		elif resize_mode == "right" or resize_mode == "corner":
			next_width = clampf(resize_size.x + mouse_delta.x, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
		if resize_mode == "bottom" or resize_mode == "corner":
			next_height = clampf(resize_size.y + mouse_delta.y, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)
		size = Vector2(next_width, next_height)
		custom_minimum_size = Vector2(next_width, MIN_PANEL_HEIGHT)
	if not user_positioned and get_parent() != null and get_parent().size.x > size.x + 24.0:
		position.x = get_parent().size.x - size.x - 12.0


func _create_resize_grips() -> void:
	_create_resize_grip("bottom", Control.CURSOR_VSIZE, 0.0, 1.0, 1.0, 1.0, 8.0, -8.0, -6.0, 0.0)
	_create_resize_grip("left", Control.CURSOR_HSIZE, 0.0, 0.0, 0.0, 1.0, 0.0, 6.0, 8.0, -8.0)
	_create_resize_grip("right", Control.CURSOR_HSIZE, 1.0, 1.0, 0.0, 1.0, -6.0, 0.0, 8.0, -8.0)
	_create_resize_grip("corner", Control.CURSOR_FDIAGSIZE, 1.0, 1.0, 1.0, 1.0, -12.0, 0.0, -12.0, 0.0)


func _create_resize_grip(mode: String, cursor: int, left_anchor: float, right_anchor: float, top_anchor: float, bottom_anchor: float, left_offset: float, right_offset: float, top_offset: float, bottom_offset: float) -> void:
	var grip := Control.new()
	grip.name = "ResizeGrip_" + mode
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = cursor
	grip.anchor_left = left_anchor
	grip.anchor_right = right_anchor
	grip.anchor_top = top_anchor
	grip.anchor_bottom = bottom_anchor
	grip.offset_left = left_offset
	grip.offset_right = right_offset
	grip.offset_top = top_offset
	grip.offset_bottom = bottom_offset
	grip.gui_input.connect(_on_resize_input.bind(mode))
	overlay.add_child(grip)


func _on_resize_input(event: InputEvent, mode: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			resize_mode = mode
			user_positioned = true
			resize_mouse = get_global_mouse_position()
			resize_size = size
			resize_position = position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not resize_mode.is_empty():
		get_viewport().set_input_as_handled()
