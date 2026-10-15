extends Node # 或者 Control

# 如果需要调用 VinoOrphanScanner，直接用类名调用其静态方法即可
func _ready() -> void:
	var result = VinoOrphanScanner.scan_project([".godot"])
	print("扫描完成，孤立资源数: ", result["SUMMARY"]["orphan_count"])
