
extends Control

# ==================================================
# 调试显示参数
# ==================================================

# 打断 Debug
var enemy_interrupt_flash_timer: float = 0.0
var enemy_interrupt_flash_duration: float = 0.8
var enemy_interrupt_position: Vector2 = Vector2.ZERO

@export var timeline_width: float = 420.0
@export var timeline_y: float = 120.0
@export var show_hitbox: bool = true
@export var show_player_collision: bool = true
@export var show_player_origin: bool = true
@export var show_executor_info: bool = true

@export var show_energy: bool = true
@export var show_movement_info: bool = true
@export var show_dash_charges: bool = true

var player: CharacterBody2D
var executor: CombatActionExecutor
var combo_executor: CombatComboExecutor
var enemy: EnemyBase
var enemy_executor: CombatActionExecutor
var enemy_ai_controller: EnemyAIController


# 伤害数字
var damage_numbers: Array[Label] = []



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 寻找 Player
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	if player == null:
		push_warning("CombatDebugOverlay：没有找到 Player1")
		return

	# 获取 Player 的 Executor
	executor = player.get_node_or_null(
		"CombatActionExecutor"
	) as CombatActionExecutor

	if executor == null:
		push_warning("CombatDebugOverlay：没有找到 CombatActionExecutor")

	# 获取 Player 的 ComboExecutor
	combo_executor = player.get_node_or_null(
		"CombatComboExecutor"
	) as CombatComboExecutor

	if combo_executor == null:
		push_warning("CombatDebugOverlay：没有找到 CombatComboExecutor")

	# 监听伤害数字
	if player.has_signal("debug_damage_number"):
		player.connect(
			"debug_damage_number",
			_on_debug_damage_number
		)

	# 寻找 EnemyBase
	var scene_nodes := get_tree().current_scene.find_children(
		"*",
		"",
		true,
		false
	)

	for node in scene_nodes:
		if node is EnemyBase:
			enemy = node as EnemyBase
			break

	# 获取 Enemy 的 AIController
	if enemy != null:
		if enemy.has_signal("debug_damage_number"):
			enemy.connect(
				"debug_damage_number",
				_on_debug_damage_number
			)

		enemy_ai_controller = enemy.get_node_or_null(
			"AIController"
		) as EnemyAIController

		if enemy_ai_controller == null:
			push_warning("CombatDebugOverlay：没有找到 EnemyAIController")

		# 获取 Enemy 的 CombatActionExecutor
		enemy_executor = enemy.get_node_or_null(
			"CombatActionExecutor"
		) as CombatActionExecutor

		if enemy_executor == null:
			push_warning("CombatDebugOverlay：没有找到 Enemy CombatActionExecutor")

		# 监听敌人被打断事件
		if not HitManager.target_interrupted.is_connected(
			_on_target_interrupted
		):
			HitManager.target_interrupted.connect(
				_on_target_interrupted
			)

	else:
		push_warning("CombatDebugOverlay：没有找到 EnemyBase")



func _process(delta: float) -> void:
	if enemy_interrupt_flash_timer > 0.0:
		enemy_interrupt_flash_timer = maxf(
			enemy_interrupt_flash_timer - delta,
			0.0
		)

	queue_redraw()


func _draw() -> void:
	if player == null:
		return

	_draw_timeline()
	_draw_enemy_timeline()
	_draw_player_origin()
	_draw_movement_track_path()
	_draw_player_collision()
	_draw_hitbox()
	_draw_executor_info()
	_draw_player_death_cleanup_info()
	_draw_pending_combo_info()
	_draw_energy()
	_draw_movement_info()
	_draw_enemy_ai_info()
	_draw_dash_charges()
	_draw_death_test_controls()

	# 显示打断标记
	if enemy_interrupt_flash_timer > 0.0:
		var marker_color := Color(1.0, 0.1, 0.1)	
		var font := ThemeDB.fallback_font

		draw_line(
			enemy_interrupt_position + Vector2(0.0, -10.0),
			enemy_interrupt_position + Vector2(0.0, 24.0),
			marker_color,
			3.0
		)

		draw_string(
			font,
			enemy_interrupt_position + Vector2(8.0, -8.0),
			"INTERRUPTED!",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			marker_color
		)


# ==================================================
# 攻击时间轴
# ==================================================

