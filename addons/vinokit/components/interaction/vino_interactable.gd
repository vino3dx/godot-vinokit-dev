class_name VinoInteractable
extends Area3D
## 3D 场景里"可被鼠标点击/悬停"的通用对象，靠碰撞体做拾取（需要一个 CollisionShape3D 子节点）。
## 挂上这个脚本后，配合一台开启 input_ray_pickable 的 Camera3D 即可直接收到点击/悬停信号，
## 不需要在业务代码里自己写 raycast。

signal hovered ## 鼠标移入
signal unhovered ## 鼠标移出
signal clicked(event: InputEventMouseButton) ## 鼠标在其上按下

@export var highlight_on_hover: bool = true ## 是否在悬停时自动放大（简单反馈，复杂效果建议自己接 hovered/unhovered 信号）
@export_range(1.0, 1.5) var hover_scale: float = 1.05 ## 悬停时的缩放系数

var _base_scale: Vector3
var _is_hovered: bool = false


func _ready() -> void:
	input_ray_pickable = true
	_base_scale = scale
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func _on_mouse_entered() -> void:
	_is_hovered = true
	hovered.emit()
	if highlight_on_hover:
		_animate_scale(_base_scale * hover_scale)

func _on_mouse_exited() -> void:
	_is_hovered = false
	unhovered.emit()
	if highlight_on_hover:
		_animate_scale(_base_scale)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit(event)

func _animate_scale(target_scale: Vector3) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", target_scale, 0.15)
