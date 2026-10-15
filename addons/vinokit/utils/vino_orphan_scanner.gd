@tool
class_name VinoOrphanScanner
extends RefCounted
## VinoOrphanScanner：孤立资源扫描器（纯只读）。
##
## 扫描 res:// 下的全部资源文件，用两种互补手段判断“是否被引用”：
## 1. 原生依赖查询：ResourceLoader.get_dependencies() 读取 .tscn/.tres/.gd 的依赖树；
## 2. 文本静态分析：解析 .gd/.tscn/.tres/project.godot 等文本中的 res:// 路径、
##    uid:// 引用（经 *.uid 边车文件与资源头反查）、class_name 标识符交叉引用，
##    以及 project.godot 的 main_scene / autoload / icon 配置。
##
## 分类语义：
## - ORPHAN    ：未发现任何引用，且项目中不存在无法静态解析的动态加载。
## - REFERENCED：已发现至少一处具体引用（依赖 / 文本路径 / 配置 / class_name）。
## - UNCERTAIN ：无法确认——被动态拼接的静态前缀覆盖，或项目中存在无法静态解析的
##               load()/ResourceLoader.load()（详见 DYNAMIC_SOURCES）。
##               这类资源绝不伪造为 ORPHAN。
##
## 安全约束：全过程只读，仅使用 DirAccess / FileAccess / ResourceLoader /
## ProjectSettings 做读取与静态分析，不写、不删、不改任何文件。
## .godot 目录与引擎生成的 .uid / .import 文件不参与分类。

const TAG := "VinoOrphanScanner"

## 参与文本静态分析的扩展名（小写，不含点）
const TEXT_EXTS := ["gd", "tscn", "tres", "res", "godot", "cfg", "ini", "json", "md", "txt", "csv", "xml", "gdshader", "shader"]

## 需要调用 ResourceLoader.get_dependencies() 的扩展名（其余文件没有依赖查询价值）
const DEP_EXTS := ["tscn", "tres", "res", "gd"]

## 报告中展示的资源类型标签
const TYPE_BY_EXT := {
	"tscn": "scene", "scn": "scene",
	"gd": "script",
	"tres": "resource", "res": "resource",
	"png": "texture", "jpg": "texture", "jpeg": "texture", "webp": "texture",
	"svg": "texture", "bmp": "texture", "tga": "texture", "dds": "texture",
	"exr": "texture", "hdr": "texture",
	"ogg": "audio", "wav": "audio", "mp3": "audio",
	"ogv": "video", "mp4": "video", "webm": "video", "avi": "video", "mov": "video",
	"ttf": "font", "otf": "font", "woff": "font", "woff2": "font",
	"gdshader": "shader", "shader": "shader",
	"mat": "material",
	"json": "data", "csv": "data", "xml": "data",
	"cfg": "config", "ini": "config", "toml": "config",
	"md": "doc", "txt": "doc",
}

## 从文本中提取路径时需要剥离的尾随字符
const _TRAILING_CHARS := ".,;:!?)]}\"'"