func _draw_timeline() -> void:
	var action_name: String = str(player.get("debug_action_name"))
	var phase_name: String = str(player.get("debug_phase_name"))

	if action_name == "待机":
		draw_string(
			ThemeDB.fallback_font,
			Vector2(size.x * 0.5 - 30.0, timeline_y),
			"待机",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color.WHITE
		)
		return

	var startup: float = float(player.get("debug_startup_duration"))
	var active: float = float(player.get("debug_active_duration"))
	var recovery: float = float(player.get("debug_recovery_duration"))
	var elapsed: float = float(player.get("debug_action_elapsed"))

	var total: float = startup + active + recovery

	if total <= 0.0:
		return

	var start_x: float = (size.x - timeline_width) * 0.5
	var bar_y: float = timeline_y + 20.0

	draw_string(
		ThemeDB.fallback_font,
		Vector2(start_x, timeline_y),
		action_name + "  |  " + phase_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color.WHITE
	)

	var startup_width: float = timeline_width * startup / total
	var active_width: float = timeline_width * active / total
	var recovery_width: float = timeline_width * recovery / total

	# 前摇
	draw_rect(
		Rect2(start_x, bar_y, startup_width, 14.0),
		Color(0.95, 0.72, 0.20)
	)

	# 生效
	draw_rect(
		Rect2(start_x + startup_width, bar_y, active_width, 14.0),
		Color(0.95, 0.25, 0.25)
	)

	# 后摇
	draw_rect(
		Rect2(
			start_x + startup_width + active_width,
			bar_y,
			recovery_width,
			14.0
		),
		Color(0.25, 0.55, 0.95)
	)

	# HitInstance 时间窗口：相对于 Active 起点显示。
	if (
		executor != null
		and executor.is_action_running()
		and executor.current_context.action_data.hit_module_enabled
	):
		var context: CombatActionContext = executor.current_context
		var active_duration: float = context.action_data.active
		var active_start_x: float = start_x + startup_width

		if active_duration > 0.0:
			for index in range(context.action_data.hit_instances.size()):
				var hit_instance: HitInstanceData = (
					context.action_data.hit_instances[index]
				)

				if hit_instance == null:
					continue

				var start_ratio: float = clampf(
					hit_instance.start_time / active_duration,
					0.0,
					1.0
				)
				var end_ratio: float = clampf(
					hit_instance.end_time / active_duration,
					0.0,
					1.0
				)

				if end_ratio <= start_ratio:
					continue

				var instance_rect := Rect2(
					active_start_x + active_width * start_ratio,
					bar_y + 18.0 + float(index) * 6.0,
					maxf(active_width * (end_ratio - start_ratio), 2.0),
					4.0
				)

				draw_rect(
					instance_rect,
					Color(1.0, 0.35, 0.2, 0.95),
					true
				)

				draw_string(
					ThemeDB.fallback_font,
					instance_rect.position + Vector2(-22.0, 5.0),
					"HI%d" % index,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					10,
					Color(1.0, 0.65, 0.45)
				)

	# 时间轴游标
	var progress: float = clampf(elapsed / total, 0.0, 1.0)
	var cursor_x: float = start_x + timeline_width * progress

	draw_line(
		Vector2(cursor_x, bar_y - 5.0),
		Vector2(cursor_x, bar_y + 19.0),
		Color.WHITE,
		2.0
	)


# ==================================================
# 坐标转换
# ==================================================

