
@tool
extends CombatActionModule
class_name MovementModule


enum MovementMode {
	NONE,
	DASH,
	VELOCITY_OVERRIDE,
	MOVEMENT_TRACK
}


enum MovementCollisionStrategy {
	BLOCK,
	IGNORE_WORLD
}

enum DirectionSource {
	INPUT_DIRECTION,
	FACING_DIRECTION,
	CUSTOM_DIRECTION
}

enum EndVelocityMode {
	PRESERVE_CURRENT,
	SET_SPEED
}

enum OverridePhaseMode {
	SPEED_PROTECTION,
	LINEAR_INTERPOLATION,
	DIRECT_SET
}

enum StabilizationActivationMode {
	PHASE_RANGE,
	DURATION
}

enum StabilizationPhase {
	STARTUP,
	ACTIVE,
	RECOVERY
}


# ==================================================
# Inspector 显示控制
# ==================================================

@export_group("额外位移")

var _movement_mode: MovementMode = MovementMode.NONE

@export var movement_mode: MovementMode:
	get:
		return _movement_mode
	set(value):
		if _movement_mode == value:
			return
		_movement_mode = value
		call_deferred("notify_property_list_changed")
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = property.get("name", &"")

	var is_dash_mode: bool = movement_mode == MovementMode.DASH
	var is_override_mode: bool = movement_mode == MovementMode.VELOCITY_OVERRIDE
	var is_movement_track_mode: bool = movement_mode == MovementMode.MOVEMENT_TRACK

	var dash_properties: Array[StringName] = [
		&"dash_speed",
		&"dash_duration",
		&"dash_up_end_y_multiplier",
		&"dash_diagonal_up_end_y_multiplier",
		&"dash_duck_speed_multiplier",
		&"end_velocity_enabled",
		&"exclude_diagonal_down_end",
		&"dash_time_freeze_enabled",
		&"dash_time_freeze_duration"
	]

	var override_properties: Array[StringName] = [
		&"override_phase_mode",
		&"override_duration",
		&"override_speed",
		&"override_direction_source",
		&"override_custom_direction",
		&"override_suppress_gravity"
	]

	var movement_track_properties: Array[StringName] = [
		&"movement_track_duration",
		&"movement_track_x",
		&"movement_track_y",
		&"movement_track_collision_strategy"
	]

	if property_name in dash_properties and not is_dash_mode:
		property.usage = PROPERTY_USAGE_NO_EDITOR

	if property_name in override_properties and not is_override_mode:
		property.usage = PROPERTY_USAGE_NO_EDITOR

	if property_name in movement_track_properties and not is_movement_track_mode:
		property.usage = PROPERTY_USAGE_NO_EDITOR

	# Duration and collision strategy are configured in the Hit Editor panel.
	if property_name in [&"movement_track_duration", &"movement_track_collision_strategy"] and is_movement_track_mode:
		property.usage = PROPERTY_USAGE_STORAGE

	if property_name == &"stabilization_enabled" and is_movement_track_mode:
		property.usage = PROPERTY_USAGE_NO_EDITOR

	if property_name in [&"end_velocity_mode", &"end_speed"]:
		if not is_dash_mode and not is_override_mode:
			property.usage = PROPERTY_USAGE_NO_EDITOR

	if property_name == &"dash_time_freeze_duration":
		if not is_dash_mode or not dash_time_freeze_enabled:
			property.usage = PROPERTY_USAGE_NO_EDITOR

	var is_stabilization_enabled: bool = stabilization_enabled

	var is_phase_range_property: bool = (
		property_name == &"stabilization_start_phase"
		or property_name == &"stabilization_end_phase"
	)

	var is_duration_property: bool = (
		property_name == &"stabilization_duration_start_phase"
		or property_name == &"stabilization_duration"
	)

	var is_stabilization_config_property: bool = (
		property_name == &"stabilization_activation_mode"
		or property_name == &"stabilization_speed"
		or is_phase_range_property
		or is_duration_property
	)

	if is_stabilization_config_property:
		if is_movement_track_mode:
			property.usage = PROPERTY_USAGE_NO_EDITOR
		elif not is_stabilization_enabled:
			property.usage = PROPERTY_USAGE_NO_EDITOR

		elif stabilization_activation_mode == StabilizationActivationMode.PHASE_RANGE:
			if is_duration_property:
				property.usage = PROPERTY_USAGE_NO_EDITOR

		elif stabilization_activation_mode == StabilizationActivationMode.DURATION:
			if is_phase_range_property:
				property.usage = PROPERTY_USAGE_NO_EDITOR