## 扫描项目中的孤立资源，返回结构化结果（只读，无任何副作用）。
## exclude_paths 中的目录/文件不参与分类，但仍作为引用来源参与分析
## （避免“仅被排除目录引用的文件”被误判为孤立）。
##
## 返回结构：
## {
##   "SUMMARY": {
##     "total": int, "orphan_count": int, "referenced_count": int,
##     "uncertain_count": int, "dynamic_source_count": int, "elapsed_ms": int,
##   },
##   "ORPHAN": [{"path": String, "type": String}],
##   "REFERENCED": [{"path": String, "type": String, "sources": Array}],
##   "UNCERTAIN": [{"path": String, "type": String, "reason": String}],
##   "DYNAMIC_SOURCES": [{"file": String, "prefixes": PackedStringArray, "unresolvable": bool}],
## }
static func scan_project(exclude_paths: PackedStringArray) -> Dictionary:
	var start_ms := Time.get_ticks_msec()
	VinoLogger.info(TAG, "开始扫描 res:// 下的孤立资源...")

	var excludes := _normalize_excludes(exclude_paths)
	var all_files := _collect_files("res://")
	all_files.sort()
	var file_set := {}
	for f: String in all_files:
		file_set[f] = true

	# uid -> res:// 路径映射（来自 *.uid 边车文件与 .tscn/.tres 资源头）
	var uid_map := _build_uid_map(all_files)

	# 排除引擎生成的 .uid / .import，得到可分析、可分类的文件
	var analyzable := PackedStringArray()
	for f: String in all_files:
		var ext := f.get_extension().to_lower()
		if ext == "uid" or ext == "import":
			continue
		analyzable.append(f)

	# path -> Array[来源文件]；来源为 "engine" 时表示引擎自身依赖
	var refs := {}
	_add_ref(refs, "res://project.godot", "engine", file_set)

	# 第一遍：文本静态分析（res:// 路径、uid://、class_name 声明、动态加载）
	var class_files := {} # class_name -> 声明所在文件
	var dynamic_sources: Array = []
	for f: String in analyzable:
		if not (f.get_extension().to_lower() in TEXT_EXTS):
			continue
		var text := _read_text(f)
		if text.is_empty():
			continue
		_collect_path_refs(text, f, refs, uid_map, file_set)
		if f.get_extension().to_lower() == "gd":
			_collect_class_names(f, text, class_files)
			_analyze_dynamic_loads(f, text, dynamic_sources)

	# 第二遍：class_name 标识符交叉引用（其他文件中出现即视为被引用）
	_resolve_class_refs(class_files, analyzable, refs, file_set)

	# 第三遍：project.godot 配置（main_scene / autoload / icon）
	_scan_project_config(refs, uid_map, file_set)

	# 第四遍：原生依赖查询
	for f: String in analyzable:
		if not (f.get_extension().to_lower() in DEP_EXTS):
			continue
		for dep: String in ResourceLoader.get_dependencies(f):
			_add_ref(refs, dep, f, file_set)

	# 分类
	var has_unresolvable := false
	for d: Dictionary in dynamic_sources:
		if d.get("unresolvable", false):
			has_unresolvable = true
			break

	var orphan: Array = []
	var referenced: Array = []
	var uncertain: Array = []
	for f: String in analyzable:
		if _is_excluded(f, excludes):
			continue
		var entry := {"path": f, "type": _type_of(f)}
		if refs.has(f):
			var sources: Array = refs[f]
			sources.sort()
			entry["sources"] = sources.slice(0, 10)
			referenced.append(entry)
			continue
		var hit := _find_dynamic_prefix(f, dynamic_sources)
		if not hit.is_empty():
			entry["reason"] = "可能被 \"%s\" 动态加载（静态前缀 %s）" % [hit[0], hit[1]]
			uncertain.append(entry)
		elif has_unresolvable:
			entry["reason"] = "项目存在无法静态解析的动态加载（见 DYNAMIC_SOURCES），无法排除被引用"
			uncertain.append(entry)
		else:
			orphan.append(entry)

	var elapsed := Time.get_ticks_msec() - start_ms
	VinoLogger.info(TAG, "扫描完成：孤立 %d / 已引用 %d / 无法确认 %d（耗时 %d ms）" % [
		orphan.size(), referenced.size(), uncertain.size(), elapsed])

	return {
		"SUMMARY": {
			"total": orphan.size() + referenced.size() + uncertain.size(),
			"orphan_count": orphan.size(),
			"referenced_count": referenced.size(),
			"uncertain_count": uncertain.size(),
			"dynamic_source_count": dynamic_sources.size(),
			"elapsed_ms": elapsed,
		},
		"ORPHAN": orphan,
		"REFERENCED": referenced,
		"UNCERTAIN": uncertain,
		"DYNAMIC_SOURCES": dynamic_sources,
	}


