@tool
extends Control

const LICENSE_CONFIG_PATH := "res://addons/license_manager/license_config.cfg"

var checkbox: CheckBox
var status_label: Label


func _ready() -> void:
	name = "授权"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "License Manager 模块控制"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	checkbox = CheckBox.new()
	checkbox.text = "启用授权验证 (License)"
	checkbox.toggled.connect(_on_toggled)
	vbox.add_child(checkbox)

	status_label = Label.new()
	vbox.add_child(status_label)

	_refresh()


func _on_toggled(pressed: bool) -> void:
	var config := ConfigFile.new()
	# 加载已有配置，保留其他可能的配置项
	config.load(LICENSE_CONFIG_PATH)
	config.set_value("license", "enabled", pressed)
	
	# 保存配置到文件
	var err = config.save(LICENSE_CONFIG_PATH)
	if err != OK:
		push_error("【LSM】保存配置文件失败: ", err)
		
	_refresh()


func _refresh() -> void:
	var config := ConfigFile.new()
	var err := config.load(LICENSE_CONFIG_PATH)
	var enabled: bool = true

	if err == OK:
		enabled = config.get_value("license", "enabled", true)
	else:
		# 首次初始化配置文件
		config.set_value("license", "enabled", true)
		config.save(LICENSE_CONFIG_PATH)

	checkbox.set_pressed_no_signal(enabled)

	if enabled:
		status_label.text = "● 当前状态: 已启用"
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		status_label.text = "● 当前状态: 已关闭"
		status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
