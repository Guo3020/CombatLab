@tool
extends Control

const CANVAS_SCRIPT = preload("res://addons/hitbox_editor/hitbox_editor_canvas.gd")
const TIMELINE_SCRIPT = preload("res://addons/hitbox_editor/hitbox_editor_timeline.gd")

var action_data: CombatActionData
var selected_instance: HitInstanceData
var selected_hitbox: HitboxData
var tree: Tree
var canvas: Control
var timeline: Control
var status: Label
var plugin: EditorPlugin
var last_tree_signature: String = ""

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

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220.0
	split.add_child(left)

	var list_label := Label.new()
	list_label.text = "HitInstance / Hitbox 列表"
	left.add_child(list_label)

	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(_on_tree_selected)
	left.add_child(tree)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center)

	var canvas_label := Label.new()
	canvas_label.text = "二维工作区 — 角色原点"
	center.add_child(canvas_label)

	canvas = Control.new()
	canvas.set_script(CANVAS_SCRIPT)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(500, 360)
	canvas.hitbox_selected.connect(_on_canvas_selected)
	center.add_child(canvas)

	var timeline_label := Label.new()
	timeline_label.text = "Active 时间轴"
	center.add_child(timeline_label)

	timeline = Control.new()
	timeline.set_script(TIMELINE_SCRIPT)
	timeline.custom_minimum_size = Vector2(500, 112)
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.hit_instance_selected.connect(_on_timeline_selected)
	center.add_child(timeline)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)
	_show_empty()
	set_process(true)

func _process(_delta: float) -> void:
	if action_data == null:
		return

	# Resource properties edited in the Inspector do not always emit
	# Resource.changed. Refresh the small editor views while this tool is open.
	canvas.queue_redraw()
	timeline.queue_redraw()

	var signature := _build_tree_signature()
	if signature != last_tree_signature:
		_refresh_tree()
		_update_status()

func set_editor_plugin(value: EditorPlugin) -> void:
	plugin = value
	if is_instance_valid(canvas):
		canvas.set_undo_redo(plugin.get_undo_redo())

func set_action_data(value: CombatActionData) -> void:
	if value == null:
		return
	if action_data == value:
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
				j,
				hitbox.shape_type,
				str(hitbox.offset),
				str(hitbox.rectangle_size),
				hitbox.rotation_degrees,
				str(hitbox.circle_radius),
				str(hitbox.capsule_radius),
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
		status.text = "%s  |  请在左侧选择命中实例或判定框。" % label

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