func _world_to_screen(world_position: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform * world_position


# ==================================================
# Player 根节点原点
# ==================================================

func _draw_player_origin() -> void:
	if not show_player_origin:
		return

	var origin: Vector2 = _world_to_screen(player.global_position)

	# 原点圆圈
	draw_circle(
		origin,
		5.0,
		Color(1.0, 0.9, 0.2)
	)

	# X 轴
	draw_line(
		origin + Vector2(-12.0, 0.0),
		origin + Vector2(12.0, 0.0),
		Color(1.0, 0.9, 0.2),
		2.0
	)

	# Y 轴
	draw_line(
		origin + Vector2(0.0, -12.0),
		origin + Vector2(0.0, 12.0),
		Color(1.0, 0.9, 0.2),
		2.0
	)

	draw_string(
		ThemeDB.fallback_font,
		origin + Vector2(12.0, -12.0),
		"Player Origin (0, 0)",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(1.0, 0.9, 0.2)
	)


# ==================================================
# MovementTrack 路径 Debug
# ==================================================

func _draw_movement_track_path() -> void:
	if player == null:
		return

	var controller := player.get("movement_controller") as PlayerMovementController
	if controller == null or not controller.is_movement_track_active():
		return

	var request: Dictionary = controller.get_active_movement_request()
	var x_curve := request.get("movement_track_x") as Curve
	var y_curve := request.get("movement_track_y") as Curve
	if x_curve == null or y_curve == null:
		return

	# 与 MovementController 使用相同的坐标转换：
	# X 按 Action 开始时捕获的面向镜像，Y 的正值代表向上。
	var facing_direction := -1.0 if float(
		request.get("movement_track_facing_direction", 1)
	) < 0.0 else 1.0
	var current_progress: float = controller.movement_track_progress
	var current_curve_position := Vector2(
		x_curve.sample_baked(current_progress) * facing_direction,
		-y_curve.sample_baked(current_progress)
	)
	var points := PackedVector2Array()

	# 以角色当前位置为锚点，绘制相对于当前轨迹进度的前后路径。
	for index in range(21):
		var progress := float(index) / 20.0
		var curve_position := Vector2(
			x_curve.sample_baked(progress) * facing_direction,
			-y_curve.sample_baked(progress)
		)
		var relative_displacement := curve_position - current_curve_position
		points.append(
			_world_to_screen(player.global_position + relative_displacement)
		)

	if points.size() >= 2:
		draw_polyline(points, Color(0.35, 0.95, 0.75, 0.9), 2.0)

	var current_position := _world_to_screen(player.global_position)
	draw_circle(current_position, 5.0, Color(0.95, 0.95, 1.0))


# ==================================================
# Player 身体碰撞框
# ==================================================

func _draw_player_collision() -> void:
	if not show_player_collision:
		return

	var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if collision == null or collision.shape == null:
		return

	var rectangle := collision.shape as RectangleShape2D

	if rectangle == null:
		return

	var center: Vector2 = _world_to_screen(collision.global_position)

	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()

	var world_size: Vector2 = rectangle.size * collision.global_scale.abs()
	var screen_size: Vector2 = world_size * canvas_transform.get_scale().abs()

	var rect := Rect2(center - screen_size * 0.5, screen_size)

	# 身体碰撞框：绿色
	draw_rect(
		rect,
		Color(0.2, 1.0, 0.4, 0.10),
		true
	)

	draw_rect(
		rect,
		Color(0.2, 1.0, 0.4, 0.9),
		false,
		2.0
	)

	draw_string(
		ThemeDB.fallback_font,
		rect.position + Vector2(0.0, -6.0),
		"Player Collision",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(0.2, 1.0, 0.4)
	)


# ==================================================
# 攻击判定框
# ==================================================

func _draw_hitbox() -> void:
	if not show_hitbox:
		return

	_draw_actor_hitboxes(executor, "Player")
	_draw_actor_hitboxes(enemy_executor, "Enemy")


func _draw_actor_hitboxes(
	action_executor: CombatActionExecutor,
	actor_label: String
) -> void:
	if action_executor == null or not action_executor.is_action_running():
		return

	var debug_data: Dictionary = action_executor.get_debug_data()
	var runtime_data: Dictionary = debug_data.get("runtime_data", {})
	var instances: Array = runtime_data.get("hit_instance_runtime", [])

	for instance_data in instances:
		var area := instance_data.get("area") as Area2D

		if not is_instance_valid(area):
			continue

		var is_active: bool = bool(instance_data.get("enabled", false))
		var border_color: Color
		var fill_color: Color

		if is_active:
			border_color = Color(1.0, 0.2, 0.2, 1.0)
			fill_color = Color(1.0, 0.15, 0.15, 0.18)
		else:
			border_color = Color(0.15, 0.65, 1.0, 0.8)
			fill_color = Color(0.15, 0.65, 1.0, 0.07)

		for child in area.get_children():
			var collision := child as CollisionShape2D

			if collision == null or collision.shape == null:
				continue

			_draw_runtime_hitbox_shape(
				collision,
				border_color,
				fill_color
			)

		var label_position: Vector2 = (
			_world_to_screen(area.global_position)
			+ Vector2(0.0, -18.0)
		)

		var state_text: String = "ACTIVE" if is_active else "INACTIVE"
		var hit_count: int = int(instance_data.get("hit_count", 0))
		var instance_index: int = int(instance_data.get("index", 0))

		draw_string(
			ThemeDB.fallback_font,
			label_position,
			"%s HI-%d | %s | Hits: %d" % [
				actor_label,
				instance_index,
				state_text,
				hit_count
			],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			border_color
		)


func _draw_runtime_hitbox_shape(
	collision: CollisionShape2D,
	border_color: Color,
	fill_color: Color
) -> void:
	var outline := _get_hitbox_shape_outline(collision.shape)

	if outline.size() < 3:
		return

	var screen_points := PackedVector2Array()

	for local_point in outline:
		var world_point: Vector2 = collision.global_transform * local_point
		screen_points.append(_world_to_screen(world_point))

	draw_colored_polygon(screen_points, fill_color)

	var closed_points := screen_points.duplicate()
	closed_points.append(screen_points[0])
	draw_polyline(closed_points, border_color, 2.0)


func _get_hitbox_shape_outline(shape: Shape2D) -> PackedVector2Array:
	var points := PackedVector2Array()

	if shape is RectangleShape2D:
		var half_size: Vector2 = (shape as RectangleShape2D).size * 0.5
		points.append(Vector2(-half_size.x, -half_size.y))
		points.append(Vector2(half_size.x, -half_size.y))
		points.append(Vector2(half_size.x, half_size.y))
		points.append(Vector2(-half_size.x, half_size.y))

	elif shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius

		for index in range(32):
			var angle: float = TAU * float(index) / 32.0
			points.append(Vector2(cos(angle), sin(angle)) * radius)

	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var radius: float = capsule.radius
		var half_segment: float = maxf(
			capsule.height * 0.5 - radius,
			0.0
		)

		# 上半圆：从左侧经过顶部到右侧。
		for index in range(17):
			var angle: float = PI + PI * float(index) / 16.0
			points.append(
				Vector2(cos(angle), sin(angle)) * radius
				+ Vector2(0.0, -half_segment)
			)

		# 下半圆：从右侧经过底部到左侧。
		for index in range(17):
			var angle: float = PI * float(index) / 16.0
			points.append(
				Vector2(cos(angle), sin(angle)) * radius
				+ Vector2(0.0, half_segment)
			)

	return points


# ==================================================
# Executor 调试信息
# ==================================================

func _draw_executor_info() -> void:
	if not show_executor_info or executor == null:
		return

	var debug_data: Dictionary = executor.get_debug_data()

	var runtime_data: Dictionary = {}

	if debug_data.get("runtime_data") is Dictionary:
		runtime_data = debug_data["runtime_data"]

	var running: bool = executor.is_action_running()

	var state_text: String = "Executor: RUNNING" if running else "Executor: IDLE"

	var active_hit_instances: int = int(
		runtime_data.get("hit_instance_active_count", 0)
	)
	var total_hit_instances: int = int(
		runtime_data.get("hit_instance_count", 0)
	)
	var hitbox_state: String = "%d / %d" % [
		active_hit_instances,
		total_hit_instances
	]

	var info_position := Vector2(20.0, 35.0)

	draw_string(
		ThemeDB.fallback_font,
		info_position,
		state_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color.WHITE
	)

	draw_string(
		ThemeDB.fallback_font,
		info_position + Vector2(0.0, 22.0),
		"Active HitInstances: " + hitbox_state,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.3, 0.8, 1.0)
	)


