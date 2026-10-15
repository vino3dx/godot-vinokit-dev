extends VinoContentBrowser
## 项目适配示例：把通用内容浏览组件接回具体项目的数据源。
##
## 本文件只是示例，不会被插件自动加载。用法：
##   1. 复制到你的项目里（例如 res://scenes/browser/content_browser_adapter.gd）；
##   2. 把下面几处「项目数据入口」换成你项目自己的实现（单例 / 自动加载 / 资源文件）；
##   3. 让项目场景继承 vino_content_browser.tscn 并把根节点脚本换成本脚本，
##      或先实例化 vino_content_browser.tscn、加入场景树前 set_script(本脚本)。
##
## 说明：示例用 get_node("/root/GameManager") 动态访问项目单例，是为了让本文件在
## 没有 GameManager 的环境里也能被正常解析，不报「标识符未声明」错误。
## 下面的「两轮目录匹配」同样属于项目逻辑：通用组件只接收已解析好的目录，
## 不关心目录是怎么定位来的。

func _ready() -> void:
	super._ready()

	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager == null:
		VinoLogger.warn(TAG, "未找到 /root/GameManager，请按项目实际情况修改适配脚本")
		return

	back_requested.connect(_on_back_requested)

	var raw_module_data: Variant = game_manager.get("current_module_data")
	var module_data: Dictionary = raw_module_data if typeof(raw_module_data) == TYPE_DICTIONARY else {}
	set_title(String(module_data.get("display_name", "")))

	# 显式 sections 优先，没有则回退「文件夹即内容」扫描。
	var raw_sections: Variant = module_data.get("sections", [])
	if typeof(raw_sections) == TYPE_ARRAY and not (raw_sections as Array).is_empty():
		set_sections(raw_sections)
	else:
		load_from_directory(_resolve_module_directory(module_data, game_manager))


## 项目侧目录解析（原通用脚本里的模块匹配逻辑，按项目约定自行维护）：
##   1. 精确匹配——依次尝试 data_dir → display_name → 模块标识；
##   2. 剥离排序前缀后比对——兼容 "1_国家政策及意义" 这类根目录下带序号的模块文件夹。
## 找不到时返回空串，由 load_from_directory 走「目录无效」占位提示。
func _resolve_module_directory(module_data: Dictionary, game_manager: Node) -> String:
	const MODULE_DATA_ROOT := "res://data/modules"
	var candidates: Array[String] = [
		String(module_data.get("data_dir", "")),
		String(module_data.get("display_name", "")),
		String(game_manager.get("current_module_id")),
	]

	var searched_names: Array[String] = []
	for candidate: String in candidates:
		if candidate.is_empty() or searched_names.has(candidate):
			continue
		searched_names.append(candidate)
		var directory_path: String = "%s/%s" % [MODULE_DATA_ROOT, candidate]
		if DirAccess.open(directory_path) != null:
			return directory_path

	if DirAccess.open(MODULE_DATA_ROOT) == null:
		return ""
	# 第二轮：按剥离排序前缀后的名字再找一轮（与通用组件的标题剥离规则保持一致）。
	var prefix_pattern := RegEx.create_from_string("^[0-9０-９]+[_\\-\\.、·．～~—－\\s　]*")
	for candidate: String in searched_names:
		var directory := DirAccess.open(MODULE_DATA_ROOT)
		directory.list_dir_begin()
		var entry_name: String = directory.get_next()
		while not entry_name.is_empty():
			if not entry_name.begins_with(".") and directory.current_is_dir():
				var clean_name: String = prefix_pattern.sub(entry_name, "", true).strip_edges()
				if clean_name == candidate:
					directory.list_dir_end()
					return "%s/%s" % [MODULE_DATA_ROOT, entry_name]
			entry_name = directory.get_next()
		directory.list_dir_end()
	return ""


func _on_back_requested() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null and game_manager.has_method("go_back"):
		game_manager.call("go_back")
