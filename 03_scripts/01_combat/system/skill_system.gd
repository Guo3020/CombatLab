extends Node
class_name SkillSystem


signal resources_changed(
	current_energy: float,
	max_energy: float,
	current_decibel: float,
	max_decibel: float
)


const MAX_ENERGY: float = 100.0
const MAX_DECIBEL: float = 3000.0


@export_group("技能配置")
@export var normal_skill: CombatComboData
@export var special_skill: CombatComboData
@export var ultimate_action_data: CombatActionData


@export_group("初始资源")
@export_range(0.0, 100.0, 1.0)
var starting_energy: float = 0.0

@export_range(0.0, 3000.0, 1.0)
var starting_decibel: float = 0.0


var current_energy: float = 0.0
var current_decibel: float = 0.0

var actor: Node2D = null
var combo_executor: CombatComboExecutor = null


func _ready() -> void:
	current_energy = clampf(starting_energy, 0.0, MAX_ENERGY)
	current_decibel = clampf(starting_decibel, 0.0, MAX_DECIBEL)

	actor = get_parent() as Node2D

	if actor == null:
		push_error("SkillSystem：没有找到所属角色")
		return

	combo_executor = actor.get_node_or_null(
		"CombatComboExecutor"
	) as CombatComboExecutor

	if combo_executor == null:
		push_error("SkillSystem：没有找到 CombatComboExecutor")
		return

	_emit_resources_changed()


# ==================================================
# 技能请求
# ==================================================

func request_skill() -> bool:
	if combo_executor == null:
		return false

	if normal_skill == null:
		push_warning("SkillSystem：没有配置普通技能")
		return false

	# 默认选择普通技能。
	var selected_skill := normal_skill

	# 第一段能量足够时，优先选择强化特殊技。
	if special_skill != null and special_skill.get_action_count() > 0:
		var first_action := special_skill.get_action(0)

		if can_pay_action_cost(first_action):
			selected_skill = special_skill

	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.START_COMBO
	request.combo_data = selected_skill

	return combo_executor.submit_request(request)


func request_ultimate() -> bool:
	if combo_executor == null:
		return false

	if ultimate_action_data == null:
		return false

	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.START_ACTION
	request.action_data = ultimate_action_data

	return combo_executor.submit_request(request)


# ==================================================
# 能量
# ==================================================

func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return

	var previous_energy := current_energy
	current_energy = minf(current_energy + amount, MAX_ENERGY)

	if current_energy != previous_energy:
		_emit_resources_changed()


func consume_energy(amount: float) -> bool:
	if amount < 0.0 or not has_enough_energy(amount):
		return false

	if amount == 0.0:
		return true

	current_energy -= amount
	_emit_resources_changed()
	return true


func has_enough_energy(amount: float) -> bool:
	return amount >= 0.0 and current_energy >= amount


# ==================================================
# 喧响值
# ==================================================

func add_decibel(amount: float) -> void:
	if amount <= 0.0:
		return

	var previous_decibel := current_decibel
	current_decibel = minf(current_decibel + amount, MAX_DECIBEL)

	if current_decibel != previous_decibel:
		_emit_resources_changed()


func consume_decibel(amount: float) -> bool:
	if amount < 0.0 or not has_enough_decibel(amount):
		return false

	if amount == 0.0:
		return true

	current_decibel -= amount
	_emit_resources_changed()
	return true


func has_enough_decibel(amount: float) -> bool:
	return amount >= 0.0 and current_decibel >= amount


# ==================================================
# Action 资源消耗
# ==================================================

func can_pay_action_cost(action_data: CombatActionData) -> bool:
	if action_data == null:
		return false

	var decibel_cost := action_data.get_decibel_cost()

	return (
		has_enough_energy(action_data.energy_cost)
		and has_enough_decibel(decibel_cost)
	)


func consume_action_cost(action_data: CombatActionData) -> bool:
	if not can_pay_action_cost(action_data):
		return false

	var energy_cost := action_data.energy_cost
	var decibel_cost := action_data.get_decibel_cost()

	# 先检查全部资源，再统一扣除，避免只扣除其中一种资源。
	if energy_cost > 0.0:
		current_energy -= energy_cost

	if decibel_cost > 0.0:
		current_decibel -= decibel_cost

	if energy_cost > 0.0 or decibel_cost > 0.0:
		_emit_resources_changed()

	return true


# ==================================================
# 资源信号
# ==================================================

func _emit_resources_changed() -> void:
	resources_changed.emit(
		current_energy,
		MAX_ENERGY,
		current_decibel,
		MAX_DECIBEL
	)
