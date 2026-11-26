
extends CombatActionModule
class_name DefenseModule


enum DefenseType {
	INVINCIBLE,
	DAMAGE_IMMUNE
}

enum ActivationMode {
	PHASE_RANGE,
	DURATION
}

enum ActivationPhase {
	STARTUP,
	ACTIVE,
	RECOVERY
}


@export_group("防御设置")
@export var defense_type: DefenseType = DefenseType.INVINCIBLE
@export var activation_mode: ActivationMode = ActivationMode.PHASE_RANGE
@export var trigger_time_slow_on_success: bool = false


@export_group("阶段范围模式")
@export var start_phase: ActivationPhase = ActivationPhase.ACTIVE
@export var end_phase: ActivationPhase = ActivationPhase.ACTIVE


@export_group("持续时间模式")
@export var duration_start_phase: ActivationPhase = ActivationPhase.ACTIVE
@export var duration: float = 0.2


func get_module_id() -> StringName:
	return &"defense"


func on_module_start(context: RefCounted) -> void:
	var defense_controller := _get_defense_controller(context)
	if defense_controller == null:
		return

	var source_id := _get_source_id(context)

	if not module_enabled:
		_clear_defense_source(defense_controller, source_id)
		return

	if activation_mode == ActivationMode.PHASE_RANGE:
		if _is_phase_in_range(context.current_phase):
			_set_defense_source(defense_controller, source_id)
		else:
			_clear_defense_source(defense_controller, source_id)

	else:
		var started_key := _get_runtime_key(context, "duration_started")
		var remaining_key := _get_runtime_key(context, "duration_remaining")
		var finished_key := _get_runtime_key(context, "duration_finished")

		context.runtime_data[started_key] = false
		context.runtime_data[remaining_key] = 0.0
		context.runtime_data[finished_key] = false

		if _is_duration_start_phase(context.current_phase):
			_start_duration(context, defense_controller, source_id)


func on_module_update(context: RefCounted, delta: float) -> void:
	var defense_controller := _get_defense_controller(context)
	if defense_controller == null:
		return

	var source_id := _get_source_id(context)

	if not module_enabled:
		_clear_defense_source(defense_controller, source_id)
		return

	if activation_mode == ActivationMode.PHASE_RANGE:
		if _is_phase_in_range(context.current_phase):
			_set_defense_source(defense_controller, source_id)
		else:
			_clear_defense_source(defense_controller, source_id)

	else:
		_update_duration(
			context,
			defense_controller,
			source_id,
			delta
		)


func on_module_end(context: RefCounted) -> void:
	var defense_controller := _get_defense_controller(context)
	if defense_controller == null:
		return

	var source_id := _get_source_id(context)

	# 延迟清理旧来源。
	# 如果新动作已经替换了来源，旧来源 ID 不会清除新来源。
	if defense_type == DefenseType.INVINCIBLE:
		defense_controller.call_deferred(
			"clear_action_invincible_source",
			source_id
		)
	else:
		defense_controller.call_deferred(
			"clear_action_damage_immune_source",
			source_id
		)


# ==================================================
# 阶段范围模式
# ==================================================

func _is_phase_in_range(phase: StringName) -> bool:
	var current_order := _get_phase_order_from_name(phase)
	var start_order := int(start_phase)
	var end_order := int(end_phase)

	if current_order < 0:
		return false

	if start_order > end_order:
		return false

	# 开始阶段和结束阶段都包含在范围内。
	return current_order >= start_order and current_order <= end_order


# ==================================================
# 持续时间模式
# ==================================================

func _update_duration(
	context: RefCounted,
	defense_controller: DefenseController,
	source_id: StringName,
	delta: float
) -> void:
	var started_key := _get_runtime_key(context, "duration_started")
	var remaining_key := _get_runtime_key(context, "duration_remaining")
	var finished_key := _get_runtime_key(context, "duration_finished")

	var has_started: bool = context.runtime_data.get(
		started_key,
		false
	)

	var is_finished: bool = context.runtime_data.get(
		finished_key,
		false
	)

	# 已结束，不再重复执行。
	if is_finished:
		return

	# 尚未开始：等待进入指定阶段。
	if not has_started:
		if _is_duration_start_phase(context.current_phase):
			_start_duration(context, defense_controller, source_id)
		return

	var remaining: float = context.runtime_data.get(
		remaining_key,
		0.0
	)

	# Executor 传入的 delta 已经应用过角色时间倍率。
	# 这里直接使用，不再重复计算。
	remaining = maxf(remaining - delta, 0.0)
	context.runtime_data[remaining_key] = remaining

	# 持续时间结束，只执行一次。
	if remaining <= 0.0:
		context.runtime_data[finished_key] = true

		_clear_defense_source(
			defense_controller,
			source_id
		)


func _start_duration(
	context: RefCounted,
	defense_controller: DefenseController,
	source_id: StringName
) -> void:
	var started_key := _get_runtime_key(context, "duration_started")
	var remaining_key := _get_runtime_key(context, "duration_remaining")
	var finished_key := _get_runtime_key(context, "duration_finished")

	context.runtime_data[started_key] = true
	context.runtime_data[finished_key] = false

	if duration <= 0.0:
		context.runtime_data[remaining_key] = 0.0
		context.runtime_data[finished_key] = true

		_clear_defense_source(
			defense_controller,
			source_id
		)

		push_warning("DefenseModule：持续时间必须大于 0")
		return

	context.runtime_data[remaining_key] = duration

	_set_defense_source(
		defense_controller,
		source_id
	)


func _is_duration_start_phase(phase: StringName) -> bool:
	return phase == _get_phase_name(duration_start_phase)


# ==================================================
# 通用辅助函数
# ==================================================

func _get_phase_name(phase: ActivationPhase) -> StringName:
	match phase:
		ActivationPhase.STARTUP:
			return &"startup"
		ActivationPhase.ACTIVE:
			return &"active"
		ActivationPhase.RECOVERY:
			return &"recovery"

	return &""


func _get_phase_order_from_name(phase: StringName) -> int:
	match phase:
		&"startup":
			return 0
		&"active":
			return 1
		&"recovery":
			return 2

	return -1


func _get_runtime_key(
	_context: RefCounted,
	suffix: String
) -> StringName:
	return StringName(
		"defense_%s_%s" % [
			get_instance_id(),
			suffix
		]
	)


func _get_source_id(context: RefCounted) -> StringName:
	var key := StringName(
		"defense_source_%s" % get_instance_id()
	)

	if not context.runtime_data.has(key):
		context.runtime_data[key] = StringName(
			"action_%s_module_%s" % [
				context.get_instance_id(),
				get_instance_id()
			]
		)

	return context.runtime_data[key]


func _set_defense_source(
	defense_controller: DefenseController,
	source_id: StringName
) -> void:
	if defense_type == DefenseType.INVINCIBLE:
		defense_controller.set_action_invincible_source(
			source_id,
			trigger_time_slow_on_success
		)
	else:
		defense_controller.set_action_damage_immune_source(source_id)


func _clear_defense_source(
	defense_controller: DefenseController,
	source_id: StringName = &""
) -> void:
	if defense_type == DefenseType.INVINCIBLE:
		defense_controller.clear_action_invincible_source(source_id)
	else:
		defense_controller.clear_action_damage_immune_source(source_id)


func _get_defense_controller(
	context: RefCounted
) -> DefenseController:
	if context.actor == null:
		return null

	return context.actor.get_node_or_null(
		"DefenseController"
	) as DefenseController