# ==================================================
# 动作稳定
# ==================================================

@export_group("动作稳定")

@export var stabilization_enabled: bool = true:
	set(value):
		stabilization_enabled = value
		notify_property_list_changed()


@export var stabilization_activation_mode: StabilizationActivationMode = StabilizationActivationMode.PHASE_RANGE:
	set(value):
		stabilization_activation_mode = value
		notify_property_list_changed()


@export_range(0.0, 10000.0, 50.0)
var stabilization_speed: float = 4000.0

@export var stabilization_start_phase: StabilizationPhase = StabilizationPhase.STARTUP

@export var stabilization_end_phase: StabilizationPhase = StabilizationPhase.RECOVERY

@export var stabilization_duration_start_phase: StabilizationPhase = StabilizationPhase.ACTIVE

@export_range(0.01, 10.0, 0.01)
var stabilization_duration: float = 0.2


var stabilize_vertical_in_air: bool = true


# ==================================================
# DASH 配置
# ==================================================

@export_group("DASH 配置")

@export_range(0.0, 3000.0, 10.0)
var dash_speed: float = 960.0

@export_range(0.01, 5.0, 0.01)
var dash_duration: float = 0.15

@export_range(0.0, 1.0, 0.01)
var dash_up_end_y_multiplier: float = 0.75

@export_range(0.0, 1.0, 0.01)
var dash_diagonal_up_end_y_multiplier: float = 0.75

@export_range(0.1, 3.0, 0.05)
var dash_duck_speed_multiplier: float = 1.2

@export var end_velocity_enabled: bool = true

@export var exclude_diagonal_down_end: bool = true

@export var dash_time_freeze_enabled: bool = false:
	set(value):
		dash_time_freeze_enabled = value
		notify_property_list_changed()

@export_range(0.01, 0.5, 0.01)
var dash_time_freeze_duration: float = 0.05

@export var end_velocity_mode: EndVelocityMode = EndVelocityMode.PRESERVE_CURRENT

@export_range(0.0, 3000.0, 10.0)
var end_speed: float = 160.0


# ==================================================
# 通用速度覆盖配置
# ==================================================

@export_group("通用速度覆盖")

@export var override_phase_mode: OverridePhaseMode = OverridePhaseMode.SPEED_PROTECTION

@export_range(0.01, 5.0, 0.01)
var override_duration: float = 0.15

@export_range(0.0, 3000.0, 10.0)
var override_speed: float = 240.0

@export var override_direction_source: DirectionSource = DirectionSource.INPUT_DIRECTION

@export var override_custom_direction: Vector2 = Vector2.RIGHT

@export var override_suppress_gravity: bool = false


# ==================================================
# MovementTrack 配置
# ==================================================

@export_group("MovementTrack")

@export var movement_track_duration: float = 0.2

@export var movement_track_x: Curve = Curve.new()

@export var movement_track_y: Curve = Curve.new()

@export var movement_track_collision_strategy: MovementCollisionStrategy = MovementCollisionStrategy.BLOCK


func _init() -> void:
	_initialize_flat_track_curve(movement_track_x)
	_initialize_flat_track_curve(movement_track_y)


func _initialize_flat_track_curve(curve: Curve) -> void:
	if curve == null:
		return

	if curve.resource_name.is_empty():
		curve.resource_name = "MovementTrack Curve"

	if curve.get_point_count() == 0:
		curve.add_point(Vector2(0.0, 0.0))
		curve.add_point(Vector2(1.0, 0.0))
	elif curve.get_point_count() == 1:
		curve.set_point_position(0, Vector2(0.0, 0.0))
		curve.add_point(Vector2(1.0, 0.0))
	else:
		curve.set_point_position(0, Vector2(0.0, 0.0))
		curve.set_point_position(
			curve.get_point_count() - 1,
			Vector2(1.0, 0.0)
		)

	curve.min_value = -1000.0
	curve.max_value = 1000.0
	curve.bake_resolution = 1000.0


# ==================================================
# 模块接口
# ==================================================

func get_module_id() -> StringName:
	return &"movement"


