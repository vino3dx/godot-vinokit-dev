@tool
class_name VinoScreenCapture
extends Node
## VinoScreenCapture：VinoKit 全局快捷截图工具
##
## 功能：异步截取当前 Godot 编辑器主窗口视口的高清图像，并自动保存为带时间戳的 PNG。
##
## 使用方式：由 plugin.gd 的工具箱菜单动态实例化，配置保存目录后调用 capture_screen()，
## 截图完成后通过 capture_finished 信号异步回调，插件再回收本节点，无内存泄漏。
## 保存目录不存在时会自动递归创建，零配置直接可用。

## 截图完成信号：success 为是否成功，saved_path 为实际保存路径（失败时为空串）
signal capture_finished(success: bool, saved_path: String)

## 默认截图保存目录（项目内，保存后可在编辑器文件系统面板直接查看）
const DEFAULT_SAVE_DIR := "res://screenshots"

## 截图保存目录，不存在时自动递归创建
@export_dir var save_dir_path: String = DEFAULT_SAVE_DIR

## 截图文件名前缀（最终文件名形如 capture_20261015_120000.png）
@export var file_prefix: String = "capture"

## 最近一次成功保存的路径（供调用方查询，失败时置空）
var _last_saved_path := ""


## 执行截图：等待当前帧绘制完成后回读视口纹理，保存为 PNG
## 完成后发出 capture_finished(success, saved_path) 信号，并返回错误码
func capture_screen() -> Error:
	# 回读视口纹理前必须等本帧绘制结束，否则可能拿到全黑图像
	await RenderingServer.frame_post_draw

	var image := _grab_viewport_image()
	if image == null:
		_log_error("无法获取视口图像，截图失败。")
		capture_finished.emit(false, "")
		return FAILED

	var err := _save_image(image)
	capture_finished.emit(err == OK, _last_saved_path)
	return err


## 获取截图目标视口：编辑器内截取编辑器主窗口视口，游戏运行时截取自身所在视口
func _get_target_viewport() -> Viewport:
	if Engine.is_editor_hint():
		var base_control := EditorInterface.get_base_control()
		if base_control != null:
			var editor_viewport := base_control.get_viewport()
			if editor_viewport != null:
				return editor_viewport
	return get_viewport()


## 从视口纹理回读高清图像；失败返回 null
func _grab_viewport_image() -> Image:
	var viewport := _get_target_viewport()
	if viewport == null:
		_log_error("未找到可截取的视口。")
		return null
	var texture := viewport.get_texture()
	if texture == null:
		_log_error("目标视口没有可用纹理。")
		return null
	var image := texture.get_image()
	if image == null:
		_log_error("视口纹理回读失败。")
	return image


## 保存图像为 PNG；保存目录不存在时自动递归创建，返回错误码
func _save_image(image: Image) -> Error:
	_last_saved_path = ""

	var save_dir := save_dir_path.strip_edges()
	if save_dir.is_empty():
		save_dir = DEFAULT_SAVE_DIR

	# 目录不存在时自动递归创建，保证零配置直接可用
	if not DirAccess.dir_exists_absolute(save_dir):
		var make_err := DirAccess.make_dir_recursive_absolute(save_dir)
		if make_err != OK:
			_log_error("创建截图保存目录失败: %s (错误码 %d)" % [save_dir, make_err])
			return make_err

	var prefix := file_prefix.strip_edges()
	if prefix.is_empty():
		prefix = "capture"

	# 文件名带时间戳，防止覆盖历史截图
	var now := Time.get_datetime_dict_from_system()
	var file_name := "%s_%04d%02d%02d_%02d%02d%02d.png" % [
		prefix, now.year, now.month, now.day, now.hour, now.minute, now.second]
	var save_path := save_dir.path_join(file_name)

	var err := image.save_png(save_path)
	if err != OK:
		_log_error("保存截图失败: %s (错误码 %d)" % [save_path, err])
		return err

	_last_saved_path = save_path
	_log_info("截图已保存: %s (%d x %d)" % [save_path, image.get_width(), image.get_height()])

	# 保存到项目目录后立即刷新文件系统，让截图出现在编辑器文件面板中
	if save_dir.begins_with("res://") and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return OK


func _log_info(msg: String) -> void:
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger != null and logger.has_method("info"):
			logger.info("VinoScreenCapture", msg)
			return
	print("[VinoScreenCapture] " + msg)


func _log_error(msg: String) -> void:
	if is_inside_tree():
		var logger := get_node_or_null("/root/VinoLogger")
		if logger != null and logger.has_method("error"):
			logger.error("VinoScreenCapture", msg)
			return
	push_error("[VinoScreenCapture] " + msg)
