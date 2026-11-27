
extends CharacterBody2D
class_name EnemyBase


signal debug_damage_number(world_position: Vector2, amount: float)


@export_group("生命值")
@export var max_health: float = 100.0

@export_group("受击设置")
@export_range(0, 10, 1)
var default_super_armor_level: int = 0
@export var hit_reaction_action: CombatActionData


func get_effective_super_armor_level() -> int:
	if combat_action_executor.is_action_running():
		var action_data: CombatActionData = (
			combat_action_executor.current_context.action_data
		)

		if action_data.action_type == &"hit_reaction":
			return default_super_armor_level

		return action_data.super_armor_level

	return default_super_armor_level


var current_health: float = 0.0
var is_dead: bool = false

@onready var movement_controller: EnemyMovementController = $MovementController
@onready var combat_action_executor: CombatActionExecutor = $CombatActionExecutor
@onready var combat_combo_executor: CombatComboExecutor = $CombatComboExecutor
@onready var defense_controller: DefenseController = $DefenseController

@onready var polygon: Polygon2D = $Polygon2D
@onready var polygon_base_scale: Vector2 = $Polygon2D.scale

var facing_direction: float = 1.0


func _ready() -> void:
	current_health = max_health

	if not HitManager.target_interrupted.is_connected(
		_on_target_interrupted
	):
		HitManager.target_interrupted.connect(
			_on_target_interrupted
		)

	if not combat_action_executor.action_started.is_connected(
		_on_executor_action_started
	):
		combat_action_executor.action_started.connect(
			_on_executor_action_started
		)


# ==============================
# 朝向
# ==============================

func get_facing_direction() -> int:
	return int(facing_direction)


# 普通面向更新入口。
# Action 运行期间锁定面向，不响应外部普通更新。
func set_facing_direction(direction: float) -> void:
	if direction == 0.0:
		return

	if combat_action_executor.is_facing_locked():
		return

	_set_facing_direction(direction)


# 强制设置面向。
# 仅供 Action 启动时同步 Context 面向等需要绕过锁定的情况使用。
func _set_facing_direction(direction: float) -> void:
	if direction == 0.0:
		return

	facing_direction = signf(direction)

	polygon.scale.x = absf(polygon_base_scale.x) * facing_direction
	polygon.scale.y = polygon_base_scale.y


# 新 Action 启动时，以新 Context 的面向作为锁定方向。
func _on_executor_action_started(
	context: CombatActionContext
) -> void:
	if context == null:
		return

	_set_facing_direction(context.facing_direction)


# ==============================
# 生命值与受伤
# ==============================

func take_damage(damage: float) -> void:
	if is_dead:
		return

	if damage <= 0.0:
		return

	current_health = maxf(current_health - damage, 0.0)

	print(name, "受到伤害：", damage)
	print("剩余生命值：", current_health)

	if current_health <= 0.0:
		die()


# ==============================
# 死亡
# ==============================

func die() -> void:
	if is_dead:
		return

	is_dead = true

	velocity = Vector2.ZERO
	movement_controller.stop_moving()

	if combat_combo_executor.is_combo_running:
		combat_combo_executor.cancel_combo()

	if combat_action_executor.is_action_running():
		combat_action_executor.cancel_action()

	print(name, "被击败！")


# ==============================
# 物理更新
# ==============================

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var actor_delta: float = CombatTimeManager.get_actor_delta(
		self,
		delta
	)

	if actor_delta <= 0.0:
		return

	movement_controller.update_movement()
	_move_and_slide_with_time_scale(actor_delta, delta)


# ==============================
# 受击反应
# ==============================

func _on_target_interrupted(
	target: Node,
	_attacker: Node,
	_action_progress: float,
	_phase_name: String
) -> void:
	if target != self:
		return

	if is_dead:
		return

	if hit_reaction_action == null:
		push_warning(name, "：没有配置受击 Action")
		return

	var request := CombatActionRequest.new()
	request.request_type = CombatActionRequest.RequestType.START_ACTION
	request.action_data = hit_reaction_action

	combat_combo_executor.submit_request(request)


# ==============================
# 时间倍率移动
# ==============================

func _move_and_slide_with_time_scale(
	actor_delta: float,
	physics_delta: float
) -> void:
	if physics_delta <= 0.0 or actor_delta <= 0.0:
		return

	var time_scale: float = actor_delta / physics_delta

	velocity *= time_scale
	move_and_slide()
	velocity /= time_scale
