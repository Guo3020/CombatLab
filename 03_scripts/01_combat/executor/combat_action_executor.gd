
extends Node
class_name CombatActionExecutor


const DEBUG_ACTION_OVERRIDE: bool = true


# ==================================================
# 信号
# ==================================================

signal action_started(context: CombatActionContext)
signal action_phase_changed(context: CombatActionContext)
signal action_finished(context: CombatActionContext, was_cancelled: bool)


# ==================================================
# 当前动作
# ==================================================

var current_context: CombatActionContext = null

var active_modules: Array[CombatActionModule] = []

var last_movement_debug: Dictionary = {}


# ==================================================
# 动作启动
# ==================================================

func start_action(
	action_data: CombatActionData,
	actor: Node2D,
	facing_direction: int = 1,
	input_direction: Vector2 = Vector2.ZERO
) -> bool:

	if DEBUG_ACTION_OVERRIDE:
		print("\n========== Action Start Request ==========")

		if action_data != null:
			print(
				"请求动作：", action_data.action_name,
				" | Priority：", action_data.action_priority,
				" | Unoverrideable：", action_data.unoverrideable
			)
		else:
			print("请求动作：null")

		print("当前是否有运行中的 Action：", is_action_running())

		if is_action_running():
			print(
				"当前动作：", current_context.action_data.action_name,
				" | Priority：", current_context.action_data.action_priority,
				" | Phase：", current_context.current_phase,
				" | Unoverrideable：", current_context.action_data.unoverrideable,
				" | Cancelable Flags：", current_context.action_data.cancelable_phases
			)

	# 基础检查。
	if action_data == null:
		if DEBUG_ACTION_OVERRIDE:
			print("[拒绝] action_data 为 null")
		return false

	if actor == null:
		if DEBUG_ACTION_OVERRIDE:
			print("[拒绝] actor 为 null")
		return false

	# 检查当前动作是否允许被覆盖。
	if is_action_running():
		var can_override := _can_override_current_action(action_data)

		if DEBUG_ACTION_OVERRIDE:
			print("覆盖判断结果：", can_override)

		if not can_override:
			if DEBUG_ACTION_OVERRIDE:
				print("[拒绝] 当前 Action 不允许被覆盖")
				print("==========================================\n")
			return false

	# 检查并消耗动作所需能量。
	if action_data.energy_cost > 0.0:
		var energy := actor.get_node_or_null("CombatEnergy") as CombatEnergy

		if energy == null:
			push_warning("CombatActionExecutor：动作需要能量，但角色没有 CombatEnergy")
			if DEBUG_ACTION_OVERRIDE:
				print("[拒绝] 找不到 CombatEnergy")
			return false

		if not energy.consume_energy(action_data.energy_cost):
			print("能量不足，无法启动动作：", action_data.action_name)
			if DEBUG_ACTION_OVERRIDE:
				print("[拒绝] 能量不足")
			return false

	# 新动作成功通过启动检查，取消之前的成功闪避时缓。
	CombatTimeManager.cancel_successful_dodge_time_slow()

	# 如果旧动作仍在运行，标记为被新动作替换。
	if is_action_running():
		if DEBUG_ACTION_OVERRIDE:
			print(
				"[覆盖成功] 结束旧动作：",
				current_context.action_data.action_name
			)

		_finish_action(true, &"replaced")

	# 创建新动作上下文。
	current_context = CombatActionContext.new()
	current_context.setup(
		action_data,
		actor,
		facing_direction,
		input_direction
	)

	# 清理模块列表。
	active_modules.clear()
	current_context.module_debug_data.clear()

	# --------------------------------------------------
	# 自动创建 HitModule
	# --------------------------------------------------

	var has_hit_instances: bool = false

	for hit_instance in action_data.hit_instances:
		if hit_instance != null:
			has_hit_instances = true
			break

	if has_hit_instances:
		var hit_module := HitModule.new()

		active_modules.append(hit_module)
		hit_module.on_module_start(current_context)

		current_context.module_debug_data.append({
			"module_id": String(hit_module.get_module_id()),
			"module_name": hit_module.module_name,
			"enabled": true,
			"running": true
		})

	# --------------------------------------------------
	# 启动其他启用的模块
	# --------------------------------------------------

	for module in action_data.modules:
		if module == null:
			continue

		if not module.module_enabled:
			continue

		# HitModule 由 Executor 自动创建，跳过手动配置项。
		if module is HitModule:
			continue

		active_modules.append(module)
		module.on_module_start(current_context)

		# 记录模块调试信息。
		current_context.module_debug_data.append({
			"module_id": String(module.get_module_id()),
			"module_name": module.module_name,
			"enabled": true,
			"running": true
		})

	action_started.emit(current_context)

	if DEBUG_ACTION_OVERRIDE:
		print("[启动成功] ", action_data.action_name)
		print("==========================================\n")

	return true


