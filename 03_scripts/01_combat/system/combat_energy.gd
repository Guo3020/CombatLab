
extends Node
class_name CombatEnergy


# ==================================================
# 信号
# ==================================================

signal energy_changed(current_energy: float, max_energy: float)


# ==================================================
# 能量配置
# ==================================================

const MAX_ENERGY: float = 100.0

@export_range(0.0, 100.0, 1.0)
var starting_energy: float = 0.0

var current_energy: float = 0.0


# ==================================================
# 初始化
# ==================================================

func _ready() -> void:
	current_energy = clampf(starting_energy, 0.0, MAX_ENERGY)


# ==================================================
# 增加能量
# ==================================================

func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return

	var previous_energy := current_energy

	current_energy = minf(
		current_energy + amount,
		MAX_ENERGY
	)

	if current_energy != previous_energy:
		energy_changed.emit(current_energy, MAX_ENERGY)


# ==================================================
# 消耗能量
# ==================================================

func consume_energy(amount: float) -> bool:
	if amount < 0.0:
		return false

	if not has_enough_energy(amount):
		return false

	if amount == 0.0:
		return true

	current_energy -= amount

	energy_changed.emit(current_energy, MAX_ENERGY)

	return true


# ==================================================
# 检查能量是否足够
# ==================================================

func has_enough_energy(amount: float) -> bool:
	if amount < 0.0:
		return false

	return current_energy >= amount
