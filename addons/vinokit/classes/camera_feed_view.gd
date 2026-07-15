extends Control
class_name CameraFeedView
## CameraFeedView：用于在UI中显示摄像头画面
## 通过 CameraServer 获取摄像头 Feed，并用 CameraTexture 实时渲染
## 适用于摄像头预览、AR/视觉识别调试、视频流UI显示

var camera_texture: CameraTexture ## 📷 摄像头纹理（用于渲染画面）
var camera_extension: CameraServerExtension ## 📡 CameraServer 扩展（权限 / feed 管理）

# === 初始化摄像头系统 ===
func _ready() -> void:
	# 第一步：开启摄像头监控（允许枚举设备）
	CameraServer.set_monitoring_feeds(true)

	# 第二步：实例化扩展（内部会同步设备列表）
	camera_extension = CameraServerExtension.new() 

	# 第三步：权限检查
	if camera_extension.permission_granted():
		_start_camera()
	else:
		camera_extension.permission_result.connect(_on_permission_result)
		camera_extension.request_permission()


# === 摄像头权限回调 ===
func _on_permission_result(granted: bool) -> void:
	if granted:
		_start_camera()
	else:
		push_error("摄像头权限被拒绝")


# === 启动摄像头并绑定 CameraTexture ===
func _start_camera() -> void:
	print("当前 feeds: ", CameraServer.feeds())

	if CameraServer.get_feed_count() == 0:
		push_error("没有检测到任何摄像头 Feed")
		return

	# ⚠ 不使用类型注解，避免被强转为 CameraFeed 导致 API 受限
	var feed = CameraServer.get_feed(0)
	
	print("找到 Feed: ", feed.get_name(), " id=", feed.get_id())
	print("支持格式: ", feed.get_formats())
	
	# 激活摄像头
	feed.set_active(true) 
	
	# 创建 CameraTexture 并绑定 feed
	camera_texture = CameraTexture.new()
	camera_texture.camera_feed_id = feed.get_id()
	camera_texture.which_feed = CameraServer.FEED_RGBA_IMAGE


# === 每帧刷新画面 ===
func _process(_delta: float) -> void:
	if camera_texture:
		queue_redraw()


# === UI绘制摄像头的画面 ===
func _draw() -> void:
	if camera_texture and camera_texture.get_width() > 0:
		draw_texture_rect(camera_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)
