class_name VinoArray
extends RefCounted
## 数组相关的静态工具函数。

## 安全取值：index 越界时返回 default_value 而不是报错，适合"配置项不确定长度"的场景。
static func get_or_default(array: Array, index: int, default_value: Variant = null) -> Variant:
	if index < 0 or index >= array.size():
		return default_value
	return array[index]

## 保序去重（Array.duplicate 不会去重，Dictionary 去重会打乱顺序，这里两者都保留）。
static func unique(array: Array) -> Array:
	var seen := {}
	var result := []
	for item in array:
		if not seen.has(item):
			seen[item] = true
			result.append(item)
	return result

## Fisher-Yates 洗牌，返回新数组（不修改原数组）。
static func shuffled(array: Array) -> Array:
	var result := array.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result

## 随机取一个元素；数组为空时返回 default_value。
static func random_pick(array: Array, default_value: Variant = null) -> Variant:
	if array.is_empty():
		return default_value
	return array[randi() % array.size()]

## 把数组按 chunk_size 切成若干个子数组，最后一组可能不满。
static func chunk(array: Array, chunk_size: int) -> Array:
	if chunk_size <= 0:
		return [array]
	var result := []
	var i := 0
	while i < array.size():
		result.append(array.slice(i, min(i + chunk_size, array.size())))
		i += chunk_size
	return result

## 找到第一个满足 predicate(item) 的元素；predicate 是 Callable，找不到返回 default_value。
static func find_first(array: Array, predicate: Callable, default_value: Variant = null) -> Variant:
	for item in array:
		if predicate.call(item):
			return item
	return default_value
