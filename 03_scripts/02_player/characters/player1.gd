
extends CharacterBody2D


signal debug_damage_number(world_position: Vector2, amount: float)


# ==================================================
# 生命值
# ==================================================

@export_group("生命值")
@export var max_health: float = 100.0

@export_group("受击设置")
@export_range(0, 10, 1)
var default_super_armor_level: int = 0

@export_group("动作资源")
@export var dash_action_data: CombatActionData


func get_effective_super_armor_level() -> int:
	if combat_action_executor.is_action_running():
		return combat_action_executor.current_context.action_data.super_armor_level

	return default_super_armor_level


var current_health: float = 0.0
var is_dead: bool = false


# ==================================================
# Dash 参数
# ==================================================

@export_group("Dash 参数")
@export var dash_max_charges: int = 2
@export var dash_recharge_time: float = 1.20


# ==================================================
# Special Dash 输入参数
# ==================================================

@export_group("Special Dash 输入")
@export_range(0.05, 1.0, 0.05)
var special_dash_hold_threshold: float = 0.10


# Dash 状态统一从对应控制器读取。
var is_dashing: bool:
	get:
		return movement_controller != null and movement_controller.is_dashing


var is_invincible: bool:
	get:
		return defense_controller != null and defense_controller.is_invincible


var dash_charges: int:
	get:
		if movement_controller == null:
			return 0
		return movement_controller.dash_charges


# ==================================================
# Special Dash 输入状态
# ==================================================

var special_dash_hold_active: bool = false
var special_dash_hold_started_on_floor: bool = false
var special_dash_hold_timer: float = 0.0

var special_dash_press_direction: Vector2 = Vector2.ZERO
var special_dash_last_valid_direction: Vector2 = Vector2.ZERO

var special_dash_preparing: bool = false
var special_dash_ground_attempted: bool = false

var dash_input_updates_facing: bool = true


# ==================================================
# 输入缓存
# ==================================================

var move_input_direction: float = 0.0
var move_input_vector: Vector2 = Vector2.ZERO

var jump_button_held: bool = false
var jump_release_pending: bool = false

var dash_input_pending: bool = false
var dash_input_direction: Vector2 = Vector2.ZERO

var normalattack_input_pending: bool = false
var skill_input_pending: bool = false


# ==================================================
# 角色与战斗系统
# ==================================================

var facing_direction: float = 1.0

var movement_controller: PlayerMovementController

# MovementModule 使用的统一请求入口；实际控制器仍由 PlayerMovementController 承担。
var movement_request_handler: Object:
	get:
		return movement_controller


@onready var combat_action_executor: CombatActionExecutor = $CombatActionExecutor
@onready var combat_combo_executor: CombatComboExecutor = $CombatComboExecutor
@onready var combat_energy: CombatEnergy = $CombatEnergy
@onready var skill_selector: SkillSelector = $SkillSelector
@onready var defense_controller: DefenseController = $DefenseController


# ==================================================
# 调试数据
# ==================================================

var debug_action_name: String = "待机"
var debug_phase_name: String = ""

var debug_startup_duration: float = 0.0
var debug_active_duration: float = 0.0
var debug_recovery_duration: float = 0.0

var debug_action_elapsed: float = 0.0
var debug_action_active: bool = false

var debug_energy_current: float = 0.0
var debug_energy_max: float = 100.0


# ==================================================
# 初始化
# ==================================================

func _ready() -> void:
	current_health = max_health

	movement_controller = PlayerMovementController.new(
		combat_action_executor,
		combat_combo_executor,
		self
	)

	movement_controller.dash_action_data = dash_action_data
	movement_controller.dash_max_charges = dash_max_charges
	movement_controller.dash_recharge_time = dash_recharge_time
	movement_controller.dash_charges = dash_max_charges

	if current_health <= 0.0:
		die()

	combat_action_executor.action_started.connect(
		_on_executor_action_started
	)

	combat_action_executor.action_phase_changed.connect(
		_on_executor_action_phase_changed
	)

	combat_action_executor.action_finished.connect(
		_on_executor_action_finished
	)

	debug_energy_current = combat_energy.current_energy
	debug_energy_max = combat_energy.MAX_ENERGY

	combat_energy.energy_changed.connect(_on_energy_changed)