# ==================================================
# Player 死亡清理 Debug
# ==================================================

func _draw_player_death_cleanup_info() -> void:
	if player == null or not bool(player.get("is_dead")):
		return

	var debug_data: Dictionary = player.call(
		"get_death_cleanup_debug_data"
	)

	var all_clear: bool = bool(debug_data.get("all_clear", false))
	var info_position := Vector2(20.0, size.y - 230.0)
	var line_height: float = 18.0
	var font := ThemeDB.fallback_font

	var title_text := (
		"PLAYER DEATH CLEANUP: PASS"
		if all_clear
		else "PLAYER DEATH CLEANUP: CHECK"
	)
	var title_color := Color(0.3, 1.0, 0.45) if all_clear else Color(1.0, 0.3, 0.25)

	draw_string(
		font,
		info_position,
		title_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		title_color
	)

	var checks: Array[Dictionary] = [
		{
			"label": "Action / Combo",
			"passed": (
				not bool(debug_data.get("action_running", true))
				and not bool(debug_data.get("combo_running", true))
				and not bool(debug_data.get("combo_input_buffered", true))
				and not bool(debug_data.get("pending_combo", true))
			)
		},
		{
			"label": "HitInstances: %d active" % int(debug_data.get("active_hit_instances", -1)),
			"passed": int(debug_data.get("active_hit_instances", -1)) == 0
		},
		{
			"label": "Movement / Track",
			"passed": not bool(debug_data.get("movement_active", true))
		},
		{
			"label": "Collision Mask restored",
			"passed": bool(debug_data.get("collision_mask_restored", false))
		},
		{
			"label": "Input buffers",
			"passed": bool(debug_data.get("input_buffers_clear", false))
		},
		{
			"label": "Duck / Landing / Stabilization",
			"passed": (
				bool(debug_data.get("duck_and_landing_clear", false))
				and not bool(debug_data.get("stabilization_active", true))
			)
		},
		{
			"label": "Debug timeline",
			"passed": bool(debug_data.get("debug_timeline_clear", false))
		},
	]

	for index in range(checks.size()):
		var check: Dictionary = checks[index]
		var passed: bool = bool(check["passed"])
		draw_string(
			font,
			info_position + Vector2(0.0, line_height * float(index + 1)),
			("%s: %s" % [
				check["label"],
				"PASS" if passed else "FAIL"
			]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.35, 1.0, 0.5) if passed else Color(1.0, 0.3, 0.25)
		)

	var collision_mask_layers: Array = debug_data.get(
		"collision_mask_layers",
		[]
	)
	var layer_labels: Array[String] = []
	for layer in collision_mask_layers:
		layer_labels.append(str(layer))
	var mask_layers_text: String = (
		", ".join(layer_labels)
		if not layer_labels.is_empty()
		else "None"
	)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 9.0),
		"Collision Mask Layers: " + mask_layers_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(0.5, 0.85, 1.0)
	)

	var death_velocity: Vector2 = debug_data.get(
		"death_velocity",
		Vector2.ZERO
	)
	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 10.0),
		"Death Velocity: (%.1f, %.1f)" % [
			death_velocity.x,
			death_velocity.y
		],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(0.8, 0.8, 0.8)
	)


