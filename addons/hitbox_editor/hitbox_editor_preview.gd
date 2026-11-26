@tool
extends Control

const SHAPE_RECTANGLE: int = 0
const SHAPE_CIRCLE: int = 1
const SHAPE_CAPSULE: int = 2
const PREVIEW_SCALE: float = 0.75

var current_resource: Resource
var last_preview_state: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(280.0, 240.0)
	set_process(true)
	last_preview_state = _get_preview_state()
	queue_redraw()


func _process(_delta: float) -> void:
	var preview_state := _get_preview_state()
	if preview_state != last_preview_state:
		last_preview_state = preview_state
		queue_redraw()


func set_resource_data(resource: Resource) -> void:
	current_resource = resource
	last_preview_state = _get_preview_state()
	queue_redraw()


func _get_preview_state() -> Dictionary:
	if current_resource == null:
		return {}

	return {
		"shape_type": current_resource.get("shape_type"),
		"offset": current_resource.get("offset"),
		"rotation_degrees": current_resource.get("rotation_degrees"),
		"rectangle_size": current_resource.get("rectangle_size"),
		"circle_radius": current_resource.get("circle_radius"),
		"capsule_radius": current_resource.get("capsule_radius"),
		"capsule_height": current_resource.get("capsule_height")
	}


func _draw() -> void:
	var center := size * 0.5
	_draw_grid(center)
	_draw_origin(center)

	if current_resource == null:
		_draw_empty_hint(center)
		return

	var shape_type: int = int(current_resource.get("shape_type"))
	var offset: Vector2 = current_resource.get("offset")
	var rotation_degrees: float = float(current_resource.get("rotation_degrees"))
	var shape_position := center + offset * PREVIEW_SCALE
	var rotation_radians := deg_to_rad(rotation_degrees)

	_draw_hitbox(shape_type, shape_position, rotation_radians)


func _draw_grid(center: Vector2) -> void:
	var grid_color := Color(0.35, 0.38, 0.43, 0.35)
	var step: float = 40.0
	var x: float = fposmod(center.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid_color, 1.0)
		x += step
	var y: float = fposmod(center.y, step)
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid_color, 1.0)
		y += step


func _draw_origin(center: Vector2) -> void:
	var axis_color := Color(0.85, 0.85, 0.85, 0.8)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), axis_color, 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), axis_color, 1.0)
	draw_circle(center, 4.0, Color(1.0, 0.85, 0.25))
	draw_string(ThemeDB.fallback_font, center + Vector2(8.0, -8.0), "Origin", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, axis_color)


func _draw_hitbox(shape_type: int, position: Vector2, rotation: float) -> void:
	var fill_color := Color(1.0, 0.22, 0.18, 0.22)
	var line_color := Color(1.0, 0.35, 0.28, 0.95)
	draw_set_transform(position, rotation, Vector2.ONE * PREVIEW_SCALE)

	match shape_type:
		SHAPE_RECTANGLE:
			var rect_size: Vector2 = current_resource.get("rectangle_size")
			var rect := Rect2(-rect_size * 0.5, rect_size)
			draw_rect(rect, fill_color, true)
			draw_rect(rect, line_color, false, 2.0 / PREVIEW_SCALE)
		SHAPE_CIRCLE:
			var radius: float = float(current_resource.get("circle_radius"))
			draw_circle(Vector2.ZERO, radius, fill_color)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, line_color, 2.0 / PREVIEW_SCALE)
		SHAPE_CAPSULE:
			var radius: float = float(current_resource.get("capsule_radius"))
			var height: float = maxf(float(current_resource.get("capsule_height")), radius * 2.0)
			var half_segment: float = maxf((height - radius * 2.0) * 0.5, 0.0)
			var body_rect := Rect2(Vector2(-radius, -half_segment), Vector2(radius * 2.0, half_segment * 2.0))
			draw_rect(body_rect, fill_color, true)
			draw_circle(Vector2(0.0, -half_segment), radius, fill_color)
			draw_circle(Vector2(0.0, half_segment), radius, fill_color)
			draw_line(Vector2(-radius, -half_segment), Vector2(-radius, half_segment), line_color, 2.0 / PREVIEW_SCALE)
			draw_line(Vector2(radius, -half_segment), Vector2(radius, half_segment), line_color, 2.0 / PREVIEW_SCALE)
			draw_arc(Vector2(0.0, -half_segment), radius, PI, TAU, 32, line_color, 2.0 / PREVIEW_SCALE)
			draw_arc(Vector2(0.0, half_segment), radius, 0.0, PI, 32, line_color, 2.0 / PREVIEW_SCALE)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(position, 3.0, line_color)


func _draw_empty_hint(center: Vector2) -> void:
	var hint := "选择 HitboxData\n以预览形状"
	draw_multiline_string(ThemeDB.fallback_font, center + Vector2(-55.0, 28.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, -1, Color(0.7, 0.7, 0.7))
