extends Control
@onready var texture_rect: TextureRect = $TextureRect
var tex_path: String

func _ready() -> void:
	VinoConfig.bind(self)
	
	print("tex_path = ", tex_path)
	var img := Image.load_from_file(tex_path)
	
	if img:
		texture_rect.texture = ImageTexture.create_from_image(img)