# ==================================================
# 输入采集
# ==================================================

func _process(delta: float) -> void:
	if is_dead:
		move_input_direction = 0.0
		move_input_vector = Vector2.ZERO

		jump_button_held = false
		jump_release_pending = false

		dash_input_pending = false
		normalattack_input_pending = false
		skill_input_pending = false

		_reset_special_dash_input_state()
		return

	# Debug 时间轴跟随角色时间。
	if debug_action_active:
		var actor_delta: float = CombatTimeManager.get_actor_delta(
			self,
			delta
		)
		debug_action_elapsed += actor_delta

	move_input_direction = Input.get_axis(
		"move_left",
		"move_right"
	)

	move_input_vector = Vector2(
		move_input_direction,
		Input.get_axis("move_up", "move_down")
	)

	jump_button_held = Input.is_action_pressed("jump")

	if Input.is_action_just_pressed("jump"):
		movement_controller.buffer_jump_input()

	if Input.is_action_just_released("jump"):
		jump_release_pending = true

	if Input.is_action_just_pressed("dodge"):
		_begin_special_dash_input()

	if special_dash_hold_active and Input.is_action_pressed("dodge"):
		_update_special_dash_hold(delta)

	if Input.is_action_just_released("dodge"):
		_release_special_dash_input()

	if Input.is_action_just_pressed("normalattack"):
		normalattack_input_pending = true

	if Input.is_action_just_pressed("skill"):
		skill_input_pending = true


# ==================================================
# Special Dash 输入状态机
# ==================================================

func _begin_special_dash_input() -> void:
	special_dash_hold_active = true
	special_dash_hold_started_on_floor = is_on_floor()

	special_dash_hold_timer = 0.0
	special_dash_press_direction = move_input_vector
	special_dash_last_valid_direction = Vector2.ZERO

	special_dash_preparing = false
	special_dash_ground_attempted = false

	if move_input_vector != Vector2.ZERO:
		special_dash_last_valid_direction = move_input_vector.normalized()

	if special_dash_hold_started_on_floor:
		var direction := move_input_vector

		if direction == Vector2.ZERO:
			direction = Vector2(-facing_direction, 0.0)
			dash_input_updates_facing = false
		else:
			dash_input_updates_facing = true

		dash_input_pending = true
		dash_input_direction = direction.normalized()

	else:
		dash_input_updates_facing = true


func _update_special_dash_hold(delta: float) -> void:
	if move_input_vector != Vector2.ZERO:
		special_dash_last_valid_direction = move_input_vector.normalized()

	special_dash_hold_timer += delta

	if special_dash_hold_timer < special_dash_hold_threshold:
		return

	if special_dash_hold_started_on_floor:
		if not special_dash_ground_attempted:
			special_dash_ground_attempted = true
			_try_ground_special_dash()

		return

	if not special_dash_preparing:
		special_dash_preparing = true


func _release_special_dash_input() -> void:
	if not special_dash_hold_active:
		return

	special_dash_hold_active = false

	if special_dash_hold_started_on_floor:
		_reset_special_dash_hold_state()
		return

	var direction: Vector2

	if special_dash_preparing:
		direction = _get_special_dash_direction()

	else:
		direction = special_dash_press_direction

		if direction == Vector2.ZERO:
			direction = Vector2(facing_direction, 0.0)

	dash_input_pending = true
	dash_input_direction = direction.normalized()
	dash_input_updates_facing = true

	special_dash_preparing = false

	_reset_special_dash_hold_state()


func _get_special_dash_direction() -> Vector2:
	if special_dash_last_valid_direction == Vector2.ZERO:
		return Vector2.UP

	return special_dash_last_valid_direction


func _try_ground_special_dash() -> void:
	pass


func _reset_special_dash_hold_state() -> void:
	special_dash_hold_timer = 0.0
	special_dash_press_direction = Vector2.ZERO
	special_dash_last_valid_direction = Vector2.ZERO

	special_dash_hold_started_on_floor = false
	special_dash_ground_attempted = false


func _reset_special_dash_input_state() -> void:
	special_dash_hold_active = false
	special_dash_preparing = false
	dash_input_updates_facing = true

	_reset_special_dash_hold_state()


