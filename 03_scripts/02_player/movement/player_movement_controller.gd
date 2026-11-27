extends RefCounted
class_name PlayerMovementController


# ==================================================
# 枚举
# ==================================================

enum MovementMode {
	NONE,
	DASH,
	VELOCITY_OVERRIDE,
	MOVEMENT_TRACK
}

enum PhaseMode {
	SPEED_PROTECTION,
	LINEAR_INTERPOLATION,
	DIRECT_SET
}

enum EndVelocityMode {
	PRESERVE_CURRENT,
	SET_SPEED
}


# ==================================================
# 基础移动
# ==================================================

var move_speed: float = 450.0
var ground_acceleration: float = 2000.0
var ground_deceleration: float = 3000.0
var ground_overspeed_deceleration: float = 600.0
var air_acceleration_multiplier: float = 0.5


# ==================================================
# 跳跃
# ==================================================

var jump_velocity: float = -600.0
var jump_horizontal_boost: float = 180.0
var gravity: float = 1000.0
var jump_cut_multiplier: float = 0.3

const jump_action_priority: int = -1

# Super Jump / Hyper Jump
var super_jump_horizontal_speed: float = 900.0
var duck_super_jump_x_multiplier: float = 1.25
var duck_super_jump_y_multiplier: float = 0.55

# Super / Hyper Jump 不受跳跃可变高度影响。
var jump_height_locked: bool = false

# 下一物理帧打印跳跃后的实际速度。
var pending_jump_speed_debug: bool = false
var pending_jump_speed_debug_type: String = ""


# ==================================================
# 蹲伏与 Duck
# ==================================================

var crouch_friction: float = 2000.0

# Ultra 落地后的 Duck 滑行摩擦力。
var duck_friction: float = 2000.0

# 当前是否处于 Duck 滑行状态。
var is_duck_sliding: bool = false


# ==================================================
# 狼跳与跳跃缓存
# ==================================================

var coyote_time: float = 0.4
var coyote_timer: float = 0.0

var jump_buffer_time: float = 1.0
var jump_buffer_timer: float = 0.0


# ==================================================
# Dash 配置
# ==================================================

var dash_action_data: CombatActionData = preload(
	"res://04_resources/player1_action/normal_dash.tres"
)

var dash_max_charges: int = 2
var dash_recharge_time: float = 1.20

var dash_charges: int = 2
var dash_recharge_timers: Array[float] = []

# Dash 预输入缓存。
# 后续输入会覆盖之前的请求，只保留最后一次。
var dash_buffered: bool = false
var dash_buffered_direction: Vector2 = Vector2.ZERO
var dash_buffered_update_facing: bool = true

# 记录最近一次成功启动的实际 Dash 方向。
var last_dash_direction: Vector2 = Vector2.RIGHT

# 斜下 Dash 已经产生向下运动，等待落地触发 Ultra。
# 这个状态独立于 Dash Movement 的生命周期。
var ultra_landing_pending: bool = false

# 地面直接斜下 Dash 时，转换为水平 Duck Dash。
var dash_grounded_ultra_applied: bool = false
var dash_grounded_ultra_speed: float = 0.0


# ==================================================
# Movement 独立运行状态
# ==================================================

var active_movement_source_id: StringName = &""
var active_movement_request: Dictionary = {}

var movement_end_velocity_settled: bool = false

# IGNORE_WORLD 临时移除 Layer 2 时，保存 Action 开始前的原始 Mask。
var movement_track_original_collision_mask: int = -1
var movement_track_collision_mask_modified: bool = false
var movement_track_progress: float = 0.0
var movement_track_displacement: Vector2 = Vector2.ZERO
var movement_track_start_position: Vector2 = Vector2.ZERO


# ==================================================
# Movement 运行计时与阶段状态
# ==================================================

var movement_phase_elapsed: float = 0.0
var movement_suppress_gravity: bool = false

var movement_phase_start_velocity: Vector2 = Vector2.ZERO
var movement_phase_initialized: bool = false

var movement_vertical_released: bool = false
var movement_airborne_time: float = 0.0


# ==================================================
# Stabilization 运行状态
# ==================================================

var stabilization_context_id: int = 0
var stabilization_locked: bool = false


# ==================================================
# 外部引用
# ==================================================

var action_executor: CombatActionExecutor
var combo_executor: CombatComboExecutor
var actor: Node2D
var defense_controller: DefenseController


func _init(
	p_action_executor: CombatActionExecutor,
	p_combo_executor: CombatComboExecutor,
	p_actor: Node2D
) -> void:
	action_executor = p_action_executor
	combo_executor = p_combo_executor
	actor = p_actor

	if actor != null:
		defense_controller = actor.get_node_or_null(
			"DefenseController"
		) as DefenseController


# ==================================================
# 普通水平移动
# ==================================================


func update_movement(
	actor_delta: float,
	current_velocity: Vector2,
	move_input: Vector2,
	actor_is_on_floor: bool,
	is_crouching: bool = false,
	use_overspeed_deceleration: bool = false
) -> Vector2:

	if actor_is_on_floor and is_crouching:
		current_velocity.x = move_toward(
			current_velocity.x,
			0.0,
			crouch_friction * actor_delta
		)
		return current_velocity

	var target_speed: float = move_input.x * move_speed
	var acceleration: float = 0.0

	var air_multiplier: float = 1.0

	if not actor_is_on_floor:
		air_multiplier = air_acceleration_multiplier

	if is_zero_approx(move_input.x):
		if use_overspeed_deceleration:
			acceleration = ground_overspeed_deceleration * air_multiplier
		else:
			acceleration = ground_deceleration * air_multiplier

	elif current_velocity.x * move_input.x < 0.0:
		acceleration = ground_acceleration * air_multiplier

	elif absf(current_velocity.x) > move_speed:
		acceleration = ground_overspeed_deceleration * air_multiplier

	else:
		acceleration = ground_acceleration * air_multiplier

	current_velocity.x = move_toward(
		current_velocity.x,
		target_speed,
		acceleration * actor_delta
	)

	return current_velocity


