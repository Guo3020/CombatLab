@tool
extends Control

const CANVAS_SCRIPT = preload("res://addons/hitbox_editor/hitbox_editor_canvas.gd")
const TIMELINE_SCRIPT = preload("res://addons/hitbox_editor/hitbox_editor_timeline.gd")

const PANEL_POSITION_SETTING := "editors/hit_editor/instance_panel_position"
const PANEL_WIDTH_SETTING := "editors/hit_editor/instance_panel_width"
const DEFAULT_PANEL_POSITION := Vector2(12, 42)
const DEFAULT_PANEL_WIDTH := 250.0
const MIN_PANEL_WIDTH := 210.0
const MAX_PANEL_WIDTH := 560.0

var action_data: CombatActionData
var selected_instance: HitInstanceData
var selected_hitbox: HitboxData
var tree: Tree
var tree_panel: PanelContainer
var panel_header: Control
var resize_grip: Control
var canvas: Control
var timeline: Control
var status: Label
var plugin: EditorPlugin
var last_tree_signature: String = ""
var panel_dragging := false
var panel_resizing := false
var pointer_start := Vector2.ZERO
var panel_start_position := Vector2.ZERO
var panel_start_size := Vector2.ZERO

func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var title := Label.new()
	title.text = "命中编辑器"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var inspect := Button.new()
	inspect.text = "在检查器中查看选中资源"
	inspect.pressed.connect(_inspect_selected)
	header.add_child(inspect)

	canvas = Control.new()
	canvas.set_script(CANVAS_SCRIPT)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(500, 300)
	canvas.hitbox_selected.connect(_on_canvas_selected)
	layout.add_child(canvas)

	_create_floating_instance_list()

	timeline = Control.new()
	timeline.set_script(TIMELINE_SCRIPT)
	timeline.custom_minimum_size = Vector2(500, 132)
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.hit_instance_selected.connect(_on_timeline_selected)
	layout.add_child(timeline)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)

	_show_empty()
	set_process(true)

func _create_floating_instance_list() -> void:
	tree_panel = PanelContainer.new()
	tree_panel.name = "HitInstanceFloatingPanel"
	tree_panel.position = _load_panel_position()
	tree_panel.custom_minimum_size = Vector2(_load_panel_width(), 210)
	tree_panel.size = Vector2(_load_panel_width(), 230)
	tree_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.085, 0.6)
	panel_style.border_color = Color(0.48, 0.56, 0.68, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 5
	panel_style.content_margin_bottom = 8
	tree_panel.add_theme_stylebox_override("panel", panel_style)
	canvas.add_child(tree_panel)

	var list_layout := VBoxContainer.new()
	tree_panel.add_child(list_layout)

	panel_header = HBoxContainer.new()
	panel_header.custom_minimum_size.y = 22
	panel_header.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	panel_header.gui_input.connect(_on_panel_header_input)
	list_layout.add_child(panel_header)

	var list_label := Label.new()
	list_label.text = "命中实例"
	list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	list_label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 1.0))
	list_label.add_theme_constant_override("outline_size", 3)
	list_label.add_theme_font_size_override("font_size", 13)
	panel_header.add_child(list_label)

	var drag_hint := Label.new()
	drag_hint.text = "移动"
	drag_hint.add_theme_font_size_override("font_size", 10)
	drag_hint.add_theme_color_override("font_color", Color(0.72, 0.77, 0.86))
	panel_header.add_child(drag_hint)

	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 150
	tree.item_selected.connect(_on_tree_selected)
	list_layout.add_child(tree)

	resize_grip = Control.new()
	resize_grip.custom_minimum_size = Vector2(18, 18)
	resize_grip.size = Vector2(18, 18)
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	resize_grip.gui_input.connect(_on_resize_grip_input)
	tree_panel.add_child(resize_grip)
	tree_panel.resized.connect(_position_resize_grip)
	_position_resize_grip()

func _position_resize_grip() -> void:
	if not is_instance_valid(resize_grip) or not is_instance_valid(tree_panel):
		return
	resize_grip.position = tree_panel.size - resize_grip.size - Vector2(3, 3)

