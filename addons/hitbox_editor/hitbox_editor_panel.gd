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
const RESIZE_EDGE_WIDTH := 8.0
const EYE_BUTTON_ID := 1
const MOVE_UP := 0
const MOVE_DOWN := 1
const MOVE_TO_TOP := 2
const MOVE_TO_BOTTOM := 3

var action_data: CombatActionData
var selected_instance: HitInstanceData
var selected_hitbox: HitboxData
var tree: Tree
var context_menu: PopupMenu
var context_hitbox: HitboxData
var context_instance: HitInstanceData
var hidden_instances: Dictionary = {}
var hidden_hitboxes: Dictionary = {}
var undo_redo: EditorUndoRedoManager
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
	canvas.hitbox_context_requested.connect(_on_canvas_context_requested)
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
	var tree_background := StyleBoxFlat.new()
	tree_background.bg_color = Color(0.055, 0.065, 0.085, 0.0)
	tree.add_theme_stylebox_override("panel", tree_background)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 150
	tree.item_selected.connect(_on_tree_selected)
	tree.button_clicked.connect(_on_tree_button_clicked)
	tree.gui_input.connect(_on_tree_gui_input)
	list_layout.add_child(tree)

	context_menu = PopupMenu.new()
	tree.add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)

	resize_grip = Control.new()
	resize_grip.custom_minimum_size = Vector2(RESIZE_EDGE_WIDTH, 1)
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	resize_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	resize_grip.gui_input.connect(_on_resize_grip_input)
	tree_panel.add_child(resize_grip)
	tree_panel.resized.connect(_position_resize_grip)
	_position_resize_grip()

func _position_resize_grip() -> void:
	if not is_instance_valid(resize_grip) or not is_instance_valid(tree_panel):
		return
	resize_grip.position = Vector2(
		tree_panel.size.x - RESIZE_EDGE_WIDTH,
		0.0
	)
	resize_grip.size = Vector2(
		RESIZE_EDGE_WIDTH,
		tree_panel.size.y
	)

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
	undo_redo = plugin.get_undo_redo()
	if is_instance_valid(canvas):
		canvas.set_undo_redo(undo_redo)

func set_action_data(value: CombatActionData) -> void:
	if value == null or action_data == value:
		return

	action_data = value
	selected_instance = null
	selected_hitbox = null
	hidden_instances.clear()
	hidden_hitboxes.clear()
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
		if selected_hitbox != null:
			_select_tree_item(selected_hitbox)
		elif selected_instance != null:
			_select_tree_item(selected_instance)
	_update_status()

