extends RefCounted
class_name CombatMovementInterface


# ==================================================
# Action Movement 生命周期原因
# ==================================================

enum MovementEndReason {
	COMPLETED,
	CANCELLED,
	REPLACED,
	JUMP_INTERRUPTED
}


# ==================================================
# 统一请求契约（Duck Typing）
# ==================================================
# GDScript 不支持传统接口的多继承。
# 此类集中定义方法约定并负责安全分发；它不是移动控制器。
# Actor 提供的 movement_request_handler 只需实现下面两个方法。


static func supports(handler: Object) -> bool:
	if not is_instance_valid(handler):
		return false

	return (
		handler.has_method("receive_action_movement_request")
		and handler.has_method("notify_movement_action_finished")
	)


static func receive_action_movement_request(
	handler: Object,
	source_id: StringName,
	request: Dictionary
) -> bool:
	if not supports(handler):
		return false

	return bool(
		handler.call(
			"receive_action_movement_request",
			source_id,
			request
		)
	)


static func notify_movement_action_finished(
	handler: Object,
	source_id: StringName,
	end_reason: MovementEndReason
) -> void:
	if not supports(handler):
		return

	handler.call(
		"notify_movement_action_finished",
		source_id,
		end_reason
	)
