@tool
extends EditorInspectorPlugin

func _can_handle(object: Object) -> bool:
	return object is Curve and String(object.resource_name).begins_with("MovementTrack")


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if object is Curve and name in ["bake_resolution", "min_domain", "max_domain", "min_value", "max_value"]:
		return true
	return false
