
extends RefCounted
class_name CombatActionRequest

enum RequestType {
	CONTINUE_COMBO,
	START_COMBO,
	START_ACTION
}

var request_type: int = RequestType.START_ACTION
var combo_data: CombatComboData = null
var action_data: CombatActionData = null

# 请求携带的方向快照。
# 0 表示尚未指定面向，提交请求时由角色当前面向补齐。
var facing_direction: int = 0
var input_direction: Vector2 = Vector2.ZERO

# 标记方向是否已经捕获，避免缓存请求再次提交时覆盖原快照。
var actor_state_captured: bool = false


func capture_actor_state(actor: Node) -> void:
	if actor == null or actor_state_captured:
		return

	# 没有显式指定面向时，读取角色当前面向。
	if facing_direction == 0:
		if actor.has_method("get_facing_direction"):
			facing_direction = int(actor.call("get_facing_direction"))
		else:
			for property in actor.get_property_list():
				if property["name"] == "facing_direction":
					facing_direction = int(actor.get("facing_direction"))
					break

	# 没有显式指定输入方向时，读取角色当前移动输入。
	if input_direction == Vector2.ZERO:
		for property in actor.get_property_list():
			if property["name"] == "move_input_vector":
				var value: Variant = actor.get("move_input_vector")
				if value is Vector2:
					input_direction = value
				break

	actor_state_captured = true