# ==================================================
# 重力
# ==================================================

func apply_gravity(
	actor_delta: float,
	current_velocity: Vector2,
	actor_is_on_floor: bool,
	suppress_gravity: bool
) -> Vector2:

	if not actor_is_on_floor and not suppress_gravity:
		current_velocity.y += gravity * actor_delta

	return current_velocity


# ==================================================
# 普通跳跃
# ==================================================

func apply_jump(
	current_velocity: Vector2,
	horizontal_input: float
) -> Vector2:

	if has_action_movement():
		_finish_active_movement(
			CombatMovementInterface.MovementEndReason.JUMP_INTERRUPTED
		)

	is_duck_sliding = false

	# 普通 Jump 保留可变跳跃高度。
	jump_height_locked = false

	var input_direction: float = clampf(
		horizontal_input,
		-1.0,
		1.0
	)

	current_velocity.x += (
		jump_horizontal_boost * input_direction
	)

	current_velocity.y = jump_velocity

	return current_velocity


# ==================================================
# Super / Hyper Jump 方向判定
# ==================================================

func _get_jump_horizontal_direction(
	horizontal_input: float,
	current_velocity: Vector2
) -> float:

	# 优先级 1：当前方向输入。
	if not is_zero_approx(horizontal_input):
		return signf(horizontal_input)

	# 优先级 2：当前水平速度。
	if not is_zero_approx(current_velocity.x):
		return signf(current_velocity.x)

	# 优先级 3：最近一次实际 Dash 方向。
	if not is_zero_approx(last_dash_direction.x):
		return signf(last_dash_direction.x)

	# 最后兜底：角色面向方向。
	var facing: float = _get_facing_direction().x

	if is_zero_approx(facing):
		facing = 1.0

	return facing


# ==================================================
# Super Jump
# ==================================================

func apply_super_jump(
	current_velocity: Vector2,
	horizontal_input: float = 0.0
) -> Vector2:

	if has_action_movement():
		_finish_active_movement(
			CombatMovementInterface.MovementEndReason.JUMP_INTERRUPTED
		)

	is_duck_sliding = false

	# Super Jump 固定跳跃高度，不响应松开跳跃键。
	jump_height_locked = true

	var direction: float = _get_jump_horizontal_direction(
		horizontal_input,
		current_velocity
	)

	# 水平速度保护：
	# 同方向已有速度高于目标值时保留；
	# 低于目标值时补足；
	# 反方向速度则修正到目标方向。
	current_velocity = _apply_minimum_velocity_in_direction(
		current_velocity,
		Vector2(direction, 0.0),
		super_jump_horizontal_speed
	)

	current_velocity.y = jump_velocity

	# 第一条：跳跃瞬间，MovementController 设置完成后的速度。
	print(
		"Super Jump | 跳跃瞬间速度：",
		current_velocity
	)

	# 下一次 update_action_movement() 时打印实际速度。
	pending_jump_speed_debug = true
	pending_jump_speed_debug_type = "Super Jump"

	return current_velocity


# ==================================================
# Hyper Jump
# ==================================================

func apply_hyper_jump(
	current_velocity: Vector2,
	horizontal_input: float = 0.0
) -> Vector2:

	if has_action_movement():
		_finish_active_movement(
			CombatMovementInterface.MovementEndReason.JUMP_INTERRUPTED
		)

	is_duck_sliding = false

	# Hyper Jump 固定跳跃高度，不响应松开跳跃键。
	jump_height_locked = true

	var direction: float = _get_jump_horizontal_direction(
		horizontal_input,
		current_velocity
	)

	var hyper_horizontal_speed: float = (
		super_jump_horizontal_speed
		* duck_super_jump_x_multiplier
	)

	# Hyper 保留自己的 1.25 水平倍率，
	# 但不覆盖已经更快的同方向水平速度。
	current_velocity = _apply_minimum_velocity_in_direction(
		current_velocity,
		Vector2(direction, 0.0),
		hyper_horizontal_speed
	)

	current_velocity.y = (
		jump_velocity
		* duck_super_jump_y_multiplier
	)

	# 第一条：跳跃瞬间，MovementController 设置完成后的速度。
	print(
		"Hyper Jump | 跳跃瞬间速度：",
		current_velocity
	)

	# 下一次 update_action_movement() 时打印实际速度。
	pending_jump_speed_debug = true
	pending_jump_speed_debug_type = "Hyper Jump"

	return current_velocity


# ==================================================
# 跳跃速度 Debug
# ==================================================

func _print_pending_jump_speed_debug() -> void:

	if not pending_jump_speed_debug:
		return

	pending_jump_speed_debug = false

	if actor == null:
		return

	var current_velocity: Vector2 = actor.get("velocity")

	# 第二条：经过一帧物理更新后的实际速度。
	print(
		pending_jump_speed_debug_type,
		" | 1 帧后速度：",
		current_velocity
	)


