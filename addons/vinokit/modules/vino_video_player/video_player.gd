class_name VideoOverlayPlayer
extends Control

## 全屏视频播放组件（单脚本，鼠标 / 触屏双端适配）。
##
## ============================================================
## 用法（在需要弹出播放器的场景里，随便挂一个脚本，比如按钮所在节点的脚本）：
## ============================================================
##
## @export var video_player_scene: PackedScene   # Inspector 里把 video_player.tscn 拖进来
## @export var video_path: String = "E:/Download/Video/1.mp4"
##
## func _on_watch_button_pressed() -> void:
##     var player: VideoOverlayPlayer = video_player_scene.instantiate()
##     get_tree().current_scene.add_child(player)
##     player.open_video(video_path)
##
## 交互规则：
##   - 打开即自动播放，底部工具栏默认不显示
##   - 鼠标：悬停在屏幕底部 hover_zone_height 像素范围内时显示工具栏
##   - 触屏：点一下屏幕任意位置显示工具栏
##   - 显示后 hide_delay 秒无操作（且鼠标不在底部热区）自动隐藏
##   - 点击 BtnExit（或 auto_close_on_finish = true 时播放完毕）后自动 queue_free() 销毁自己

signal closed

@export var seek_step: float = 10.0
## 显示后多少秒无操作自动隐藏工具栏
@export var hide_delay: float = 1.5
## 屏幕底部多少像素范围内，鼠标悬停会触发显示工具栏（建议 >= 工具栏实际高度）
@export var hover_zone_height: float = 120.0
@export var auto_close_on_finish: bool = false
## 也可以直接在 Inspector 里填好路径，实例化后不调用 open_video() 也会自动播放
@export var video_path: String = ""

@onready var _color_rect: ColorRect = $ColorRect
@onready var _video: VideoStreamPlayer = $VideoStreamPlayer
@onready var _bar: PanelContainer = $VideoToolBar
@onready var _btn_pause_and_play: Button = $VideoToolBar/HBoxContainer/BtnPauseAndPlay
@onready var _btn_stop: Button = $VideoToolBar/HBoxContainer/BtnStop
@onready var _btn_rewind: Button = $VideoToolBar/HBoxContainer/BtnRewind
@onready var _btn_forward: Button = $VideoToolBar/HBoxContainer/BtnForward
@onready var _slider_playback: HSlider = $VideoToolBar/HBoxContainer/HSliderPlayback
@onready var _btn_mute: Button = $VideoToolBar/HBoxContainer/BtnMute
@onready var _slider_volume: HSlider = $VideoToolBar/HBoxContainer/HSliderVolume
@onready var _btn_exit: Button = $VideoToolBar/HBoxContainer/BtnExit

var _is_dragging: bool = false
var _is_muted: bool = false
var _volume_before_mute: float = 0.5
var _hide_timer: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS

	_slider_playback.min_value = 0
	_slider_playback.max_value = 100
	_slider_volume.min_value = 0
	_slider_volume.max_value = 100
	_slider_volume.value = _video.volume * 100.0

	# 打开即自动播放，工具栏默认不显示
	_bar.visible = false

	_connect_signals()

	if not video_path.is_empty():
		_load_video(video_path)
		_start_video()


func _process(delta: float) -> void:
	# 更新进度条
	if _video.is_playing() and not _video.paused and not _is_dragging:
		var length := _video.get_stream_length()
		if length > 0:
			_slider_playback.value = (_video.stream_position / length) * 100.0

	# 桌面端：鼠标悬停在底部热区内，持续保持显示
	var mouse_pos := get_local_mouse_position()
	var in_hover_zone := mouse_pos.y >= size.y - hover_zone_height \
		and mouse_pos.y <= size.y and mouse_pos.x >= 0 and mouse_pos.x <= size.x
	if in_hover_zone:
		_show_controls()

	# 自动隐藏
	if _bar.visible and not in_hover_zone:
		_hide_timer += delta
		if _hide_timer >= hide_delay:
			_bar.visible = false


func _input(event: InputEvent) -> void:
	# 触屏端：点一下屏幕任意位置就显示工具栏
	if event is InputEventScreenTouch and event.pressed:
		_show_controls()


func _connect_signals() -> void:
	_video.finished.connect(_on_video_finished)
	_slider_playback.drag_started.connect(_on_slider_drag_started)
	_slider_playback.drag_ended.connect(_on_slider_drag_ended)
	_slider_playback.value_changed.connect(_on_playback_value_changed)
	_btn_pause_and_play.pressed.connect(_on_btn_pause_and_play_pressed)
	_btn_stop.pressed.connect(_on_btn_stop_pressed)
	_btn_rewind.pressed.connect(_seek_relative.bind(-seek_step))
	_btn_forward.pressed.connect(_seek_relative.bind(seek_step))
	_btn_mute.pressed.connect(_on_btn_mute_pressed)
	_slider_volume.value_changed.connect(_on_volume_value_changed)
	_btn_exit.pressed.connect(close)


