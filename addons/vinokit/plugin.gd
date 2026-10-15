@tool
extends EditorPlugin
## VinoKit 插件入口：注册核心 Autoload 单例，并在编辑器顶部主菜单栏的“帮助”菜单正后方
## 插入一个独立的 “VinoKit” 一级下拉菜单（孤立资源扫描 + “工具箱”子菜单）。
##
## 工具箱只挂载 tools/ 下真正的 @tool 编辑器工具；utils/ 下的 vino_array / vino_color 等
## 纯静态函数库不再进入菜单，回归 res://addons/vinokit/utils/ 直接代码调用。

const VinoOrphanScanner = preload("res://addons/vinokit/utils/vino_orphan_scanner.gd")
const VinoProjectDirs = preload("res://addons/vinokit/tools/vino_project_dirs.gd")

## tools/ 下的编辑器工具脚本（均为 @tool extends Node，实例化并进入场景树后才能触发）
const VinoZipPackerScript = preload("res://addons/vinokit/tools/vino_zip_packer.gd")
const VinoShaderConverterScript = preload("res://addons/vinokit/tools/vino_shader_converter.gd")
const VinoConfigValidatorScript = preload("res://addons/vinokit/tools/vino_config_validator.gd")
const VinoClassExplorerScript = preload("res://addons/vinokit/tools/vino_class_explorer.gd")
const VinoScreenCaptureScript = preload("res://addons/vinokit/tools/vino_screen_capture.gd")

const AUTOLOADS := {
	"VinoConfig": "res://addons/vinokit/core/vino_config_loader.gd",
	"VinoAssets": "res://addons/vinokit/core/vino_asset_loader.gd",
	"VinoData": "res://addons/vinokit/core/vino_data_loader.gd",
	"VinoWindow": "res://addons/vinokit/core/vino_window_controller.gd",
}

## 一级菜单标题
const MENU_TITLE := "VinoKit"

## 降级方案使用的“项目 -> 工具”菜单路径
const TOOL_MENU_PATH := "VinoKit/📋 孤立资源扫描..."

## 顶部“帮助”菜单的候选标题，覆盖常见编辑器界面语言
const HELP_MENU_TITLES := ["Help", "帮助", "ヘルプ", "Aide", "Hilfe", "Ayuda", "Aiuto", "Ajuda", "Помощь", "帮助(&H)"]

# 菜单项枚举，用于区分点击了哪一项
enum MenuAction {
	SCAN_ORPHANS,
	TOOL_ZIP_PACKER,
	TOOL_SHADER_CONVERTER,
	TOOL_CONFIG_VALIDATOR,
	TOOL_CLASS_EXPLORER,
	TOOL_SCREEN_CAPTURE,
	TOOL_CREATE_PROJECT_DIRS,
	TOOL_CLEAN_EMPTY_DIRS,
}

var _vino_menu: PopupMenu = null
var _tools_menu: PopupMenu = null
var _menu_bar: MenuBar = null
var _used_tool_fallback := false

## 当前打开的路径选择弹窗（同一时间只允许一个）
var _active_dialog: FileDialog = null

## 已实例化的临时工具节点，退出时统一回收
var _active_tools: Array[Node] = []


func _enter_tree() -> void:
	# 1. 注册原有的核心 Autoload 单例
	for singleton_name: String in AUTOLOADS:
		if not ProjectSettings.has_setting("autoload/" + singleton_name):
			add_autoload_singleton(singleton_name, AUTOLOADS[singleton_name])

	# 2. 在编辑器顶部主菜单栏创建专用的 “VinoKit” 菜单
	_init_top_menu()

	var joined := "、".join(AUTOLOADS.keys().map(func(n): return "[%s]" % n))
	print("【VinoKit】核心模块已加载: %s" % joined)


func _exit_tree() -> void:
	# 1. 先回收弹窗与临时工具节点，避免编辑器内残留实例
	_close_dialog(_active_dialog)
	for tool: Node in _active_tools.duplicate():
		_despawn_tool(tool)
	_active_tools.clear()

	# 2. 清理顶部菜单栏的 VinoKit 菜单
	_cleanup_top_menu()

	# 3. 移除原有的 Autoload 单例
	for singleton_name: String in AUTOLOADS:
		remove_autoload_singleton(singleton_name)
	print("【VinoKit】核心模块已卸载")


