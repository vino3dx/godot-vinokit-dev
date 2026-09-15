class_name VinoLogger
extends RefCounted
## 统一日志输出。原插件里各模块直接散落 print()，正式环境下无法整体关闭；
## 现集中到这里，由 VinoConfig 的 debug_print 开关统一控制普通信息的输出，
## 警告 / 错误始终输出（因为它们本身就是需要被看见的问题）。

static var debug_enabled: bool = true

static func info(tag: String, msg: String) -> void:
	if debug_enabled:
		print("[%s] %s" % [tag, msg])

static func warn(tag: String, msg: String) -> void:
	push_warning("[%s] %s" % [tag, msg])

static func error(tag: String, msg: String) -> void:
	push_error("[%s] %s" % [tag, msg])
