extends Node
class_name SkillSelector


@export_group("普通技能")
@export var normal_skill: CombatComboData

@export_group("强化特殊技")
@export var special_skill: CombatComboData


var actor: Node2D = null
var combat_energy: CombatEnergy = null
var combo_executor: CombatComboExecutor = null


func _ready() -> void:
	actor = get_parent() as Node2D

	if actor == null:
		push_error("SkillSelector：没有找到所属角色")
		return

	combat_energy = actor.get_node_or_null(
		"CombatEnergy"
	) as CombatEnergy

	combo_executor = actor.get_node_or_null(
		"CombatComboExecutor"
	) as CombatComboExecutor

	if combat_energy == null:
		push_error("SkillSelector：没有找到 CombatEnergy")
		return

	if combo_executor == null:
		push_error("SkillSelector：没有找到 CombatComboExecutor")
		return


func request_skill() -> bool:
	if combat_energy == null or combo_executor == null:
		return false

	if normal_skill == null:
		push_warning("SkillSelector：没有配置普通技能")
		return false

	# 默认选择普通技能。
	var selected_skill := normal_skill

	# 能量足够时，优先选择强化特殊技。
	if special_skill != null and special_skill.get_action_count() > 0:
		var first_action := special_skill.get_action(0)

		if combat_energy.has_enough_energy(first_action.energy_cost):
			selected_skill = special_skill

	# 创建统一动作请求。
	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.START_COMBO
	request.combo_data = selected_skill

	return combo_executor.submit_request(request)