# ==================================================
# 跳跃高度截断
# ==================================================

func cut_jump(current_velocity: Vector2) -> Vector2:

	# Super / Hyper Jump 不允许提前截断。
	if jump_height_locked:
		return current_velocity

	if current_velocity.y < 0.0:
		current_velocity.y *= jump_cut_multiplier

	return current_velocity


# ==================================================
# Super Jump 条件
# ==================================================

func can_super_jump() -> bool:

	var context := _get_dash_context()

	if context == null:
		return false

	var direction: Vector2 = active_movement_request.get(
		"dash_direction",
		context.input_direction
	)

	# 只有水平 Dash 能接 Super Jump。
	return (
		not is_zero_approx(direction.x)
		and is_zero_approx(direction.y)
	)


# ==================================================
# Movement 状态查询
# ==================================================

func has_action_movement() -> bool:
	return not active_movement_source_id.is_empty()


func get_active_movement_source_id() -> StringName:
	return active_movement_source_id


func get_active_movement_request() -> Dictionary:
	return active_movement_request.duplicate(true)


# ==================================================
# 接收 Action Movement 请求
# ==================================================

func receive_action_movement_request(
	source_id: StringName,
	request: Dictionary
) -> bool:

	if source_id.is_empty():
		push_warning("MovementController：Movement 来源 ID 不能为空")
		return false

	if request.is_empty():
		push_warning("MovementController：不能接收空 Movement 请求")
		return false

	var requested_mode: int = int(
		request.get("movement_mode", MovementMode.NONE)
	)

	if (
		requested_mode != MovementMode.NONE
		and requested_mode != MovementMode.DASH
		and requested_mode != MovementMode.VELOCITY_OVERRIDE
		and requested_mode != MovementMode.MOVEMENT_TRACK
	):
		push_warning("MovementController：不支持的 Movement 模式")
		return false

	if request.has("dash_direction"):
		if not request["dash_direction"] is Vector2:
			push_warning("MovementController：Dash 方向必须是 Vector2")
			return false

	if request.has("override_direction"):
		if not request["override_direction"] is Vector2:
			push_warning("MovementController：Override 方向必须是 Vector2")
			return false

	if requested_mode == MovementMode.MOVEMENT_TRACK:
		if not request.get("movement_track_x") is Curve or not request.get("movement_track_y") is Curve:
			push_warning("MovementController：MovementTrack 需要有效的 X / Y Curve")
			return false
		if float(request.get("movement_track_duration", 0.0)) <= 0.0:
			push_warning("MovementController：MovementTrack Duration 必须大于 0")
			return false

	if source_id == active_movement_source_id:
		active_movement_request = request.duplicate(true)
		return true

	if has_action_movement():
		_finish_active_movement(
			CombatMovementInterface.MovementEndReason.REPLACED
		)

	# 新的 Movement 接管时，结束旧 Duck 滑行。
	is_duck_sliding = false

	active_movement_source_id = source_id
	active_movement_request = request.duplicate(true)

	movement_end_velocity_settled = false

	_reset_movement_runtime_state()
	if requested_mode == MovementMode.MOVEMENT_TRACK and actor != null:
		movement_track_start_position = actor.global_position
	_apply_movement_track_collision_strategy(active_movement_request)

	return true


# ==================================================
# Action 生命周期通知
# ==================================================

func notify_movement_action_finished(
	source_id: StringName,
	end_reason: CombatMovementInterface.MovementEndReason
) -> void:

	if source_id != active_movement_source_id:
		return

	match end_reason:

		CombatMovementInterface.MovementEndReason.COMPLETED:
			if int(
				active_movement_request.get(
					"movement_mode",
					MovementMode.NONE
				)
			) == MovementMode.NONE or int(
				active_movement_request.get(
					"movement_mode",
					MovementMode.NONE
				)
			) == MovementMode.MOVEMENT_TRACK:
				_finish_active_movement(
					CombatMovementInterface.MovementEndReason.COMPLETED
				)

		CombatMovementInterface.MovementEndReason.CANCELLED:
			_finish_active_movement(
				CombatMovementInterface.MovementEndReason.CANCELLED
			)

		CombatMovementInterface.MovementEndReason.REPLACED:
			_finish_active_movement(
				CombatMovementInterface.MovementEndReason.REPLACED
			)

		CombatMovementInterface.MovementEndReason.JUMP_INTERRUPTED:
			_finish_active_movement(
				CombatMovementInterface.MovementEndReason.JUMP_INTERRUPTED
			)


# ==================================================
# Movement 自身结束
# ==================================================

func finish_action_movement(source_id: StringName) -> void:

	if source_id != active_movement_source_id:
		return

	_finish_active_movement(
		CombatMovementInterface.MovementEndReason.COMPLETED
	)


# ==================================================
# Movement 结束处理
# ==================================================

func _finish_active_movement(
	end_reason: CombatMovementInterface.MovementEndReason
) -> void:

	if not has_action_movement():
		return

	if (
		end_reason == CombatMovementInterface.MovementEndReason.COMPLETED
		or end_reason == CombatMovementInterface.MovementEndReason.REPLACED
	):
		_apply_movement_end_velocity_once()

	_clear_active_movement()


func _clear_active_movement() -> void:

	_restore_movement_track_collision_mask()

	active_movement_source_id = &""
	active_movement_request.clear()

	movement_end_velocity_settled = false

	_reset_movement_runtime_state()


# ==================================================
# End Velocity 一次性结算
# ==================================================

