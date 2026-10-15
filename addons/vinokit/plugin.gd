@tool
extends EditorPlugin
## VinoKit 插件入口：注册核心 Autoload 单例，并在编辑器顶部主菜单栏的“帮助”菜单正后方
## 插入一个独立的 “VinoKit” 一级下拉菜单，内含孤立资源扫描及“工具”子菜单。

const VinoOrphanScanner = preload("res://addons/vinokit/utils/vino_orphan_scanner.gd")

const AUTOLOADS := {
	"VinoConfig": "res://addons/vinokit/core/vino_config_loader.gd",
	"VinoAssets": "res://addons/vinokit/core/vino_asset_loader.gd",
	"VinoData": "res://addons/vinokit/core/vino_data_loader.gd",
	"VinoWindow": "res://addons/vinokit/core/vino_window_controller.gd",
}

## 一级菜单标题
const MENU_TITLE := "VinoKit"

## 降级方案使用的“项目 -> 工具”菜单路径
const TOOL_MENU_PATH := "VinoKit/扫描孤立资源..."

## 顶部“帮助”菜单的候选标题，覆盖常见编辑器界面语言
const HELP_MENU_TITLES := ["Help", "帮助", "ヘルプ", "Aide", "Hilfe", "Ayuda", "Aiuto", "Ajuda", "Помощь", "帮助(&H)"]

# 菜单项枚举，用于区分点击了哪一项
enum MenuAction {
	SCAN_ORPHANS,
	TOOL_ARRAY,
	TOOL_COLOR,
	TOOL_DICTIONARY,
	TOOL_MATH,
	TOOL_NODE,
	TOOL_STRING,
}

var _vino_menu: PopupMenu = null
var _tools_menu: PopupMenu = null
var _menu_bar: MenuBar = null
var _used_tool_fallback := false

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
	# 1. 清理顶部菜单栏的 VinoKit 菜单
	_cleanup_top_menu()

	# 2. 移除原有的 Autoload 单例
	for singleton_name: String in AUTOLOADS:
		remove_autoload_singleton(singleton_name)
	print("【VinoKit】核心模块已卸载")

## 初始化顶部主菜单栏：在“帮助”菜单之后插入 “VinoKit” 一级菜单
func _init_top_menu() -> void:
	# 主下拉菜单
	_vino_menu = PopupMenu.new()
	_vino_menu.name = MENU_TITLE
	_vino_menu.add_item("扫描孤立资源...", MenuAction.SCAN_ORPHANS)
	
	_vino_menu.add_separator()

	# 创建“工具”子菜单 (Tools)
	_tools_menu = PopupMenu.new()
	_tools_menu.name = "ToolsSubMenu"
	_tools_menu.add_item("数组工具 (vino_array.gd)", MenuAction.TOOL_ARRAY)
	_tools_menu.add_item("颜色工具 (vino_color.gd)", MenuAction.TOOL_COLOR)
	_tools_menu.add_item("字典工具 (vino_dictionary.gd)", MenuAction.TOOL_DICTIONARY)
	_tools_menu.add_item("数学工具 (vino_math.gd)", MenuAction.TOOL_MATH)
	_tools_menu.add_item("节点工具 (vino_node.gd)", MenuAction.TOOL_NODE)
	_tools_menu.add_item("字符串工具 (vino_string.gd)", MenuAction.TOOL_STRING)
	_tools_menu.id_pressed.connect(_on_menu_item_pressed)

	# 【必须】将 _tools_menu 添加为 _vino_menu 的子节点，否则 add_submenu_node_item 会校验失败且导致内存泄漏
	_vino_menu.add_child(_tools_menu)
	_vino_menu.add_submenu_node_item("工具 (Tools)", _tools_menu)

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
	print("[VinoKit] 已在编辑器顶部菜单栏挂载 “%s” 菜单（含工具子菜单）。" % MENU_TITLE)

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
		MenuAction.TOOL_ARRAY:
			print("[VinoKit] 点击了：数组工具 (vino_array.gd) —— 纯静态类，可按需调用静态方法。")
		MenuAction.TOOL_COLOR:
			print("[VinoKit] 点击了：颜色工具 (vino_color.gd) —— 纯静态类，可按需调用静态方法。")
		MenuAction.TOOL_DICTIONARY:
			print("[VinoKit] 点击了：字典工具 (vino_dictionary.gd) —— 纯静态类，可按需调用静态方法。")
		MenuAction.TOOL_MATH:
			print("[VinoKit] 点击了：数学工具 (vino_math.gd) —— 纯静态类，可按需调用静态方法。")
		MenuAction.TOOL_NODE:
			print("[VinoKit] 点击了：节点工具 (vino_node.gd) —— 纯静态类，可按需调用静态方法。")
		MenuAction.TOOL_STRING:
			print("[VinoKit] 点击了：字符串工具 (vino_string.gd) —— 纯静态类, 可按需调用静态方法。")

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
	print("        VinoKit 资源扫描报告        ")
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