# ==================================================
# Movement Debug
# ==================================================


func _draw_movement_info() -> void:
	if not show_movement_info:
		return

	if executor == null:
		return

	var debug_data: Dictionary = executor.get_debug_data()
	var runtime_data: Dictionary = debug_data.get("runtime_data", {})

	var movement_debug: Dictionary = runtime_data.get(
		"movement_debug",
		{}
	)

	var movement_controller := player.get("movement_controller") as PlayerMovementController
	var movement_track_active: bool = (
		movement_controller != null
		and movement_controller.is_movement_track_active()
	)

	if movement_debug.is_empty() and not movement_track_active:
		return

	var info_position := Vector2(20.0, 350.0)
	var line_height := 20.0
	var font := ThemeDB.fallback_font
	var font_size := 14

	var movement_mode: String = str(
		movement_debug.get("movement_mode", "UNKNOWN")
	)
	if movement_track_active:
		movement_mode = "MOVEMENT_TRACK"

	var stabilization: bool = movement_debug.get(
		"stabilization_enabled",
		false
	)

	var override_enabled: bool = movement_debug.get(
		"velocity_override_enabled",
		false
	)
	if movement_track_active:
		override_enabled = false

	var override_active: bool = movement_debug.get(
		"velocity_override_active",
		false
	)

	var override_finished: bool = movement_debug.get(
		"velocity_override_finished",
		false
	)

	var suppress_gravity: bool = movement_override_gravity_debug()

	draw_string(
		font,
		info_position,
		"Movement Debug",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(0.4, 0.85, 1.0)
	)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height),
		"Mode: " + movement_mode,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 2.0),
		"Stabilization: " + ("ON" if stabilization else "OFF"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.GREEN if stabilization else Color.GRAY
	)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 3.0),
		"Velocity Override: " + (
			"ACTIVE" if override_active
			else "FINISHED" if override_finished
			else "WAITING" if override_enabled
			else "OFF"
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.ORANGE if override_active else Color.GRAY
	)

	if movement_track_active:
		var track_request: Dictionary = movement_controller.get_active_movement_request()
		var duration: float = float(track_request.get("movement_track_duration", 0.0))
		var strategy: String = "IGNORE_WORLD" if int(track_request.get("movement_track_collision_strategy", 0)) == 1 else "BLOCK"
		var current_mask: int = player.collision_mask

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 4.0),
			"Track: %.1f%%  |  %.3fs / %.3fs" % [
				movement_controller.movement_track_progress * 100.0,
				movement_controller.movement_phase_elapsed,
				duration
			],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.5, 1.0, 0.75)
		)

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 5.0),
			"Collision: %s  |  Mask: %d" % [strategy, current_mask],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.9, 0.85, 0.55)
		)

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 6.0),
			"Track Offset: %s" % str(movement_controller.movement_track_displacement),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.7, 0.85, 1.0)
		)

	if override_enabled:
		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 4.0),
			"Gravity Suppressed: " + (
				"YES" if suppress_gravity else "NO"
			),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color.ORANGE if suppress_gravity else Color.GRAY
		)

		# 实时速度
		var current_velocity: Vector2 = player.velocity

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 5.0),
			"Velocity X: %.1f" % current_velocity.x,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color.WHITE
		)

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 6.0),
			"Velocity Y: %.1f" % current_velocity.y,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color.WHITE
		)

		draw_string(
			font,
			info_position + Vector2(0.0, line_height * 7.0),
			"Velocity Magnitude: %.1f" % current_velocity.length(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.4, 0.85, 1.0)
		)