## 外部调用入口：设置视频路径并开始播放。
## 无论组件是否已经进入场景树都可以安全调用：
##   - 已经在树里：立即加载并播放
##   - 还没进树（instantiate() 之后、add_child() 之前调用）：先记下路径，_ready() 时自动播放
func open_video(path: String) -> void:
	video_path = path
	if is_inside_tree():
		_load_video(video_path)
		_start_video()


func _load_video(path: String) -> void:
	if path.is_empty():
		push_error("VideoOverlayPlayer: video_path 为空")
		return

	# 1. 规范化路径分隔符（防止 Windows 下斜杠与反斜杠混用问题）
	var target_path := path.simplify_path()

	# 2. 判断是否为绝对路径（支持 Windows 盘符如 "E:/" 或 Linux/Mac 的根路径 "/"）
	var is_absolute := target_path.is_absolute_path() or (OS.get_name() == "Windows" and target_path.length() >= 2 and target_path[1] == ":")

	# 3. 如果是相对路径，自动拼接到 exe/运行文件 同级目录下
	if not is_absolute:
		var base_dir := OS.get_executable_path().get_base_dir()
		target_path = base_dir.path_join(target_path)

	# 4. 检查最终文件是否存在
	if not FileAccess.file_exists(target_path):
		push_error("VideoOverlayPlayer: 视频文件未找到: %s" % target_path)
		return

	if not ClassDB.class_exists("FFmpegVideoStream"):
		push_error("VideoOverlayPlayer: FFmpeg 插件未启用")
		return

	# 5. FFmpeg 插件加载路径处理
	var stream_ff = ClassDB.instantiate("FFmpegVideoStream")
	# 统一转换为系统绝对路径，确保原生 C++ 插件能正确读取
	stream_ff.file = ProjectSettings.globalize_path(target_path)
	_video.stream = stream_ff


func _start_video() -> void:
	if _video.stream == null:
		return
	# FFmpeg 插件防卡死重置逻辑：重新赋值流以刷新解码器
	var temp_stream = _video.stream
	_video.stream = null
	_video.stream = temp_stream
	_video.stream_position = 0.0
	_video.paused = false
	_video.play()


## 对外暴露的关闭入口：BtnExit、外部代码都可以调用它来关闭组件。
func close() -> void:
	closed.emit()
	queue_free()


func _on_btn_pause_and_play_pressed() -> void:
	if _video.stream == null:
		return
	if _video.is_playing():
		_video.paused = not _video.paused
	else:
		_video.play()
	_show_controls()


func _on_btn_stop_pressed() -> void:
	if _video.stream == null:
		return
	_video.stop()
	_video.stream_position = 0.0
	_video.paused = false
	# 同样通过重新赋值 stream 刷新 FFmpeg 解码上下文
	var temp_stream = _video.stream
	_video.stream = null
	_video.stream = temp_stream
	_slider_playback.value = 0
	_show_controls()


func _on_video_finished() -> void:
	_slider_playback.value = 0
	_show_controls()
	if auto_close_on_finish:
		close()


func _seek_relative(seconds: float) -> void:
	if _video.stream == null:
		return
	var length := _video.get_stream_length()
	_video.stream_position = clampf(_video.stream_position + seconds, 0.0, length)
	_show_controls()


func _on_playback_value_changed(value: float) -> void:
	if _video.stream != null and _is_dragging:
		var length := _video.get_stream_length()
		if length > 0:
			_video.stream_position = (value / 100.0) * length


func _on_slider_drag_started() -> void:
	_is_dragging = true
	_show_controls()


func _on_slider_drag_ended(_value_changed: bool) -> void:
	_is_dragging = false
	_show_controls()


func _on_volume_value_changed(value: float) -> void:
	_video.volume = value / 100.0
	if _is_muted:
		_is_muted = false
	_show_controls()


func _on_btn_mute_pressed() -> void:
	_is_muted = not _is_muted
	if _is_muted:
		_volume_before_mute = _video.volume
		_video.volume = 0.0
	else:
		_video.volume = _volume_before_mute
		_slider_volume.value = _volume_before_mute * 100.0
	_show_controls()


func _show_controls() -> void:
	_hide_timer = 0.0
	_bar.visible = true