func _apply_movement_end_velocity_once() -> void:

	if movement_end_velocity_settled:
		return

	if actor == null:
		movement_end_velocity_settled = true
		return

	var current_velocity: Vector2 = actor.get("velocity")

	current_velocity = _calculate_movement_end_velocity(
		current_velocity,
		active_movement_request
	)

	actor.set("velocity", current_velocity)

	movement_end_velocity_settled = true


func _calculate_movement_end_velocity(
	current_velocity: Vector2,
	request: Dictionary
) -> Vector2:

	var movement_mode: int = int(
		request.get("movement_mode", MovementMode.NONE)
	)

	match movement_mode:

		MovementMode.DASH:
			return _calculate_dash_end_velocity(
				current_velocity,
				request
			)

		MovementMode.VELOCITY_OVERRIDE:
			return _calculate_override_end_velocity(
				current_velocity,
				request
			)

	return current_velocity




func _calculate_dash_end_velocity(
	current_velocity: Vector2,
	request: Dictionary
) -> Vector2:

	if not bool(request.get("end_velocity_enabled", true)):
		return current_velocity

	var direction: Vector2 = request.get(
		"dash_direction",
		Vector2.RIGHT
	)

	if direction.length_squared() <= 0.0001:
		return current_velocity

	direction = direction.normalized()

	var end_speed: float = maxf(
		float(request.get("end_speed", 160.0)),
		0.0
	)

	var exclude_diagonal_down: bool = bool(
		request.get("exclude_diagonal_down_end", true)
	)

	var is_diagonal_down: bool = (
		direction.x != 0.0
		and direction.y > 0.0
	)

	# 斜下 Dash：使用速度保护，不直接覆盖当前速度
	if exclude_diagonal_down and is_diagonal_down:
		return _apply_minimum_velocity_in_direction(
			current_velocity,
			direction,
			end_speed
		)

	var end_velocity: Vector2 = direction * end_speed

	if direction.x == 0.0 and direction.y < 0.0:
		var multiplier: float = float(
			request.get("dash_up_end_y_multiplier", 0.75)
		)
		end_velocity.y *= multiplier

	elif direction.x != 0.0 and direction.y < 0.0:
		var multiplier: float = float(
			request.get(
				"dash_diagonal_up_end_y_multiplier",
				0.75
			)
		)
		end_velocity.y *= multiplier

	return end_velocity




func _calculate_override_end_velocity(
	current_velocity: Vector2,
	request: Dictionary
) -> Vector2:

	var end_velocity_mode: int = int(
		request.get(
			"end_velocity_mode",
			EndVelocityMode.PRESERVE_CURRENT
		)
	)

	if end_velocity_mode != EndVelocityMode.SET_SPEED:
		return current_velocity

	var end_speed: float = maxf(
		float(request.get("end_speed", 0.0)),
		0.0
	)

	var direction: Vector2 = request.get(
		"override_direction",
		Vector2.RIGHT
	)

	if direction.length_squared() <= 0.0001:
		return current_velocity

	return direction.normalized() * end_speed


# ==================================================
# 更新 Action Movement
# ==================================================

func update_action_movement(
	actor_delta: float,
	current_velocity: Vector2,
	actor_gravity: float,
	actor_is_on_floor: bool
) -> Dictionary:

	# 如果上一物理帧触发了 Super / Hyper Jump，
	# 此时读取 Actor 已经完成上一帧 move_and_slide() 的速度。
	_print_pending_jump_speed_debug()

	var result := {
		"active": false,
		"velocity": current_velocity,
		"suppress_gravity": false
	}

	# Dash 已经结束，但斜下 Dash 的落地 Ultra 仍在等待。
	# 这条状态不依赖 active_movement_source_id。
	if (
		ultra_landing_pending
		and actor_is_on_floor
		and not has_action_movement()
	):
		current_velocity.x *= 1.2
		current_velocity.y = 0.0

		ultra_landing_pending = false
		is_duck_sliding = true

		result["active"] = true
		result["velocity"] = current_velocity

		return result

	# Duck 滑行属于 MovementController 自身状态，
	# 不再依赖 Dash Movement 请求是否仍然存在。
	if is_duck_sliding and not has_action_movement():
		return _update_duck_slide(
			actor_delta,
			current_velocity,
			actor_is_on_floor
		)

	if not has_action_movement():
		return result

	var movement_mode: int = int(
		active_movement_request.get(
			"movement_mode",
			MovementMode.NONE
		)
	)

	match movement_mode:

		MovementMode.DASH:
			return _update_dash_movement(
				actor_delta,
				current_velocity,
				actor_is_on_floor
			)

		MovementMode.VELOCITY_OVERRIDE:
			return _update_velocity_override(
				actor_delta,
				current_velocity,
				actor_gravity,
				actor_is_on_floor
			)

		MovementMode.MOVEMENT_TRACK:
			return _update_movement_track(
				actor_delta,
				current_velocity
			)

		_:
			return result


# ==================================================
# Duck 滑行
# ==================================================

func _update_duck_slide(
	actor_delta: float,
	current_velocity: Vector2,
	actor_is_on_floor: bool
) -> Dictionary:

	var result := {
		"active": true,
		"velocity": current_velocity,
		"suppress_gravity": false
	}

	# 离开地面后结束 Duck 滑行，恢复普通空中移动。
	if not actor_is_on_floor:
		is_duck_sliding = false
		result["active"] = false
		return result

	current_velocity.x = move_toward(
		current_velocity.x,
		0.0,
		duck_friction * actor_delta
	)

	if is_zero_approx(current_velocity.x):
		current_velocity.x = 0.0
		is_duck_sliding = false

	result["velocity"] = current_velocity

	return result