## 初始化顶部主菜单栏：在“帮助”菜单之后插入 “VinoKit” 一级菜单
func _init_top_menu() -> void:
	# 主下拉菜单
	_vino_menu = PopupMenu.new()
	_vino_menu.name = MENU_TITLE
	_vino_menu.add_item("📋 孤立资源扫描...", MenuAction.SCAN_ORPHANS)

	_vino_menu.add_separator()

	# 创建“工具箱”子菜单 (Tools)：只包含 tools/ 下的编辑器工具
	_tools_menu = PopupMenu.new()
	_tools_menu.name = "ToolsSubMenu"
	_tools_menu.add_item("📦 一键打包 ZIP (VinoZipPacker)", MenuAction.TOOL_ZIP_PACKER)
	_tools_menu.add_item("🔄 Shader 转 VisualShader (VinoShaderConverter)", MenuAction.TOOL_SHADER_CONVERTER)
	_tools_menu.add_item("🔍 配置合法性检查 (VinoConfigValidator)", MenuAction.TOOL_CONFIG_VALIDATOR)
	_tools_menu.add_item("🛠️ 类反射探测器 (ClassExplorer)", MenuAction.TOOL_CLASS_EXPLORER)
	_tools_menu.add_item("📸 快捷截图与水印 (VinoScreenCapture)", MenuAction.TOOL_SCREEN_CAPTURE)
	_tools_menu.add_separator()
	_tools_menu.add_item("📁 一键创建项目目录 (标准结构)", MenuAction.TOOL_CREATE_PROJECT_DIRS)
	_tools_menu.add_item("🧹 一键清除空目录", MenuAction.TOOL_CLEAN_EMPTY_DIRS)
	_tools_menu.id_pressed.connect(_on_menu_item_pressed)

	# 【必须】将 _tools_menu 添加为 _vino_menu 的子节点，否则 add_submenu_node_item 会校验失败且导致内存泄漏
	_vino_menu.add_child(_tools_menu)
	_vino_menu.add_submenu_node_item("📁 工具箱 (Tools)", _tools_menu)

	# 绑定主菜单点击事件
	_vino_menu.id_pressed.connect(_on_menu_item_pressed)

	# 定位编辑器顶部主菜单栏
	var base_control := EditorInterface.get_base_control()
	_menu_bar = _find_editor_menu_bar(base_control)
	if _menu_bar == null:
		_vino_menu.queue_free()
		_vino_menu = null
		_tools_menu = null
		_fallback_to_tool_menu()
		return

	# 追加为 MenuBar 的子节点，再移动到“帮助”菜单正后方
	_menu_bar.add_child(_vino_menu)
	var help_index := _find_help_menu_index(_menu_bar)
	if help_index >= 0:
		var help_popup := _menu_bar.get_menu_popup(help_index)
		if help_popup != null:
			_menu_bar.move_child(_vino_menu, help_popup.get_index() + 1)
	else:
		print("[VinoKit] 提示：未定位到“帮助”菜单，已追加到主菜单栏末尾。")

	# 显式设置显示标题
	var self_index := _find_menu_index(_menu_bar, _vino_menu)
	if self_index >= 0:
		_menu_bar.set_menu_title(self_index, MENU_TITLE)
	print("[VinoKit] 已在编辑器顶部菜单栏挂载 “%s” 菜单（含工具箱子菜单）。" % MENU_TITLE)


## 辅助函数：在编辑器控件树中递归查找顶部主菜单栏
func _find_editor_menu_bar(node: Node) -> MenuBar:
	var candidates: Array[MenuBar] = []
	_collect_menu_bars(node, candidates)

	for bar: MenuBar in candidates:
		if _find_help_menu_index(bar) >= 0:
			return bar

	if node != null:
		var tree := node.get_tree()
		if tree != null and tree.root != node:
			_collect_menu_bars(tree.root, candidates)
			for bar: MenuBar in candidates:
				if _find_help_menu_index(bar) >= 0:
					return bar

	var best: MenuBar = null
	for bar: MenuBar in candidates:
		if best == null or bar.get_menu_count() > best.get_menu_count():
			best = bar
	return best


