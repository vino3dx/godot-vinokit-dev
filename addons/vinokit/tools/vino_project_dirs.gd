@tool
class_name VinoProjectDirs
extends RefCounted
## VinoProjectDirs：项目标准目录结构维护（一键创建标准目录 + 清理空目录）。
##
## 功能一 create_standard_dirs()：按 Godot 社区通用习惯在 res:// 下创建标准目录
## （scenes/ scripts/ assets/... 等）。逐项检查目录是否已存在，已存在则跳过，
## 只新增缺失目录，不覆盖、不删除、不修改任何既有文件。
##
## 功能二 clean_empty_dirs()：清理 res:// 下的完全空目录。
## 历史教训：早期版本在递归遍历过程中直接调用 DirAccess.remove_absolute() 删除目录，
## 属于“边遍历边删除”，导致 Godot 编辑器内存访问违例、直接闪退崩溃。
## 现改为严格的“两阶段法”：
## - 阶段一（只读收集）：Post-order（先子目录、后父目录）递归遍历，仅收集
##   “绝对空”目录的路径；每个 DirAccess 句柄即开即关（list_dir_end() 之后
##   显式置空引用，确保底层 C++ 对象立即销毁），遍历全程不执行任何删除；
## - 阶段二（集中删除）：所有遍历结束、全部 DirAccess 句柄释放之后，
##   才按收集顺序（子目录在前）统一执行删除，且删除前对每个目录二次复核仍为空。
##
## dry_run 模式：只执行阶段一并打印将被删除的目录，不执行阶段二（用于排查闪退点）。
##
## 四道安全防线（缺一不可）：
## 1. 非空判定：目录内包含任何文件（含 .import / .uid / .gdignore 等边车与
##    隐藏文件）即视为有效目录，严禁删除；
## 2. 排除保护：.godot 引擎缓存目录与 addons 插件目录（按目录名匹配，任意层级）
##    不进入、不遍历、不删除；其父目录因“存在未清理子树”同样受到保护；
## 3. 根目录保护：传入的 root（默认 res://）自身永不删除；
## 4. 深度防护：递归深度超过 MAX_SCAN_DEPTH 立即停止深入，防止异常循环打爆调用栈。

const TAG := "VinoProjectDirs"

## 标准项目目录结构（res:// 相对路径，符合 Godot 社区通用习惯）
const STANDARD_DIRS := [
	"scenes",
	"scripts",
	"assets/images",
	"assets/audio",
	"assets/fonts",
	"assets/materials",
	"components",
	"addons",
]

## 清理空目录时按目录名匹配的强制排除项（任意层级均不进入、不删除）
const CLEAN_EXCLUDE_NAMES := [".godot", "addons"]

## 阶段一递归遍历的最大深度（root 记为第 1 层），防止异常循环打爆调用栈
const MAX_SCAN_DEPTH := 32


## 在 root（默认 res://）下创建标准项目目录。
## 返回 {"created": [...], "skipped": [...], "failed": [...]}，路径均为 res:// 相对路径。
## 非破坏性操作：只创建缺失目录，单项失败不影响其他目录。
static func create_standard_dirs(root := "res://") -> Dictionary:
	var created := PackedStringArray()
	var skipped := PackedStringArray()
	var failed := PackedStringArray()

	for rel: String in STANDARD_DIRS:
		var abs_path: String = root.path_join(rel)
		# 已存在的目录直接跳过，避免重复创建或触碰既有文件
		if DirAccess.dir_exists_absolute(abs_path):
			skipped.append(rel)
			continue
		var err: int = DirAccess.make_dir_recursive_absolute(abs_path)
		if err == OK:
			created.append(rel)
			VinoLogger.info(TAG, "已创建目录: " + rel)
		else:
			failed.append(rel)
			VinoLogger.warn(TAG, "创建目录失败 (%d): %s" % [err, abs_path])

	return {
		"created": created,
		"skipped": skipped,
		"failed": failed,
	}


## 递归清理 root（默认 res://）下所有完全空的目录（两阶段法，杜绝边遍历边删除）。
## dry_run 为 true 时只扫描并打印将被删除的目录，不执行任何删除。
## 返回 {"scanned": int, "removed": [...], "would_remove": [...], "skipped": [...], "failed": [...], "dry_run": bool}，
## 路径均为 res:// 相对路径；skipped 为被排除保护的目录；would_remove 仅 dry_run 时有内容。
static func clean_empty_dirs(root := "res://", dry_run := false) -> Dictionary:
	var normalized_root := _normalize_root(root)

	# 阶段一：只读遍历，收集所有“绝对空”目录（全程不执行任何删除操作）
	var scan_result := {
		"scanned": 0,
		"empty_dirs": PackedStringArray(),
		"skipped": PackedStringArray(),
	}
	_collect_empty_dirs(normalized_root, normalized_root, 1, scan_result)

	var delete_result := {
		"removed": PackedStringArray(),
		"failed": PackedStringArray(),
	}
	var would_remove := PackedStringArray()

	if dry_run:
		# 试运行：只打印，不删除
		for dir_path: String in scan_result["empty_dirs"]:
			would_remove.append(_to_relative(dir_path))
			VinoLogger.info(TAG, "[dry_run] 将删除: " + _to_relative(dir_path))
	else:
		# 阶段二：遍历全部结束、DirAccess 句柄已全部释放后，集中执行删除
		_delete_empty_dirs(scan_result["empty_dirs"], delete_result)

	VinoLogger.info(TAG, "空目录清理%s完成：扫描 %d / %s %d / 排除 %d / 失败 %d" % [
		"(试运行)" if dry_run else "", scan_result["scanned"],
		"待删除" if dry_run else "删除",
		would_remove.size() if dry_run else delete_result["removed"].size(),
		scan_result["skipped"].size(), delete_result["failed"].size()])

	return {
		"scanned": scan_result["scanned"],
		"removed": delete_result["removed"],
		"would_remove": would_remove,
		"skipped": scan_result["skipped"],
		"failed": delete_result["failed"],
		"dry_run": dry_run,
	}


