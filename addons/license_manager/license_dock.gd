@tool
extends Control

const LICENSE_CONFIG_PATH := "res://addons/license_manager/license_config.cfg"

var checkbox: CheckBox
var status_label: Label


func _ready() -> void:
	name = "授权许可"

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
	config.load(LICENSE_CONFIG_PATH)
	config.set_value("license", "enabled", pressed)
	config.save(LICENSE_CONFIG_PATH)
	_refresh()


func _refresh() -> void:
	var config := ConfigFile.new()
	var err := config.load(LICENSE_CONFIG_PATH)
	var enabled: bool = false

	if err != OK:
		config.set_value("license", "enabled", false)
		config.save(LICENSE_CONFIG_PATH)
	else:
		enabled = config.get_value("license", "enabled", false)

	checkbox.set_pressed_no_signal(enabled)

	if enabled:
		status_label.text = "● 当前状态: 已启用"
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		status_label.text = "● 当前状态: 已关闭"
		status_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
