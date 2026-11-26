
extends Node
class_name EnemyAIController


enum Mode {
	STATIONARY,
	CHASE_AND_ATTACK
}


@export_group("AI 模式")
@export var mode: Mode = Mode.CHASE_AND_ATTACK

@export_group("感知设置")
@export var detection_range: float = 300.0

@export_group("攻击设置")
@export var attack_range: float = 48.0
@export var attack_cooldown: float = 0.75

@export_group("攻击 Combo 列表")
@export var attack_combos: Array[EnemyAttackComboEntry] = []


var enemy: EnemyBase
var target_player: Node2D

var is_player_detected: bool = false
var attack_cooldown_timer: float = 0.0


func _ready() -> void:
	enemy = get_parent() as EnemyBase

	if enemy == null:
		push_warning("AIController：找不到 EnemyBase 父节点")
		return

	call_deferred("_connect_combo_signals")


func _connect_combo_signals() -> void:
	if enemy == null:
		return

	if enemy.combat_combo_executor == null:
		push_error("AIController：找不到 CombatComboExecutor")
		return

	enemy.combat_combo_executor.combo_action_started.connect(
		_on_combo_action_started
	)


func _process(delta: float) -> void:
	if enemy == null:
		return

	if enemy.is_dead:
		enemy.movement_controller.stop_moving()
		return

	var actor_delta: float = CombatTimeManager.get_actor_delta(
		enemy,
		delta
	)

	# 局部冻结期间，AI 的冷却、感知和行为全部暂停。
	if actor_delta <= 0.0:
		return

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer = maxf(
			attack_cooldown_timer - actor_delta,
			0.0
		)

	if mode == Mode.STATIONARY:
		enemy.movement_controller.stop_moving()
		return

	_update_player_detection()
	_update_behavior()


# ==================================================
# 玩家感知
# ==================================================

func _update_player_detection() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if player == null or player.get("is_dead") == true:
		target_player = null
		_set_player_detected(false)

		if enemy.combat_combo_executor.is_combo_running:
			enemy.combat_combo_executor.cancel_combo()

		enemy.movement_controller.stop_moving()
		return

	var distance := enemy.global_position.distance_to(
		player.global_position
	)

	var detected := distance <= detection_range

	if detected:
		target_player = player
	else:
		target_player = null

	_set_player_detected(detected)


func _set_player_detected(detected: bool) -> void:
	if is_player_detected == detected:
		return

	is_player_detected = detected


# ==================================================
# 行为判断
# ==================================================

func _update_behavior() -> void:
	if target_player == null:
		enemy.movement_controller.stop_moving()
		return

	var horizontal_distance := (
		target_player.global_position.x
		- enemy.global_position.x
	)

	# 面向玩家。
	if horizontal_distance != 0.0:
		enemy.set_facing_direction(signf(horizontal_distance))

	# Combo 正在执行，不重复启动攻击。
	if enemy.combat_combo_executor.is_combo_running:
		enemy.movement_controller.stop_moving()
		return

	# 如果有其他 Action 正在执行，暂不发起攻击。
	if enemy.combat_action_executor.is_action_running():
		enemy.movement_controller.stop_moving()
		return

	# 进入攻击范围。
	if absf(horizontal_distance) <= attack_range:
		enemy.movement_controller.stop_moving()
		_try_attack()
		return

	# 尚未进入攻击范围，继续追踪。
	enemy.movement_controller.set_move_direction(
		signf(horizontal_distance)
	)


# ==================================================
# 权重随机选择 Combo
# ==================================================

func _select_attack_combo() -> CombatComboData:
	var valid_entries: Array[EnemyAttackComboEntry] = []
	var total_weight: float = 0.0

	# 收集有效选项并计算总权重。
	for entry in attack_combos:
		if entry == null:
			continue

		if entry.combo_data == null:
			continue

		if entry.weight <= 0.0:
			continue

		valid_entries.append(entry)
		total_weight += entry.weight

	# 没有可用选项。
	if valid_entries.is_empty() or total_weight <= 0.0:
		return null

	# 在总权重范围内随机抽取。
	var random_value := randf_range(0.0, total_weight)

	for entry in valid_entries:
		random_value -= entry.weight

		if random_value < 0.0:
			return entry.combo_data

	# 浮点误差保护。
	return valid_entries.back().combo_data


# ==================================================
# 发起攻击
# ==================================================

func _try_attack() -> void:
	if attack_cooldown_timer > 0.0:
		return

	var selected_combo: CombatComboData = _select_attack_combo()

	if selected_combo == null:
		return

	# 创建启动 Combo 请求。
	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.START_COMBO
	request.combo_data = selected_combo

	# 统一交给 CombatComboExecutor 处理。
	var request_accepted: bool = (
		enemy.combat_combo_executor.submit_request(request)
	)

	# 只有请求成功提交，才启动攻击冷却。
	if request_accepted:
		attack_cooldown_timer = attack_cooldown


# ==================================================
# AI 自动请求 Combo 下一段
# ==================================================

func _on_combo_action_started(
	action_index: int,
	_context: CombatActionContext
) -> void:
	var combo_executor := enemy.combat_combo_executor

	if not combo_executor.is_combo_running:
		return

	if combo_executor.current_combo_data == null:
		return

	# 最后一段不需要请求下一段。
	if combo_executor.current_combo_data.is_last_action(action_index):
		return

	# 创建继续 Combo 请求。
	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.CONTINUE_COMBO

	combo_executor.submit_request(request)


# ==================================================
# Debug 数据
# ==================================================

func get_debug_data() -> Dictionary:
	var mode_name := "STATIONARY"

	if mode == Mode.CHASE_AND_ATTACK:
		mode_name = "CHASE_AND_ATTACK"

	var combo_executor := enemy.combat_combo_executor if enemy != null else null

	var combo_running := false
	var combo_index := -1
	var combo_total := 0
	var time_frozen := false

	if enemy != null:
		time_frozen = CombatTimeManager.is_actor_time_frozen(enemy)

	if combo_executor != null:
		combo_running = combo_executor.is_combo_running

		if combo_running and combo_executor.current_combo_data != null:
			combo_index = combo_executor.current_action_index + 1
			combo_total = combo_executor.current_combo_data.get_action_count()

	return {
		"mode": mode_name,
		"player_detected": is_player_detected,
		"attack_cooldown": attack_cooldown_timer,
		"attack_cooldown_max": attack_cooldown,
		"attack_range": attack_range,
		"detection_range": detection_range,
		"combo_running": combo_running,
		"combo_index": combo_index,
		"combo_total": combo_total,
		"time_frozen": time_frozen,
		"is_dead": enemy.is_dead if enemy != null else false
	}