# ==================================================
# DASH 实际运动
# ==================================================

func _update_dash_movement(
	actor_delta: float,
	current_velocity: Vector2,
	actor_is_on_floor: bool
) -> Dictionary:

	var result := {
		"active": true,
		"velocity": current_velocity,
		"suppress_gravity": true
	}

	var direction: Vector2 = active_movement_request.get(
		"dash_direction",
		_get_facing_direction()
	)

	if direction.length_squared() <= 0.0001:
		direction = _get_facing_direction()

	direction = direction.normalized()

	var dash_speed: float = maxf(
		float(active_movement_request.get("dash_speed", 0.0)),
		0.0
	)

	var dash_duration: float = maxf(
		float(active_movement_request.get("dash_duration", 0.01)),
		0.01
	)

	# 地面 Ultra 已经转换后，后续 Dash 帧使用水平速度。
	if dash_grounded_ultra_applied:
		direction = Vector2(
			signf(direction.x),
			0.0
		)

		dash_speed = dash_grounded_ultra_speed

	var target_velocity: Vector2 = direction * dash_speed

	# Dash 水平速度保护。
	# 只保护水平速度，不保护斜向 Dash 的垂直速度。
	if direction.x != 0.0:
		if current_velocity.x * direction.x > 0.0:
			if absf(current_velocity.x) > absf(target_velocity.x):
				target_velocity.x = current_velocity.x
	else:
		target_velocity.x = 0.0

	# --------------------------------------------------
	# 地面直接发动斜下 Dash：Grounded Ultra
	# --------------------------------------------------

	if (
		not dash_grounded_ultra_applied
		and movement_phase_elapsed <= 0.0001
		and actor_is_on_floor
		and direction.x != 0.0
		and direction.y > 0.0
	):
		var slide_multiplier: float = float(
			active_movement_request.get(
				"dash_duck_speed_multiplier",
				1.2
			)
		)

		# 斜下 Dash 的水平分量乘 1.2。
		target_velocity.x *= slide_multiplier
		target_velocity.y = 0.0

		dash_grounded_ultra_speed = absf(target_velocity.x)
		dash_grounded_ultra_applied = true

		# 已经进入 Duck 状态。
		is_duck_sliding = true

	# --------------------------------------------------
	# 空中斜下 Dash：等待落地触发 Ultra
	# --------------------------------------------------

	elif (
		not dash_grounded_ultra_applied
		and direction.x != 0.0
		and direction.y > 0.0
	):
		if target_velocity.y > 0.0:
			ultra_landing_pending = true

	# --------------------------------------------------
	# 空中斜下 Dash 落地
	# --------------------------------------------------

	if (
		ultra_landing_pending
		and actor_is_on_floor
	):
		var slide_multiplier: float = float(
			active_movement_request.get(
				"dash_duck_speed_multiplier",
				1.2
			)
		)

		# 保留当前 Dash 水平速度，再乘 1.2。
		target_velocity.x *= slide_multiplier
		target_velocity.y = 0.0

		ultra_landing_pending = false

		# 先清理 Dash Movement，不结算普通 End Velocity。
		# Dash Action Context 仍然由 CombatActionExecutor 管理。
		_clear_active_movement()

		is_duck_sliding = true

		result["velocity"] = target_velocity
		return result

	# --------------------------------------------------
	# Dash 计时
	# --------------------------------------------------

	movement_phase_elapsed += actor_delta

	if movement_phase_elapsed >= dash_duration:
		movement_phase_elapsed = dash_duration

		target_velocity = _complete_movement_with_velocity(
			target_velocity
		)

	result["velocity"] = target_velocity

	return result


# ==================================================
# MovementTrack 实际运动
# ==================================================

func _update_movement_track(
	actor_delta: float,
	_current_velocity: Vector2
) -> Dictionary:
	var result := {
		"active": true,
		"velocity": Vector2.ZERO,
		"suppress_gravity": true
	}

	if actor_delta <= 0.0:
		result["velocity"] = Vector2.ZERO
		return result

	var duration: float = maxf(
		float(active_movement_request.get("movement_track_duration", 0.2)),
		0.01
	)
	var next_elapsed: float = minf(
		movement_phase_elapsed + actor_delta,
		duration
	)
	var progress: float = clampf(next_elapsed / duration, 0.0, 1.0)

	var x_curve := active_movement_request.get("movement_track_x") as Curve
	var y_curve := active_movement_request.get("movement_track_y") as Curve

	if x_curve == null or y_curve == null:
		push_warning("MovementController：MovementTrack Curve 无效，结束当前 Movement")
		_finish_active_movement(CombatMovementInterface.MovementEndReason.CANCELLED)
		result["active"] = false
		return result

	# MovementTrack X follows the facing direction captured when the Action started.
	# Y uses intuitive authoring coordinates: positive is upward, negative is downward.
	var facing_direction := -1.0 if float(active_movement_request.get("movement_track_facing_direction", 1)) < 0.0 else 1.0
	var start_displacement := Vector2(
		x_curve.sample_baked(0.0) * facing_direction,
		-y_curve.sample_baked(0.0)
	)
	var next_displacement := Vector2(
		x_curve.sample_baked(progress) * facing_direction,
		-y_curve.sample_baked(progress)
	) - start_displacement

	var frame_displacement := next_displacement - movement_track_displacement
	var output_velocity := frame_displacement / actor_delta

	movement_phase_elapsed = next_elapsed
	movement_track_progress = progress
	movement_track_displacement = next_displacement

	result["velocity"] = output_velocity

	if progress >= 1.0:
		result["velocity"] = _complete_movement_with_velocity(output_velocity)

	return result


