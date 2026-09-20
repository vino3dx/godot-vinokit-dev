@tool
class_name VinoConfigValidator
extends Node
## VinoConfigValidator - VinoKit 配置与场景树合法性检查工具
##
## 在 Godot 编辑器 Inspector 面板中勾选 [trigger_validate] 即可一键执行全盘诊断

## 待校验的 INI 配置文件路径 (支持 res://, user:// 或 Windows 绝对路径)
@export_file("*.ini") var config_file_path: String = "config.ini"

## 检查 INI 中引用的外部文件/图片路径是否在物理磁盘上真实存在
@export var check_external_files_exist: bool = true

## 是否对当前场景树下的节点与 INI 小节 [Section] 进行同名对齐匹配检查
@export var check_scene_nodes_match: bool = true

## Inspector 触发开关 (勾选即运行校验)
@export var trigger_validate: bool = false:
	set(value):
		if value:
			validate_all()
			trigger_validate = false

var _config := ConfigFile.new()
var _error_count := 0
var _warning_count := 0


## 执行全量诊断校验
func validate_all() -> void:
	_error_count = 0
	_warning_count = 0
	
	print("\n==================================================")
	_log_info("🔍 [VinoConfigValidator] 开始执行配置与场景检查...")
	
	var real_config_path := _resolve_system_path(config_file_path)
	
	# 1. 检查 INI 文件是否存在
	if not FileAccess.file_exists(real_config_path):
		_log_error("配置文件不存在: " + real_config_path)
		_print_summary()
		return

	# 2. 尝试读取与语法解析校验
	var file := FileAccess.open(real_config_path, FileAccess.READ)
	if not file:
		_log_error("无法读取配置文件: " + real_config_path)
		_print_summary()
		return

	var raw_text := file.get_as_text().replace("\\", "/")
	file.close()

	# 使用与 VinoConfigLoader 一致的预处理规范
	var lines := raw_text.split("\n")
	for i in lines.size():
		lines[i] = _fix_line(lines[i])

	var parse_err := _config.parse("\n".join(lines))
	if parse_err != OK:
		_log_error("config.ini 语法解析失败 (错误码: %d)，请检查 UTF-8 编码或语法规则！" % parse_err)
		_print_summary()
		return

	_log_info("✅ config.ini 文件解析成功，包含 [%d] 个配置小节" % _config.get_sections().size())

	# 3. 检查小节内部的外部文件路径是否存在
	if check_external_files_exist:
		_validate_file_paths()

	# 4. 检查场景树节点与 INI 小节及变量的对齐情况
	if check_scene_nodes_match:
		var root_node := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if root_node:
			_validate_node_tree(root_node)
		else:
			_log_warn("当前未打开有效场景，跳过场景树节点匹配校验")

	_print_summary()


## 校验所有以 path / file / tex / img / bg 结尾的配置路径值是否指向真实文件
func _validate_file_paths() -> void:
	for section in _config.get_sections():
		for key in _config.get_section_keys(section):
			var val = _config.get_value(section, key)
			if val is String and not val.is_empty():
				# 当 Key 包含路径关键字，或者 Val 看起来像文件后缀时进行诊断
				var is_path_key := key.contains("path") or key.contains("file") or key.contains("tex") or key.contains("img") or key.contains("bg")
				var has_extension: bool = val.get_extension() != ""
				
				if is_path_key or has_extension:
					var target_path := _resolve_system_path(val)
					if not FileAccess.file_exists(target_path) and not DirAccess.dir_exists_absolute(target_path):
						_log_warn("小节 [%s] 中的 '%s = %s' 指向的文件或路径不存在！(解析目标: %s)" % [section, key, val, target_path])


## 递归检查场景节点与 INI 配置的绑定对齐情况
func _validate_node_tree(node: Node) -> void:
	if _config.has_section(node.name):
		var keys := _config.get_section_keys(node.name)
		for key in keys:
			if not (key in node):
				_log_warn("小节 [%s] 配置了键 '%s'，但节点 '%s' (%s) 上不存在该变量属性！" % [node.name, key, node.name, node.get_class()])
			else:
				_log_info("  └─ 节点 '%s' 成功匹配键: '%s'" % [node.name, key])

	for child in node.get_children():
		_validate_node_tree(child)


## 修正单行未加引号的字符串（保持与 VinoConfigLoader 解析策略完全一致）
func _fix_line(line: String) -> String:
	var stripped := line.strip_edges()
	if stripped.begins_with(";") or stripped.begins_with("#") or stripped.begins_with("[") or stripped == "":
		return line
	var eq_pos := line.find("=")
	if eq_pos == -1:
		return line
	var key := line.substr(0, eq_pos).strip_edges()
	var val := line.substr(eq_pos + 1).strip_edges()
	if val.begins_with('"') or val.begins_with("'") or val == "true" or val == "false" or val.is_valid_float() or val.is_valid_int():
		return line
	if val == "":
		return key + ' = ""'
	return key + ' = "' + val + '"'


## 路径标准化转义与 VinoPathResolver 解耦兼容
func _resolve_system_path(path: String) -> String:
	var clean := path.replace("\\", "/")
	if clean.begins_with("user://") or clean.begins_with("res://"):
		clean = ProjectSettings.globalize_path(clean)
		
	if is_inside_tree():
		var resolver := get_node_or_null("/root/VinoPathResolver")
		if resolver and resolver.has_method("resolve"):
			return resolver.resolve(clean)
			
	return clean


func _log_info(msg: String) -> void:
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger and logger.has_method("info"):
			logger.info("VinoConfigValidator", msg)
			return
	print("[VinoConfigValidator] " + msg)


func _log_warn(msg: String) -> void:
	_warning_count += 1
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger and logger.has_method("warn"):
			logger.warn("VinoConfigValidator", msg)
			return
	push_warning("[VinoConfigValidator] " + msg)


func _log_error(msg: String) -> void:
	_error_count += 1
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger and logger.has_method("error"):
			logger.error("VinoConfigValidator", msg)
			return
	push_error("[VinoConfigValidator] " + msg)


func _print_summary() -> void:
	print("--------------------------------------------------")
	if _error_count == 0 and _warning_count == 0:
		print("🎉 [VinoConfigValidator] 校验完成：配置与场景 perfect！未发现任何错误或隐患。")
	else:
		print("⚠️ [VinoConfigValidator] 校验完成：发现 %d 个错误，%d 个警告，请按上方提示修正！" % [_error_count, _warning_count])
	print("==================================================\n")