func on_module_start(context: RefCounted) -> void:
	var action_context := context as CombatActionContext

	if action_context == null:
		return

	if not is_instance_valid(action_context.actor):
		return

	var movement_request := {
		"movement_mode": movement_mode,

		"stabilization_enabled": stabilization_enabled,
		"stabilization_activation_mode": stabilization_activation_mode,
		"stabilization_start_phase": stabilization_start_phase,
		"stabilization_end_phase": stabilization_end_phase,
		"stabilization_duration_start_phase": stabilization_duration_start_phase,
		"stabilization_duration": stabilization_duration,
		"stabilization_speed": stabilization_speed,
		"stabilize_vertical_in_air": stabilize_vertical_in_air,

		"end_velocity_mode": end_velocity_mode,
		"end_speed": end_speed
	}

	var movement_debug := {
		"movement_mode": _get_movement_mode_name(),

		"stabilization_enabled": stabilization_enabled,
		"stabilization_activation_mode": _get_stabilization_mode_name(),

		"velocity_override_enabled": movement_mode != MovementMode.NONE,
		"velocity_override_active": false,
		"velocity_override_finished": false,

		"suppress_gravity": false
	}

	if movement_mode == MovementMode.DASH:
		var direction := action_context.input_direction

		if direction.length_squared() <= 0.0001:
			direction = Vector2.RIGHT * action_context.facing_direction

		direction = direction.normalized()

		movement_request.merge({
			"dash_speed": dash_speed,
			"dash_duration": dash_duration,
			"dash_direction": direction,
			"dash_duck_speed_multiplier": dash_duck_speed_multiplier,
			"end_velocity_enabled": end_velocity_enabled,
			"exclude_diagonal_down_end": exclude_diagonal_down_end,
			"dash_up_end_y_multiplier": dash_up_end_y_multiplier,
			"dash_diagonal_up_end_y_multiplier": dash_diagonal_up_end_y_multiplier,
			"dash_time_freeze_enabled": dash_time_freeze_enabled,
			"dash_time_freeze_duration": dash_time_freeze_duration
		})

		movement_debug.merge({
			"dash_speed": dash_speed,
			"dash_duration": dash_duration,
			"dash_direction": direction,
			"dash_duck_speed_multiplier": dash_duck_speed_multiplier,
			"dash_time_freeze_enabled": dash_time_freeze_enabled,
			"dash_time_freeze_duration": dash_time_freeze_duration
		})

	elif movement_mode == MovementMode.MOVEMENT_TRACK:
		movement_request.merge({
			"movement_track_duration": movement_track_duration,
			"movement_track_facing_direction": action_context.facing_direction,
			"movement_track_x": movement_track_x,
			"movement_track_y": movement_track_y,
			"movement_track_collision_strategy": movement_track_collision_strategy
		})

		movement_debug.merge({
			"movement_track_duration": movement_track_duration,
			"movement_track_collision_strategy": "IGNORE_WORLD" if movement_track_collision_strategy == MovementCollisionStrategy.IGNORE_WORLD else "BLOCK"
		})

	elif movement_mode == MovementMode.VELOCITY_OVERRIDE:
		var direction := _get_direction(
			action_context,
			override_direction_source,
			override_custom_direction
		)

		movement_request.merge({
			"override_phase_mode": override_phase_mode,
			"override_duration": override_duration,
			"override_speed": override_speed,
			"override_direction": direction,
			"override_suppress_gravity": override_suppress_gravity
		})

		movement_debug.merge({
			"override_phase_mode": override_phase_mode,
			"override_duration": override_duration,
			"override_speed": override_speed,
			"override_direction": direction
		})

	var movement_source_id := StringName(
		"action_%d_module_%d" % [
			action_context.get_instance_id(),
			get_instance_id()
		]
	)

	movement_debug["movement_source_id"] = movement_source_id

	# --------------------------------------------------
	# 提交 Movement Request
	# --------------------------------------------------
	# 不再根据 MovementMode 判断是否提交。
	# NONE 也可能包含 Stabilization 等 Movement 行为。
	# 只要加载并启动了 MovementModule，就提交请求。

	var movement_handler: Object = action_context.actor.get(
		"movement_request_handler"
	) as Object

	if not CombatMovementInterface.supports(movement_handler):
		push_warning(
			"MovementModule: Actor 的 movement_request_handler 未实现 CombatMovementInterface，Movement 请求未提交。"
		)
	else:
		var accepted := CombatMovementInterface.receive_action_movement_request(
			movement_handler,
			movement_source_id,
			movement_request
		)

		if accepted:
			action_context.runtime_data["movement_source_id"] = movement_source_id

			# 只有 Dash 才请求 TimeFreeze。
			if (
				movement_mode == MovementMode.DASH
				and dash_time_freeze_enabled
			):
				var time_freeze_source_id := StringName(
					"%s_time_freeze" % movement_source_id
				)

				CombatTimeManager.request_actor_time_freeze(
					action_context.actor,
					time_freeze_source_id,
					dash_time_freeze_duration
				)

				action_context.runtime_data["movement_time_freeze_source_id"] = time_freeze_source_id

		else:
			push_warning(
				"MovementModule: movement_request_handler 拒绝了 Movement 请求。"
			)

	action_context.runtime_data["movement_request"] = movement_request
	action_context.runtime_data["movement_debug"] = movement_debug


