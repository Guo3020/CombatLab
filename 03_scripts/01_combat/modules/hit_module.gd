
extends CombatActionModule
class_name HitModule


var hit_instance_runtime: Array[Dictionary] = []


func _init() -> void:
	module_name = "Hit"


func get_module_id() -> StringName:
	return &"hit"


# ==================================================
# 模块启动
# ==================================================

func on_module_start(context: RefCounted) -> void:
	hit_instance_runtime.clear()

	if context == null or context.action_data == null:
		return

	if context.actor == null:
		return

	var template_area := context.actor.get_node_or_null(
		"AttackArea"
	) as Area2D

	var collision_mask: int = 1

	if template_area != null:
		collision_mask = template_area.collision_mask
	else:
		push_warning(
			"HitModule：找不到旧 AttackArea，暂时使用默认 Collision Mask 1"
		)

	for index in range(context.action_data.hit_instances.size()):
		var hit_instance: HitInstanceData = (
			context.action_data.hit_instances[index]
		)

		if hit_instance == null:
			continue

		var runtime_area := Area2D.new()
		runtime_area.name = "HitInstance_%d" % index
		runtime_area.collision_layer = 0
		runtime_area.collision_mask = collision_mask
		runtime_area.monitoring = false
		runtime_area.monitorable = false

		context.actor.add_child(runtime_area)

		# 每个 HitboxData 创建一个 CollisionShape2D。
		for hitbox_data in hit_instance.hitboxes:
			if hitbox_data == null:
				continue

			var collision_shape := _create_collision_shape(hitbox_data)

			if collision_shape == null:
				continue

			runtime_area.add_child(collision_shape)

		var hit_targets: Array[Node2D] = []

		var callback := Callable(
			self,
			"_on_body_entered"
		).bind(
			context,
			hit_instance,
			hit_targets
		)

		runtime_area.body_entered.connect(callback)

		hit_instance_runtime.append({
			"data": hit_instance,
			"area": runtime_area,
			"hit_targets": hit_targets,
			"callback": callback,
			"enabled": false
		})

	context.runtime_data["hit_module_enabled"] = true
	context.runtime_data["hit_instance_count"] = hit_instance_runtime.size()

	print(
		"HitModule：启动，HitInstance 数量：",
		hit_instance_runtime.size()
	)


# ==================================================
# 创建碰撞形状
# ==================================================

func _create_collision_shape(
	hitbox_data: HitboxData
) -> CollisionShape2D:

	var collision_shape := CollisionShape2D.new()

	match hitbox_data.shape_type:
		HitboxData.ShapeType.RECTANGLE:
			var rectangle := RectangleShape2D.new()
			rectangle.size = hitbox_data.rectangle_size
			collision_shape.shape = rectangle

		HitboxData.ShapeType.CIRCLE:
			var circle := CircleShape2D.new()
			circle.radius = hitbox_data.circle_radius
			collision_shape.shape = circle

		HitboxData.ShapeType.CAPSULE:
			var capsule := CapsuleShape2D.new()
			capsule.radius = hitbox_data.capsule_radius
			capsule.height = maxf(
				hitbox_data.capsule_height,
				hitbox_data.capsule_radius * 2.0
			)
			collision_shape.shape = capsule

		_:
			push_warning("HitModule：不支持的 Hitbox Shape 类型")
			collision_shape.queue_free()
			return null

	collision_shape.position = hitbox_data.offset
	collision_shape.rotation_degrees = hitbox_data.rotation_degrees

	return collision_shape


# ==================================================
# 模块更新
# ==================================================

func on_module_update(context: RefCounted, _delta: float) -> void:
	if context.current_phase != &"active":
		_disable_all_hit_instances()
		return

	var active_time: float = context.phase_elapsed

	for runtime in hit_instance_runtime:
		var hit_instance: HitInstanceData = runtime["data"]
		var area: Area2D = runtime["area"]

		if not is_instance_valid(area):
			continue

		var should_enable: bool = (
			active_time >= hit_instance.start_time
			and active_time < hit_instance.end_time
		)

		if bool(runtime["enabled"]) == should_enable:
			continue

		runtime["enabled"] = should_enable
		area.set_deferred("monitoring", should_enable)

	context.runtime_data["hit_module_enabled"] = true


