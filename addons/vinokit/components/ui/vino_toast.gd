class_name VinoToast
extends CanvasLayer
## 屏幕角落的浮动提示条，纯代码构建界面，不需要任何 .tscn。
## 用法：场景里放一个空节点挂上此脚本（建议放在最外层，process_mode 设为 Always），
## 然后在任意地方 toast_node.show_message("已保存") 即可；支持多条同时排队显示。

@export var anchor_corner: int = 2 ## 对应 Control.PRESET 的角落编号，默认 2 = 左下角
@export var default_duration: float = 2.0 ## 默认停留时长（秒），不含淡入淡出
@export var fade_duration: float = 0.25 ## 淡入/淡出各自的时长
@export var margin: float = 24.0 ## 距离屏幕边缘的边距

var _container: VBoxContainer


func _ready() -> void:
	layer = 100 # 尽量盖在其他 UI 之上
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_container = VBoxContainer.new()
	_container.set_anchors_preset(anchor_corner as Control.LayoutPreset)
	_container.add_theme_constant_override("separation", 8)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.position -= Vector2(margin, margin) * (1 if anchor_corner in [1, 2, 3] else -1)
	root.add_child(_container)

## 显示一条提示；duration <= 0 时使用 default_duration。
func show_message(text: String, duration: float = -1.0) -> void:
	var use_duration := default_duration if duration <= 0.0 else duration

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.modulate.a = 0.0
	_container.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, fade_duration)
	tween.tween_interval(use_duration)
	tween.tween_property(label, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(label.queue_free)
