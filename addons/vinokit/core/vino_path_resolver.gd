class_name VinoPathResolver
extends RefCounted
## 统一路径解析工具。
##
## 原插件中 AssetLoader / DataLoader / ConfigLoader 三处各自重复实现了一遍
## “编辑器内按 res:// 处理，导出后优先匹配 exe 同级目录外部文件”的逻辑，
## 现收敛到这一处，其余模块只调用 resolve() / resolve_via()。
##
## 规则：
## 1. 绝对路径：原样返回
## 2. 编辑器运行：统一按 res:// 处理
## 3. 导出运行：优先匹配 exe 同级目录下的外部文件，不存在则回退到包内 res://

static func resolve(path: String) -> String:
	if path.is_empty() or path.is_absolute_path():
		return path

	if OS.has_feature("editor"):
		return path if path.begins_with("res://") else "res://".path_join(path)

	var exe_dir := OS.get_executable_path().get_base_dir()
	var external_path := exe_dir.path_join(path.replace("res://", ""))
	if FileAccess.file_exists(external_path):
		return external_path

	return path if path.begins_with("res://") else "res://".path_join(path)

## 若传入的 config_node 是可用的 VinoConfigLoader（或兼容对象），优先委托给它的
## resolve_path()，以尊重用户在配置文件里自定义的寻址策略；否则退回本地默认规则。
static func resolve_via(path: String, config_node: Object) -> String:
	if config_node and config_node.has_method("resolve_path"):
		return config_node.resolve_path(path)
	return resolve(path)