func is_movement_track_active() -> bool:
	return (
		has_action_movement()
		and int(active_movement_request.get("movement_mode", MovementMode.NONE))
			== MovementMode.MOVEMENT_TRACK
	)


func _apply_movement_track_collision_strategy(request: Dictionary) -> void:
	if int(request.get("movement_mode", MovementMode.NONE)) != MovementMode.MOVEMENT_TRACK:
		return

	var strategy: int = int(
		request.get("movement_track_collision_strategy", 0)
	)
	if strategy != 1:
		return

	if not actor is CollisionObject2D:
		push_warning("MovementController：Actor 不是 CollisionObject2D，无法应用 IGNORE_WORLD")
		return

	var collision_object := actor as CollisionObject2D
	movement_track_original_collision_mask = collision_object.collision_mask
	movement_track_collision_mask_modified = true

	# Layer 2（普通地图碰撞）对应 bit 1；Layer 1 始终保留。
	collision_object.collision_mask = (
		movement_track_original_collision_mask & ~(1 << 1)
	)


func _restore_movement_track_collision_mask() -> void:
	if not movement_track_collision_mask_modified:
		return

	if is_instance_valid(actor) and actor is CollisionObject2D:
		(actor as CollisionObject2D).collision_mask = movement_track_original_collision_mask

	movement_track_original_collision_mask = -1
	movement_track_collision_mask_modified = false


# ==================================================
# Velocity Override 实际运动
# ==================================================

func _update_velocity_override(
	actor_delta: float,
	current_velocity: Vector2,
	actor_gravity: float,
	actor_is_on_floor: bool
) -> Dictionary:

	var result := {
		"active": true,
		"velocity": current_velocity,
		"suppress_gravity": false
	}

	var direction: Vector2 = active_movement_request.get(
		"override_direction",
		_get_facing_direction()
	)

	if direction.length_squared() <= 0.0001:
		direction = _get_facing_direction()

	direction = direction.normalized()

	var phase_mode: int = int(
		active_movement_request.get(
			"override_phase_mode",
			PhaseMode.SPEED_PROTECTION
		)
	)

	var phase_speed: float = maxf(
		float(active_movement_request.get("override_speed", 0.0)),
		0.0
	)

	var phase_duration: float = maxf(
		float(active_movement_request.get("override_duration", 0.01)),
		0.01
	)

	movement_suppress_gravity = bool(
		active_movement_request.get(
			"override_suppress_gravity",
			false
		)
	)

	if not movement_phase_initialized:
		movement_phase_start_velocity = current_velocity
		movement_phase_initialized = true

	if actor_is_on_floor:
		movement_vertical_released = true

	if not actor_is_on_floor and not movement_vertical_released:
		movement_airborne_time += actor_delta

	var target_velocity: Vector2 = direction * phase_speed
	var output_velocity: Vector2 = current_velocity

	match phase_mode:

		PhaseMode.SPEED_PROTECTION:
			output_velocity = _apply_minimum_velocity_in_direction(
				output_velocity,
				direction,
				phase_speed
			)

		PhaseMode.LINEAR_INTERPOLATION:
			var next_elapsed: float = minf(
				movement_phase_elapsed + actor_delta,
				phase_duration
			)

			var progress: float = clampf(
				next_elapsed / phase_duration,
				0.0,
				1.0
			)

			var interpolated_velocity: Vector2 = (
				movement_phase_start_velocity.lerp(
					target_velocity,
					progress
				)
			)

			output_velocity.x = interpolated_velocity.x

			if not movement_vertical_released:
				if not actor_is_on_floor:
					output_velocity.y = interpolated_velocity.y

					if not movement_suppress_gravity:
						output_velocity.y += (
							actor_gravity * movement_airborne_time
						)

		PhaseMode.DIRECT_SET:
			output_velocity = target_velocity

		_:
			output_velocity = _apply_minimum_velocity_in_direction(
				output_velocity,
				direction,
				phase_speed
			)

	movement_phase_elapsed += actor_delta

	if movement_phase_elapsed >= phase_duration:
		movement_phase_elapsed = phase_duration

		output_velocity = _complete_movement_with_velocity(
			output_velocity
		)

	result["velocity"] = output_velocity
	result["suppress_gravity"] = movement_suppress_gravity

	return result


# ==================================================
# Movement 完成与本帧速度结算
# ==================================================

func _complete_movement_with_velocity(
	current_velocity: Vector2
) -> Vector2:

	if not has_action_movement():
		return current_velocity

	if movement_end_velocity_settled:
		return current_velocity

	current_velocity = _calculate_movement_end_velocity(
		current_velocity,
		active_movement_request
	)

	movement_end_velocity_settled = true

	_clear_active_movement()

	return current_velocity


# ==================================================
# 速度保护
# ==================================================

func _apply_minimum_velocity_in_direction(
	current_velocity: Vector2,
	direction: Vector2,
	target_speed: float
) -> Vector2:

	if direction.length_squared() <= 0.0001:
		return current_velocity

	var normalized_direction := direction.normalized()
	var current_speed := current_velocity.dot(normalized_direction)

	if current_speed < target_speed:
		current_velocity += normalized_direction * (
			target_speed - current_speed
		)

	return current_velocity


