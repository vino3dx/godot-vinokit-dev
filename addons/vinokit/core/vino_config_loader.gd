class_name VinoConfigLoader
extends Node
## VinoConfigLoader - 全局配置文件加载器（独立无依赖版）
##
## 建议 Autoload 挂载名称：VinoConfig
## 1. 任意位置获取配置：VinoConfig.get_value("Section", "Key", default)
## 2. 自动注入属性到节点：VinoConfig.bind(self)
## 3. 可选传入注入完成后的回调函数；若未指定则自动查找节点上的 _apply_config() 方法

signal config_loaded

var config_file_path: String = "config.ini"
var debug_print: bool = true
var is_loaded: bool = false

var _config := ConfigFile.new()


## 生命周期初始化
func _ready() -> void:
	_load()


## 加载并解析配置文件
func _load() -> void:
	_config = ConfigFile.new()
	is_loaded = false
	var real_path := resolve_path(config_file_path)
	if not FileAccess.file_exists(real_path):
		push_warning("[VinoConfigLoader] 未找到配置文件: " + real_path)
		return
	var file := FileAccess.open(real_path, FileAccess.READ)
	if not file:
		push_error("[VinoConfigLoader] 无法打开配置文件: " + real_path)
		return
	var raw := file.get_as_text().replace("\\", "/")
	file.close()
	var lines := raw.split("\n")
	for i in lines.size():
		lines[i] = _fix_line(lines[i])
	if _config.parse("\n".join(lines)) != OK:
		push_error("[VinoConfigLoader] 解析失败，请检查 config.ini 格式（需 UTF-8）")
		return
	is_loaded = true
	_log("✅ 配置加载成功，节点小节: " + str(_config.get_sections()))
	config_loaded.emit()


## 通用自适应路径解析：委托给 VinoPathResolver，与插件内其余模块共用同一套规则。
func resolve_path(path: String) -> String:
	return VinoPathResolver.resolve(path)


## 自动绑定并注入配置到节点同名变量
## section_name 为空时，默认匹配当前 node.name
## callback 可选传入注入完成后的回调函数；若未指定则自动查找节点上的 _apply_config() 方法
func bind(node: Node, section_name: String = "", callback: Callable = Callable()) -> void:
	var section := section_name if not section_name.is_empty() else node.name
	if not is_loaded:
		config_loaded.connect(func(): _do_bind(node, section, callback), CONNECT_ONE_SHOT)
		return
	_do_bind(node, section, callback)


## 执行具体的属性注入逻辑，并在完成后自动触发回调或约定方法
func _do_bind(node: Node, section: String, callback: Callable = Callable()) -> void:
	if not is_instance_valid(node) or not has_section(section):
		return
	for key in get_section_keys(section):
		if key in node:
			node.set(key, get_value(section, key))
	if callback.is_valid():
		callback.call()
	elif node.has_method("_apply_config"):
		node.call("_apply_config")


## 获取配置项的值
func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	if not is_loaded:
		return default_value
	return _config.get_value(section, key, default_value)


## 检查是否存在某个小节
func has_section(section: String) -> bool:
	return is_loaded and _config.has_section(section)


## 获取指定小节下的所有键名
func get_section_keys(section: String) -> Array:
	if not is_loaded or not _config.has_section(section):
		return []
	return _config.get_section_keys(section)


## 内部处理：自动给未加引号的字符串补充引号，防止解析报错
func _fix_line(line: String) -> String:
	var stripped := line.strip_edges()
	if stripped.begins_with(";") or stripped.begins_with("#") \
	or stripped.begins_with("[") or stripped == "":
		return line
	var eq_pos := line.find("=")
	if eq_pos == -1:
		return line
	var key := line.substr(0, eq_pos).strip_edges()
	var val := line.substr(eq_pos + 1).strip_edges()
	if val.begins_with('"') or val.begins_with("'") \
	or val == "true" or val == "false" \
	or val.is_valid_float() or val.is_valid_int():
		return line
	if val == "":
		return key + ' = ""'
	return key + ' = "' + val + '"'


## 内部日志打印
func _log(msg: String) -> void:
	if debug_print:
		print("[VinoConfigLoader] ", msg)