## 递归收集 node 子树中的所有 MenuBar
func _collect_menu_bars(node: Node, out: Array[MenuBar]) -> void:
	if node is MenuBar:
		if not out.has(node):
			out.append(node)
	for child in node.get_children():
		_collect_menu_bars(child, out)


## 返回“帮助”菜单在 menu_bar 中的菜单序号；未找到返回 -1
func _find_help_menu_index(menu_bar: MenuBar) -> int:
	for i in menu_bar.get_menu_count():
		var popup := menu_bar.get_menu_popup(i)
		var title := menu_bar.get_menu_title(i)
		if title.is_empty() and popup != null:
			title = String(popup.name)
		title = title.strip_edges().replace("&", "")
		if HELP_MENU_TITLES.has(title) or title.to_lower() == "help":
			return i
	return -1


## 返回目标 PopupMenu 在 menu_bar 中的菜单序号；未找到返回 -1
func _find_menu_index(menu_bar: MenuBar, target: PopupMenu) -> int:
	for i in menu_bar.get_menu_count():
		if menu_bar.get_menu_popup(i) == target:
			return i
	return -1


## 降级方案：未捕获到顶部 MenuBar 时，挂载到“项目 -> 工具”菜单
func _fallback_to_tool_menu() -> void:
	add_tool_menu_item(TOOL_MENU_PATH, _on_scan_orphans_triggered)
	_used_tool_fallback = true
	print("[VinoKit] 提示：未直接捕获到顶部 MenuBar，已降级挂载至 项目 -> 工具。")


## 清理顶部菜单，避免残留节点与内存泄漏
func _cleanup_top_menu() -> void:
	if _vino_menu != null and is_instance_valid(_vino_menu):
		var parent := _vino_menu.get_parent()
		if parent != null:
			parent.remove_child(_vino_menu)
		# _tools_menu 是 _vino_menu 的子节点，随父节点一并释放
		_vino_menu.queue_free()
	_vino_menu = null
	_tools_menu = null
	_menu_bar = null

	if _used_tool_fallback:
		remove_tool_menu_item(TOOL_MENU_PATH)
		_used_tool_fallback = false


## 下拉菜单点击事件分发
func _on_menu_item_pressed(id: int) -> void:
	match id:
		MenuAction.SCAN_ORPHANS:
			_on_scan_orphans_triggered()
		MenuAction.TOOL_ZIP_PACKER:
			_run_zip_packer()
		MenuAction.TOOL_SHADER_CONVERTER:
			_run_shader_converter()
		MenuAction.TOOL_CONFIG_VALIDATOR:
			_run_config_validator()
		MenuAction.TOOL_CLASS_EXPLORER:
			_run_class_explorer()
		MenuAction.TOOL_SCREEN_CAPTURE:
			_run_screen_capture()
		MenuAction.TOOL_CREATE_PROJECT_DIRS:
			_run_create_project_dirs()
		MenuAction.TOOL_CLEAN_EMPTY_DIRS:
			_run_clean_empty_dirs()


## 触发孤立资源扫描，并把结构化报告打印到 Output 面板
func _on_scan_orphans_triggered() -> void:
	print("[VinoKit] 正在启动孤立资源扫描...")

	var exclude_paths := PackedStringArray([
		".godot",
		"addons/vinokit"
	])

	var result := VinoOrphanScanner.scan_project(exclude_paths)
	var summary := result.get("SUMMARY", {})

	print("========================================")
	print("          VinoKit 资源扫描报告          ")
	print("========================================")
	print("总计扫描文件: %d" % summary.get("total", 0))
	print("疑似孤立资源: %d" % summary.get("orphan_count", 0))
	print("已发现引用:   %d" % summary.get("referenced_count", 0))
	print("无法确认:     %d" % summary.get("uncertain_count", 0))
	print("耗时:         %d ms" % summary.get("elapsed_ms", 0))
	print("========================================")

	var orphans: Array = result.get("ORPHAN", [])
	if not orphans.is_empty():
		print("\n【疑似孤立资源列表】")
		for item in orphans:
			print("  [%s] %s" % [item.get("type"), item.get("path")])
	else:
		print("\n太棒了！项目中没有发现疑似孤立资源。")


