class_name VinoNode
extends RefCounted
## Node 树相关的静态工具函数。

## 安全获取子节点：路径不存在或类型不匹配时返回 null 而不是报错崩溃。
## 用法：VinoNode.get_typed(self, "UI/ConfirmButton", Button)
static func get_typed(root: Node, path: NodePath, expected_type: Variant = null) -> Node:
	if not root.has_node(path):
		VinoLogger.warn("VinoNode", "节点不存在: %s" % path)
		return null
	var node := root.get_node(path)
	if expected_type != null and not is_instance_of(node, expected_type):
		VinoLogger.warn("VinoNode", "节点类型不匹配: %s (期望 %s)" % [path, expected_type])
		return null
	return node

## 递归向上查找第一个匹配 predicate(node) 的祖先节点；找不到返回 null。
static func find_ancestor(node: Node, predicate: Callable) -> Node:
	var current := node.get_parent()
	while current != null:
		if predicate.call(current):
			return current
		current = current.get_parent()
	return null

## 递归查找所有满足 predicate(node) 的后代节点（深度优先）。
static func find_all_descendants(root: Node, predicate: Callable) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if predicate.call(child):
			result.append(child)
		result.append_array(find_all_descendants(child, predicate))
	return result

## 一次性断开某个信号上挂的所有连接，常用于节点复用/对象池场景清理旧回调。
static func disconnect_all(emitter: Object, signal_name: StringName) -> void:
	for connection in emitter.get_signal_connection_list(signal_name):
		emitter.disconnect(signal_name, connection["callable"])

## 安全 queue_free：对已经是 null 或已被标记删除的节点调用不会报错。
static func safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()
