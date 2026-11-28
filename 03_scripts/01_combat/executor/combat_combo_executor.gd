
extends Node
class_name CombatComboExecutor


signal combo_started(combo_data: CombatComboData)
signal combo_action_started(action_index: int, context: CombatActionContext)
signal combo_finished(was_cancelled: bool)
signal combo_debug_updated(debug_data: Dictionary)


# ==================================================
# 连击配置
# ==================================================

@export_group("连击配置")
@export var combo_data: CombatComboData

var current_combo_data: CombatComboData = null

var actor: Node2D = null
var action_executor: CombatActionExecutor = null

var is_combo_running: bool = false
var current_action_index: int = -1

var combo_window_timer: float = 0.0
var combo_window_open: bool = false

var combo_input_buffered: bool = false
var combo_input_request: CombatActionRequest = null


# ==================================================
# 普通取消输入缓存
# ==================================================

var pending_combo_request: CombatActionRequest = null


func _ready() -> void:
	actor = get_parent() as Node2D

	if actor == null:
		push_error("ComboExecutor：没有找到所属角色")
		return

	action_executor = actor.get_node_or_null(
		"CombatActionExecutor"
	) as CombatActionExecutor

	if action_executor == null:
		push_error("ComboExecutor：没有找到 CombatActionExecutor")
		return

	action_executor.action_finished.connect(
		_on_action_finished
	)

	action_executor.action_phase_changed.connect(
		_on_action_phase_changed
	)


func _get_actor_input_direction() -> Vector2:
	if not ("move_input_vector" in actor):
		return Vector2.ZERO

	var value: Variant = actor.get("move_input_vector")

	if value is Vector2:
		return value

	return Vector2.ZERO


# ==================================================
# 统一 Action Request 入口
# ==================================================

func submit_request(request: CombatActionRequest) -> bool:

	if request == null:
		return false

	if action_executor == null or actor == null:
		return false

	# 在请求进入系统时捕获方向。
	# 后续即使缓存，也不会重新读取角色状态。
	request.capture_actor_state(actor)

	match request.request_type:

		CombatActionRequest.RequestType.CONTINUE_COMBO:
			return request_next_action(request)


		CombatActionRequest.RequestType.START_COMBO:
			return _start_combo_request(request)


		CombatActionRequest.RequestType.START_ACTION:
			if request.action_data == null:
				return false

			return action_executor.start_action(
				request.action_data,
				actor,
				request.facing_direction,
				request.input_direction
			)


		_:
			push_error("ComboExecutor：未知的 Action Request 类型")
			return false


func create_combo_request(
	requested_combo: CombatComboData = null
) -> CombatActionRequest:

	var request := CombatActionRequest.new()

	request.request_type = CombatActionRequest.RequestType.START_COMBO
	request.combo_data = requested_combo

	# 创建请求时就捕获方向。
	request.capture_actor_state(actor)

	return request


# ==================================================
# 启动连击
# ==================================================

# 保留原来的调用方式，避免其他脚本直接调用 start_combo 时失效。
func start_combo(
	requested_combo: CombatComboData = null
) -> bool:

	var request := create_combo_request(requested_combo)

	return _start_combo_request(request)


func _start_combo_request(
	request: CombatActionRequest
) -> bool:

	if request == null:
		return false

	request.capture_actor_state(actor)

	var selected_combo := request.combo_data

	if selected_combo == null:
		selected_combo = combo_data

	if selected_combo == null:
		push_error("ComboExecutor：没有配置 ComboData")
		return false

	if selected_combo.get_action_count() == 0:
		push_error("ComboExecutor：连击没有动作")
		return false

	var first_action := selected_combo.get_action(0)

	# 使用请求中保存的方向快照。
	var success: bool = action_executor.start_action(
		first_action,
		actor,
		request.facing_direction,
		request.input_direction
	)

	if not success:
		# 当前动作不允许立即取消时，
		# 检查是否存在未来可以取消的阶段。
		if _can_buffer_combo(first_action):
			pending_combo_request = request
			_update_debug()
			return true

		return false

	# 新动作成功启动后，清除旧缓存。
	_clear_pending_combo()

	current_combo_data = selected_combo
	is_combo_running = true
	current_action_index = 0

	combo_window_timer = first_action.input_window
	combo_window_open = first_action.input_window > 0.0

	combo_input_buffered = false
	combo_input_request = null

	combo_started.emit(current_combo_data)

	combo_action_started.emit(
		current_action_index,
		action_executor.current_context
	)

	_update_debug()

	return true