# ==============================
# 工具箱：tools/ 下的编辑器工具
# ==============================

## 📦 VinoZipPacker：先选源文件夹，再选 ZIP 输出目录（参数全部由用户当场指定）
func _run_zip_packer() -> void:
	if not _can_open_dialog():
		return

	# 工具脚本通过 preload 动态实例化，属性/方法按脚本实际定义动态调用
	var tool = _spawn_tool(VinoZipPackerScript, "VinoZipPackerTool")

	_open_dir_dialog("① 选择要打包的文件夹", func(source_dir: String) -> void:
		if source_dir.is_empty():
			print("[VinoKit] VinoZipPacker：已取消源文件夹选择。")
			_despawn_tool(tool)
			return
		tool.source_dir_path = source_dir

		_open_dir_dialog("② 选择 ZIP 输出目录", func(output_dir: String) -> void:
			if output_dir.is_empty():
				print("[VinoKit] VinoZipPacker：已取消输出目录选择。")
				_despawn_tool(tool)
				return
			tool.zip_output_path = output_dir
			print("[VinoKit] VinoZipPacker 开始打包：%s -> %s" % [source_dir, output_dir])
			var err: int = tool.pack_to_zip()
			print("[VinoKit] VinoZipPacker 执行结束，返回码 %d（0 = 成功）" % err)
			_despawn_tool(tool))
	)


## 🔄 VinoShaderConverter：选择单个 .gdshader，转换结果由工具自身保存为同目录 *_visual.tres
func _run_shader_converter() -> void:
	if not _can_open_dialog():
		return

	var tool = _spawn_tool(VinoShaderConverterScript, "VinoShaderConverterTool")

	_open_file_dialog("选择要转换的 .gdshader 文件", PackedStringArray(["*.gdshader ; Godot Shader"]), func(file_path: String) -> void:
		if file_path.is_empty():
			print("[VinoKit] VinoShaderConverter：已取消文件选择。")
			_despawn_tool(tool)
			return
		tool.source_file = file_path
		print("[VinoKit] VinoShaderConverter 开始转换：%s" % file_path)
		# trigger_convert 是工具的触发开关，赋值后工具内部执行转换并自动复位
		tool.trigger_convert = true
		print("[VinoKit] VinoShaderConverter 执行结束（结果资源与源文件同目录，后缀 _visual.tres）。")
		_despawn_tool(tool))


## 🔍 VinoConfigValidator：无参数，直接执行配置与场景树全量诊断
func _run_config_validator() -> void:
	var tool = _spawn_tool(VinoConfigValidatorScript, "VinoConfigValidatorTool")
	tool.validate_all()
	_despawn_tool(tool)


## 🛠️ ClassExplorer：优先探测编辑器当前选中节点的类，未选中时沿用工具默认目标（Node）
func _run_class_explorer() -> void:
	var selected_class := _get_selected_class_name()

	# auto_run 必须在加入场景树前关闭，否则 _ready() 会先按默认目标跑一遍
	var tool = _spawn_tool(VinoClassExplorerScript, "ClassExplorerTool", func(node: Node) -> void:
		node.auto_run = false
		if not selected_class.is_empty():
			node.target_class = selected_class)

	if selected_class.is_empty():
		print("[VinoKit] ClassExplorer 未检测到选中节点，使用工具默认目标类。")
	else:
		print("[VinoKit] ClassExplorer 探测编辑器当前选中节点的类：%s" % selected_class)
	tool.explore_target()
	_despawn_tool(tool)


