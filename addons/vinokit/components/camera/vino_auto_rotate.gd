class_name VinoAutoRotate
extends Node
## 挂到任意 Node3D（含 Camera3D）上即可让其父节点绕指定轴匀速自转，
## 常配合 VinoOrbitCamera 做"无人操作 N 秒后自动展示旋转"的待机效果。

@export var axis: Vector3 = Vector3.UP ## 旋转轴（局部空间）
@export_range(-360.0, 360.0) var degrees_per_second: float = 15.0 ## 转速，负值表示反方向
@export var auto_start: bool = true ## 是否一进场景就开始转
@export var idle_delay: float = 0.0 ## 大于 0 时：需要先调用 notify_interaction() 累计等待这么久才开始转（待机触发场景用）

var _enabled: bool = false
var _idle_timer: float = 0.0
var _target: Node3D


func _ready() -> void:
	_target = get_parent() as Node3D
	if _target == null:
		VinoLogger.error("VinoAutoRotate", "父节点不是 Node3D，组件不会生效")
		set_process(false)
		return
	_enabled = auto_start and idle_delay <= 0.0
	set_process(true)

## 外部在检测到用户交互（拖拽相机/点击等）时调用，重置待机计时并暂停自转。
func notify_interaction() -> void:
	_idle_timer = 0.0
	_enabled = false

func _process(delta: float) -> void:
	if not _enabled:
		if idle_delay > 0.0:
			_idle_timer += delta
			if _idle_timer >= idle_delay:
				_enabled = true
		return
	_target.rotate(axis.normalized(), deg_to_rad(degrees_per_second) * delta)