# ==================================================
# Movement 运行状态重置
# ==================================================

func _reset_movement_runtime_state() -> void:

	movement_phase_elapsed = 0.0
	movement_suppress_gravity = false

	movement_phase_start_velocity = Vector2.ZERO
	movement_phase_initialized = false

	movement_vertical_released = false
	movement_airborne_time = 0.0

	movement_track_progress = 0.0
	movement_track_displacement = Vector2.ZERO
	movement_track_start_position = Vector2.ZERO

	dash_grounded_ultra_applied = false
	dash_grounded_ultra_speed = 0.0


# ==================================================
# 当前 Action 请求
# ==================================================

func _get_current_action_context() -> CombatActionContext:

	if action_executor == null:
		return null

	if not action_executor.is_action_running():
		return null

	return action_executor.current_context


# ==================================================
# Stabilization 阶段判断
# ==================================================

func _get_stabilization_phase_index(
	phase: StringName
) -> int:

	match phase:
		&"startup":
			return 0

		&"active":
			return 1

		&"recovery":
			return 2

	return -1


func _is_stabilization_phase_reached(
	context: CombatActionContext,
	request: Dictionary
) -> bool:

	var current_index: int = _get_stabilization_phase_index(
		context.current_phase
	)

	var start_index: int = int(
		request.get("stabilization_duration_start_phase", 1)
	)

	if current_index < 0:
		return false

	return current_index >= start_index


# ==================================================
# Stabilization 是否正在生效
# ==================================================

func has_action_stabilization() -> bool:

	var context := _get_current_action_context()

	if context == null:
		stabilization_context_id = 0
		stabilization_locked = false
		return false

	var request: Variant = context.runtime_data.get(
		"movement_request",
		{}
	)

	if not request is Dictionary:
		stabilization_context_id = 0
		stabilization_locked = false
		return false

	if is_movement_track_active():
		stabilization_context_id = 0
		stabilization_locked = false
		return false

	if not bool(request.get("stabilization_enabled", false)):
		stabilization_context_id = 0
		stabilization_locked = false
		return false


	var context_id: int = context.get_instance_id()

	if stabilization_context_id != context_id:
		stabilization_context_id = context_id
		stabilization_locked = false

	var activation_mode: int = int(
		request.get("stabilization_activation_mode", 0)
	)

	match activation_mode:

		0:
			var current_index: int = _get_stabilization_phase_index(
				context.current_phase
			)

			var start_index: int = int(
				request.get("stabilization_start_phase", 0)
			)

			var end_index: int = int(
				request.get("stabilization_end_phase", 2)
			)

			if start_index > end_index:
				return false

			return (
				current_index >= start_index
				and current_index <= end_index
			)

		1:
			return _is_stabilization_phase_reached(
				context,
				request
			) and float(
				context.runtime_data.get(
					"stabilization_elapsed",
					0.0
				)
			) < float(
				request.get("stabilization_duration", 0.2)
			)

	return false


# ==================================================
# Stabilization 实际执行
# ==================================================

func apply_action_stabilization(
	current_velocity: Vector2,
	actor_delta: float,
	actor_is_on_floor: bool
) -> Vector2:

	var context := _get_current_action_context()

	if context == null:
		stabilization_context_id = 0
		stabilization_locked = false
		return current_velocity

	var request: Variant = context.runtime_data.get(
		"movement_request",
		{}
	)

	if not request is Dictionary:
		stabilization_context_id = 0
		stabilization_locked = false
		return current_velocity

	if not has_action_stabilization():
		stabilization_context_id = 0
		stabilization_locked = false
		return current_velocity

	var context_id: int = context.get_instance_id()

	if stabilization_context_id != context_id:
		stabilization_context_id = context_id
		stabilization_locked = false

	var activation_mode: int = int(
		request.get("stabilization_activation_mode", 0)
	)

	if activation_mode == 1:
		var elapsed: float = float(
			context.runtime_data.get(
				"stabilization_elapsed",
				0.0
			)
		)

		elapsed += actor_delta

		context.runtime_data["stabilization_elapsed"] = elapsed

		if elapsed >= float(
			request.get("stabilization_duration", 0.2)
		):
			stabilization_context_id = 0
			stabilization_locked = false
			return current_velocity

	var stabilization_speed: float = maxf(
		float(request.get("stabilization_speed", 3000.0)),
		0.0
	)

	if stabilization_locked:
		current_velocity.x = 0.0
	else:
		current_velocity.x = move_toward(
			current_velocity.x,
			0.0,
			stabilization_speed * actor_delta
		)

		if is_zero_approx(current_velocity.x):
			current_velocity.x = 0.0
			stabilization_locked = true

	var stabilize_vertical: bool = bool(
		request.get("stabilize_vertical_in_air", true)
	)

	if not actor_is_on_floor and stabilize_vertical:
		current_velocity.y = move_toward(
			current_velocity.y,
			0.0,
			stabilization_speed * actor_delta
		)

	return current_velocity


# ==================================================
# Dash 状态查询
# ==================================================

var is_dashing: bool:
	get:
		if _get_dash_context() != null:
			return true

		return (
			has_action_movement()
			and int(
				active_movement_request.get(
					"movement_mode",
					MovementMode.NONE
				)
			) == MovementMode.DASH
		)





