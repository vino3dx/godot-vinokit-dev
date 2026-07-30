class_name VinoConfigLoader
extends Node
## [b]VinoConfigLoader - 全局配置文件加载器[/b]
##
## 建议 Autoload 挂载名称：[b]VinoConfig[/b]
## 可以在任意地方直接使用 VinoConfig.get_value("Section", "Key", default)

signal config_loaded

@export_file("*.ini") var config_file_path: String = "data/config.ini"
@export var debug_print: bool = true

var _config := ConfigFile.new()
var is_loaded: bool = false
var exe_dir: String = ""

# ==============================
# 生命周期
# ==============================
func _ready() -> void:
	if OS.has_feature("editor"):
		exe_dir = "res://"
	else:
		exe_dir = OS.get_executable_path().get_base_dir()
		
	_load()

func _load() -> void:
	_config = ConfigFile.new()
	is_loaded = false

	var real_path := resolve_path(config_file_path)

	if not FileAccess.file_exists(real_path):
		push_error("[VinoConfigLoader] 未找到配置文件: " + real_path)
		return

	var file := FileAccess.open(real_path, FileAccess.READ)
	if not file:
		push_error("[VinoConfigLoader] 无法打开配置文件: " + real_path)
		return

	var raw := file.get_as_text().replace("\\", "/")
	file.close()

	# 逐行自动补引号预处理 [cite: 8]
	var lines := raw.split("\n")
	var fixed: PackedStringArray = []
	for line in lines:
		fixed.append(_fix_line(line))
	raw = "\n".join(fixed)

	if _config.parse(raw) != OK:
		push_error("[VinoConfigLoader] 解析失败，请检查 config.ini 格式（需 UTF-8）")
		return

	is_loaded = true
	_log("✅ 配置加载成功，节点小节: " + str(_config.get_sections()))
	config_loaded.emit()

# ==============================
# 通用自适应路径解析（框架核心方法）
# ==============================
func resolve_path(path: String) -> String:
	if path.is_empty():
		return ""
	# 1. 绝对路径直接返回
	if path.is_absolute_path():
		return path
		
	# 2. 编辑器模式下
	if OS.has_feature("editor"):
		if not path.begins_with("res://"):
			return "res://".path_join(path)
		return path
	else:
		# 3. 打包导出后：优先匹配 exe 同目录外部文件
		var external_path := exe_dir.path_join(path.replace("res://", ""))
		if FileAccess.file_exists(external_path):
			return external_path
		# 4. 外部不存在，回退到包内 res://
		if not path.begins_with("res://"):
			return "res://".path_join(path)
		return path

# ==============================
# 对外查询接口
# ==============================
func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	if not is_loaded:
		return default_value
	return _config.get_value(section, key, default_value)

func has_section(section: String) -> bool:
	return is_loaded and _config.has_section(section)

func get_section_keys(section: String) -> Array:
	if not is_loaded or not _config.has_section(section):
		return []
	return _config.get_section_keys(section)

# ==============================
# 内部工具
# ==============================
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
	if val.begins_with('"') or val.begins_with("'"):
		return line
	if val == "true" or val == "false":
		return line
	if val.is_valid_float() or val.is_valid_int():
		return line
	if val == "":
		return key + ' = ""'
	return key + ' = "' + val + '"'

func _log(msg: String) -> void:
	if debug_print:
		print("[VinoConfigLoader] ", msg)
