@tool
extends EditorPlugin

const LICENSE_SINGLETON := "LicenseManager"
const LICENSE_SCRIPT := "res://addons/vinokit/modules/license/license_manager.gd"
const DOCK_SCRIPT := "res://addons/vinokit/dock/vinokit_dock.gd"

var dock: Control


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + LICENSE_SINGLETON):
		add_autoload_singleton(LICENSE_SINGLETON, LICENSE_SCRIPT)

	dock = preload("res://addons/vinokit/dock/vinokit_dock.gd").new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	print("【vinokit】已加载,控制面板已挂载到右侧 Dock")


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
