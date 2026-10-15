extends Node

var a := 100
var b := "这是测试配置文件"

var udp := "192.168.1.126"

func _ready() -> void:

	# 2. 绑定注入完成后，变量已被替换为 config.ini 中的数值
	print(a, "\n", b, udp)
