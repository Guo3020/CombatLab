@tool
extends Resource
class_name HitboxData


# ==================================================
# 判定形状
# ==================================================

enum ShapeType {
	RECTANGLE,
	CIRCLE,
	CAPSULE
}

@export_group("形状")

@export_enum("矩形", "圆形", "胶囊形")
var shape_type: int = ShapeType.RECTANGLE


# ==================================================
# 局部变换
# ==================================================

@export_group("局部变换")

# 以 Actor 根节点原点为基准。
# 左右朝向镜像时，运行时由 HitModule 处理 X 方向。
@export var offset: Vector2 = Vector2(45.0, 0.0)

@export_range(-180.0, 180.0, 0.1)
var rotation_degrees: float = 0.0


# ==================================================
# 矩形
# ==================================================

@export_group("矩形")

@export var rectangle_size: Vector2 = Vector2(80.0, 50.0)


# ==================================================
# 圆形
# ==================================================

@export_group("圆形")

@export_range(1.0, 500.0, 1.0)
var circle_radius: float = 25.0


# ==================================================
# 胶囊形
# ==================================================

@export_group("胶囊形")

@export_range(1.0, 250.0, 1.0)
var capsule_radius: float = 20.0

# CapsuleShape2D 的 height 是胶囊整体高度，不能小于直径。
@export_range(2.0, 500.0, 1.0)
var capsule_height: float = 60.0