# ==================================================
# 物理更新
# ==================================================

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return

	var actor_delta: float = CombatTimeManager.get_actor_delta(
		self,
		delta
	)

	# TimeFreeze 只暂停角色自身执行层。
	# 输入采集仍然在 _process() 中继续。
	if actor_delta <= 0.0:
		return

	# --------------------------------------------------
	# 运动状态计时
	# --------------------------------------------------

	movement_controller.update_dash(actor_delta)

	movement_controller.update_coyote_time(
		actor_delta,
		is_on_floor()
	)

	movement_controller.update_jump_buffer(actor_delta)

	if jump_release_pending:
		jump_release_pending = false
		velocity = movement_controller.cut_jump(velocity)

	# --------------------------------------------------
	# Action Movement
	# --------------------------------------------------

	var velocity_override_active: bool = false
	var suppress_gravity: bool = false

	var movement_result: Dictionary = movement_controller.update_action_movement(
		actor_delta,
		velocity,
		movement_controller.gravity,
		is_on_floor()
	)

	velocity_override_active = movement_result["active"]
	suppress_gravity = movement_result["suppress_gravity"]

	if velocity_override_active:
		velocity = movement_result["velocity"]

	# --------------------------------------------------
	# 重力
	# --------------------------------------------------

	velocity = movement_controller.apply_gravity(
		actor_delta,
		velocity,
		is_on_floor(),
		suppress_gravity
	)

	
	# --------------------------------------------------
	# 普通移动
	# --------------------------------------------------

	if velocity_override_active:
		pass

	else:
		var action_running: bool = (
			combat_action_executor.is_action_running()
		)

		# Action 期间不允许普通输入改变面向。
		if not action_running and move_input_direction != 0.0:
			_update_facing(move_input_direction)

		# Action 期间不允许普通蹲伏。
		var is_crouching: bool = (
			is_on_floor()
			and Input.is_action_pressed("move_down")
			and not action_running
		)

		# Action 期间屏蔽普通移动输入，
		# 但保留已有速度，让移动系统继续自然减速。
		var effective_move_input: Vector2 = Vector2.ZERO

		if not action_running:
			effective_move_input.x = move_input_direction

		if not movement_controller.has_action_stabilization():
			velocity = movement_controller.update_movement(
				actor_delta,
				velocity,
				effective_move_input,
				is_on_floor(),
				is_crouching,
				action_running
			)


	# --------------------------------------------------
	# Dash 请求
	# --------------------------------------------------

	if dash_input_pending:
		dash_input_pending = false

		var dash_request_accepted: bool = request_dash(
			dash_input_direction,
			dash_input_updates_facing
		)

		dash_input_updates_facing = true

		if dash_request_accepted:
			movement_controller.consume_buffered_jump()

	# --------------------------------------------------
	# Super Jump / Hyper Jump / 普通 Jump
	# --------------------------------------------------

	if movement_controller.has_buffered_jump():
		var jump_started: bool = false

		# Hyper Jump：Duck 滑行期间跳跃。
		if (
			movement_controller.is_duck_sliding
			and movement_controller.can_coyote_jump()
		):
			if combat_action_executor.is_action_running():
				combat_action_executor.cancel_action()

			velocity = movement_controller.apply_hyper_jump(
				velocity,
				move_input_direction
			)

			jump_started = true

		# Super Jump：水平 Dash 期间跳跃。
		elif (
			movement_controller.can_super_jump()
			and movement_controller.can_coyote_jump()
		):
			if combat_action_executor.is_action_running():
				combat_action_executor.cancel_action()

			velocity = movement_controller.apply_super_jump(
				velocity,
				move_input_direction
			)

			jump_started = true

		# 普通 Jump：继续使用原来的 Action 优先级规则。
		elif (
			movement_controller.can_coyote_jump()
			and combat_action_executor.can_interrupt_current_action(
				movement_controller.jump_action_priority
			)
		):
			if combat_action_executor.is_action_running():
				combat_action_executor.cancel_action()

			velocity = movement_controller.apply_jump(
				velocity,
				move_input_direction
			)

			jump_started = true

		if jump_started:
			if not jump_button_held:
				velocity = movement_controller.cut_jump(velocity)

			movement_controller.coyote_timer = 0.0
			movement_controller.consume_buffered_jump()

	# --------------------------------------------------
	# 普通攻击请求
	# --------------------------------------------------

	_process_normal_attack_input()

	# --------------------------------------------------
	# 技能请求
	# --------------------------------------------------

	_process_skill_input()

	# --------------------------------------------------
	# 动作稳定
	# --------------------------------------------------

	if not is_dashing:
		velocity = movement_controller.apply_action_stabilization(
			velocity,
			actor_delta,
			is_on_floor()
		)

	# --------------------------------------------------
	# 物理移动
	# --------------------------------------------------

	_move_and_slide_with_time_scale(actor_delta, delta)


