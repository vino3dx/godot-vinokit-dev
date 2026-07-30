extends Node2D

var points: Array[Vector2]
@onready var polygon_2d: Polygon2D = $Polygon2D

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		points.append(event.position)
	
	
		polygon_2d.polygon = points