# ==================================================
# 动作覆盖判断
# ==================================================

func can_interrupt_current_action(
	requested_priority: int
) -> bool:
	if not is_action_running():
		return true

	return _can_override_current_action_by_priority(
		requested_priority
	)


func _can_override_current_action(
	new_action: CombatActionData
) -> bool:
	if new_action == null:
		return false

	return _can_override_current_action_by_priority(
		new_action.action_priority
	)


func _can_override_current_action_by_priority(
	requested_priority: int
) -> bool:

	if current_context == null:
		if DEBUG_ACTION_OVERRIDE:
			print("[覆盖判断] current_context 为 null，允许覆盖")
		return true

	var current_action: CombatActionData = current_context.action_data

	if DEBUG_ACTION_OVERRIDE:
		print("\n---------- Action Override Check ----------")
		print("当前动作：", current_action.action_name)
		print("当前 Priority：", current_action.action_priority)
		print("请求 Priority：", requested_priority)
		print("当前 Phase：", current_context.current_phase)
		print("Unoverrideable：", current_action.unoverrideable)
		print("Cancelable Flags：", current_action.cancelable_phases)

	# 当前动作禁止被覆盖。
	if current_action.unoverrideable:
		if DEBUG_ACTION_OVERRIDE:
			print("[覆盖失败] 当前动作 Unoverrideable")
			print("-------------------------------------------")
		return false

	# 新行为优先级更高，可以无视普通取消阶段限制。
	if requested_priority > current_action.action_priority:
		if DEBUG_ACTION_OVERRIDE:
			print("[覆盖成功] 请求 Priority 更高")
			print("-------------------------------------------")
		return true

	# 优先级相同或更低，检查当前动作是否允许在当前阶段被取消。
	var current_phase: StringName = current_context.current_phase

	if not current_action.can_be_cancelled_from(current_phase):
		if DEBUG_ACTION_OVERRIDE:
			print("[覆盖失败] 当前阶段不允许取消")
			print("-------------------------------------------")
		return false

	if DEBUG_ACTION_OVERRIDE:
		print("[覆盖成功] 当前阶段允许取消")
		print("-------------------------------------------")

	return true


# ==================================================
# 动作更新
# ==================================================

func _process(delta: float) -> void:
	if not is_action_running():
		return

	var actor_delta: float = CombatTimeManager.get_actor_delta(
		current_context.actor,
		delta
	)

	if actor_delta <= 0.0:
		return

	# 锁定本次更新开始时的动作上下文。
	var processing_context: CombatActionContext = current_context
	var remaining_time: float = actor_delta

	# 防止异常配置导致阶段切换死循环。
	var safety_counter: int = 0

	while (
		processing_context.is_running
		and current_context == processing_context
		and safety_counter < 8
	):
		var phase_duration: float = _get_phase_duration()
		var phase_remaining: float = phase_duration - processing_context.phase_elapsed

		# 当前阶段已经结束，进入下一阶段。
		if phase_remaining <= 0.00001:
			_advance_phase()
			safety_counter += 1

			# 动作结束或被替换，立即退出旧动作循环。
			if (
				current_context != processing_context
				or not processing_context.is_running
			):
				return

			continue

		# 本次更新没有剩余时间。
		if remaining_time <= 0.0:
			break

		# 计算本次实际推进的时间。
		var step_time: float = min(remaining_time, phase_remaining)

		# 更新当前动作的所有模块。
		for module in active_modules:
			if (
				current_context != processing_context
				or not processing_context.is_running
			):
				return

			module.on_module_update(processing_context, step_time)

		# 再次确认动作没有被替换。
		if (
			current_context != processing_context
			or not processing_context.is_running
		):
			return

		# 更新动作计时。
		processing_context.phase_elapsed += step_time
		processing_context.elapsed_time += step_time
		remaining_time -= step_time
		safety_counter += 1