func _disable_all_hit_instances() -> void:
	for runtime in hit_instance_runtime:
		var area: Area2D = runtime["area"]

		if is_instance_valid(area):
			area.set_deferred("monitoring", false)

		runtime["enabled"] = false


# ==================================================
# 命中处理
# ==================================================

func _on_body_entered(
	body: Node2D,
	context: RefCounted,
	hit_instance: HitInstanceData,
	hit_targets: Array
) -> void:

	if context == null or not context.is_running:
		return

	if context.current_phase != &"active":
		return

	if body == null or not is_instance_valid(body):
		return

	if body == context.actor:
		return

	if body.get("is_dead") == true:
		return

	if not body.has_method("take_damage"):
		return

	# 同一个 HitInstance 对同一目标只结算一次。
	if body in hit_targets:
		return

	var target_defense := body.get_node_or_null(
		"DefenseController"
	) as DefenseController

	if target_defense == null:
		push_warning("HitModule：目标缺少 DefenseController")
		return

	var hit_result: int = target_defense.get_hit_result()

	# 无敌状态不记录命中。
	if hit_result == DefenseController.HitResult.INVINCIBLE:
		if target_defense.should_trigger_time_slow_on_success():
			CombatTimeManager.trigger_successful_dodge_time_slow()
			print("HitModule：成功闪避，触发全局时缓")
		else:
			print("HitModule：目标处于无敌状态，攻击无效")

		return

	# 正常命中和免伤都记录目标。
	hit_targets.append(body)
	context.target = body

	# 正常命中。
	if hit_result == DefenseController.HitResult.HIT:
		body.take_damage(hit_instance.damage)

		HitManager.process_hit(
			context as CombatActionContext,
			body
		)

		if (
			context.actor != null
			and context.actor.has_signal("debug_damage_number")
		):
			context.actor.emit_signal(
				"debug_damage_number",
				body.global_position,
				hit_instance.damage
			)

		print(
			"HitModule：正常命中 ",
			body.name,
			" | 伤害：",
			hit_instance.damage
		)

	# 免伤。
	elif hit_result == DefenseController.HitResult.IMMUNE:
		print("HitModule：目标处于免伤状态，未造成伤害")

	# 正常命中和免伤都会触发本次 HitInstance 的 Hitstop。
	_apply_hitstop(context, hit_instance)


# ==================================================
# Hitstop
# ==================================================

func _apply_hitstop(
	context: RefCounted,
	hit_instance: HitInstanceData
) -> void:

	if not hit_instance.hitstop_enabled:
		return

	if context.actor == null or not is_instance_valid(context.actor):
		return

	var source_prefix: String = "hitstop_%d_%d" % [
		context.get_instance_id(),
		hit_instance.get_instance_id()
	]

	if hit_instance.attacker_time_freeze_enabled:
		CombatTimeManager.request_actor_time_freeze(
			context.actor,
			StringName(source_prefix + "_attacker"),
			hit_instance.attacker_time_freeze_duration
		)

	if (
		hit_instance.target_time_freeze_enabled
		and context.target != null
		and is_instance_valid(context.target)
	):
		CombatTimeManager.request_actor_time_freeze(
			context.target,
			StringName(source_prefix + "_target"),
			hit_instance.target_time_freeze_duration
		)


# ==================================================
# 模块结束
# ==================================================

func on_module_end(context: RefCounted) -> void:
	_disable_all_hit_instances()

	for runtime in hit_instance_runtime:
		var area: Area2D = runtime["area"]

		if is_instance_valid(area):
			area.queue_free()

	hit_instance_runtime.clear()

	if context != null:
		context.runtime_data["hit_module_enabled"] = false

	print("HitModule：模块结束")
