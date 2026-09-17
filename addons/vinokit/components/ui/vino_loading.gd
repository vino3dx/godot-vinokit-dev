class_name VinoLoading
extends Control
## 纯 _draw() 绘制的旋转加载指示器，不依赖任何外部贴图，直接挂到场景里一个 Control 节点上即可使用。
## 用法：添加一个 Control 节点，挂上此脚本，设置好 custom_minimum_size 即可。

@export var line_color: Color = Color.WHITE ## 指示器颜色
@export_range(1.0, 20.0) var line_width: float = 4.0 ## 圆弧线宽
@export_range(0.1, 1.0) var arc_ratio: float = 0.25 ## 圆弧占整圈的比例（越小越像"缺口转圈"）
@export_range(30.0, 1080.0) var degrees_per_second: float = 360.0 ## 转速
@export var auto_start: bool = true ## 是否创建后立即开始转

var _current_deg: float = 0.0
var _running: bool = false


func _ready() -> void:
	if auto_start:
		start()

func start() -> void:
	_running = true
	set_process(true)
	visible = true

func stop() -> void:
	_running = false
	set_process(false)

func _process(delta: float) -> void:
	if not _running:
		return
	_current_deg = fmod(_current_deg + degrees_per_second * delta, 360.0)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := min(size.x, size.y) * 0.5 - line_width
	if radius <= 0.0:
		return
	var start_angle := deg_to_rad(_current_deg)
	var end_angle := start_angle + TAU * arc_ratio
	draw_arc(center, radius, start_angle, end_angle, 32, line_color, line_width, true)