## 递归收集 root 下所有文件（跳过 .godot 目录）。纯只读遍历。
static func _collect_files(root: String) -> PackedStringArray:
	var files := PackedStringArray()
	var pending := [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			VinoLogger.warn(TAG, "无法打开目录: " + dir_path)
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir():
				if name != "." and name != ".." and name != ".godot":
					pending.append(dir_path.path_join(name))
			else:
				files.append(dir_path.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
	return files

## 归一化排除列表：统一为不带结尾 "/" 的 res:// 路径。
static func _normalize_excludes(exclude_paths: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for raw: String in exclude_paths:
		var p := raw.strip_edges().replace("\\", "/")
		while p.ends_with("/"):
			p = p.trim_suffix("/")
		if p.is_empty() or p == "res://":
			continue
		if not p.begins_with("res://"):
			p = "res://" + p
		if not result.has(p):
			result.append(p)
	return result

## file 是否命中排除列表（文件本身或其所在目录被排除）。
static func _is_excluded(file: String, excludes: PackedStringArray) -> bool:
	for ex: String in excludes:
		if file == ex or file.begins_with(ex + "/"):
			return true
	return false

## 读取文本文件；失败返回空串。只读。
static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		VinoLogger.warn(TAG, "无法读取文件: " + path)
		return ""
	return f.get_as_text()

## 构建 uid -> res:// 路径映射：来源为 *.uid 边车文件与 .tscn/.tres 首行资源头。
static func _build_uid_map(all_files: PackedStringArray) -> Dictionary:
	var uid_map := {}
	var header_re := RegEx.create_from_string("uid=\"(uid://[A-Za-z0-9]+)\"")
	for path: String in all_files:
		var ext := path.get_extension().to_lower()
		if ext == "uid":
			var sidecar := FileAccess.open(path, FileAccess.READ)
			if sidecar == null:
				continue
			var uid_str := sidecar.get_line().strip_edges()
			sidecar.close()
			if uid_str.begins_with("uid://"):
				uid_map[uid_str] = path.trim_suffix(".uid")
		elif ext == "tscn" or ext == "tres":
			var res := FileAccess.open(path, FileAccess.READ)
			if res == null:
				continue
			var first_line := res.get_line()
			res.close()
			var m := header_re.search(first_line)
			if m != null:
				uid_map[m.get_string(1)] = path
	return uid_map

## 从文本中收集引用：所有 res:// 路径，以及可经 uid_map 反查的 uid:// 引用。
static func _collect_path_refs(text: String, source: String, refs: Dictionary, uid_map: Dictionary, file_set: Dictionary) -> void:
	var path_re := RegEx.create_from_string("res://[^\\s\"'<>\\[\\]{}()|&?*,;:]+")
	for m: RegExMatch in path_re.search_all(text):
		_add_ref(refs, m.get_string(), source, file_set)
	var uid_re := RegEx.create_from_string("uid://[A-Za-z0-9]+")
	for m: RegExMatch in uid_re.search_all(text):
		var target: String = uid_map.get(m.get_string(), "")
		if not target.is_empty():
			_add_ref(refs, target, source, file_set)

## 收集 .gd 中的 class_name 声明。
static func _collect_class_names(file: String, text: String, class_files: Dictionary) -> void:
	var re := RegEx.create_from_string("(?m)^[ \\t]*class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)")
	for m: RegExMatch in re.search_all(text):
		var cls_name: String = m.get_string(1)
		if not class_files.has(cls_name):
			class_files[cls_name] = file

## 第二遍：任意文本文件中出现 class_name 标识符，即视为该脚本被引用。
## 声明文件自身不计入（那只是声明，不是引用）。
static func _resolve_class_refs(class_files: Dictionary, analyzable: PackedStringArray, refs: Dictionary, file_set: Dictionary) -> void:
	if class_files.is_empty():
		return
	var name_res := {}
	for cls_name: String in class_files:
		name_res[cls_name] = RegEx.create_from_string("\\b%s\\b" % cls_name)
	for f: String in analyzable:
		if not (f.get_extension().to_lower() in TEXT_EXTS):
			continue
		var text := _read_text(f)
		if text.is_empty():
			continue
		for cls_name: String in class_files:
			if class_files[cls_name] == f:
				continue
			if name_res[cls_name].search(text) != null:
				_add_ref(refs, class_files[cls_name], f, file_set)

## 分析 .gd 中的 load()/ResourceLoader.load() 调用：
## - 参数为纯字符串字面量 -> 静态引用（已被 res:// 扫描捕获，忽略）；
## - 参数为 "res://前缀" + 变量 之类的拼接 -> 记录可提取的静态前缀；
## - 参数完全无法静态确定（如 load(path_var)）-> 标记 unresolvable。
static func _analyze_dynamic_loads(file: String, text: String, dynamic_sources: Array) -> void:
	var re := RegEx.create_from_string("(?<![\\w.])(?:ResourceLoader[ \\t]*\\.[ \\t]*)?load[ \\t]*\\(")
	var prefixes := PackedStringArray()
	var unresolvable := false
	for m: RegExMatch in re.search_all(text):
		var open_idx := text.find("(", m.get_start())
		if open_idx == -1:
			continue
		var arg := _extract_call_argument(text, open_idx).strip_edges()
		if arg.is_empty():
			continue
		var literal := _leading_string_literal(arg)
		var rest := arg.substr(arg.length() - literal.length()).strip_edges() if not literal.is_empty() else ""
		if not literal.is_empty() and rest.is_empty():
			continue # 纯字面量，属于静态引用
		var value := literal.substr(1, literal.length() - 2) if not literal.is_empty() else ""
		if value.begins_with("res://"):
			if not prefixes.has(value):
				prefixes.append(value)
		else:
			unresolvable = true
	if prefixes.is_empty() and not unresolvable:
		return
	dynamic_sources.append({
		"file": file,
		"prefixes": prefixes,
		"unresolvable": unresolvable,
	})

## 从 text 的 open_idx（"(" 所在下标）提取配平的调用参数文本；括号不配平时返回剩余全部。
static func _extract_call_argument(text: String, open_idx: int) -> String:
	var depth := 1
	var i := open_idx + 1
	var n := text.length()
	while i < n and depth > 0:
		var c := text[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return text.substr(open_idx + 1, i - open_idx - 1)
		i += 1
	return text.substr(open_idx + 1)

## 若 arg 以字符串字面量开头，返回该字面量原文（含引号）；否则返回 ""。
static func _leading_string_literal(arg: String) -> String:
	var t := arg.strip_edges()
	if t.length() < 2 or (t[0] != "\"" and t[0] != "'"):
		return ""
	var end := t.find(t[0], 1)
	if end < 2:
		return ""
	return t.substr(0, end + 1)

## project.godot 配置分析：main_scene / config/icon / autoload。
## 优先取 ProjectSettings 权威值，再用 project.godot 文本兜底（覆盖 uid:// 写法）。
static func _scan_project_config(refs: Dictionary, uid_map: Dictionary, file_set: Dictionary) -> void:
	_add_ref_value(refs, ProjectSettings.get_setting("run/main_scene", ""), "engine", uid_map, file_set)
	_add_ref_value(refs, ProjectSettings.get_setting("config/icon", ""), "engine", uid_map, file_set)
	for p: Dictionary in ProjectSettings.get_property_list():
		var name := String(p.name)
		if name.begins_with("autoload/"):
			_add_ref_value(refs, ProjectSettings.get_setting(name, ""), "engine", uid_map, file_set)

	var text := _read_text("res://project.godot")
	if text.is_empty():
		return
	for key: String in ["run/main_scene", "config/icon"]:
		var re := RegEx.create_from_string("(?m)^[ \\t]*%s[ \\t]*=[ \\t]*\"([^\"]*)\"" % key)
		for m: RegExMatch in re.search_all(text):
			_add_ref_value(refs, m.get_string(1), "engine", uid_map, file_set)
	var in_autoload := false
	for line: String in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("["):
			in_autoload = t == "[autoload]"
		elif in_autoload and "=" in t:
			_add_ref_value(refs, t.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\""), "engine", uid_map, file_set)

## 解析配置中的资源指向（res:// 路径或可反查的 uid://），记录引用。
static func _add_ref_value(refs: Dictionary, value: Variant, source: String, uid_map: Dictionary, file_set: Dictionary) -> void:
	if value == null:
		return
	var v := str(value).strip_edges().trim_prefix("*")
	if v.begins_with("uid://"):
		v = uid_map.get(v, "")
	if not v.begins_with("res://"):
		return
	_add_ref(refs, v, source, file_set)

## 记录一条引用；仅当目标确实存在于扫描范围内时才记录
##（忽略悬空引用与 .godot 等生成物路径）。
static func _add_ref(refs: Dictionary, target: String, source: String, file_set: Dictionary) -> void:
	var path := _clean_path(target)
	if path.is_empty() or not file_set.has(path):
		return
	if not refs.has(path):
		refs[path] = []
	var sources: Array = refs[path]
	if not sources.has(source):
		sources.append(source)

## 清理从文本提取的路径：去掉首尾空白与句尾标点。
static func _clean_path(raw: String) -> String:
	var p := raw.strip_edges()
	while not p.is_empty() and _TRAILING_CHARS.contains(p[p.length() - 1]):
		p = p.substr(0, p.length() - 1)
	return p

## 若 file 落在某个动态加载的静态前缀之下，返回 [来源文件, 前缀]；否则返回空数组。
static func _find_dynamic_prefix(file: String, dynamic_sources: Array) -> Array:
	for d: Dictionary in dynamic_sources:
		for prefix: String in d.get("prefixes", []):
			if file.begins_with(prefix):
				return [d.get("file", ""), prefix]
	return []

## 扩展名 -> 报告中的资源类型标签。
static func _type_of(file: String) -> String:
	return TYPE_BY_EXT.get(file.get_extension().to_lower(), "other")
