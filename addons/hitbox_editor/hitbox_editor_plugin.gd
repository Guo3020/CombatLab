@tool
extends EditorPlugin

const PANEL_SCRIPT = preload("res://addons/hitbox_editor/hitbox_editor_panel.gd")
var main_panel: Control

func _enter_tree() -> void:
	main_panel = Control.new()
	main_panel.set_script(PANEL_SCRIPT)
	main_panel.name = "HitEditor"
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(main_panel)
	main_panel.set_editor_plugin(self)
	main_panel.hide()

func _exit_tree() -> void:
	if is_instance_valid(main_panel):
		main_panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Hit Editor"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if is_instance_valid(main_panel):
		main_panel.visible = visible

func _handles(object: Object) -> bool:
	return object is CombatActionData

func _edit(object: Object) -> void:
	# Inspector selection may temporarily move to another object when the
	# user clicks the editor workspace. Keep the last Action pinned.
	if object is CombatActionData and is_instance_valid(main_panel):
		main_panel.set_action_data(object)
