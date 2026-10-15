extends Node

# 你的场景脚本
func _ready() -> void:
	$TextureRect.texture = VinoAssets.load_texture("测试图片 (1).jpg")
	$TextureRect2.texture = VinoAssets.load_texture("测试图片 (2).jpg")
	$TextureRect3.texture = VinoAssets.load_texture("测试图片 (3).jpg")
	
	$AudioStreamPlayer.stream = VinoAssets.load_audio("测试音频.mp3")
	
	$VideoStreamPlayer.stream = VinoAssets.load_video("测试视频.mp4")

func _on_button_pressed() -> void:
	$AudioStreamPlayer.play()
	
func _on_button_2_pressed() -> void:
	$VideoStreamPlayer.play()
