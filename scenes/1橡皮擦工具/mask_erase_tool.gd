extends TextureRect
class_name MaskEraseTool

signal erase_changed(percent:float) ## 信号：当擦除发送变化时
signal erase_completed ## 信号：当擦除完成时

# 软刷 / 铲子
enum EraseShape {
	BRUSH,
	SHOVEL
}

@export_group("工具设置")
@export var erase_shape:EraseShape = EraseShape.BRUSH ## 笔刷类型选择 三角形/圆形
@export var brush_size:int = 50 ## 笔刷半径
@export var enable_erase := true ## 启用笔刷

@export_group("鼠标指针")
@export var cursor_texture:Texture2D


var mask_image:Image
var mask_texture:ImageTexture
var shader_material:ShaderMaterial
var completed := false


func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	_create_mask()
	_create_shader()


func _gui_input(event):
	if not enable_erase:
		return

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			erase_at(event.position)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			erase_at(event.position)

	elif event is InputEventScreenTouch:
		if event.pressed:
			erase_at(event.position)

	elif event is InputEventScreenDrag:
		erase_at(event.position)


# 创建遮罩
func _create_mask():
	if texture == null:
		return

	var texture_size = texture.get_size()

	mask_image = Image.create(
		int(texture_size.x),
		int(texture_size.y),
		false,
		Image.FORMAT_RF
	)

	mask_image.fill(Color.WHITE)

	mask_texture = ImageTexture.create_from_image(mask_image)


# 创建着色器
func _create_shader():
	var shader = Shader.new()

	shader.code = """
shader_type canvas_item;

uniform sampler2D mask_texture;

void fragment()
{
	vec4 color = texture(TEXTURE, UV);
	float mask = texture(mask_texture, UV).r;
	color.a *= mask;
	COLOR = color;
}
"""

	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	material = shader_material

	shader_material.set_shader_parameter(
		"mask_texture",
		mask_texture
	)


# 擦除时的位置
func erase_at(pos:Vector2):
	if mask_image == null:
		return

	var uv = Vector2(
		pos.x / size.x,
		pos.y / size.y
	)

	var image_pos = Vector2(
		uv.x * mask_image.get_width(),
		uv.y * mask_image.get_height()
	)

	match erase_shape:
		EraseShape.BRUSH:
			erase_circle(image_pos)

		EraseShape.SHOVEL:
			erase_triangle(image_pos)

	mask_texture.update(mask_image)
	calculate_progress()


# 圆形笔刷
func erase_circle(pos:Vector2):
	var radius = brush_size

	for x in range(-radius,radius):
		for y in range(-radius,radius):

			if x*x+y*y > radius*radius:
				continue

			var px = int(pos.x+x)
			var py = int(pos.y+y)

			if px < 0 or py < 0:
				continue

			if px >= mask_image.get_width():
				continue

			if py >= mask_image.get_height():
				continue

			mask_image.set_pixel(
				px,
				py,
				Color.BLACK
			)


# 三角形笔刷
func erase_triangle(pos:Vector2):
	var width = brush_size * 2
	var height = brush_size * 2

	var half_w = width / 2.0
	var half_h = height / 2.0

	for x in range(-int(half_w),int(half_w)):
		for y in range(-int(half_h),int(half_h)):
			var rate = float(y + half_h) / height
			var max_width = width * rate

			if abs(x) > max_width / 2.0:
				continue

			set_mask_pixel(
				int(pos.x+x),
				int(pos.y+y)
			)


# 设置像素遮罩
func set_mask_pixel(x:int,y:int):
	if x < 0 or y < 0:
		return

	if x >= mask_image.get_width() or y >= mask_image.get_height():
		return

	mask_image.set_pixel(
		x,
		y,
		Color.BLACK
	)


# 计算完成进度 0-1
func calculate_progress():
	var count := 0
	var total := 0

	for x in range(0,mask_image.get_width(),10):
		for y in range(0,mask_image.get_height(),10):
			total += 1

			if mask_image.get_pixel(x,y).r < 0.5:
				count += 1

	var percent = float(count) / total

	erase_changed.emit(percent)

	if percent >= 0.6 and not completed:
		completed = true
		erase_completed.emit()


# 启用工具
func enable_tool():
	enable_erase = true

	#if cursor_texture:
		#CursorManager.set_cursor(cursor_texture)


# 禁用工具
func disable_tool():
	enable_erase = false
	
	#CursorManager.reset_cursor()
