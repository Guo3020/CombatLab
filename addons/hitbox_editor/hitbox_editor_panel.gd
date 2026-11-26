@tool
extends VBoxContainer

var current_resource: Resource
var title_label: Label
var info_label: Label
var preview: Control


func _ready() -> void:
	custom_minimum_size = Vector2(320.0, 300.0)
	
	title_label = Label.new()
	title_label.text = "Hitbox Editor — Preview"
	add_child(title_label)

	info_label = Label.new()
	info_label.text = "在 Inspector 中选择一个 HitboxData Resource。"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info_label)

	preview = Control.new()
	preview.set_script(preload("res://addons/hitbox_editor/hitbox_editor_preview.gd"))
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(280.0, 240.0)
	add_child(preview)


func set_editing_resource(object: Object) -> void:
	if object is Resource and _has_hitbox_properties(object):
		current_resource = object
		info_label.text = "当前资源：%s" % object.resource_path.get_file()
		preview.set_resource_data(object)
	else:
		current_resource = null
		if is_instance_valid(info_label):
			info_label.text = "在 Inspector 中选择一个 HitboxData Resource。"
		if is_instance_valid(preview):
			preview.set_resource_data(null)


func _has_hitbox_properties(resource: Resource) -> bool:
	var has_shape_type := false
	var has_offset := false
	for property_info in resource.get_property_list():
		if property_info.name == "shape_type":
			has_shape_type = true
		elif property_info.name == "offset":
			has_offset = true
	return has_shape_type and has_offset
