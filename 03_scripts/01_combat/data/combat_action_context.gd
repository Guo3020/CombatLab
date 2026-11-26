
extends RefCounted
class_name CombatActionContext


# ==================================================
# 动作基本信息
# ==================================================

var action_data: CombatActionData = null
var actor: Node2D = null
var target: Node2D = null


# ==================================================
# 动作状态
# ==================================================

var current_phase: StringName = &""
var is_running: bool = false
var elapsed_time: float = 0.0
var phase_elapsed: float = 0.0


# ==================================================
# 方向数据
# ==================================================

# 角色当前面向：只表示朝左还是朝右。
var facing_direction: int = 1

# 动作启动时采集的输入方向，可以是八方向。
var input_direction: Vector2 = Vector2.ZERO

# 当前动作实际采用的攻击方向。
# 默认使用角色面向，之后可以由目标吸附逻辑修改。
var attack_direction: Vector2 = Vector2.RIGHT


# ==================================================
# 运行时数据
# ==================================================

var runtime_data: Dictionary = {}
var module_debug_data: Array[Dictionary] = []


# ==================================================
# 初始化
# ==================================================

func setup(
	new_action_data: CombatActionData,
	new_actor: Node2D,
	new_facing_direction: int = 1,
	new_input_direction: Vector2 = Vector2.ZERO
) -> void:

	action_data = new_action_data
	actor = new_actor

	facing_direction = 1 if new_facing_direction >= 0 else -1

	input_direction = new_input_direction.normalized()

	# 初始攻击方向回退到角色面向。
	attack_direction = Vector2.RIGHT * facing_direction

	target = null

	current_phase = &"startup"
	is_running = true

	elapsed_time = 0.0
	phase_elapsed = 0.0

	runtime_data.clear()
	module_debug_data.clear()


# ==================================================
# 方向设置
# ==================================================

func set_attack_direction(direction: Vector2) -> void:

	if direction.length_squared() <= 0.0001:
		attack_direction = Vector2.RIGHT * facing_direction
		return

	attack_direction = direction.normalized()


# ==================================================
# 阶段管理
# ==================================================

func set_phase(new_phase: StringName) -> void:
	current_phase = new_phase
	phase_elapsed = 0.0


# ==================================================
# 运行时数据接口
# ==================================================

func set_runtime_value(key: StringName, value: Variant) -> void:
	runtime_data[key] = value


func get_runtime_value(
	key: StringName,
	default_value: Variant = null
) -> Variant:
	return runtime_data.get(key, default_value)
