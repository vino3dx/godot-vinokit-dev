extends Control

@onready var file_dialog: FileDialog = $FileDialog
@onready var color_picker_button: ColorPickerButton = $ColorPickerButton
@onready var h_slider: HSlider = $HSlider
@onready var texture_rect: TextureRect = $TextureRect

# 用于模式标记：是在打开文件，还是在保存文件
enum FileMode { OPEN_IMAGE, SAVE_IMAGE }
var current_file_mode: FileMode = FileMode.OPEN_IMAGE

var shader_mat: ShaderMaterial

func _ready() -> void:
	# 1. 确保 ShaderMaterial 存在
	if texture_rect.material is ShaderMaterial:
		shader_mat = texture_rect.material as ShaderMaterial
	else:
		push_error("TextureRect 上没有绑定 ShaderMaterial！")
		return

	# 2. 绑定 UI 事件
	color_picker_button.color_changed.connect(_on_color_changed)
	h_slider.value_changed.connect(_on_threshold_changed)
	
	# 3. 绑定 FileDialog 回调
	file_dialog.file_selected.connect(_on_file_selected)
	
	# 设置 FileDialog 初始过滤规则
	file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp ; 支持的图片类型"]

# --- 按钮与控件回调 ---

func _on_color_changed(new_color: Color) -> void:
	if shader_mat:
		shader_mat.set_shader_parameter("key_color", new_color)

func _on_threshold_changed(new_value: float) -> void:
	if shader_mat:
		# 假设 Slider 的范围是 0~100，转成 Shader 需要的 0.0~1.0
		var normalized_val = new_value / h_slider.max_value
		shader_mat.set_shader_parameter("threshold", normalized_val)

# 触发打开图片弹窗（绑定给“打开图片”按钮）
func _on_open_button_pressed() -> void:
	current_file_mode = FileMode.OPEN_IMAGE
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_clamped(Vector2i(800, 600))

# 触发保存图片弹窗（绑定给“保存图片”按钮）
func _on_save_button_pressed() -> void:
	if texture_rect.texture == null:
		push_warning("没有可保存的图片！")
		return
	current_file_mode = FileMode.SAVE_IMAGE
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.popup_centered_clamped(Vector2i(800, 600))

# --- 文件打开与保存核心逻辑 ---

func _on_file_selected(path: String) -> void:
	match current_file_mode:
		FileMode.OPEN_IMAGE:
			_load_image_from_path(path)
		FileMode.SAVE_IMAGE:
			_save_processed_image(path)

# 加载本地图片并显示在 TextureRect
func _load_image_from_path(path: String) -> void:
	var img = Image.load_from_file(path)
	if img:
		var tex = ImageTexture.create_from_image(img)
		texture_rect.texture = tex
	else:
		push_error("图片加载失败：" + path)

# 提取应用 Shader 后的图片像素并保存为 PNG
func _save_processed_image(output_path: String) -> void:
	var orig_texture = texture_rect.texture
	if not orig_texture:
		return

	# 使用 SubViewport 在后台无干扰渲染抠图结果
	var vp = SubViewport.new()
	vp.size = orig_texture.get_size()
	vp.transparent_bg = true # 开启透明背景
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	
	# 创建临时 Sprite2D 应用相同材质
	var sprite = Sprite2D.new()
	sprite.texture = orig_texture
	sprite.material = shader_mat
	sprite.centered = false
	
	vp.add_child(sprite)
	add_child(vp)
	
	# 等待一帧让 GPU 完成渲染
	await RenderingServer.frame_post_draw
	
	# 获取渲染后的像素并保存
	var result_img = vp.get_texture().get_image()
	result_img.save_png(output_path)
	
	# 清理临时节点
	vp.queue_free()
	print("保存成功：" + output_path)