func movement_override_gravity_debug() -> bool:
	if player == null:
		return false

	var controller: PlayerMovementController = player.get("movement_controller")

	if controller == null:
		return false

	return controller.movement_suppress_gravity

func _draw_pending_combo_info() -> void:
	if combo_executor == null:
		return

	var debug_data: Dictionary = combo_executor.get_debug_data()

	var has_pending: bool = debug_data.get(
		"pending_combo",
		false
	)

	var pending_name: String = str(
		debug_data.get("pending_combo_name", "")
	)

	var info_position := Vector2(size.x - 260.0, 35.0)

	var state_text := "Pending Combo: YES" if has_pending else "Pending Combo: NO"

	var state_color := Color(0.3, 1.0, 0.5) if has_pending else Color(0.7, 0.7, 0.7)

	draw_string(
		ThemeDB.fallback_font,
		info_position,
		state_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		state_color
	)

	draw_string(
		ThemeDB.fallback_font,
		info_position + Vector2(0.0, 22.0),
		"Pending Name: " + (pending_name if has_pending else "-"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color.WHITE
	)


# ==================================================
# 伤害数字
# ==================================================

func _on_debug_damage_number(
	world_position: Vector2,
	amount: float
) -> void:
	var number_label := Label.new()

	number_label.text = str(int(amount))
	number_label.add_theme_font_size_override("font_size", 22)
	number_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.85, 0.25)
	)
	number_label.add_theme_color_override(
		"font_shadow_color",
		Color.BLACK
	)
	number_label.add_theme_constant_override("shadow_offset_x", 2)
	number_label.add_theme_constant_override("shadow_offset_y", 2)

	add_child(number_label)

	number_label.position = _world_to_screen(world_position)
	number_label.position.x -= 10.0

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		number_label,
		"position:y",
		number_label.position.y - 45.0,
		0.55
	)

	tween.tween_property(
		number_label,
		"modulate:a",
		0.0,
		0.55
	)

	tween.chain().tween_callback(number_label.queue_free)

# ==================================================
# 能量调试显示
# ==================================================

func _draw_energy() -> void:
	if not show_energy or player == null:
		return

	# 从 Player1 获取能量数据
	var current_energy: float = float(
		player.get("debug_energy_current")
	)

	var max_energy: float = float(
		player.get("debug_energy_max")
	)

	# 防止最大能量为 0 时发生除零
	if max_energy <= 0.0:
		return

	# 计算能量比例
	var energy_ratio: float = clampf(
		current_energy / max_energy,
		0.0,
		1.0
	)

	var bar_position := Vector2(20.0, 100.0)
	var bar_size := Vector2(220.0, 12.0)

	# 能量文字
	draw_string(
		ThemeDB.fallback_font,
		Vector2(20.0, 92.0),
		"Energy: %.0f / %.0f" % [
			current_energy,
			max_energy
		],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color.WHITE
	)

	# 能量条背景
	draw_rect(
		Rect2(bar_position, bar_size),
		Color(0.15, 0.15, 0.18, 0.9),
		true
	)

	# 当前能量
	draw_rect(
		Rect2(
			bar_position,
			Vector2(bar_size.x * energy_ratio, bar_size.y)
		),
		Color(0.2, 0.65, 1.0),
		true
	)

	# 能量条边框
	draw_rect(
		Rect2(bar_position, bar_size),
		Color(0.8, 0.8, 0.85),
		false,
		1.0
	)


