class_name VinoConfigLoader
extends Node
## VinoConfigLoader - 全局配置文件加载器
##
## 建议 Autoload 挂载名称：VinoConfig（放在 Autoload 列表最上面，保证其他 Autoload 也能被注入）
## 1. 任意位置获取配置：VinoConfig.get_value("Section", "Key", default)
## 2. 自动注入（默认开启，无需手动调用）：节点名 == ini 小节名 时，
##    小节里的 key 会自动写入该节点脚本里同名的成员变量（局部变量无效）。
##    注入发生在节点 _ready() 之前；节点上若有 _apply_config() 方法，会在节点 ready 后自动调用。
## 3. 手动绑定（可选）：VinoConfig.bind(node, "自定义小节名", callback)，用于节点名与小节名不一致的情况
## 4. 已知名字的资源根目录：VinoConfig.get_root("assets") —— ini 里 [Paths] 配了 assets 就用配置值
##    （换目录、换盘符都不用改代码），没配就默认去 exe 同级目录下找 assets/ 文件夹，
##    找不到再回退包内 res://assets
## 5. 不确定资源文件夹到底叫什么名字时：VinoConfig.get_asset_root() —— ini 没配置的情况下，
##    按 default_asset_roots 里的顺序依次探测 exe 同级目录，命中第一个真实存在的文件夹就用它
##    （例如有的机器上是 assets/，有的是 data/，不用为每台机器改配置）

signal config_loaded

const BOUND_META := "_vino_config_bound" # 已注入标记，防止重复注入

var config_file_path: String = "config.ini"
var debug_print: bool = true
var is_loaded: bool = false
var auto_bind: bool = true # 是否自动遍历场景树并按 节点名==小节名 注入配置

## get_asset_root() 在 ini 未显式配置时依次探测的候选文件夹名，按优先级排列。
## 项目里习惯用别的名字（比如 Resources、StreamingAssets）可以直接在这里改，或者用
## get_asset_root(["Resources", "StreamingAssets"]) 临时传自定义候选列表。
var default_asset_roots: PackedStringArray = ["assets", "res", "resource", "data"]

var _config := ConfigFile.new()


## 生命周期初始化
func _ready() -> void:
	_load()
	if auto_bind:
		get_tree().node_added.connect(_on_node_added)
		_bind_tree(get_tree().root)


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
	_log("已加载，节点小节: " + str(_config.get_sections()))
	config_loaded.emit()


## 通用自适应路径解析：委托给 VinoPathResolver，与插件内其余模块共用同一套规则。
## 绝对路径原样返回；编辑器内按 res:// 处理；导出后优先匹配 exe 同级目录下的外部文件/文件夹，
## 找不到再回退包内 res://。
func resolve_path(path: String) -> String:
	return VinoPathResolver.resolve(path)


## 读取一个“路径类”配置项并直接解析好返回，省去 resolve_path(get_value(...)) 两步写法。
## - ini 里写了该 key：以 ini 里的值为准（可以是绝对路径，也可以是相对路径）
## - ini 里没写：用调用方传入的 default_relative_path 作为默认值
## 最终都会走 resolve_path()。
## 用法：var assets_dir = VinoConfig.get_config_path("Paths", "assets_dir", "assets")
func get_config_path(section: String, key: String, default_relative_path: String) -> String:
	var raw := str(get_value(section, key, default_relative_path))
	return resolve_path(raw)


## get_config_path() 的便捷封装：约定固定读取 [Paths] 小节，且默认相对路径就是 root_name 本身，
## 适合“已经知道资源文件夹具体叫什么名字”的场景（比如就叫 assets）。
## - config.ini 里写了 [Paths] 下同名 key：用 ini 里的值（整体换目录，改这一行不用碰代码）
##     [Paths]
##     assets = "D:/SharedAssets"
## - 没写：默认去 exe 同级目录下找同名文件夹（导出后），或包内 res://root_name（编辑器内 / 找不到时）
func get_root(root_name: String, default_relative_path: String = "") -> String:
	var fallback := default_relative_path if not default_relative_path.is_empty() else root_name
	return get_config_path("Paths", root_name, fallback)


