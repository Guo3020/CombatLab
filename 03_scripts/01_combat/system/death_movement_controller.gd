extends RefCounted
class_name DeathMovementController


enum DeathMode {
	NONE,
	NON_KNOCKBACK,
	KNOCKBACK
}


const NON_KNOCKBACK_HORIZONTAL_SPEED: float = 500.0


var actor: CharacterBody2D
var mode: DeathMode = DeathMode.NONE

var gravity: float = 1200.0
var horizontal_deceleration: float = 900.0
var landing_bounce_ratio: float = 0.35

var is_active: bool = false
var is_settled: bool = false

var was_on_floor: bool = false
var bounce_on_landing: bool = false
var bounce_count: int = 0
var impact_velocity_y: float = 0.0


func begin_non_knockback(
	target_actor: CharacterBody2D,
	attack_direction: Vector2,
	gravity_value: float,
	deceleration_value: float = 900.0,
	bounce_ratio_value: float = 0.35
) -> void:
	actor = target_actor
	mode = DeathMode.NON_KNOCKBACK

	gravity = maxf(gravity_value, 0.0)
	horizontal_deceleration = maxf(deceleration_value, 0.0)
	landing_bounce_ratio = clampf(bounce_ratio_value, 0.0, 1.0)

	was_on_floor = actor.is_on_floor()
	bounce_on_landing = not was_on_floor
	bounce_count = 0
	is_settled = false
	is_active = true

	# 有攻击来源时，只使用攻击方向决定水平正负，速度固定为 500。
	# 无来源时保留死亡瞬间的水平速度。
	if not is_zero_approx(attack_direction.x):
		actor.velocity.x = signf(attack_direction.x) * NON_KNOCKBACK_HORIZONTAL_SPEED

	# 地面死亡不需要保留向地面挤压的垂直速度。
	if was_on_floor and actor.velocity.y > 0.0:
		actor.velocity.y = 0.0


func update_before_move(delta: float) -> void:
	if not is_active or actor == null or not is_instance_valid(actor):
		return

	if is_settled:
		actor.velocity = Vector2.ZERO
		return

	if actor.is_on_floor():
		if actor.velocity.y > 0.0:
			actor.velocity.y = 0.0
	else:
		actor.velocity.y += gravity * delta

	actor.velocity.x = move_toward(
		actor.velocity.x,
		0.0,
		horizontal_deceleration * delta
	)

	# 在 move_and_slide() 前记录速度，供落地回弹计算使用。
	impact_velocity_y = actor.velocity.y


func update_after_move() -> void:
	if not is_active or actor == null or not is_instance_valid(actor):
		return

	var on_floor_now: bool = actor.is_on_floor()
	var just_landed: bool = on_floor_now and not was_on_floor

	if just_landed:
		if (
			bounce_on_landing
			and bounce_count == 0
			and impact_velocity_y > 0.0
		):
			actor.velocity.y = -impact_velocity_y * landing_bounce_ratio
			bounce_count += 1
		else:
			is_settled = true
			actor.velocity = Vector2.ZERO

	elif on_floor_now and not bounce_on_landing:
		actor.velocity.y = 0.0
		if is_zero_approx(actor.velocity.x):
			is_settled = true

	was_on_floor = on_floor_now


func get_debug_data() -> Dictionary:
	var mode_name: String = "NONE"
	match mode:
		DeathMode.NON_KNOCKBACK:
			mode_name = "NON_KNOCKBACK"
		DeathMode.KNOCKBACK:
			mode_name = "KNOCKBACK"

	var current_velocity := Vector2.ZERO
	if actor != null and is_instance_valid(actor):
		current_velocity = actor.velocity

	return {
		"mode": mode_name,
		"active": is_active,
		"settled": is_settled,
		"bounce_count": bounce_count,
		"bounce_on_landing": bounce_on_landing,
		"velocity": current_velocity,
		"gravity": gravity,
		"horizontal_deceleration": horizontal_deceleration,
		"landing_bounce_ratio": landing_bounce_ratio
	}
