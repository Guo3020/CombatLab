
extends Resource
class_name CombatComboData


@export_group("连击基本信息")

@export var combo_id: StringName = &""
@export var combo_name: String = "新连击"


@export_group("连击动作")

# 按顺序排列的动作资源
@export var actions: Array[CombatActionData] = []


# ==================================================
# 连击数据接口
# ==================================================

# 获取连击总段数
func get_action_count() -> int:
	return actions.size()


# 根据段数获取动作
func get_action(index: int) -> CombatActionData:
	if index < 0 or index >= actions.size():
		return null

	return actions[index]


# 判断是否存在指定段数
func has_action(index: int) -> bool:
	return index >= 0 and index < actions.size()


# 判断是否为最后一段
func is_last_action(index: int) -> bool:
	return index == actions.size() - 1
