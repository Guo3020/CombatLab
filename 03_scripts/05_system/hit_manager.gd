
extends Node


signal target_interrupted(
	target: Node,
	attacker: Node,
	action_progress: float,
	phase_name: String
)


func process_hit(
	attacker_context: CombatActionContext,
	target: Node
) -> bool:
	if not is_instance_valid(target):
		return false

	if attacker_context == null:
		return false

	if attacker_context.action_data == null:
		return false

	if target.get("is_dead") == true:
		return false

	if not target.has_method("get_effective_super_armor_level"):
		return false

	# 获取目标当前动作执行器
	var target_action_executor: Node = target.get_node_or_null(
		"CombatActionExecutor"
	)

	# 保存被打断时的动作进度
	var action_progress: float = 0.0
	var phase_name: String = "待机"

	if target_action_executor != null:
		if target_action_executor.is_action_running():
			var target_context: CombatActionContext = (
				target_action_executor.current_context
			)

			if target_context != null and target_context.action_data != null:
				var target_action_data: CombatActionData = (
					target_context.action_data
				)

				# 不可覆盖的动作不能被打断
				if target_action_data.unoverrideable:
					print(target.name, "：当前动作不可被打断")
					return false

				var total: float = (
					target_action_data.startup
					+ target_action_data.active
					+ target_action_data.recovery
				)

				if total > 0.0:
					action_progress = clampf(
						target_context.elapsed_time / total,
						0.0,
						1.0
					)

				phase_name = str(target_context.current_phase)

	# 比较攻击者打断等级与目标有效霸体等级
	var interrupt_level: int = attacker_context.action_data.interrupt_level
	var super_armor_level: int = target.get_effective_super_armor_level()

	if interrupt_level <= super_armor_level:
		return false

	# 优先取消整个 Combo
	var combo_executor: Node = target.get_node_or_null(
		"CombatComboExecutor"
	)

	if combo_executor != null:
		var combo_running: bool = bool(
			combo_executor.get("is_combo_running")
		)

		if combo_running and combo_executor.has_method("cancel_combo"):
			combo_executor.cancel_combo()
		else:
			_cancel_target_action(target)
	else:
		_cancel_target_action(target)

	print(target.name, "：进入受击动画状态")

	# 发送打断事件
	target_interrupted.emit(
		target,
		attacker_context.actor,
		action_progress,
		phase_name
	)

	return true


func _cancel_target_action(target: Node) -> void:
	var action_executor: Node = target.get_node_or_null(
		"CombatActionExecutor"
	)

	if action_executor == null:
		return

	if action_executor.has_method("is_action_running"):
		if action_executor.is_action_running():
			action_executor.cancel_action()
