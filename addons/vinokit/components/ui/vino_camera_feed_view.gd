class_name CameraFeedView
extends Control
## CameraFeedView - 在 UI 中显示摄像头实时画面
##
## 通过 CameraServer 获取 Feed，并用 CameraTexture 渲染。
## 若项目额外集成了名为 CameraServerExtension 的权限管理 GDExtension（常见于移动端
## 摄像头权限申请场景），会先走它的权限流程；未集成时（如桌面端）直接尝试打开摄像头。

const TAG := "CameraFeedView"

var camera_texture: CameraTexture
var _camera_extension: Object = null

func _ready() -> void:
	CameraServer.set_monitoring_feeds(true)

	if ClassDB.class_exists("CameraServerExtension"):
		_camera_extension = ClassDB.instantiate("CameraServerExtension")
		if _camera_extension.permission_granted():
			_start_camera()
		else:
			_camera_extension.permission_result.connect(_on_permission_result)
			_camera_extension.request_permission()
	else:
		_start_camera()

func _on_permission_result(granted: bool) -> void:
	if granted:
		_start_camera()
	else:
		VinoLogger.error(TAG, "摄像头权限被拒绝")

func _start_camera() -> void:
	if CameraServer.get_feed_count() == 0:
		VinoLogger.error(TAG, "没有检测到任何摄像头 Feed")
		return

	var feed := CameraServer.get_feed(0)
	VinoLogger.info(TAG, "找到 Feed: %s id=%d" % [feed.get_name(), feed.get_id()])
	feed.set_active(true)

	camera_texture = CameraTexture.new()
	camera_texture.camera_feed_id = feed.get_id()
	camera_texture.which_feed = CameraServer.FEED_RGBA_IMAGE

func _process(_delta: float) -> void:
	if camera_texture:
		queue_redraw()

func _draw() -> void:
	if camera_texture and camera_texture.get_width() > 0:
		draw_texture_rect(camera_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)
