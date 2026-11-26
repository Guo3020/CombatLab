extends Resource
class_name EnemyAttackComboEntry


@export_group("攻击 Combo")
@export var combo_data: CombatComboData

@export_group("选择权重")
@export_range(0.0, 100.0, 0.1)
var weight: float = 1.0