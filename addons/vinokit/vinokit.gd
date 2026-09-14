@tool
extends EditorPlugin

# 使用字典配置所有 Autoload 单例名称与对应的路径
const AUTOLOADS: Dictionary = {
	"VinoAssets": "res://addons/vinokit/core/vino_asset_loader.gd",
	"VinoConfig": "res://addons/vinokit/core/vino_config_loader.gd",
	"VinoData": "res://addons/vinokit/core/vino_data_loader.gd",
	"VinoWindow": "res://addons/vinokit/core/vino_window_controller.gd"
}

func _enter_tree() -> void:
	for name: String in AUTOLOADS:
		var script_path: String = AUTOLOADS[name]
		if not ProjectSettings.has_setting("autoload/" + name):
			add_autoload_singleton(name, script_path)
			
	var names_str := "、".join(AUTOLOADS.keys().map(func(k): return "[%s]" % k))
	print("【VinoKit】核心库已加载: %s 服务就绪" % names_str)


func _exit_tree() -> void:
	for name: String in AUTOLOADS:
		remove_autoload_singleton(name)
	
	print("【VinoKit】核心库已经卸载")
