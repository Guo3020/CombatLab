
@tool
extends CombatActionModule
class_name HitstopModule


const FRAME_DURATION: float = 1.0 / 60.0


# ==================================================
# 攻击者局部冻结
# ==================================================

@export_group("攻击者局部冻结")

@export var attacker_time_freeze_enabled: bool = true

@export_range(0.0, 1.0, 0.001)
var attacker_time_freeze_duration: float = 0.05:
	set(value):
		attacker_time_freeze_duration = value
		target_time_freeze_duration = value + FRAME_DURATION


# ==================================================
# 命中目标局部冻结
# ==================================================

@export_group("目标局部冻结")

@export var target_time_freeze_enabled: bool = true

@export_range(0.0, 1.0, 0.001)
var target_time_freeze_duration: float = 0.066667


# ==================================================
# 发出局部冻结请求
# ==================================================

func apply_hitstop(context: CombatActionContext) -> void:
	if context == null:
		return

	if not is_instance_valid(context.actor):
		return

	# 使用动作 Context 和模块实例生成来源 ID。
	# 攻击者与目标使用不同 ID。
	var source_prefix: String = "time_freeze_%d_%d" % [
		context.get_instance_id(),
		get_instance_id()
	]

	if attacker_time_freeze_enabled:
		CombatTimeManager.request_actor_time_freeze(
			context.actor,
			StringName(source_prefix + "_attacker"),
			attacker_time_freeze_duration
		)

	if target_time_freeze_enabled:
		if is_instance_valid(context.target):
			CombatTimeManager.request_actor_time_freeze(
				context.target,
				StringName(source_prefix + "_target"),
				target_time_freeze_duration
			)
