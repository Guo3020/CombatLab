
extends Resource
class_name CombatActionModule


@export_group("模块基本信息")

@export var module_enabled: bool = true

@export var module_name: String = "新模块"


# 模块唯一标识
func get_module_id() -> StringName:
	return &"base"


# 模块开始执行时调用
func on_module_start(_context: RefCounted) -> void:
	pass


# 模块每帧更新时调用
func on_module_update(_context: RefCounted, _delta: float) -> void:
	pass


# 模块结束时调用
func on_module_end(_context: RefCounted) -> void:
	pass
