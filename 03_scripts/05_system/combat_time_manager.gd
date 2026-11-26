
extends Node


# ==================================================
# 成功闪避时缓设置
# ==================================================

const SUCCESS_DODGE_TIME_SLOW_SOURCE: StringName = &"successful_dodge_time_slow"
const SUCCESS_DODGE_TIME_SLOW_MULTIPLIER: float = 0.2
const SUCCESS_DODGE_TIME_SLOW_DELAY: float = 0.1
const SUCCESS_DODGE_TIME_SLOW_DURATION: float = 0.8

var success_dodge_time_slow_delay_timer: float = 0.0
var success_dodge_time_slow_timer: float = 0.0


# ==================================================
# Actor 局部时间冻结
# ==================================================

# Key：被冻结的 Actor
# Value：
# {
#     "source_id": StringName,
#     "remaining": float
# }
#
# 同一个 Actor 同时只保留一条冻结记录。
# 新请求会直接刷新并替换旧记录。

var actor_time_freeze_records: Dictionary = {}


func _process(delta: float) -> void:
	_update_success_dodge_time_slow(delta)
	_update_actor_time_freezes(delta)


# ==================================================
# 成功闪避时缓
# ==================================================

# 成功闪避时调用：开始等待时缓延迟。
func trigger_successful_dodge_time_slow() -> void:
	# 清除上一次正在运行的时缓。
	remove_global_time_scale(
		SUCCESS_DODGE_TIME_SLOW_SOURCE
	)

	success_dodge_time_slow_timer = 0.0
	success_dodge_time_slow_delay_timer = SUCCESS_DODGE_TIME_SLOW_DELAY

	print("CombatTimeManager：成功闪避，开始等待时缓")


# 新动作成功启动时调用：取消等待或正在运行的时缓。
func cancel_successful_dodge_time_slow() -> void:
	success_dodge_time_slow_delay_timer = 0.0
	success_dodge_time_slow_timer = 0.0

	remove_global_time_scale(
		SUCCESS_DODGE_TIME_SLOW_SOURCE
	)




func _update_success_dodge_time_slow(delta: float) -> void:
	# 使用真实时间，不受游戏时间倍率影响。
	var remaining_delta: float = get_real_delta(delta)

	# 处理时缓触发延迟。
	if success_dodge_time_slow_delay_timer > 0.0:
		if remaining_delta < success_dodge_time_slow_delay_timer:
			success_dodge_time_slow_delay_timer -= remaining_delta
			return

		# 延迟结束，计算本帧剩余的真实时间。
		remaining_delta -= success_dodge_time_slow_delay_timer
		success_dodge_time_slow_delay_timer = 0.0

		_start_successful_dodge_time_slow()

	# 处理时缓持续时间。
	if success_dodge_time_slow_timer <= 0.0:
		return

	success_dodge_time_slow_timer -= remaining_delta

	if success_dodge_time_slow_timer <= 0.0:
		success_dodge_time_slow_timer = 0.0

		remove_global_time_scale(
			SUCCESS_DODGE_TIME_SLOW_SOURCE
		)

		print("CombatTimeManager：成功闪避时缓结束")


func _start_successful_dodge_time_slow() -> void:
	success_dodge_time_slow_timer = SUCCESS_DODGE_TIME_SLOW_DURATION

	add_global_time_scale(
		SUCCESS_DODGE_TIME_SLOW_SOURCE,
		SUCCESS_DODGE_TIME_SLOW_MULTIPLIER
	)

	print("CombatTimeManager：成功闪避，触发全局时缓")


# ==================================================
# Actor 局部时间冻结接口
# ==================================================

# 请求冻结 Actor。
#
# 同一个 Actor 收到新请求时：
# 直接替换旧冻结记录，重新开始计时。
#
# source_id 用于标识请求来源，不决定冻结是否叠加。

func request_actor_time_freeze(
	actor: Node,
	source_id: StringName,
	duration: float
) -> bool:
	if not is_instance_valid(actor):
		return false

	if duration <= 0.0:
		return false

	if source_id == &"":
		push_warning("CombatTimeManager：TimeFreeze 必须提供 source_id")
		return false

	actor_time_freeze_records[actor] = {
		"source_id": source_id,
		"remaining": duration
	}

	return true


# 取消 Actor 的冻结。
#
# 只有当前冻结记录的 source_id 与传入值相同时才会取消。
# 防止旧请求的结束逻辑误取消后来刷新上的冻结。

func cancel_actor_time_freeze(
	actor: Node,
	source_id: StringName
) -> void:
	if not is_instance_valid(actor):
		return

	if not actor_time_freeze_records.has(actor):
		return

	var record: Dictionary = actor_time_freeze_records[actor]

	if record.get("source_id", &"") != source_id:
		return

	actor_time_freeze_records.erase(actor)


# 更新所有 Actor 的冻结倒计时。

func _update_actor_time_freezes(delta: float) -> void:
	# 使用 keys 快照，避免遍历期间修改 Dictionary。
	var actors: Array = actor_time_freeze_records.keys()

	for actor in actors:
		if not is_instance_valid(actor):
			actor_time_freeze_records.erase(actor)
			continue

		if not actor_time_freeze_records.has(actor):
			continue

		var record: Dictionary = actor_time_freeze_records[actor]
		var remaining: float = record.get("remaining", 0.0)

		# 忽略 Actor 自身冻结，但保留全局时间和局部倍率影响。
		var actor_delta: float = get_actor_unpaused_delta(
			actor,
			delta
		)

		remaining -= actor_delta

		if remaining <= 0.0:
			actor_time_freeze_records.erase(actor)
		else:
			record["remaining"] = remaining
			actor_time_freeze_records[actor] = record


