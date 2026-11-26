@tool
extends Resource
class_name HitInstanceData


const FRAME_DURATION: float = 1.0 / 60.0


func _init() -> void:
	if hitboxes.is_empty():
		hitboxes = [
			HitboxData.new()
		]


# ==================================================
# 命中时间
# ==================================================

@export_group("命中时间")

# 时间均相对于 Action 的 Active 阶段起点。
@export_range(0.0, 5.0, 0.01)
var start_time: float = 0.0

@export_range(0.0, 5.0, 0.01)
var end_time: float = 0.1


# ==================================================
# 命中效果
# ==================================================

@export_group("命中效果")

@export_range(0.0, 10000.0, 0.1)
var damage: float = 10.0


# ==================================================
# 攻击判定
# ==================================================

# 同一个 HitInstance 的所有 Hitbox 同时开启和关闭，
# 并共享同一份目标命中记录。
@export_group("攻击判定")

# 运行时 HitInstance Area2D 使用的碰撞遮罩。
# 默认 1，保持原 AttackArea 的默认检测层。
@export_flags_2d_physics var collision_mask: int = 1

@export var hitboxes: Array[HitboxData] = []


# ==================================================
# Hitstop
# ==================================================

@export_group("Hitstop")

@export var hitstop_enabled: bool = true

# 保留旧 HitstopModule 对攻击者和目标分别启用/关闭的能力。
@export var attacker_time_freeze_enabled: bool = true

@export_range(0.0, 1.0, 0.001)
var attacker_time_freeze_duration: float = 0.05:
	set(value):
		attacker_time_freeze_duration = value
		target_time_freeze_duration = value + FRAME_DURATION

@export var target_time_freeze_enabled: bool = true

@export_range(0.0, 1.0, 0.001)
var target_time_freeze_duration: float = 0.066667