## 📸 VinoScreenCapture：先选截图保存目录（取消则用默认 res://screenshots），
## 再截取编辑器主视口并叠加水印自动保存；截图完成信号到达后才回收工具节点
func _run_screen_capture() -> void:
	if not _can_open_dialog():
		return

	_open_dialog("选择截图保存目录（取消则使用默认 %s）" % VinoScreenCaptureScript.DEFAULT_SAVE_DIR,
		FileDialog.FILE_MODE_OPEN_DIR,
		FileDialog.ACCESS_RESOURCES,
		VinoScreenCaptureScript.DEFAULT_SAVE_DIR,
		PackedStringArray(),
		func(dir_path: String) -> void:
			var save_dir := dir_path if not dir_path.is_empty() else VinoScreenCaptureScript.DEFAULT_SAVE_DIR
			if dir_path.is_empty():
				print("[VinoKit] VinoScreenCapture：未选择目录，使用默认保存目录 %s。" % save_dir)

			var tool := _spawn_tool(VinoScreenCaptureScript, "VinoScreenCaptureTool")
			tool.save_dir_path = save_dir
			# capture_screen 内部需等待下一帧回读视口，完成后由 capture_finished 信号通知再回收，避免协程中断
			tool.capture_finished.connect(func(_success: bool, _saved_path: String) -> void:
				_despawn_tool(tool))
			tool.capture_screen())


# ==============================
# 项目结构维护：标准目录创建与空目录清理
# ==============================

## 📁 一键创建标准项目目录：非破坏性操作（只新增缺失目录，不覆盖既有文件），直接执行并输出报告
func _run_create_project_dirs() -> void:
	var result := VinoProjectDirs.create_standard_dirs()
	_print_create_dirs_report(result)


## 🧹 一键清除空目录：破坏性操作，先弹确认框说明规则与风险，确认后才执行
func _run_clean_empty_dirs() -> void:
	_open_confirm_dialog(
		"确认清除空目录？",
		"将自底向上递归删除 res:// 下所有完全空的文件夹（目录内不含任何文件；\n"
		+ "只要存在 .import / .uid 等边车文件即视为有效目录并保留）。\n"
		+ "排除项：.godot/ 引擎缓存与 addons/ 插件目录（任意层级）不会进入，也不会被删除。\n"
		+ "删除不可撤销，建议先提交 Git 或备份项目后再执行。",
		func() -> void:
			_do_clean_empty_dirs.call_deferred())


## 延迟到弹窗信号栈之外执行清理；删除后让编辑器重新扫描，避免 FileSystem 面板持有已删除目录
func _do_clean_empty_dirs() -> void:
	var result := VinoProjectDirs.clean_empty_dirs()
	_print_clean_dirs_report(result)
	EditorInterface.get_resource_filesystem().scan()


## 输出“创建项目目录”报告
func _print_create_dirs_report(result: Dictionary) -> void:
	var created: PackedStringArray = result.get("created", PackedStringArray())
	var skipped: PackedStringArray = result.get("skipped", PackedStringArray())
	var failed: PackedStringArray = result.get("failed", PackedStringArray())

	print("========================================")
	print("       VinoKit 项目目录创建报告        ")
	print("========================================")
	print("新建目录 (%d):" % created.size())
	for rel: String in created:
		print("  + %s" % rel)
	print("已存在跳过 (%d):" % skipped.size())
	for rel: String in skipped:
		print("  = %s" % rel)
	if not failed.is_empty():
		print("创建失败 (%d):" % failed.size())
		for rel: String in failed:
			print("  ! %s" % rel)
	print("========================================")


## 输出“清除空目录”报告
func _print_clean_dirs_report(result: Dictionary) -> void:
	var scanned: int = result.get("scanned", 0)
	var removed: PackedStringArray = result.get("removed", PackedStringArray())
	var skipped: PackedStringArray = result.get("skipped", PackedStringArray())
	var failed: PackedStringArray = result.get("failed", PackedStringArray())

	print("========================================")
	print("       VinoKit 空目录清理报告          ")
	print("========================================")
	print("扫描目录:   %d" % scanned)
	print("删除空目录: %d" % removed.size())
	for rel: String in removed:
		print("  - %s" % rel)
	print("排除保留:   %d" % skipped.size())
	for rel: String in skipped:
		print("  = %s" % rel)
	if not failed.is_empty():
		print("删除失败:   %d" % failed.size())
		for rel: String in failed:
			print("  ! %s" % rel)
	print("========================================")