func _process(_delta: float) -> void:
	if panel_dragging:
		tree_panel.position = _clamp_panel_position(panel_start_position + get_global_mouse_position() - pointer_start)
	if panel_resizing:
		var new_width := clampf(panel_start_size.x + get_global_mouse_position().x - pointer_start.x, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
		tree_panel.size.x = new_width
		tree_panel.custom_minimum_size.x = new_width
		_position_resize_grip()

	if action_data == null:
		return

	canvas.queue_redraw()
	timeline.queue_redraw()

	var signature := _build_tree_signature()
	if signature != last_tree_signature:
		_refresh_tree()
		_connect_resource_changes()
		_update_status()

func _on_panel_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			panel_dragging = true
			pointer_start = get_global_mouse_position()
			panel_start_position = tree_panel.position
			panel_header.accept_event()
		else:
			panel_dragging = false
			_save_panel_settings()
	elif event is InputEventMouseMotion and panel_dragging:
		panel_header.accept_event()

func _on_resize_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			panel_resizing = true
			pointer_start = get_global_mouse_position()
			panel_start_size = tree_panel.size
			resize_grip.accept_event()
		else:
			panel_resizing = false
			_save_panel_settings()
	elif event is InputEventMouseMotion and panel_resizing:
		resize_grip.accept_event()

func _load_panel_position() -> Vector2:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(PANEL_POSITION_SETTING):
		var value: Variant = settings.get_setting(PANEL_POSITION_SETTING)
		if value is Vector2:
			return value
	return DEFAULT_PANEL_POSITION

func _load_panel_width() -> float:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(PANEL_WIDTH_SETTING):
		return clampf(float(settings.get_setting(PANEL_WIDTH_SETTING)), MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
	return DEFAULT_PANEL_WIDTH

func _save_panel_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(PANEL_POSITION_SETTING, tree_panel.position)
	settings.set_setting(PANEL_WIDTH_SETTING, tree_panel.size.x)

func _clamp_panel_position(value: Vector2) -> Vector2:
	var max_x := maxf(canvas.size.x - 80.0, 0.0)
	var max_y := maxf(canvas.size.y - 50.0, 0.0)
	return Vector2(clampf(value.x, 0.0, max_x), clampf(value.y, 0.0, max_y))

func set_editor_plugin(value: EditorPlugin) -> void:
	plugin = value
	if is_instance_valid(canvas):
		canvas.set_undo_redo(plugin.get_undo_redo())

func set_action_data(value: CombatActionData) -> void:
	if value == null or action_data == value:
		return

	action_data = value
	selected_instance = null
	selected_hitbox = null
	last_tree_signature = ""
	if not is_instance_valid(tree):
		return

	_refresh_tree()
	canvas.set_action_data(value)
	timeline.set_action_data(value)
	_connect_resource_changes()
	_update_status()

func _connect_resource_changes() -> void:
	if action_data == null:
		return
	if not action_data.changed.is_connected(_on_action_resource_changed):
		action_data.changed.connect(_on_action_resource_changed)
	for instance in action_data.hit_instances:
		if instance == null:
			continue
		if not instance.changed.is_connected(_on_action_resource_changed):
			instance.changed.connect(_on_action_resource_changed)
		for hitbox in instance.hitboxes:
			if hitbox != null and not hitbox.changed.is_connected(_on_action_resource_changed):
				hitbox.changed.connect(_on_action_resource_changed)

func _on_action_resource_changed() -> void:
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	if is_instance_valid(timeline):
		timeline.queue_redraw()
	var signature := _build_tree_signature()
	if signature != last_tree_signature:
		_refresh_tree()
	_update_status()

func _build_tree_signature() -> String:
	if action_data == null:
		return ""

	var parts: PackedStringArray = []
	for i in range(action_data.hit_instances.size()):
		var instance: HitInstanceData = action_data.hit_instances[i]
		if instance == null:
			parts.append("null")
			continue
		parts.append("%d:%.4f:%.4f" % [i, instance.start_time, instance.end_time])
		for j in range(instance.hitboxes.size()):
			var hitbox: HitboxData = instance.hitboxes[j]
			if hitbox == null:
				parts.append("null")
				continue
			parts.append("%d:%d:%s:%s:%.3f:%s:%s:%s" % [
				j, hitbox.shape_type, str(hitbox.offset), str(hitbox.rectangle_size),
				hitbox.rotation_degrees, str(hitbox.circle_radius), str(hitbox.capsule_radius),
				str(hitbox.capsule_height)
			])
	return "|".join(parts)

func _refresh_tree() -> void:
	if not is_instance_valid(tree):
		return
	tree.clear()
	var root := tree.create_item()
	if action_data == null:
		return

	for i in range(action_data.hit_instances.size()):
		var instance: HitInstanceData = action_data.hit_instances[i]
		if instance == null:
			continue
		var item := tree.create_item(root)
		item.set_text(0, "命中实例 %02d  [%.2f - %.2f]" % [i + 1, instance.start_time, instance.end_time])
		item.set_metadata(0, instance)
		for j in range(instance.hitboxes.size()):
			var hitbox: HitboxData = instance.hitboxes[j]
			if hitbox == null:
				continue
			var child := tree.create_item(item)
			child.set_text(0, "判定框 %02d  (%s)" % [j + 1, _shape_name(hitbox.shape_type)])
			child.set_metadata(0, hitbox)
	last_tree_signature = _build_tree_signature()

func _on_tree_selected() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	var value: Variant = item.get_metadata(0)
	if value is HitboxData:
		selected_hitbox = value
		selected_instance = _parent_instance(value)
	elif value is HitInstanceData:
		selected_instance = value
		selected_hitbox = null
	_sync_selection()
	_inspect_selected()
	_update_status()

func _on_canvas_selected(value: HitboxData) -> void:
	selected_hitbox = value
	selected_instance = _parent_instance(value)
	_select_tree_item(value)
	_sync_selection()
	_inspect_selected()
	_update_status()

func _on_timeline_selected(value: HitInstanceData) -> void:
	selected_instance = value
	selected_hitbox = null
	_select_tree_item(value)
	_sync_selection()
	_inspect_selected()
	_update_status()

func _sync_selection() -> void:
	canvas.set_selection(selected_instance, selected_hitbox)
	timeline.set_selected_instance(selected_instance)

func _select_tree_item(value: Resource) -> void:
	var root := tree.get_root()
	if root == null:
		return
	var stack: Array[TreeItem] = []
	var item := root.get_first_child()
	while item != null:
		stack.append(item)
		item = item.get_next()
	while not stack.is_empty():
		var current: TreeItem = stack.pop_back()
		if current.get_metadata(0) == value:
			tree.set_selected(current, 0)
			return
		var child := current.get_first_child()
		while child != null:
			stack.append(child)
			child = child.get_next()

func _parent_instance(value: HitboxData) -> HitInstanceData:
	if action_data == null:
		return null
	for instance in action_data.hit_instances:
		if instance != null and instance.hitboxes.has(value):
			return instance
	return null

func _inspect_selected() -> void:
	if selected_hitbox != null:
		EditorInterface.inspect_object(selected_hitbox)
	elif selected_instance != null:
		EditorInterface.inspect_object(selected_instance)
	elif action_data != null:
		EditorInterface.inspect_object(action_data)

func _update_status() -> void:
	if action_data == null:
		status.text = "请在文件系统中选择一个 CombatActionData 资源。"
		return
	var label := action_data.resource_path.get_file()
	if label.is_empty():
		label = action_data.action_name
	if selected_hitbox != null:
		status.text = "%s  |  判定框偏移：%s" % [label, str(selected_hitbox.offset)]
	elif selected_instance != null:
		status.text = "%s  |  命中实例：%.2f - %.2f 秒" % [label, selected_instance.start_time, selected_instance.end_time]
	else:
		status.text = "%s  |  请在悬浮列表中选择命中实例或判定框。" % label

func _show_empty() -> void:
	status.text = "请在文件系统中选择一个 CombatActionData 资源。"
	canvas.set_action_data(null)
	timeline.set_action_data(null)

func _shape_name(value: int) -> String:
	match value:
		HitboxData.ShapeType.RECTANGLE: return "矩形"
		HitboxData.ShapeType.CIRCLE: return "圆形"
		HitboxData.ShapeType.CAPSULE: return "胶囊形"
	return "未知"
