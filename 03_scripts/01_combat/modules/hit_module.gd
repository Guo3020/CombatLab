extends CombatActionModule
class_name HitModule


var hit_instance_runtime: Array[Dictionary] = []


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

	var facing_direction: float = -1.0 if context.facing_direction < 0 else 1.0

	for index in range(context.action_data.hit_instances.size()):
		var hit_instance: HitInstanceData = (
			context.action_data.hit_instances[index]
		)

		if hit_instance == null:
			continue

		var runtime_area := Area2D.new()
		runtime_area.name = "HitInstance_%d" % index
		runtime_area.collision_layer = 0
		runtime_area.collision_mask = context.action_data.collision_mask
		runtime_area.monitoring = false
		runtime_area.monitorable = false

		context.actor.add_child(runtime_area)

		# 一个 HitInstance 内的多个 Hitbox 同时启停，并共享命中记录。
		for hitbox_data in hit_instance.hitboxes:
			if hitbox_data == null:
				continue

			var collision_shape := _create_collision_shape(
				hitbox_data,
				facing_direction
			)

			if collision_shape == null:
				continue

			runtime_area.add_child(collision_shape)

		var hit_targets: Array[Node2D] = []
		var runtime_state: Dictionary = {"enabled": false}

		var callback := Callable(
			self,
			"_on_body_entered"
		).bind(
			context,
			hit_instance,
			hit_targets,
			runtime_area,
			runtime_state
		)

		runtime_area.body_entered.connect(callback)

		hit_instance_runtime.append({
			"data": hit_instance,
			"area": runtime_area,
			"hit_targets": hit_targets,
			"callback": callback,
			"state": runtime_state,
			"enabled": false
		})

	_write_debug_data(context)



# ==================================================
# 创建碰撞形状
# ==================================================

func _create_collision_shape(
	hitbox_data: HitboxData,
	facing_direction: float
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

	# Hitbox 数据始终以角色朝右时为基准。
	# 朝左时镜像 X Offset，并反转旋转角度。
	collision_shape.position = Vector2(
		hitbox_data.offset.x * facing_direction,
		hitbox_data.offset.y
	)
	collision_shape.rotation_degrees = (
		hitbox_data.rotation_degrees * facing_direction
	)

	return collision_shape


# ==================================================
# 模块更新
# ==================================================

func on_module_update(context: RefCounted, delta: float) -> void:
	if context.current_phase != &"active":
		_disable_all_hit_instances()
		_write_debug_data(context)
		return

	# Executor 在本次模块回调结束后才推进 phase_elapsed。
	# 因此这里判断本次时间步 [step_start, step_end] 是否与
	# HitInstance 的 [start_time, end_time) 有交集。
	# 这样跨过时间边界的这一帧就会立即切换，不必等下一次更新。
	var step_start: float = context.phase_elapsed
	var step_end: float = step_start + maxf(delta, 0.0)

	for runtime in hit_instance_runtime:
		var hit_instance: HitInstanceData = runtime["data"]
		var area: Area2D = runtime["area"]

		if not is_instance_valid(area):
			continue

		var should_enable: bool = (
			step_end > hit_instance.start_time
			and step_start < hit_instance.end_time
			and hit_instance.end_time > hit_instance.start_time
		)

		if bool(runtime["enabled"]) == should_enable:
			continue

		runtime["enabled"] = should_enable
		runtime["state"]["enabled"] = should_enable
		area.set_deferred("monitoring", should_enable)

	_write_debug_data(context)


func _disable_all_hit_instances() -> void:
	for runtime in hit_instance_runtime:
		var area: Area2D = runtime["area"]

		if is_instance_valid(area):
			area.set_deferred("monitoring", false)

		runtime["enabled"] = false
		runtime["state"]["enabled"] = false


func _write_debug_data(context: RefCounted) -> void:
	if context == null:
		return

	var debug_instances: Array[Dictionary] = []
	var active_count: int = 0

	for index in range(hit_instance_runtime.size()):
		var runtime: Dictionary = hit_instance_runtime[index]
		var hit_instance: HitInstanceData = runtime["data"]
		var is_enabled: bool = bool(runtime["enabled"])

		if is_enabled:
			active_count += 1

		debug_instances.append({
			"index": index,
			"start_time": hit_instance.start_time,
			"end_time": hit_instance.end_time,
			"enabled": is_enabled,
			"hit_count": runtime["hit_targets"].size(),
			"area": runtime["area"]
		})

	context.runtime_data["hit_instance_runtime"] = debug_instances
	context.runtime_data["hit_instance_count"] = debug_instances.size()
	context.runtime_data["hit_instance_active_count"] = active_count
	context.runtime_data["hit_instance_collision_mask"] = context.action_data.collision_mask
	context.runtime_data["hit_module_enabled"] = true


# ==================================================
# 命中处理
# ==================================================

func _on_body_entered(
	body: Node2D,
	context: RefCounted,
	hit_instance: HitInstanceData,
	hit_targets: Array[Node2D],
	runtime_area: Area2D,
	runtime_state: Dictionary
) -> void:

	if context == null or not context.is_running:
		return

	if context.current_phase != &"active":
		return

	if not runtime_state.get("enabled", false):
		return

	if not is_instance_valid(runtime_area) or not runtime_area.monitoring:
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

	# 无敌状态不记录命中，也不触发普通 Hitstop。
	if hit_result == DefenseController.HitResult.INVINCIBLE:
		if target_defense.should_trigger_time_slow_on_success():
			CombatTimeManager.trigger_successful_dodge_time_slow()
		return

	# 正常命中和免伤都记录目标。
	hit_targets.append(body)
	context.target = body

	# 只有正常命中才扣除生命并检查打断。
	if hit_result == DefenseController.HitResult.HIT:
		body.take_damage(hit_instance.damage)
		HitManager.process_hit(
			context as CombatActionContext,
			body
		)

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
		context.runtime_data.erase("hit_instance_runtime")
		context.runtime_data.erase("hit_instance_count")
		context.runtime_data.erase("hit_instance_active_count")
		context.runtime_data.erase("hit_instance_collision_mask")
		context.runtime_data["hit_module_enabled"] = false

