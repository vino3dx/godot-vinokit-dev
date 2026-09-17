class_name VinoOrbitCamera
extends Camera3D
## 鼠标拖拽环绕 + 滚轮缩放的展示相机，适合产品展示 / 数字孪生类项目。
## 直接把这个脚本挂到一个 Camera3D 节点上即可，不需要额外的 Pivot 节点。

@export var target_position: Vector3 = Vector3.ZERO ## 环绕的目标点（世界坐标）
@export var distance: float = 5.0 ## 初始距离目标点的半径
@export_range(0.1, 100.0) var min_distance: float = 1.0 ## 滚轮缩放的最近距离
@export_range(0.1, 200.0) var max_distance: float = 20.0 ## 滚轮缩放的最远距离
@export_range(0.01, 1.0) var drag_sensitivity: float = 0.3 ## 拖拽旋转灵敏度
@export_range(0.01, 1.0) var zoom_step: float = 0.1 ## 每次滚轮缩放的比例步长
@export var pitch_limit_deg: float = 85.0 ## 俯仰角上限（防止翻过头顶/地底）
@export var enable_input: bool = true ## 是否响应鼠标输入，做过场动画时可以临时关掉

var _yaw_deg: float = 0.0
var _pitch_deg: float = 20.0
var _dragging: bool = false


func _ready() -> void:
	_update_transform()

## 外部想切换环绕目标时调用（例如从"看整体"切到"看某个部件"），duration > 0 时做补间过渡。
func set_target(new_target: Vector3, duration: float = 0.0) -> void:
	if duration <= 0.0:
		target_position = new_target
		_update_transform()
		return
	var tween := create_tween()
	tween.tween_method(func(p): target_position = p; _update_transform(), target_position, new_target, duration)

func _unhandled_input(event: InputEvent) -> void:
	if not enable_input:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance * (1.0 - zoom_step), min_distance, max_distance)
			_update_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance * (1.0 + zoom_step), min_distance, max_distance)
			_update_transform()

	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw_deg -= motion.relative.x * drag_sensitivity
		_pitch_deg = clampf(_pitch_deg - motion.relative.y * drag_sensitivity, -pitch_limit_deg, pitch_limit_deg)
		_update_transform()

func _update_transform() -> void:
	var yaw_rad := deg_to_rad(_yaw_deg)
	var pitch_rad := deg_to_rad(_pitch_deg)
	var offset := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * distance
	global_position = target_position + offset
	look_at(target_position, Vector3.UP)
