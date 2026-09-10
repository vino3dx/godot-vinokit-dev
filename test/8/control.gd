extends Control

class Player:
	func _prt(txt: String ):
		print(str(txt))


func _ready() -> void:
	var sd = Player.new()
	
	sd._prt("这是测试文字")