## 不确定资源根目录到底叫什么名字时用这个：
## - ini [Paths] 下配置了 root_key（默认键名 "assets_root"）就直接用配置值，走 resolve_path()
## - 没配置：依次探测 candidates 列表（默认用 default_asset_roots），编辑器内检查 res://<name>
##   是否真实存在，导出后检查 exe 同级目录下 <name> 文件夹是否存在，命中第一个就返回
## - 全部候选都不存在：兜底返回 candidates 第一项按标准规则 resolve 后的结果
## 用法：var assets_dir = VinoConfig.get_asset_root()  # 自动在 assets/res/resource/data 里找一个存在的
func get_asset_root(candidates: PackedStringArray = PackedStringArray(), root_key: String = "assets_root", section: String = "Paths") -> String:
	var pool := candidates if not candidates.is_empty() else default_asset_roots
	if pool.is_empty():
		push_error("[VinoConfigLoader] get_asset_root: 候选列表为空")
		return ""

	if has_section(section) and get_section_keys(section).has(root_key):
		return resolve_path(str(get_value(section, root_key)))

	for candidate_name in pool:
		var candidate_path := resolve_path(candidate_name)
		if _dir_really_exists(candidate_path):
			return candidate_path

	_log("get_asset_root: 候选目录都不存在，回退到默认值 " + pool[0])
	return resolve_path(pool[0])


## 内部：判断 resolve_path() 返回的路径是否真实存在，兼容 res:// 与外部绝对路径两种情况。
func _dir_really_exists(path: String) -> bool:
	if path.begins_with("res://"):
		return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
	return DirAccess.dir_exists_absolute(path)


## 手动绑定并注入配置到节点同名变量（一般不需要，自动注入已覆盖大多数场景）
## section_name 为空时，默认匹配当前 node.name
## callback 可选传入注入完成后的回调函数；若未指定则自动查找节点上的 _apply_config() 方法
## 若该节点已被自动注入过，且没有传入自定义小节名/回调，则直接跳过（兼容旧的 bind(self) 写法）
func bind(node: Node, section_name: String = "", callback: Callable = Callable()) -> void:
	if section_name.is_empty() and not callback.is_valid() and node.has_meta(BOUND_META):
		return
	var section := section_name if not section_name.is_empty() else String(node.name)
	if not is_loaded:
		config_loaded.connect(func(): _do_bind(node, section, callback), CONNECT_ONE_SHOT)
		return
	_do_bind(node, section, callback)


## 内部：递归遍历子树，逐个尝试自动注入（处理配置加载时已在场景树里的节点）
func _bind_tree(node: Node) -> void:
	_auto_bind(node)
	for child in node.get_children():
		_bind_tree(child)


## 内部：新节点进入场景树时触发（此时节点 _ready() 还没执行，注入的值能直接被 _ready() 使用）
func _on_node_added(node: Node) -> void:
	_auto_bind(node)


## 内部：自动注入入口，按 节点名 匹配小节；已注入过或本身是 Loader 的节点跳过
func _auto_bind(node: Node) -> void:
	if node == self or not is_loaded or node.has_meta(BOUND_META):
		return
	_do_bind(node, String(node.name))


## 执行具体的属性注入逻辑，并在节点 ready 后触发回调或约定方法 _apply_config()
func _do_bind(node: Node, section: String, callback: Callable = Callable()) -> void:
	if not is_instance_valid(node) or not has_section(section):
		return
	node.set_meta(BOUND_META, true)
	for key in get_section_keys(section):
		if key in node:
			node.set(key, get_value(section, key))
	var done := callback
	if not done.is_valid() and node.has_method("_apply_config"):
		done = Callable(node, "_apply_config")
	if not done.is_valid():
		return
	if node.is_node_ready():
		done.call()
	else:
		node.ready.connect(done, CONNECT_ONE_SHOT)


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
