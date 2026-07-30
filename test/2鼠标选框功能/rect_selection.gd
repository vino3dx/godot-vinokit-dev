extends Node2D

@onready var line_2d: Line2D = $Line2D
@onready var polygon_2d: Polygon2D = $Polygon2D

var is_drawing: bool = false
var start_pos: Vector2 = Vector2.ZERO
var current_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	_update_selection_visual(Vector2.ZERO, Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_drawing = true
			start_pos = to_local(event.position)
			current_pos = start_pos # current_pos = to_local(event.position)
		else:
			if is_drawing:
				is_drawing = false
				_update_selection_visual(Vector2.ZERO, Vector2.ZERO)
	
	if event is InputEventMouseMotion and is_drawing:
		current_pos = to_local(event.position)
		_update_selection_visual(start_pos, current_pos)


func _update_selection_visual(p_start: Vector2, p_end: Vector2):
	if not is_drawing and start_pos == current_pos:
		line_2d.points = []
		polygon_2d.polygon = PackedVector2Array()
		return
		
	var p1 = p_start
	var p2 = Vector2(p_end.x, p_start.y)
	var p3 = p_end
	var p4 = Vector2(p_start.x, p_end.y)
	
	line_2d.points = [p1, p2, p3, p4]
	polygon_2d.polygon = PackedVector2Array([p1, p2, p3, p4])
	
