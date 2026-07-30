@tool
extends EditorPlugin

# 全局单例挂载名与脚本路径
const CONFIG_SINGLETON := "VinoConfig"
const CONFIG_SCRIPT := "res://addons/vinokit/core/vino_config_loader.gd"

const ASSET_SINGLETON := "VinoAssets"
const ASSET_SCRIPT := "res://addons/vinokit/core/vino_asset_loader.gd"

const WINDOW_SINGLETON := "VinoWindow"
const WINDOW_SCRIPT := "res://addons/vinokit/core/vino_window_controller.gd"

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + CONFIG_SINGLETON):
		add_autoload_singleton(CONFIG_SINGLETON, CONFIG_SCRIPT)

	if not ProjectSettings.has_setting("autoload/" + ASSET_SINGLETON):
		add_autoload_singleton(ASSET_SINGLETON, ASSET_SCRIPT)
		
	if not ProjectSettings.has_setting("autoload/" + WINDOW_SINGLETON):
		add_autoload_singleton(WINDOW_SINGLETON, WINDOW_SCRIPT)

	print("【VinoKit】核心库已加载：[VinoConfig] 与 [VinoAssets] 服务就绪。")

func _exit_tree() -> void:
	remove_autoload_singleton(CONFIG_SINGLETON)
	remove_autoload_singleton(ASSET_SINGLETON)
	print("【VinoKit】核心库已卸载。")