# ==================================================
# 判断是否值得缓存新 Combo
# ==================================================

func _can_buffer_combo(
	new_action: CombatActionData
) -> bool:

	if new_action == null:
		return false

	if not action_executor.is_action_running():
		return false

	var current_context := action_executor.current_context
	var current_action := current_context.action_data

	# 当前动作禁止被覆盖。
	if current_action.unoverrideable:
		return false

	# 高优先级动作本来就可以立即覆盖。
	# 如果启动失败，不应该在这里缓存。
	if new_action.action_priority > current_action.action_priority:
		return false

	# 检查能量，但不在这里扣除。
	if new_action.energy_cost > 0.0:
		var energy := actor.get_node_or_null(
			"CombatEnergy"
		) as CombatEnergy

		if energy == null:
			return false

		if not energy.has_enough_energy(new_action.energy_cost):
			return false

	# 只检查当前动作在未来阶段是否允许被取消。
	var phase_order: Array[StringName] = [
		&"startup",
		&"active",
		&"recovery"
	]

	var current_phase_index := phase_order.find(
		current_context.current_phase
	)

	if current_phase_index < 0:
		return false

	for i in range(current_phase_index + 1, phase_order.size()):
		var future_phase := phase_order[i]

		if not current_action.can_be_cancelled_from(future_phase):
			continue

		return true

	return false


# ==================================================
# 处理动作阶段变化
# ==================================================

func _on_action_phase_changed(
	context: CombatActionContext
) -> void:

	if pending_combo_request == null:
		return

	# 忽略已经不是当前动作的上下文。
	if context != action_executor.current_context:
		return

	# 当前动作允许在这个阶段被普通取消。
	if context.action_data.can_be_cancelled_from(
		context.current_phase
	):
		var requested_request := pending_combo_request

		_clear_pending_combo()

		_start_combo_request(requested_request)
		return

	# 如果后续已经没有可以取消的阶段，就清除缓存。
	var pending_combo := pending_combo_request.combo_data

	if pending_combo == null:
		_clear_pending_combo()
		return

	var pending_action := pending_combo.get_action(0)

	if not _can_buffer_combo(pending_action):
		_clear_pending_combo()


# ==================================================
# 清除普通取消缓存
# ==================================================

func _clear_pending_combo() -> void:
	pending_combo_request = null
	_update_debug()


# ==================================================
# 启动 Combo 内部下一段动作
# ==================================================

func _start_action(
	index: int,
	request: CombatActionRequest = null
) -> bool:

	if current_combo_data == null:
		return false

	if not current_combo_data.has_action(index):
		return false

	var action_data := current_combo_data.get_action(index)

	# 如果没有传入请求，创建一个新的连段请求。
	if request == null:
		request = CombatActionRequest.new()
		request.request_type = CombatActionRequest.RequestType.CONTINUE_COMBO
		request.capture_actor_state(actor)
	else:
		request.capture_actor_state(actor)

	# 使用请求中保存的方向快照。
	var success: bool = action_executor.start_action(
		action_data,
		actor,
		request.facing_direction,
		request.input_direction
	)

	if not success:
		return false

	current_action_index = index

	combo_window_timer = action_data.input_window
	combo_window_open = action_data.input_window > 0.0

	combo_input_buffered = false
	combo_input_request = null

	combo_action_started.emit(
		current_action_index,
		action_executor.current_context
	)

	_update_debug()

	return true


# ==================================================
# 请求 Combo 下一段
# ==================================================