func _build_tree_signature() -> String:
	if action_data == null:
		return ""

	var parts: PackedStringArray = [action_data.action_name, str(action_data.collision_mask)]
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
			parts.append("%d:%d:%d:%s:%s:%.3f:%s:%s:%s" % [
				j, hitbox.get_instance_id(), hitbox.shape_type, str(hitbox.offset), str(hitbox.rectangle_size),
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

	# ActionData 与 HitInstance 使用同一层级显示，避免标题缩进。
	var action_item := tree.create_item(root)
	action_item.set_text(0, action_data.action_name)
	action_item.set_metadata(0, action_data)

	for i in range(action_data.hit_instances.size()):
		var instance: HitInstanceData = action_data.hit_instances[i]
		if instance == null:
			continue
		var item := tree.create_item(root)
		item.set_text(0, "命中实例 %02d  [%.2f - %.2f]" % [i + 1, instance.start_time, instance.end_time])
		item.set_metadata(0, instance)
		var instance_visible := not hidden_instances.has(instance.get_instance_id())
		item.add_button(0, _get_visibility_icon(instance_visible), EYE_BUTTON_ID, false, "隐藏命中实例" if instance_visible else "显示命中实例")
		if not instance_visible:
			item.set_custom_color(0, Color(0.52, 0.55, 0.6))
		for j in range(instance.hitboxes.size()):
			var hitbox: HitboxData = instance.hitboxes[j]
			if hitbox == null:
				continue
			var child := tree.create_item(item)
			child.set_text(0, "判定框 %02d  (%s)" % [j + 1, _shape_name(hitbox.shape_type)])
			child.set_metadata(0, hitbox)
			var hitbox_visible := not hidden_hitboxes.has(hitbox.get_instance_id())
			child.add_button(0, _get_visibility_icon(hitbox_visible), EYE_BUTTON_ID, false, "隐藏判定框" if hitbox_visible else "显示判定框")
			if not hitbox_visible or not instance_visible:
				child.set_custom_color(0, Color(0.52, 0.55, 0.6))
	last_tree_signature = _build_tree_signature()

func _get_visibility_icon(visible: bool) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	if visible:
		return theme.get_icon("GuiVisibilityVisible", "EditorIcons")
	return theme.get_icon("GuiVisibilityHidden", "EditorIcons")

func _on_tree_button_clicked(item: TreeItem, _column: int, button_id: int, _mouse_button_index: int) -> void:
	if button_id != EYE_BUTTON_ID:
		return
	var value: Variant = item.get_metadata(0)
	if value is HitInstanceData:
		var instance := value as HitInstanceData
		if hidden_instances.has(instance.get_instance_id()):
			hidden_instances.erase(instance.get_instance_id())
		else:
			hidden_instances[instance.get_instance_id()] = true
		if hidden_instances.has(instance.get_instance_id()):
			if selected_instance == instance or (selected_hitbox != null and instance.hitboxes.has(selected_hitbox)):
				selected_instance = null
				selected_hitbox = null
	elif value is HitboxData:
		var hitbox := value as HitboxData
		if hidden_hitboxes.has(hitbox.get_instance_id()):
			hidden_hitboxes.erase(hitbox.get_instance_id())
		else:
			hidden_hitboxes[hitbox.get_instance_id()] = true
		if hidden_hitboxes.has(hitbox.get_instance_id()) and selected_hitbox == hitbox:
			selected_hitbox = null
	canvas.set_hidden_resources(hidden_instances, hidden_hitboxes)
	_sync_selection()
	_refresh_tree()
	_update_status()

func _on_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var item := tree.get_item_at_position(mouse_event.position)
	if item == null:
		return
	var value: Variant = item.get_metadata(0)
	if not value is HitboxData:
		return
	_show_hitbox_context_menu(value)
	tree.accept_event()

func _on_canvas_context_requested(value: HitboxData) -> void:
	_show_hitbox_context_menu(value)

func _show_hitbox_context_menu(value: HitboxData) -> void:
	context_hitbox = value
	context_instance = _parent_instance(context_hitbox)
	if context_instance == null:
		return
	selected_hitbox = context_hitbox
	selected_instance = context_instance
	_select_tree_item(context_hitbox)
	_sync_selection()
	_inspect_selected()
	_update_status()
	context_menu.clear()
	var current_index := context_instance.hitboxes.find(context_hitbox)
	context_menu.add_item("上移一层", MOVE_UP)
	context_menu.add_item("下移一层", MOVE_DOWN)
	context_menu.add_separator()
	context_menu.add_item("移至顶层", MOVE_TO_TOP)
	context_menu.add_item("移至底层", MOVE_TO_BOTTOM)
	context_menu.set_item_disabled(0, current_index >= context_instance.hitboxes.size() - 1)
	context_menu.set_item_disabled(1, current_index <= 0)
	context_menu.set_item_disabled(3, current_index >= context_instance.hitboxes.size() - 1)
	context_menu.set_item_disabled(4, current_index <= 0)
	context_menu.position = Vector2i(get_viewport().get_mouse_position())
	context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	if context_instance == null or context_hitbox == null:
		return
	var old_order: Array[HitboxData] = context_instance.hitboxes.duplicate()
	var old_index := old_order.find(context_hitbox)
	if old_index < 0:
		return
	var new_index := old_index
	match id:
		MOVE_UP:
			new_index += 1
		MOVE_DOWN:
			new_index -= 1
		MOVE_TO_TOP:
			new_index = old_order.size() - 1
		MOVE_TO_BOTTOM:
			new_index = 0
	new_index = clampi(new_index, 0, old_order.size() - 1)
	if new_index == old_index:
		return
	var new_order: Array[HitboxData] = old_order.duplicate()
	new_order.remove_at(old_index)
	new_order.insert(new_index, context_hitbox)
	if undo_redo != null:
		undo_redo.create_action("调整判定框图层")
		undo_redo.add_do_property(context_instance, "hitboxes", new_order)
		undo_redo.add_undo_property(context_instance, "hitboxes", old_order)
		undo_redo.commit_action()
	else:
		context_instance.hitboxes = new_order
	context_instance.emit_changed()
	_on_action_resource_changed()
	_select_tree_item(context_hitbox)

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
	elif value is CombatActionData:
		selected_instance = null
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
