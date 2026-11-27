
extends Node
class_name EnemyMovementController


# ==================================================
# 移动参数
# ==================================================

@export var move_speed: float = 120.0


# ==================================================
# 内部状态
# ==================================================

var actor: CharacterBody2D
var move_direction: float = 0.0


# ==================================================
# 初始化
# ==================================================

func _ready() -> void:
	actor = get_parent() as CharacterBody2D

	if actor == null:
		push_warning("MovementController：找不到 CharacterBody2D 父节点")


# ==================================================
# 移动控制接口
# ==================================================

# ==================================================
# CombatMovementInterface
# ==================================================

# 当前敌人仍只使用原有 AI 移动逻辑。
# 这两个方法仅提供统一请求契约，暂不把 Action Movement 应用到敌人移动。
func receive_action_movement_request(
	_source_id: StringName,
	_request: Dictionary
) -> bool:
	return true


func notify_movement_action_finished(
	_source_id: StringName,
	_end_reason: CombatMovementInterface.MovementEndReason
) -> void:
	pass


# ==================================================
# AI 移动控制
# ==================================================

func set_move_direction(direction: float) -> void:
	move_direction = clampf(direction, -1.0, 1.0)


func stop_moving() -> void:
	move_direction = 0.0


# ==================================================
# 移动更新
# ==================================================

func update_movement() -> void:
	if actor == null:
		return

	actor.velocity.x = move_direction * move_speed
