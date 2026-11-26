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

func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "HIT EDITOR"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var inspect := Button.new()
	inspect.text = "Inspect Selected Resource"
	inspect.pressed.connect(_inspect_selected)
	header.add_child(inspect)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220.0
	split.add_child(left)
	var list_label := Label.new()
	list_label.text = "Hit Instances / Hitboxes"
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
	canvas_label.text = "2D Workspace — Actor Origin"
	center.add_child(canvas_label)
	canvas = Control.new()
	canvas.set_script(CANVAS_SCRIPT)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(500, 360)
	canvas.hitbox_selected.connect(_on_canvas_selected)
	center.add_child(canvas)
	var timeline_label := Label.new()
	timeline_label.text = "Active Timeline"
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

func set_editor_plugin(value: EditorPlugin) -> void:
	plugin = value
	if is_instance_valid(canvas):
		canvas.set_undo_redo(plugin.get_undo_redo())

func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_instance = null
	selected_hitbox = null
	if not is_instance_valid(tree):
		return
	_refresh_tree()
	canvas.set_action_data(value)
	timeline.set_action_data(value)
	_update_status()

func _refresh_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	if action_data == null:
		return
	for i in range(action_data.hit_instances.size()):
		var instance: HitInstanceData = action_data.hit_instances[i]
		if instance == null:
			continue
		var item := tree.create_item(root)
		item.set_text(0, "HitInstance %02d  [%.2f - %.2f]" % [i + 1, instance.start_time, instance.end_time])
		item.set_metadata(0, instance)
		for j in range(instance.hitboxes.size()):
			var hitbox: HitboxData = instance.hitboxes[j]
			if hitbox == null:
				continue
			var child := tree.create_item(item)
			child.set_text(0, "Hitbox %02d  (%s)" % [j + 1, _shape_name(hitbox.shape_type)])
			child.set_metadata(0, hitbox)

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
		status.text = "Select a CombatActionData resource in FileSystem."
		return
	var label := action_data.resource_path.get_file()
	if label.is_empty():
		label = action_data.action_name
	if selected_hitbox != null:
		status.text = "%s  |  Hitbox Offset: %s" % [label, str(selected_hitbox.offset)]
	elif selected_instance != null:
		status.text = "%s  |  HitInstance %.2f - %.2f s" % [label, selected_instance.start_time, selected_instance.end_time]
	else:
		status.text = "%s  |  Select a HitInstance or Hitbox." % label

func _show_empty() -> void:
	status.text = "Select a CombatActionData resource in FileSystem."
	canvas.set_action_data(null)
	timeline.set_action_data(null)

func _shape_name(value: int) -> String:
	match value:
		HitboxData.ShapeType.RECTANGLE: return "Rectangle"
		HitboxData.ShapeType.CIRCLE: return "Circle"
		HitboxData.ShapeType.CAPSULE: return "Capsule"
	return "Unknown"