## 阶段一：只读递归收集“绝对空”目录（Post-order：先子目录、后父目录，
## 保证收集顺序即为安全的删除顺序）。
## dir_path 遍历后为空返回 true，否则返回 false（非空 / 排除 / 异常 / 超深）。
static func _collect_empty_dirs(root: String, dir_path: String, depth: int, result: Dictionary) -> bool:
	# 排除目录：不进入、不遍历，按“非空”返回以保护其父目录
	if _is_clean_excluded(dir_path):
		result["skipped"].append(_to_relative(dir_path))
		return false

	# 深度防护：超过上限立即停止深入，按“非空”处理
	if depth > MAX_SCAN_DEPTH:
		VinoLogger.warn(TAG, "目录深度超过 %d 层，停止深入遍历: %s" % [MAX_SCAN_DEPTH, dir_path])
		return false

	var dir := DirAccess.open(dir_path)
	if dir == null:
		VinoLogger.warn(TAG, "无法打开目录: " + dir_path)
		return false
	result["scanned"] += 1

	# 一次性读完整目录条目后立即关闭句柄：先记录、后递归、最后才可能标记删除，
	# 全程（含递归期间）不持有任何打开中的遍历句柄
	var has_file := false
	var sub_dirs := PackedStringArray()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			if dir.current_is_dir():
				sub_dirs.append(dir_path.path_join(name))
			else:
				has_file = true
		name = dir.get_next()
	dir.list_dir_end()
	# 显式置空引用，确保底层 C++ DirAccess 对象立即销毁、句柄彻底释放
	dir = null

	# 先递归子目录（严格的 Post-order：子目录全部处理完，才决定自身的命运）。
	# 注意：无论自身是否含文件，都必须先深入子目录，否则含文件的父目录会让整棵子树被跳过
	var all_sub_empty := true
	for sub: String in sub_dirs:
		if not _collect_empty_dirs(root, sub, depth + 1, result):
			all_sub_empty = false

	# 自身判定一：含任何文件（含 .import / .uid / .gdignore 边车与隐藏文件）
	# 即视为有效目录，不可删除（但其子目录已在上面独立处理完毕）
	if has_file:
		return false

	# 自身判定二：存在未清理的非空子树，不可删除
	if not all_sub_empty:
		return false

	# 根目录自身永不删除
	if dir_path == root:
		return true

	result["empty_dirs"].append(dir_path)
	return true


## 阶段二：集中删除阶段一收集到的空目录（收集顺序为子目录在前、父目录在后）。
## 删除前二次复核目录仍为绝对空，防止遍历期间文件系统发生并发变化。
static func _delete_empty_dirs(empty_dirs: PackedStringArray, result: Dictionary) -> void:
	for dir_path: String in empty_dirs:
		# 二次校验：确认仍为空才执行删除；删除动作本身不持有任何 DirAccess 句柄
		if not _is_dir_still_empty(dir_path):
			VinoLogger.info(TAG, "目录在删除前已非空或已不存在，跳过: " + dir_path)
			continue
		var err: int = DirAccess.remove_absolute(dir_path)
		if err == OK:
			result["removed"].append(_to_relative(dir_path))
			VinoLogger.info(TAG, "已删除空目录: " + _to_relative(dir_path))
		else:
			result["failed"].append(_to_relative(dir_path))
			VinoLogger.warn(TAG, "删除空目录失败 (%d): %s" % [err, dir_path])


## 二次复核目录是否仍为“绝对空”（不含任何条目，含隐藏文件）；句柄即开即关
static func _is_dir_still_empty(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	var is_empty := true
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			is_empty = false
			break
		name = dir.get_next()
	dir.list_dir_end()
	dir = null
	return is_empty


## 归一化 root：去掉结尾 "/"（保留 res:// 本身）
static func _normalize_root(root: String) -> String:
	if root.ends_with("/") and root != "res://":
		return root.trim_suffix("/")
	return root


## 目录路径中任一层级命中排除名即视为排除（.godot 引擎缓存 / addons 插件目录）
static func _is_clean_excluded(dir_path: String) -> bool:
	var rel := _to_relative(dir_path)
	if rel.is_empty():
		return false
	var parts := rel.split("/")
	for part: String in parts:
		if CLEAN_EXCLUDE_NAMES.has(part):
			return true
	return false


## 将 res:// 绝对路径转换为不带 res:// 前缀的相对路径；非 res:// 路径原样返回
static func _to_relative(path: String) -> String:
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	return path