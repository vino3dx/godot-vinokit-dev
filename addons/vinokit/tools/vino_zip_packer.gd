@tool
class_name VinoZipPacker
extends Node

## 内置打包文件夹到 zip 工具

## 日期格式选项枚举
enum DateFormat {
	MMDDhhmm,
	YYYYMMDD,           ## 20260921
	YYYYMMDDhhmm,       ## 202609211020
	YYYY_MM_DD,         ## 2026-09-21
	YYYYMMDD_hhmmss,    ## 20260921_102030
	YYYY_MM_DD_hhmm,    ## 2026_09_21_1020
}

## 源文件夹路径 (Windows 绝对路径，如 "D:/logs")
@export_global_dir var source_dir_path: String = ""

## 导出的 ZIP 保存路径 (Windows 绝对路径，如 "D:/out" 或 "D:/out.zip")
@export var zip_output_path: String = "C:/Users/Administrator/Downloads"

## 是否在导出的 ZIP 文件名末尾追加日期时间后缀
@export var append_date_suffix: bool = true

## 下拉选择日期格式
@export var date_format_type: DateFormat = DateFormat.MMDDhhmm

## 勾选此项一键触发打包
@export_tool_button("一键触发打包")
var pack_action: Callable = Callable(self, "_on_pack_action_pressed")


func _on_pack_action_pressed() -> void:
	pack_to_zip()


## 执行打包的核心函数 (直接操作 Windows 物理系统文件)
func pack_to_zip() -> Error:
	if source_dir_path.is_empty() or zip_output_path.is_empty():
		_log_error("路径配置不能为空！")
		return ERR_INVALID_PARAMETER

	var real_source := _resolve_win_path(source_dir_path)
	var real_output := _resolve_win_path(zip_output_path)
	
	# 1. 解析目标基础路径与文件名
	var output_dir := ""
	var base_filename := ""

	if DirAccess.dir_exists_absolute(real_output): 
		# 若填的是目录，使用源文件夹名作为默认文件名
		output_dir = real_output
		base_filename = real_source.trim_suffix("/").get_file()
	else:
		output_dir = real_output.get_base_dir()
		base_filename = real_output.get_file()
		if base_filename.to_lower().ends_with(".zip"):
			base_filename = base_filename.substr(0, base_filename.length() - 4)

	# 2. 根据开关与枚举选择处理日期后缀
	if append_date_suffix:
		var date_str := _get_enum_datetime(date_format_type)
		if not date_str.is_empty():
			base_filename = "%s_%s" % [base_filename, date_str]

	real_output = output_dir.path_join(base_filename + ".zip")

	# 3. 检查源 Windows 目录是否存在
	if not DirAccess.dir_exists_absolute(real_source):
		_log_error("Windows 源文件夹不存在: " + real_source)
		return ERR_FILE_NOT_FOUND

	# 4. 自动创建输出 ZIP 文件的父级系统目录
	if not DirAccess.dir_exists_absolute(output_dir):
		var make_dir_err := DirAccess.make_dir_recursive_absolute(output_dir)
		if make_dir_err != OK:
			_log_error("创建 Windows 目标目录失败: " + output_dir)
			return make_dir_err

	# 5. 创建 ZIPPacker 实例
	var packer := ZIPPacker.new()
	var err := packer.open(real_output, ZIPPacker.APPEND_CREATE)
	if err != OK:
		_log_error("创建 ZIP 失败，请检查 Windows 权限或路径合法性: " + real_output)
		return err

	# 6. 递归打包 Windows 目录下的所有文件
	err = _add_dir_recursive(packer, real_source, "")
	packer.close()

	if err == OK:
		_log_info("✅ 成功打包至 Windows 系统目录: " + real_output)
	else:
		_log_error("打包未完全成功，错误码: %d" % err)

	return err


## 递归遍历 Windows 系统文件并写入 ZIP
func _add_dir_recursive(packer: ZIPPacker, base_dir: String, current_rel_path: String) -> Error:
	var current_full_path := base_dir.path_join(current_rel_path) if not current_rel_path.is_empty() else base_dir
	
	var dir := DirAccess.open(current_full_path)
	if not dir:
		_log_error("无法打开 Windows 路径: " + current_full_path)
		return FAILED

	dir.list_dir_begin() 
	var file_name := dir.get_next()

	while not file_name.is_empty():
		if file_name == "." or file_name == ".." or file_name.ends_with(".import"):
			file_name = dir.get_next()
			continue

		var rel_path := current_rel_path.path_join(file_name) if not current_rel_path.is_empty() else file_name
		var full_path := base_dir.path_join(rel_path)

		if dir.current_is_dir():
			var sub_err := _add_dir_recursive(packer, base_dir, rel_path)
			if sub_err != OK:
				# 已移除废弃的 dir.list_end()
				return sub_err
		else:
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				var buffer := file.get_buffer(file.get_length())
				file.close()

				packer.start_file(rel_path)
				packer.write_file(buffer)
				packer.close_file()
			else:
				_log_error("读取磁盘文件失败: " + full_path)

		file_name = dir.get_next()

	# 已移除废弃的 dir.list_end()
	return OK


## 根据枚举选项格式化系统时间
func _get_enum_datetime(type: DateFormat) -> String:
	var now := Time.get_datetime_dict_from_system()
	
	match type:
		DateFormat.MMDDhhmm:
			return "%02d%02d%02d%02d" % [now.month, now.day, now.hour, now.minute]
		DateFormat.YYYYMMDD:
			return "%04d%02d%02d" % [now.year, now.month, now.day]
		DateFormat.YYYYMMDDhhmm:
			return "%04d%02d%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute]
		DateFormat.YYYY_MM_DD:
			return "%04d-%02d-%02d" % [now.year, now.month, now.day]
		DateFormat.YYYYMMDD_hhmmss:
			return "%04d%02d%02d_%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
		DateFormat.YYYY_MM_DD_hhmm:
			return "%04d_%02d_%02d_%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute]
			
	return ""


## Windows 绝对路径清洗
func _resolve_win_path(path: String) -> String:
	var clean := path.replace("\\", "/").strip_edges()
	if clean.begins_with("user://") or clean.begins_with("res://"):
		return ProjectSettings.globalize_path(clean)
	if clean.is_absolute_path():
		return clean
	if is_inside_tree():
		var config := get_node_or_null("/root/VinoConfig")
		if config and config.has_method("resolve_path"):
			return config.resolve_path(clean)
	return clean


func _log_info(msg: String) -> void:
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger and logger.has_method("info"):
			logger.info("VinoZipPacker", msg)
			return
	print("[VinoZipPacker] " + msg)


func _log_error(msg: String) -> void:
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger and logger.has_method("error"):
			logger.error("VinoZipPacker", msg)
			return
	push_error("[VinoZipPacker] " + msg)
