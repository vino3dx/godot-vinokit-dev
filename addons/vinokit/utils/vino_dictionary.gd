class_name VinoDictionary
extends RefCounted
## Dictionary 相关的静态工具函数。

## 深拷贝：Dictionary.duplicate(true) 对 Array/Dictionary 会递归复制，
## 但这里显式命名是为了避免团队里有人以为 duplicate() 默认参数就是深拷贝（默认是浅拷贝）。
static func deep_copy(dict: Dictionary) -> Dictionary:
	return dict.duplicate(true)

## 递归合并 override 到 base 上：两边都是 Dictionary 的键会递归合并，其余直接覆盖。
## 常用于"默认配置 + 用户配置"合并场景，不修改传入的两个字典，返回新字典。
static func merge_deep(base: Dictionary, override: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in override:
		var override_value = override[key]
		if result.has(key) and result[key] is Dictionary and override_value is Dictionary:
			result[key] = merge_deep(result[key], override_value)
		else:
			result[key] = override_value
	return result

## 按 "a.b.c" 这样的点号路径取嵌套值；任意一级不存在就返回 default_value，不会报错。
static func get_path(dict: Dictionary, key_path: String, default_value: Variant = null) -> Variant:
	var current: Variant = dict
	for key in key_path.split("."):
		if typeof(current) != TYPE_DICTIONARY or not current.has(key):
			return default_value
		current = current[key]
	return current

## 反转键值：{a: 1, b: 2} -> {1: a, 2: b}；出现重复 value 时后者覆盖前者。
static func invert(dict: Dictionary) -> Dictionary:
	var result := {}
	for key in dict:
		result[dict[key]] = key
	return result