func _get_dash_context() -> CombatActionContext:

	if action_executor == null:
		return null

	var context := action_executor.current_context

	if context == null or not context.is_running:
		return null

	if context.action_data != dash_action_data:
		return null

	return context


func _get_facing_direction() -> Vector2:

	if actor == null:
		return Vector2.RIGHT

	var facing: int = int(actor.get("facing_direction"))

	if facing == 0:
		facing = 1

	return Vector2(facing, 0.0)


# ==================================================
# 请求 Dash
# ==================================================

func request_dash(
	direction: Vector2,
	update_facing: bool = true
) -> bool:

	if dash_charges <= 0:
		return false

	var requested_direction := _get_dash_direction(direction)

	# 如果已经存在待执行请求，新输入直接覆盖旧请求。
	# 只保留最后一次输入的方向和面向设置。
	if dash_buffered:
		_buffer_dash_request(
			requested_direction,
			update_facing
		)
		return true

	# Dash 期间再次输入 Dash，缓存下一次 Dash。
	if is_dashing:
		_buffer_dash_request(
			requested_direction,
			update_facing
		)
		return true

	# 先尝试立即启动。
	if _start_dash(requested_direction, update_facing):
		return true

	# 当前有其他 Action，且它暂时拒绝 Dash 接管：
	# 保留请求，等 Action 结束或进入允许取消的阶段。
	if _get_current_action_context() != null:
		_buffer_dash_request(
			requested_direction,
			update_facing
		)
		return true

	# 没有正在运行的 Action，启动失败就不缓存。
	return false


# ==================================================
# 写入 / 覆盖 Dash 缓存
# ==================================================

func _buffer_dash_request(
	direction: Vector2,
	update_facing: bool
) -> void:

	dash_buffered = true
	dash_buffered_direction = direction
	dash_buffered_update_facing = update_facing


# ==================================================
# 启动 Dash Action
# ==================================================

func _start_dash(
	direction: Vector2,
	update_facing: bool
) -> bool:

	if actor == null or action_executor == null or combo_executor == null:
		push_warning("Dash 启动失败：缺少角色或 Executor")
		return false

	if dash_action_data == null:
		push_warning("Dash 启动失败：没有设置 dash_action_data")
		return false

	var dash_direction := _get_dash_direction(direction)

	# 创建统一 Action Request。
	var request := CombatActionRequest.new()

	request.request_type = CombatActionRequest.RequestType.START_ACTION
	request.action_data = dash_action_data

	# Dash 的实际运动方向作为请求输入方向。
	request.input_direction = dash_direction

	# 只有允许更新面向，且 Dash 有水平分量时，
	# 才明确指定本次 Action 的面向。
	# 否则由 Request 在提交时捕获角色当前面向。
	if update_facing and not is_zero_approx(dash_direction.x):
		request.facing_direction = int(signf(dash_direction.x))

	# 统一通过 CombatComboExecutor 提交。
	var started: bool = combo_executor.submit_request(request)

	if not started:
		return false

	# 以下逻辑只在 Dash Action 真正启动成功后执行。

	# 新 Dash 开始时，清除上一轮尚未触发的 Ultra 等待状态。
	ultra_landing_pending = false
	dash_grounded_ultra_applied = false
	dash_grounded_ultra_speed = 0.0

	# 只记录成功启动的实际 Dash 方向。
	last_dash_direction = dash_direction

	var current_velocity: Vector2 = actor.get("velocity")
	current_velocity.y = 0.0
	actor.set("velocity", current_velocity)

	dash_charges -= 1
	dash_recharge_timers.append(dash_recharge_time)

	return true

func _get_dash_direction(direction: Vector2) -> Vector2:

	if direction.length_squared() > 0.0001:
		return direction.normalized()

	return _get_facing_direction()


# ==================================================
# Dash 更新
# ==================================================

func update_dash(actor_delta: float) -> void:

	_update_dash_recharge(actor_delta)

	if not dash_buffered:
		return

	if dash_charges <= 0:
		return


	var next_direction := dash_buffered_direction
	var next_update_facing: bool = dash_buffered_update_facing

	var started: bool = _start_dash(
		next_direction,
		next_update_facing
	)

	# 只有真正启动成功，才清除缓存。
	if started:
		dash_buffered = false
		dash_buffered_direction = Vector2.ZERO
		dash_buffered_update_facing = true


# ==================================================
# Dash 充能恢复
# ==================================================

func _update_dash_recharge(actor_delta: float) -> void:

	for i in range(dash_recharge_timers.size() - 1, -1, -1):
		dash_recharge_timers[i] -= actor_delta

		if dash_recharge_timers[i] <= 0.0:
			dash_recharge_timers.remove_at(i)

			dash_charges = mini(
				dash_charges + 1,
				dash_max_charges
			)


# ==================================================
# Coyote Time
# ==================================================

func update_coyote_time(
	actor_delta: float,
	actor_is_on_floor: bool
) -> void:

	if actor_is_on_floor:
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(
			coyote_timer - actor_delta,
			0.0
		)


func can_coyote_jump() -> bool:
	return coyote_timer > 0.0


# ==================================================
# Jump Buffer
# ==================================================

func update_jump_buffer(actor_delta: float) -> void:

	jump_buffer_timer = maxf(
		jump_buffer_timer - actor_delta,
		0.0
	)


func buffer_jump_input() -> void:
	jump_buffer_timer = jump_buffer_time


func has_buffered_jump() -> bool:
	return jump_buffer_timer > 0.0


func consume_buffered_jump() -> void:
	jump_buffer_timer = 0.0