# ==================================================
# 战斗输入请求处理
# ==================================================

func _process_normal_attack_input() -> void:
	if not normalattack_input_pending:
		return

	normalattack_input_pending = false

	var request: CombatActionRequest

	if combat_combo_executor.is_combo_running:
		if combat_combo_executor.current_combo_data == combat_combo_executor.combo_data:
			request = CombatActionRequest.new()
			request.request_type = CombatActionRequest.RequestType.CONTINUE_COMBO
		else:
			request = combat_combo_executor.create_combo_request()
	else:
		request = combat_combo_executor.create_combo_request()

	combat_combo_executor.submit_request(request)


func _process_skill_input() -> void:
	if not skill_input_pending:
		return

	skill_input_pending = false

	skill_selector.request_skill()


# ==================================================
# 生命值与受击
# ==================================================

func take_damage(damage: float) -> void:
	if is_dead:
		return

	if damage <= 0.0:
		return

	current_health = maxf(current_health - damage, 0.0)
	debug_damage_number.emit(global_position, damage)

	if current_health <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return

	# 先锁定死亡状态，防止清理期间产生新的战斗输入。
	is_dead = true

	velocity = Vector2.ZERO
	move_input_direction = 0.0
	move_input_vector = Vector2.ZERO

	jump_button_held = false
	jump_release_pending = false

	dash_input_pending = false
	normalattack_input_pending = false
	skill_input_pending = false

	dash_input_direction = Vector2.ZERO
	dash_input_updates_facing = true

	_reset_special_dash_input_state()

	# 清除 Combo 缓存，并结束 Combo 当前动作。
	if combat_combo_executor != null:
		combat_combo_executor.clear_for_death()

	# 处理不属于 Combo 的独立 Action。
	if (
		combat_action_executor != null
		and combat_action_executor.is_action_running()
	):
		combat_action_executor.cancel_action()

	# Action 模块结束时会执行自身清理；这里再做一次死亡兜底，
	# 确保 MovementTrack 碰撞 Mask、Dash 和跳跃缓存不会残留。
	if movement_controller != null:
		movement_controller.clear_for_death()

	# 结束回调可能处理 End Velocity，因此最后再次锁定速度。
	velocity = Vector2.ZERO


# ==================================================
# 死亡清理 Debug / 验证接口
# ==================================================

