extends Control

@onready var file_dialog: FileDialog = $FileDialog
@onready var color_picker_button: ColorPickerButton = $ColorPickerButton
@onready var h_slider: HSlider = $HSlider
@onready var texture_rect: TextureRect = $TextureRect

# 文件操作模式
enum FileMode { OPEN_IMAGE, SAVE_IMAGE }
var current_file_mode := FileMode.OPEN_IMAGE
var shader_mat: ShaderMaterial

# 初始化
func _ready() -> void:
	shader_mat = texture_rect.material as ShaderMaterial
	if shader_mat == null:
		push_error("TextureRect没有ShaderMaterial")
		return

	color_picker_button.color_changed.connect(_on_color_changed)
	h_slider.value_changed.connect(_on_threshold_changed)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp;图片文件"]

# 修改抠图颜色
func _on_color_changed(color: Color) -> void:
	shader_mat.set_shader_parameter("key_color", color)

# 修改抠图阈值
func _on_threshold_changed(value: float) -> void:
	shader_mat.set_shader_parameter("threshold", value / h_slider.max_value)

# 打开图片
func _on_open_button_pressed() -> void:
	current_file_mode = FileMode.OPEN_IMAGE
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered(Vector2i(800, 600))

# 保存图片
func _on_save_button_pressed() -> void:
	if texture_rect.texture == null:
		push_warning("没有可保存的图片")
		return

	current_file_mode = FileMode.SAVE_IMAGE
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.popup_centered(Vector2i(800, 600))

# 处理文件选择
func _on_file_selected(path: String) -> void:
	match current_file_mode:
		FileMode.OPEN_IMAGE:
			_load_image(path)
		FileMode.SAVE_IMAGE:
			_save_image(path)

# 加载图片
func _load_image(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null:
		push_error("图片加载失败：" + path)
		return

	texture_rect.texture = ImageTexture.create_from_image(image)

# 渲染并保存图片
func _save_image(path: String) -> void:
	if texture_rect.texture == null:
		return

	var viewport := SubViewport.new()
	viewport.size = texture_rect.texture.get_size()
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var rect := TextureRect.new()
	rect.texture = texture_rect.texture
	rect.material = shader_mat.duplicate()
	rect.size = viewport.size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE

	viewport.add_child(rect)
	add_child(viewport)

	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	if image:
		image.save_png(path)
		print("保存成功：" + path)
	else:
		push_error("渲染结果获取失败")

	viewport.queue_free()