func request_next_action(
	request: CombatActionRequest = null
) -> bool:

	if not is_combo_running:
		return false

	if current_combo_data == null:
		return false

	if not combo_window_open:
		return false

	if current_combo_data.is_last_action(current_action_index):
		return false

	# 兼容直接调用 request_next_action 的旧入口。
	if request == null:
		request = CombatActionRequest.new()
		request.request_type = CombatActionRequest.RequestType.CONTINUE_COMBO

	request.capture_actor_state(actor)

	if action_executor.is_action_running():
		var current_action := current_combo_data.get_action(
			current_action_index
		)

		if not current_action.input_buffer_enabled:
			return false

		# 保存完整请求，而不只是记录一个布尔值。
		combo_input_buffered = true
		combo_input_request = request

		_update_debug()
		return true

	var success := _start_action(
		current_action_index + 1,
		request
	)

	if not success:
		_finish_combo(false)

	return success


# ==================================================
# 动作结束回调
# ==================================================

func _on_action_finished(
	_context: CombatActionContext,
	was_cancelled: bool
) -> void:

	# 动作已经结束，不再保留待执行的普通取消请求。
	_clear_pending_combo()

	if not is_combo_running:
		return

	if current_combo_data == null:
		return

	if was_cancelled:
		cancel_combo()
		return

	if combo_input_buffered:
		var buffered_request := combo_input_request

		combo_input_buffered = false
		combo_input_request = null

		if current_action_index < current_combo_data.get_action_count() - 1:
			var success := _start_action(
				current_action_index + 1,
				buffered_request
			)

			if success:
				return

			_finish_combo(false)
			return

	if current_combo_data.is_last_action(current_action_index):
		_finish_combo(false)
		return

	if not combo_window_open:
		_finish_combo(false)


# ==================================================
# 取消 Combo
# ==================================================

func cancel_combo() -> void:

	_clear_pending_combo()

	if not is_combo_running:
		return

	if action_executor.is_action_running():
		action_executor.cancel_action()
		return

	_finish_combo(true)


# 死亡时强制清除 Combo 与所有输入缓存。
# 普通取消负责正常生命周期；这里额外覆盖未运行状态下可能残留的缓存。
func clear_for_death() -> void:
	cancel_combo()

	_clear_pending_combo()

	combo_window_timer = 0.0
	combo_window_open = false

	combo_input_buffered = false
	combo_input_request = null

	current_action_index = -1
	current_combo_data = null

	_update_debug()


func _finish_combo(was_cancelled: bool) -> void:

	is_combo_running = false

	combo_window_timer = 0.0
	combo_window_open = false

	combo_input_buffered = false
	combo_input_request = null

	current_action_index = -1

	_clear_pending_combo()

	combo_finished.emit(was_cancelled)

	current_combo_data = null

	_update_debug()


# ==================================================
# 时间更新
# ==================================================

func _process(delta: float) -> void:

	if not is_combo_running:
		return

	var actor_delta: float = CombatTimeManager.get_actor_delta(
		actor,
		delta
	)

	if combo_window_open:
		combo_window_timer -= actor_delta

		if combo_window_timer <= 0.0:
			combo_window_timer = 0.0
			combo_window_open = false

			if not action_executor.is_action_running():
				if not combo_input_buffered:
					_finish_combo(false)
					return

	_update_debug()


# ==================================================
# Debug
# ==================================================

func get_debug_data() -> Dictionary:

	var debug_combo_data := current_combo_data

	if debug_combo_data == null:
		debug_combo_data = combo_data

	return {
		"combo_running": is_combo_running,
		"combo_name": debug_combo_data.combo_name if debug_combo_data != null else "",
		"combo_index": current_action_index,
		"combo_total": debug_combo_data.get_action_count() if debug_combo_data != null else 0,
		"combo_window_open": combo_window_open,
		"combo_window_timer": combo_window_timer,
		"combo_input_buffered": combo_input_buffered,
		"pending_combo": pending_combo_request != null,
		"pending_combo_name": (
			pending_combo_request.combo_data.combo_name
			if pending_combo_request != null
			and pending_combo_request.combo_data != null
			else ""
		)
	}


func _update_debug() -> void:
	combo_debug_updated.emit(get_debug_data())
