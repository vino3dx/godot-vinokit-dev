@tool
class_name VinoZipPacker
extends Node

## 内置打包文件夹到zip工具


## 源文件夹路径 (Windows 绝对路径，如 "D:/logs")
@export_global_dir var source_dir_path: String = ""

## 导出的 ZIP 保存路径 (Windows 绝对路径，如 "D:/out.zip"，直接在输入框里键入)
@export var zip_output_path: String = ""

## 在 Inspector 检查器勾选此项手动触发打包
@export var trigger_pack: bool = false:
	set(value):
		if value:
			pack_to_zip()
			trigger_pack = false


## 执行打包的核心函数 (直接操作 Windows 物理系统文件)
func pack_to_zip() -> Error:
	if source_dir_path.is_empty() or zip_output_path.is_empty():
		_log_error("路径配置不能为空！")
		return ERR_INVALID_PARAMETER

	var real_source := _resolve_win_path(source_dir_path)
	var real_output := _resolve_win_path(zip_output_path)
	
	if DirAccess.dir_exists_absolute(real_output): # 填的是目录 → 用源文件夹名当文件名
		real_output = real_output.path_join(real_source.trim_suffix("/").get_file() + ".zip")
	elif not real_output.to_lower().ends_with(".zip"): # 没后缀则补上
		real_output += ".zip"

	# 1. 检查源 Windows 目录是否存在
	if not DirAccess.dir_exists_absolute(real_source):
		_log_error("Windows 源文件夹不存在: " + real_source)
		return ERR_FILE_NOT_FOUND

	# 2. 自动创建输出 ZIP 文件的父级系统目录 (例如 D:/Backup/2026/ 文件夹)
	var output_dir := real_output.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_dir):
		var make_dir_err := DirAccess.make_dir_recursive_absolute(output_dir)
		if make_dir_err != OK:
			_log_error("创建 Windows 目标目录失败: " + output_dir)
			return make_dir_err

	# 3. 创建 ZIPPacker 实例
	var packer := ZIPPacker.new()
	var err := packer.open(real_output, ZIPPacker.APPEND_CREATE)
	if err != OK:
		_log_error("创建 ZIP 失败，请检查 Windows 权限或路径合法性: " + real_output)
		return err

	# 4. 递归打包 Windows 目录下的所有文件
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
	
	# 打开 Windows 物理绝对路径
	var dir := DirAccess.open(current_full_path)
	if not dir:
		_log_error("无法打开 Windows 路径: " + current_full_path)
		return FAILED

	dir.list_dir_begin() 
	var file_name := dir.get_next()

	while not file_name.is_empty():
		# 过滤系统保留项与 Godot 缓存
		if file_name == "." or file_name == ".." or file_name.ends_with(".import"):
			file_name = dir.get_next()
			continue

		var rel_path := current_rel_path.path_join(file_name) if not current_rel_path.is_empty() else file_name
		var full_path := base_dir.path_join(rel_path)

		if dir.current_is_dir():
			# 递归子目录
			var sub_err := _add_dir_recursive(packer, base_dir, rel_path)
			if sub_err != OK:
				dir.list_end()
				return sub_err
		else:
			# 读取 Windows 磁盘文件内容写入 ZIP
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

	dir.list_end()
	return OK


## Windows 绝对路径清洗（统一斜杠；res:// user:// 转物理路径；已是绝对路径则原样返回）
func _resolve_win_path(path: String) -> String:
	var clean := path.replace("\\", "/").strip_edges()
	if clean.begins_with("user://") or clean.begins_with("res://"):
		return ProjectSettings.globalize_path(clean)
	if clean.is_absolute_path():
		return clean # 已是 C:/ 或 / 开头，不再交给 VinoConfig，避免被转回 res://
	if is_inside_tree(): # 仅相对路径才委托 VinoConfig
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