## 读取编辑器当前选中节点的主类名；无选中时返回空串
func _get_selected_class_name() -> String:
	var selection := EditorInterface.get_selection()
	if selection == null:
		return ""
	var selected_nodes := selection.get_selected_nodes()
	if selected_nodes.is_empty():
		return ""
	var node: Node = selected_nodes[0]
	return node.get_class()


# ==============================
# 工具节点与弹窗的通用辅助
# ==============================

## 实例化工具脚本并挂到本插件下（编辑器工具需要进入场景树才能使用 get_tree() 等能力）
## configure 会在加入场景树前调用，用于初始化 @export 参数
func _spawn_tool(script: Script, tool_name: String, configure: Callable = Callable()) -> Node:
	var tool: Node = script.new()
	tool.name = tool_name
	if configure.is_valid():
		configure.call(tool)
	add_child(tool)
	_active_tools.append(tool)
	return tool


## 回收临时工具节点，避免残留实例
func _despawn_tool(tool: Node) -> void:
	if tool == null:
		return
	_active_tools.erase(tool)
	if is_instance_valid(tool):
		if tool.get_parent() != null:
			tool.get_parent().remove_child(tool)
		tool.queue_free()


## 同一时间只允许存在一个路径选择弹窗
func _can_open_dialog() -> bool:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		print("[VinoKit] 已有弹窗未处理，请先完成或关闭当前弹窗。")
		return false
	return true


## 弹出确认对话框（破坏性操作前必须经过用户确认）；
## 无论确认、取消还是直接关闭窗口，弹窗隐藏后统一释放，避免编辑器内残留节点
func _open_confirm_dialog(title: String, message: String, on_confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = "确认执行"
	dialog.confirmed.connect(func() -> void:
		on_confirmed.call())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			if dialog.get_parent() != null:
				dialog.get_parent().remove_child(dialog)
			dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


## 打开目录选择弹窗（操作系统文件系统，用于 ZIP 打包等物理路径场景）
func _open_dir_dialog(title: String, on_selected: Callable) -> void:
	_open_dialog(title, FileDialog.FILE_MODE_OPEN_DIR, FileDialog.ACCESS_FILESYSTEM, "", PackedStringArray(), on_selected)


## 打开文件选择弹窗（项目资源文件系统 res://）
func _open_file_dialog(title: String, filters: PackedStringArray, on_selected: Callable) -> void:
	_open_dialog(title, FileDialog.FILE_MODE_OPEN_FILE, FileDialog.ACCESS_RESOURCES, "", filters, on_selected)


## 统一创建/回收弹窗：选中或取消后立即释放弹窗，再回调结果（取消时传入空串）
## initial_dir 非空时作为弹窗打开的初始目录；参数顺序固定为
## (title, mode, access, initial_dir, filters, on_selected)，调用方必须严格按此顺序传参
func _open_dialog(title: String, mode: int, access: int, initial_dir: String, filters: PackedStringArray, on_selected: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = access
	dialog.filters = filters
	if not initial_dir.is_empty():
		dialog.current_dir = initial_dir

	dialog.dir_selected.connect(func(dir_path: String) -> void:
		_close_dialog(dialog)
		on_selected.call(dir_path))
	dialog.file_selected.connect(func(file_path: String) -> void:
		_close_dialog(dialog)
		on_selected.call(file_path))
	dialog.canceled.connect(func() -> void:
		_close_dialog(dialog)
		on_selected.call(""))

	_active_dialog = dialog
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered_ratio(0.45)


## 关闭并释放弹窗
func _close_dialog(dialog: FileDialog) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if is_instance_valid(dialog):
		if dialog.get_parent() != null:
			dialog.get_parent().remove_child(dialog)
		dialog.queue_free()