# ==================================================
# 全局时间设置
# ==================================================

var is_global_time_stopped: bool = false

# Key：效果来源 ID
# Value：时间倍率
var global_time_scale_sources: Dictionary = {}

# Key：Actor 节点
# Value：是否豁免
var global_time_stop_exempt_actors: Dictionary = {}
var global_time_scale_exempt_actors: Dictionary = {}


# ==================================================
# Actor 局部时间倍率
# ==================================================

# Key：Actor 节点
# Value：该 Actor 的时间倍率来源 Dictionary
var actor_time_scale_sources: Dictionary = {}


# ==================================================
# 获取时间增量
# ==================================================

# 真实时间：不受任何游戏时间效果影响
func get_real_delta(delta: float) -> float:
	return delta


# 世界时间：受到全局时停和全局倍率影响
func get_world_delta(delta: float) -> float:
	if is_global_time_stopped:
		return 0.0

	return delta * _get_global_time_scale()


# Actor 时间：受到全局时间、Actor 倍率和自身 TimeFreeze 影响
func get_actor_delta(actor: Node, delta: float) -> float:
	if is_actor_time_frozen(actor):
		return 0.0

	return _calculate_actor_unfrozen_delta(actor, delta)


# Actor 未冻结时间：忽略自身 TimeFreeze。
# 但仍然受到全局时间和 Actor 局部倍率影响。
func get_actor_unpaused_delta(actor: Node, delta: float) -> float:
	return _calculate_actor_unfrozen_delta(actor, delta)


func _calculate_actor_unfrozen_delta(actor: Node, delta: float) -> float:
	var global_delta := _get_global_delta_for_actor(actor, delta)
	var actor_scale := _get_actor_time_scale(actor)

	return global_delta * actor_scale


func is_actor_time_frozen(actor: Node) -> bool:
	if not is_instance_valid(actor):
		return false

	return actor_time_freeze_records.has(actor)


# ==================================================
# 全局时间倍率
# ==================================================

func add_global_time_scale(
	source_id: StringName,
	multiplier: float
) -> void:
	if multiplier < 0.0:
		push_warning("CombatTimeManager：全局时间倍率不能小于 0")
		return

	global_time_scale_sources[source_id] = multiplier


func remove_global_time_scale(source_id: StringName) -> void:
	global_time_scale_sources.erase(source_id)


func _get_global_time_scale() -> float:
	var result: float = 1.0

	for multiplier in global_time_scale_sources.values():
		result *= multiplier

	return result


# ==================================================
# Actor 局部时间倍率
# ==================================================

func add_actor_time_scale(
	actor: Node,
	source_id: StringName,
	multiplier: float
) -> void:
	if not is_instance_valid(actor):
		return

	if multiplier < 0.0:
		push_warning("CombatTimeManager：Actor 时间倍率不能小于 0")
		return

	var sources: Dictionary = actor_time_scale_sources.get(actor, {})
	sources[source_id] = multiplier
	actor_time_scale_sources[actor] = sources


func remove_actor_time_scale(
	actor: Node,
	source_id: StringName
) -> void:
	if not is_instance_valid(actor):
		return

	if not actor_time_scale_sources.has(actor):
		return

	var sources: Dictionary = actor_time_scale_sources[actor]
	sources.erase(source_id)

	if sources.is_empty():
		actor_time_scale_sources.erase(actor)
	else:
		actor_time_scale_sources[actor] = sources


func _get_actor_time_scale(actor: Node) -> float:
	if not is_instance_valid(actor):
		return 1.0

	var sources: Dictionary = actor_time_scale_sources.get(actor, {})
	var result: float = 1.0

	for multiplier in sources.values():
		result *= multiplier

	return result


# ==================================================
# 全局时停
# ==================================================

func set_global_time_stopped(stopped: bool) -> void:
	is_global_time_stopped = stopped


func add_global_time_stop_exemption(actor: Node) -> void:
	if is_instance_valid(actor):
		global_time_stop_exempt_actors[actor] = true


func remove_global_time_stop_exemption(actor: Node) -> void:
	global_time_stop_exempt_actors.erase(actor)


# ==================================================
# 全局缓速豁免
# ==================================================

func add_global_time_scale_exemption(actor: Node) -> void:
	if is_instance_valid(actor):
		global_time_scale_exempt_actors[actor] = true


func remove_global_time_scale_exemption(actor: Node) -> void:
	global_time_scale_exempt_actors.erase(actor)


# ==================================================
# 内部时间计算
# ==================================================

func _get_global_delta_for_actor(
	actor: Node,
	delta: float
) -> float:
	var is_stop_exempt := (
		is_instance_valid(actor)
		and global_time_stop_exempt_actors.has(actor)
	)

	if is_global_time_stopped and not is_stop_exempt:
		return 0.0

	var is_scale_exempt := (
		is_instance_valid(actor)
		and global_time_scale_exempt_actors.has(actor)
	)

	if is_scale_exempt:
		return delta

	return delta * _get_global_time_scale()

