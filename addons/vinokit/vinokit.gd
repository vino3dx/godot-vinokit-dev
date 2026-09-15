@tool
extends EditorPlugin
## VinoKit 插件入口：仅负责注册/卸载核心模块的 Autoload 单例。
## 非核心模块（network / ui / tools / modules 下的节点脚本）无需 Autoload，
## 按需挂载到场景节点上，或用 class_name 直接 new() 使用即可。

const AUTOLOADS := {
	"VinoConfig": "res://addons/vinokit/core/vino_config_loader.gd",
	"VinoAssets": "res://addons/vinokit/core/vino_asset_loader.gd",
	"VinoData": "res://addons/vinokit/core/vino_data_loader.gd",
	"VinoWindow": "res://addons/vinokit/core/vino_window_controller.gd",
}

func _enter_tree() -> void:
	for singleton_name: String in AUTOLOADS:
		if not ProjectSettings.has_setting("autoload/" + singleton_name):
			add_autoload_singleton(singleton_name, AUTOLOADS[singleton_name])

	var joined := "、".join(AUTOLOADS.keys().map(func(n): return "[%s]" % n))
	print("【VinoKit】核心模块已加载: %s" % joined)

func _exit_tree() -> void:
	for singleton_name: String in AUTOLOADS:
		remove_autoload_singleton(singleton_name)
	print("【VinoKit】核心模块已卸载")