func on_module_end(context: RefCounted) -> void:
	var action_context := context as CombatActionContext

	if action_context == null:
		return

	var time_freeze_source_id: StringName = StringName(
		action_context.runtime_data.get(
			"movement_time_freeze_source_id",
			&""
		)
	)

	if (
		time_freeze_source_id != &""
		and is_instance_valid(action_context.actor)
	):
		CombatTimeManager.cancel_actor_time_freeze(
			action_context.actor,
			time_freeze_source_id
		)

	var movement_source_id: StringName = StringName(
		action_context.runtime_data.get("movement_source_id", &"")
	)

	if (
		movement_source_id != &""
		and is_instance_valid(action_context.actor)
	):
		var movement_handler: Object = action_context.actor.get(
			"movement_request_handler"
		) as Object

		if CombatMovementInterface.supports(movement_handler):
			var action_end_reason: StringName = StringName(
				action_context.runtime_data.get(
					"action_end_reason",
					&"cancelled"
				)
			)

			var movement_end_reason: CombatMovementInterface.MovementEndReason

			match action_end_reason:
				&"completed":
					movement_end_reason = CombatMovementInterface.MovementEndReason.COMPLETED

				&"replaced":
					movement_end_reason = CombatMovementInterface.MovementEndReason.REPLACED

				&"cancelled":
					movement_end_reason = CombatMovementInterface.MovementEndReason.CANCELLED

				_:
					push_warning(
						"MovementModule: 未知的 Action 结束原因：%s，按取消处理。"
						% action_end_reason
					)
					movement_end_reason = CombatMovementInterface.MovementEndReason.CANCELLED

			CombatMovementInterface.notify_movement_action_finished(
				movement_handler,
				movement_source_id,
				movement_end_reason
			)

	action_context.runtime_data.erase("movement_request")
	action_context.runtime_data.erase("movement_debug")
	action_context.runtime_data.erase("movement_source_id")
	action_context.runtime_data.erase("movement_time_freeze_source_id")


# ==================================================
# Debug 数据
# ==================================================

func _get_movement_mode_name() -> String:
	match movement_mode:
		MovementMode.DASH:
			return "DASH"

		MovementMode.VELOCITY_OVERRIDE:
			return "VELOCITY_OVERRIDE"

		MovementMode.MOVEMENT_TRACK:
			return "MOVEMENT_TRACK"

		_:
			return "NONE"


func _get_stabilization_mode_name() -> String:
	match stabilization_activation_mode:
		StabilizationActivationMode.PHASE_RANGE:
			return "PHASE_RANGE"

		StabilizationActivationMode.DURATION:
			return "DURATION"

	return "UNKNOWN"


# ==================================================
# 方向计算
# ==================================================

func _get_direction(
	context: CombatActionContext,
	source: DirectionSource,
	custom_direction: Vector2
) -> Vector2:

	var direction := Vector2.ZERO

	match source:
		DirectionSource.INPUT_DIRECTION:
			direction = context.input_direction

		DirectionSource.FACING_DIRECTION:
			direction = Vector2.RIGHT * context.facing_direction

		DirectionSource.CUSTOM_DIRECTION:
			direction = custom_direction

	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT * context.facing_direction

	return direction.normalized()
