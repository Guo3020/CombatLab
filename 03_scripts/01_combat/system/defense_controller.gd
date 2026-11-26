
extends Node
class_name DefenseController


enum HitResult {
	HIT,
	IMMUNE,
	INVINCIBLE
}


@export_group("防御状态（手动测试）")
@export var manual_invincible: bool = false
@export var manual_damage_immune: bool = false


# 当前动作提供的无敌来源
var _invincible_source: StringName = &""

# 当前无敌来源是否允许触发成功闪避时缓
var _trigger_time_slow_on_success: bool = false

# 当前动作提供的免伤来源
var _damage_immune_source: StringName = &""


# 最终无敌状态：手动状态或动作来源任意一个生效即可
var is_invincible: bool:
	get:
		return manual_invincible or _invincible_source != &""


# 最终免伤状态
var is_damage_immune: bool:
	get:
		return manual_damage_immune or _damage_immune_source != &""


# 兼容旧接口：作为手动状态开关使用
func set_invincible(enabled: bool) -> void:
	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	manual_invincible = enabled

	_print_state_changes(old_invincible, old_immune)


func set_damage_immune(enabled: bool) -> void:
	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	manual_damage_immune = enabled

	_print_state_changes(old_invincible, old_immune)


# 启用或替换动作无敌来源
func set_action_invincible_source(
	source_id: StringName,
	trigger_time_slow: bool = false
) -> void:
	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	_invincible_source = source_id
	_trigger_time_slow_on_success = trigger_time_slow

	_print_state_changes(old_invincible, old_immune)


# 查询当前无敌来源是否允许触发成功闪避时缓
func should_trigger_time_slow_on_success() -> bool:
	return (
		_invincible_source != &""
		and _trigger_time_slow_on_success
	)


# 清除动作无敌来源
# 如果指定了来源 ID，只允许清除匹配的来源
# 如果来源 ID 为空，则清除当前动作来源
func clear_action_invincible_source(
	source_id: StringName = &""
) -> void:
	if source_id != &"" and _invincible_source != source_id:
		return

	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	_invincible_source = &""
	_trigger_time_slow_on_success = false

	_print_state_changes(old_invincible, old_immune)


# 启用或替换动作免伤来源
func set_action_damage_immune_source(source_id: StringName) -> void:
	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	_damage_immune_source = source_id

	_print_state_changes(old_invincible, old_immune)


# 清除动作免伤来源
func clear_action_damage_immune_source(
	source_id: StringName = &""
) -> void:
	if source_id != &"" and _damage_immune_source != source_id:
		return

	var old_invincible := is_invincible
	var old_immune := is_damage_immune

	_damage_immune_source = &""

	_print_state_changes(old_invincible, old_immune)


func get_hit_result() -> HitResult:
	if is_invincible:
		return HitResult.INVINCIBLE

	if is_damage_immune:
		return HitResult.IMMUNE

	return HitResult.HIT


func _print_state_changes(
	old_invincible: bool,
	old_immune: bool
) -> void:
	if old_invincible != is_invincible:
		if is_invincible:
			print("DefenseController：进入无敌状态")
		else:
			print("DefenseController：退出无敌状态")

	if old_immune != is_damage_immune:
		if is_damage_immune:
			print("DefenseController：进入免伤状态")
		else:
			print("DefenseController：退出免伤状态")

