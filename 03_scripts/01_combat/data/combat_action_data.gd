@tool
extends Resource
class_name CombatActionData


# ==================================================
# 初始化
# ==================================================

func _init() -> void:
	if modules.is_empty():
		modules = [
			MovementModule.new()
		]

	

# ==================================================
# 基础信息
# ==================================================

@export_group("基础信息")

@export var action_id: StringName = &""
@export var action_name: String = "新动作"
@export var action_type: StringName = &"attack"


# ==================================================
# 时间和消耗
# ==================================================

@export_group("动作时间")

@export_range(0.0, 5.0, 0.01)
var startup: float = 0.1

@export_range(0.0, 5.0, 0.01)
var active: float = 0.15

@export_range(0.0, 5.0, 0.01)
var recovery: float = 0.25

@export_range(0.0, 2.0, 0.01)
var input_window: float = 0.15

@export_range(0.0, 100.0, 1.0)
var energy_cost: float = 0.0


# ==================================================
# 动作覆盖与取消
# ==================================================

@export_group("动作覆盖与取消")

@export_range(0, 10, 1)
var action_priority: int = 0

@export var unoverrideable: bool = false

@export_flags("Startup", "Active", "Recovery")
var cancelable_phases: int = 4


const PHASE_STARTUP: int = 1
const PHASE_ACTIVE: int = 2
const PHASE_RECOVERY: int = 4


func can_be_cancelled_from(phase: StringName) -> bool:
	var phase_flag: int = 0

	match phase:
		&"startup":
			phase_flag = PHASE_STARTUP
		&"active":
			phase_flag = PHASE_ACTIVE
		&"recovery":
			phase_flag = PHASE_RECOVERY

	if phase_flag == 0:
		return false

	return (cancelable_phases & phase_flag) != 0


# ==================================================
# 受击打断与霸体
# ==================================================

@export_group("受击打断与霸体")

@export_range(0, 10, 1)
var interrupt_level: int = 0

@export_range(0, 10, 1)
var super_armor_level: int = 0

var input_buffer_enabled: bool = true


# ==================================================
# 功能模块
# ==================================================

@export_group("功能模块分组")

@export var hit_module_enabled: bool = false:
	set(value):
		if hit_module_enabled == value:
			return
		hit_module_enabled = value
		if hit_module_enabled:
			ensure_hit_instance()
		notify_property_list_changed()
		emit_changed()

@export_group("命中实例")
@export var hit_instances: Array[HitInstanceData] = []

@export_group("其他功能模块")
@export var modules: Array[CombatActionModule] = []


func ensure_hit_instance() -> void:
	if hit_module_enabled and hit_instances.is_empty():
		hit_instances.append(HitInstanceData.new())
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "hit_instances" and not hit_module_enabled:
		property.usage = PROPERTY_USAGE_STORAGE