# ==================================================
# 阶段时间
# ==================================================

func _get_phase_duration() -> float:
	if current_context == null:
		return 0.0

	var data: CombatActionData = current_context.action_data

	match current_context.current_phase:
		&"startup":
			return data.startup
		&"active":
			return data.active
		&"recovery":
			return data.recovery

	return 0.0


# ==================================================
# 阶段切换
# ==================================================

func _advance_phase() -> void:
	if current_context == null:
		return

	match current_context.current_phase:
		&"startup":
			current_context.set_phase(&"active")
			action_phase_changed.emit(current_context)

		&"active":
			current_context.set_phase(&"recovery")
			action_phase_changed.emit(current_context)

		&"recovery":
			_finish_action(false, &"completed")


# ==================================================
# 结束动作
# ==================================================

func _finish_action(
	was_cancelled: bool,
	end_reason: StringName
) -> void:
	if current_context == null:
		return

	# 防止同一个动作重复结束。
	if not current_context.is_running:
		return

	# 保存本次结束的动作上下文。
	var finished_context: CombatActionContext = current_context

	# 在模块清理运行数据之前，保存 Movement 调试信息。
	if finished_context.runtime_data.has("movement_debug"):
		last_movement_debug = finished_context.runtime_data["movement_debug"].duplicate(true)

	# 将结束原因写入 Context。
	finished_context.runtime_data["action_end_reason"] = end_reason
	finished_context.runtime_data["action_was_cancelled"] = was_cancelled

	# 通知所有模块结束。
	for module in active_modules:
		module.on_module_end(finished_context)

	# 更新模块调试状态。
	for module_debug in finished_context.module_debug_data:
		module_debug["running"] = false

	finished_context.is_running = false
	action_finished.emit(finished_context, was_cancelled)


# ==================================================
# 主动取消动作
# ==================================================

func cancel_action() -> bool:
	if not is_action_running():
		return false

	_finish_action(true, &"cancelled")
	return true


# ==================================================
# 状态查询
# ==================================================

func is_action_running() -> bool:
	return (
		current_context != null
		and current_context.is_running
	)


# ==================================================
# 面向锁定查询
# ==================================================

func is_facing_locked() -> bool:
	return is_action_running()


func get_locked_facing_direction() -> int:
	if not is_facing_locked():
		return 0

	return current_context.facing_direction


# ==================================================
# Debug 数据接口
# ==================================================

func get_debug_data() -> Dictionary:
	# 当前没有动作上下文时，仍然提供上一次 Movement 调试数据。
	if current_context == null:
		var empty_runtime_data: Dictionary = {}

		if not last_movement_debug.is_empty():
			empty_runtime_data["movement_debug"] = last_movement_debug.duplicate(true)

		return {
			"action_active": false,
			"runtime_data": empty_runtime_data
		}

	# 复制当前运行数据，避免修改 Context 本身。
	var runtime_data: Dictionary = current_context.runtime_data.duplicate(true)

	# 当前动作没有 Movement 调试数据时，使用上一次保存的数据。
	if not runtime_data.has("movement_debug"):
		if not last_movement_debug.is_empty():
			runtime_data["movement_debug"] = last_movement_debug.duplicate(true)

	return {
		"action_active": current_context.is_running,
		"action_id": String(current_context.action_data.action_id),
		"action_name": current_context.action_data.action_name,
		"phase": String(current_context.current_phase),
		"elapsed_time": current_context.elapsed_time,
		"phase_elapsed": current_context.phase_elapsed,
		"facing_direction": current_context.facing_direction,
		"modules": current_context.module_debug_data,
		"runtime_data": runtime_data
	}
