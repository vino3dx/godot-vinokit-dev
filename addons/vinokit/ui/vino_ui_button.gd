class_name VinoUIButton
extends Button
## 带悬停缩放、按下反馈、可选呼吸动画的按钮

@export_category("悬停 / 按下")
@export var hover_scale := 1.08
@export var press_scale := 0.92
@export var anim_time := 0.12

@export_category("呼吸动画")
@export var breath_enabled := false
@export var breath_scale := 1.05
@export var breath_time := 1.2

var base_scale := Vector2.ONE
var breath_tween: Tween

func _ready() -> void:
	base_scale = scale
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_exit)
	button_down.connect(_on_press)
	button_up.connect(_on_release)

	if breath_enabled:
		start_breath()

func start_breath() -> void:
	if breath_tween:
		breath_tween.kill()

	breath_tween = create_tween().set_loops()
	breath_tween.tween_property(self, "scale", base_scale * breath_scale, breath_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath_tween.tween_property(self, "scale", base_scale, breath_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_breath() -> void:
	if breath_tween:
		breath_tween.kill()
		breath_tween = null
	scale = base_scale

func _on_hover() -> void:
	stop_breath()
	create_tween().tween_property(self, "scale", base_scale * hover_scale, anim_time)

func _on_exit() -> void:
	create_tween().tween_property(self, "scale", base_scale, anim_time)
	if breath_enabled:
		start_breath()

func _on_press() -> void:
	stop_breath()
	create_tween().tween_property(self, "scale", base_scale * press_scale, 0.05)

func _on_release() -> void:
	create_tween().tween_property(self, "scale", base_scale * hover_scale, anim_time)