func get_death_cleanup_debug_data() -> Dictionary:
	var action_running: bool = (
		combat_action_executor != null
		and combat_action_executor.is_action_running()
	)

	var combo_debug: Dictionary = {}
	if combat_combo_executor != null:
		combo_debug = combat_combo_executor.get_debug_data()

	var combo_running: bool = bool(combo_debug.get("combo_running", false))
	var combo_input_buffered: bool = bool(
		combo_debug.get("combo_input_buffered", false)
	)
	var pending_combo: bool = bool(combo_debug.get("pending_combo", false))

	var action_debug: Dictionary = {}
	if combat_action_executor != null:
		action_debug = combat_action_executor.get_debug_data()

	var runtime_data: Dictionary = action_debug.get("runtime_data", {})
	var active_hit_instances: int = int(
		runtime_data.get("hit_instance_active_count", 0)
	)

	var movement_active: bool = (
		movement_controller != null
		and movement_controller.has_action_movement()
	)
	var collision_mask_restored: bool = (
		movement_controller == null
		or not movement_controller.movement_track_collision_mask_modified
	)
	var stabilization_active: bool = (
		movement_controller != null
		and (
			movement_controller.stabilization_context_id != 0
			or movement_controller.stabilization_locked
			or movement_controller.movement_suppress_gravity
		)
	)

	var input_buffers_clear: bool = (
		not dash_input_pending
		and not normalattack_input_pending
		and not skill_input_pending
		and not jump_release_pending
		and not special_dash_hold_active
		and (
			movement_controller == null
			or (
				not movement_controller.dash_buffered
				and movement_controller.jump_buffer_timer <= 0.0
			)
		)
	)

	var duck_and_landing_clear: bool = (
		movement_controller == null
		or (
			not movement_controller.is_duck_sliding
			and not movement_controller.ultra_landing_pending
		)
	)

	var debug_timeline_clear: bool = (
		not debug_action_active
		and debug_action_name == "待机"
	)

	var velocity_zero: bool = velocity.is_zero_approx()

	var all_clear: bool = (
		is_dead
		and not action_running
		and not combo_running
		and not combo_input_buffered
		and not pending_combo
		and active_hit_instances == 0
		and not movement_active
		and collision_mask_restored
		and not stabilization_active
		and input_buffers_clear
		and duck_and_landing_clear
		and debug_timeline_clear
		and velocity_zero
	)

	return {
		"all_clear": all_clear,
		"action_running": action_running,
		"combo_running": combo_running,
		"combo_input_buffered": combo_input_buffered,
		"pending_combo": pending_combo,
		"active_hit_instances": active_hit_instances,
		"movement_active": movement_active,
		"collision_mask_restored": collision_mask_restored,
		"stabilization_active": stabilization_active,
		"input_buffers_clear": input_buffers_clear,
		"duck_and_landing_clear": duck_and_landing_clear,
		"debug_timeline_clear": debug_timeline_clear,
		"velocity_zero": velocity_zero
	}


# ==================================================
# 角色面向
# ==================================================

# 普通面向更新：Action 运行期间不允许改变面向。
func _update_facing(direction: float) -> void:
	if direction == 0.0:
		return

	if combat_action_executor != null:
		if combat_action_executor.is_facing_locked():
			return

	_set_facing_direction(direction)


# 强制设置面向：只供 Action 启动时同步 Context 方向使用。
func _set_facing_direction(direction: float) -> void:
	if direction == 0.0:
		return

	facing_direction = signf(direction)
	$Polygon2D.scale.x = facing_direction


# ==================================================
# 请求 Dash
# ==================================================

func request_dash(
	direction: Vector2,
	update_facing: bool = true
) -> bool:
	return movement_controller.request_dash(
		direction,
		update_facing
	)


# ==================================================
# 统一调试接口
# ==================================================

func _set_debug_action(
	action_name: String,
	startup: float,
	active: float,
	recovery: float
) -> void:
	debug_action_name = action_name

	debug_startup_duration = startup
	debug_active_duration = active
	debug_recovery_duration = recovery

	debug_action_elapsed = 0.0
	debug_action_active = true

	if startup > 0.0:
		debug_phase_name = "前摇"
	else:
		debug_phase_name = "生效"


func _set_debug_phase(phase_name: String) -> void:
	debug_phase_name = phase_name


func _clear_debug_action() -> void:
	debug_action_name = "待机"
	debug_phase_name = ""

	debug_startup_duration = 0.0
	debug_active_duration = 0.0
	debug_recovery_duration = 0.0

	debug_action_elapsed = 0.0
	debug_action_active = false


# ==================================================
# Executor 调试信号
# ==================================================

func _on_executor_action_started(
	context: CombatActionContext
) -> void:
	# 使用新 Action Context 的面向同步角色视觉方向。
	# 这里有意绕过普通面向锁定检查。
	_set_facing_direction(context.facing_direction)

	var data := context.action_data

	_set_debug_action(
		data.action_name,
		data.startup,
		data.active,
		data.recovery
	)


func _on_executor_action_phase_changed(
	context: CombatActionContext
) -> void:
	match context.current_phase:
		&"startup":
			_set_debug_phase("前摇")

		&"active":
			_set_debug_phase("生效")

		&"recovery":
			_set_debug_phase("后摇")


func _on_executor_action_finished(
	context: CombatActionContext,
	_was_cancelled: bool
) -> void:
	if combat_action_executor.current_context != context:
		return

	_clear_debug_action()


func _on_energy_changed(
	current_energy: float,
	max_energy: float
) -> void:
	debug_energy_current = current_energy
	debug_energy_max = max_energy


# ==================================================
# 时间倍率适配物理移动
# ==================================================

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
