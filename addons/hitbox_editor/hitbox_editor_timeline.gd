@tool
extends Control

signal hit_instance_selected(instance: HitInstanceData)

const LEFT := 86.0
const TOP := 24.0
const SCALE := 180.0
var action_data: CombatActionData
var selected_instance: HitInstanceData

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func set_action_data(value: CombatActionData) -> void:
	action_data = value
	selected_instance = null
	queue_redraw()

func set_selected_instance(value: HitInstanceData) -> void:
	selected_instance = value
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12,0.13,0.15), true)
	if action_data == null:
		draw_string(ThemeDB.fallback_font, Vector2(12,28), "No Action selected", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.GRAY)
		return
	var duration := action_data.active
	draw_string(ThemeDB.fallback_font, Vector2(LEFT,15), "ACTIVE  %.2f s" % duration, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65,0.8,0.9))
	for tick in range(ceili(duration / 0.1) + 1):
		var x := LEFT + float(tick) * 0.1 * SCALE
		draw_line(Vector2(x,TOP), Vector2(x,size.y-6), Color(0.45,0.48,0.52,0.45), 1)
		draw_string(ThemeDB.fallback_font, Vector2(x+2,TOP-4), "%.1f" % (float(tick)*0.1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7,0.72,0.75))
	for i in range(action_data.hit_instances.size()):
		var item: HitInstanceData = action_data.hit_instances[i]
		if item == null: continue
		var y := TOP + 14 + float(i) * 19
		var x1 := LEFT + item.start_time * SCALE
		var x2 := LEFT + item.end_time * SCALE
		var rect := Rect2(Vector2(x1,y), Vector2(maxf(x2-x1,3),12))
		var chosen := item == selected_instance
		draw_rect(rect, Color(1,0.48,0.2,0.95 if chosen else 0.62), true)
		draw_rect(rect, Color(1,0.82,0.55,1 if chosen else 0.5), false, 1)
		draw_string(ThemeDB.fallback_font, Vector2(8,y+10), "Hit %02d" % (i+1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82,0.84,0.88))

func _gui_input(event: InputEvent) -> void:
	if action_data == null or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var index := int(floor((event.position.y - TOP - 14) / 19))
	if index >= 0 and index < action_data.hit_instances.size():
		var item := action_data.hit_instances[index]
		if item != null:
			selected_instance = item
			hit_instance_selected.emit(item)
			queue_redraw()
			accept_event()
