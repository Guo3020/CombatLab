
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