# ==================================================
# Enemy AI 调试信息
# ==================================================

func _draw_enemy_ai_info() -> void:
	if enemy_ai_controller == null:
		return

	var debug_data: Dictionary = enemy_ai_controller.get_debug_data()

	var info_position := Vector2(20.0, 175.0)
	var line_height := 22.0

	var font := ThemeDB.fallback_font
	var font_size := 15

	# AI 模式
	draw_string(
		font,
		info_position,
		"Enemy AI: " + str(debug_data.get("mode", "UNKNOWN")),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

	# 玩家感知状态
	var detected: bool = debug_data.get("player_detected", false)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height),
		"Player Detected: " + ("YES" if detected else "NO"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.GREEN if detected else Color.GRAY
	)

	# Combo 状态
	var combo_running: bool = debug_data.get("combo_running", false)
	var combo_text := "IDLE"

	if combo_running:
		combo_text = "%d / %d" % [
			debug_data.get("combo_index", 0),
			debug_data.get("combo_total", 0)
		]

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 2.0),
		"Enemy Combo: " + combo_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

	# TimeFreeze 状态
	var time_frozen: bool = debug_data.get("time_frozen", false)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 3.0),
		"Enemy TimeFreeze: " + ("ACTIVE" if time_frozen else "INACTIVE"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.ORANGE if time_frozen else Color.GRAY
	)
	# 死亡状态
	var is_dead: bool = debug_data.get("is_dead", false)

	draw_string(
		font,
		info_position + Vector2(0.0, line_height * 4.0),
		"Enemy Dead: " + str(is_dead),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.RED if is_dead else Color.GRAY
	)

	# 攻击冷却
	var cooldown: float = debug_data.get("attack_cooldown", 0.0)
	var cooldown_max: float = debug_data.get("attack_cooldown_max", 0.0)

	var cooldown_ratio := 0.0

	if cooldown_max > 0.0:
		cooldown_ratio = clampf(cooldown / cooldown_max, 0.0, 1.0)

	var bar_position := info_position + Vector2(0.0, line_height * 5.0)
	var bar_size := Vector2(180.0, 10.0)

	draw_string(
		font,
		bar_position,
		"Attack Cooldown: %.2f / %.2f s" % [
			cooldown,
			cooldown_max
		],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

	bar_position.y += 8.0

	draw_rect(
		Rect2(bar_position, bar_size),
		Color(0.2, 0.2, 0.2, 0.9),
		true
	)

	draw_rect(
		Rect2(
			bar_position,
			Vector2(bar_size.x * cooldown_ratio, bar_size.y)
		),
		Color(0.25, 0.65, 1.0),
		true
	)

# ==================================================
# Enemy 攻击时间轴
# ==================================================

func _draw_enemy_timeline() -> void:
	if enemy_executor == null:
		return

	var start_x: float = (size.x - timeline_width) * 0.5
	var bar_y: float = 195.0
	var text_y: float = 175.0

	var font := ThemeDB.fallback_font

	# 没有正在执行的动作
	if not enemy_executor.is_action_running():
		draw_string(
			font,
			Vector2(start_x, text_y),
			"Enemy：待机",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color.WHITE
		)
		return

	var context: CombatActionContext = enemy_executor.current_context

	if context == null or context.action_data == null:
		return

	var action_data: CombatActionData = context.action_data

	var startup: float = action_data.startup
	var active: float = action_data.active
	var recovery: float = action_data.recovery

	var total: float = startup + active + recovery

	if total <= 0.0:
		return

	var elapsed: float = context.elapsed_time

	var action_name: String = action_data.action_name
	var phase_name: String = str(context.current_phase)

	# 标题
	draw_string(
		font,
		Vector2(start_x, text_y),
		"Enemy：" + action_name + "  |  " + phase_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color(1.0, 0.75, 0.4)
	)

	var startup_width: float = timeline_width * startup / total
	var active_width: float = timeline_width * active / total
	var recovery_width: float = timeline_width * recovery / total

	# Startup
	draw_rect(
		Rect2(start_x, bar_y, startup_width, 14.0),
		Color(0.95, 0.72, 0.20)
	)

	# Active
	draw_rect(
		Rect2(start_x + startup_width, bar_y, active_width, 14.0),
		Color(0.95, 0.25, 0.25)
	)

	# Recovery
	draw_rect(
		Rect2(
			start_x + startup_width + active_width,
			bar_y,
			recovery_width,
			14.0
		),
		Color(0.25, 0.55, 0.95)
	)

	# 当前时间游标
	var progress: float = clampf(elapsed / total, 0.0, 1.0)
	var cursor_x: float = start_x + timeline_width * progress

	draw_line(
		Vector2(cursor_x, bar_y - 5.0),
		Vector2(cursor_x, bar_y + 19.0),
		Color.WHITE,
		2.0
	)

# ==================================================
# Enemy 打断事件
# ==================================================


func _on_target_interrupted(
	target: Node,
	_attacker: Node,
	action_progress: float,
	_phase_name: String
) -> void:
	if target != enemy:
		return

	var progress: float = clampf(
		action_progress,
		0.0,
		1.0
	)

	var start_x: float = (size.x - timeline_width) * 0.5
	var cursor_x: float = start_x + timeline_width * progress

	enemy_interrupt_position = Vector2(
		cursor_x,
		195.0
	)

	enemy_interrupt_flash_timer = enemy_interrupt_flash_duration

	queue_redraw()

# ==================================================
# Dash 充能显示
# ==================================================

func _draw_dash_charges() -> void:

	
	if not show_dash_charges or player == null:
		return

	var movement_controller := player.get(
		"movement_controller"
	) as PlayerMovementController

	if movement_controller == null:
		return

	var max_charges: int = movement_controller.dash_max_charges
	var current_charges: int = movement_controller.dash_charges
	var recharge_timers: Array = movement_controller.dash_recharge_timers
	var recharge_time: float = movement_controller.dash_recharge_time

	if max_charges <= 0:
		return

	var font := ThemeDB.fallback_font

	var radius: float = 10.0
	var spacing: float = 30.0
	var right_margin: float = 34.0
	var bottom_margin: float = 38.0

	var center_y: float = size.y - bottom_margin
	
	# DASH 文字放在充能格左侧。
	var label_x: float = (
		size.x
		- right_margin
		- (max_charges - 1) * spacing
		- 65.0
	)

	draw_string(
		font,
		Vector2(label_x, center_y + 5.0),
		"DASH",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color.WHITE
	)

	for i in range(max_charges):
		var center_x: float = (
			size.x
			- right_margin
			- (max_charges - 1 - i) * spacing
		)

		var center := Vector2(center_x, center_y)

		# 充能格背景。
		draw_circle(
			center,
			radius,
			Color(0.12, 0.14, 0.18, 0.9)
		)

		# 充能格边框。
		draw_arc(
			center,
			radius,
			0.0,
			TAU,
			32,
			Color(0.65, 0.7, 0.78, 0.9),
			2.0
		)

		if i < current_charges:
			# 已充能：完整点亮。
			draw_circle(
				center,
				radius - 3.0,
				Color(0.25, 0.85, 1.0)
			)

		else:
			# 未充能：显示恢复进度。
			var timer_index: int = i - current_charges

			if timer_index >= 0 and timer_index < recharge_timers.size():
				if recharge_time > 0.0:
					var remaining_time: float = recharge_timers[timer_index]

					var progress: float = clampf(
						1.0 - remaining_time / recharge_time,
						0.0,
						1.0
					)

					if progress > 0.0:
						draw_arc(
							center,
							radius - 2.0,
							-PI * 0.5,
							-PI * 0.5 + TAU * progress,
							32,
							Color(0.25, 0.85, 1.0),
							3.0
						)




# ==================================================
# Player 死亡测试快捷键
# ==================================================

func _draw_death_test_controls() -> void:
	if not OS.is_debug_build():
		return

	draw_string(
		ThemeDB.fallback_font,
		Vector2(20.0, 30.0),
		"Debug 输入映射：debug_player_massive_damage（大量伤害）  |  debug_player_die（直接死亡）",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.85, 0.85, 0.85, 0.9)
	)
