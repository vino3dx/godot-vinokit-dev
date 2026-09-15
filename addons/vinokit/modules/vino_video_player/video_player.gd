class_name VideoOverlayPlayer
extends Control
## 视频播放组件（单脚本，鼠标 / 触屏双端适配）。
##
## ============================================================
## 用法（在需要弹出播放器的场景里挂一个脚本，比如按钮所在节点）：
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
## 路径规则（单文件 / 文件夹通用）：
##   - 传绝对路径：直接使用
##   - 传相对路径：自动拼接到 exe（打包后运行文件）所在目录下，
##     例如打包结构为 D:/Builds/项目名/项目.exe + assets/part3/group1/xxx.mp4，
##     则只需传入 "assets/part3/group1"，整个 Builds 文件夹换到任何机器（换盘符、
##     换父目录）都不用改代码。
##   - 传文件路径：只播放这一个视频。
##   - 传文件夹路径：自动扫描该文件夹（不含子文件夹）下所有受支持的视频，
##     按文件名排序后从第一个开始连续播放，一个播完自动接力下一个；
##     全部播完后是否循环回到第一个由 directory_loop_playback 决定。
##
## 组件自身的尺寸与位置：
##   - 完全由这个 Control 节点自己的 position / size（或场景里的锚点+偏移）决定，
##     不会在运行时被脚本强制拉伸去铺满父节点。
##
## 交互规则：
##   - 打开即自动播放，底部工具栏默认不显示
##   - 鼠标：悬停在屏幕底部 hover_zone_height 像素范围内时显示工具栏
##   - 触屏：点一下屏幕任意位置显示工具栏
##   - 显示后 hide_delay 秒无操作（且鼠标不在底部热区）自动隐藏
##   - 点击 BtnExit（或 free_on_close = true 时播放完毕）后自动 queue_free() 销毁自己

const TAG := "VideoPlayer"

signal opened(path: String)
signal playback_started
signal playback_paused
signal playback_resumed
signal playback_stopped
signal playback_finished
## 文件夹连续播放模式下，播完最后一个视频、且 directory_loop_playback = false 时触发
signal playlist_finished
signal closed

@export var seek_step: float = 10.0        ## 快进快退步长（秒）
@export var hide_delay: float = 1.5        ## 显示后多少秒无操作自动隐藏工具栏
@export var hover_zone_height: float = 120.0 ## 屏幕底部多少像素范围内，鼠标悬停会触发显示工具栏
@export var open_auto_play: bool = false
@export var free_on_close: bool = false ## 播放完是否自动关闭释放（文件夹模式下指整个播放列表播完）
@export var video_path: String = ""     ## 也可直接在 Inspector 填路径（文件或文件夹皆可）
@export var directory_loop_playback: bool = true ## 文件夹模式下播完是否循环回第一个

@export_group("工具栏位置")
@export var toolbar_position: ToolbarPosition = ToolbarPosition.BOTTOM
@export var toolbar_edge_offset: float = 20.0

@export_group("工具栏基准尺寸 (按 1920x1080 设计)")
@export var toolbar_max_width_base: float = 900.0
@export var toolbar_height_base: float = 96.0
@export var button_spacing_base: float = 30.0
@export var main_button_size_base: Vector2 = Vector2(104, 104)
@export var seek_button_size_base: Vector2 = Vector2(67, 67)
@export var mute_button_size_base: Vector2 = Vector2(40, 38)
@export var playback_slider_min_width_base: float = 800.0
@export var volume_slider_min_width_base: float = 300.0
@export_range(0.3, 1.0) var ui_scale_min: float = 0.4
@export_range(1.0, 3.0) var ui_scale_max: float = 1.5

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

enum ToolbarPosition { TOP, BOTTOM }

const DESIGN_WIDTH: float = 1920.0
const DESIGN_HEIGHT: float = 1080.0
const VIDEO_EXTENSIONS: Array[String] = ["mp4", "avi", "mov", "mkv", "webm", "ogv"]

var _is_dragging: bool = false
var _is_muted: bool = false
var _volume_before_mute: float = 0.5
var _hide_timer: float = 0.0

var _video_files: Array[String] = [] ## 当前文件夹播放列表；单文件播放时为空数组
var _video_index: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS

	_slider_playback.min_value = 0
	_slider_playback.max_value = 100
	_slider_volume.min_value = 0
	_slider_volume.max_value = 100
	_slider_volume.value = _video.volume * 100.0

	_bar.visible = false
	_connect_signals()

	visible = false
	if not video_path.is_empty() and open_auto_play:
		_show_video()
		if _is_video_directory(video_path):
			_load_video_directory(video_path)
		else:
			_video_files.clear()
			_load_video(video_path)
			_start_video()

	resized.connect(_apply_toolbar_layout)
	_apply_toolbar_layout()

func _process(delta: float) -> void:
	if _video.is_playing() and not _video.paused and not _is_dragging:
		var length := _video.get_stream_length()
		if length > 0:
			_slider_playback.value = (_video.stream_position / length) * 100.0

	var mouse_pos := get_local_mouse_position()
	var in_hover_zone: bool
	if toolbar_position == ToolbarPosition.BOTTOM:
		in_hover_zone = mouse_pos.y >= size.y - hover_zone_height and mouse_pos.y <= size.y \
			and mouse_pos.x >= 0 and mouse_pos.x <= size.x
	else:
		in_hover_zone = mouse_pos.y <= hover_zone_height and mouse_pos.y >= 0 \
			and mouse_pos.x >= 0 and mouse_pos.x <= size.x

	if in_hover_zone:
		_show_controls()
	elif _bar.visible:
		_hide_timer += delta
		if _hide_timer >= hide_delay:
			_bar.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_show_controls()

func _connect_signals() -> void:
	_video.finished.connect(_on_video_finished)
	_slider_playback.drag_started.connect(_on_slider_drag_started)
	_slider_playback.drag_ended.connect(_on_slider_drag_ended)
	_slider_playback.value_changed.connect(_on_playback_value_changed)
	_slider_volume.value_changed.connect(_on_volume_value_changed)
	_btn_pause_and_play.pressed.connect(_on_btn_pause_and_play_pressed)
	_btn_stop.pressed.connect(_on_btn_stop_pressed)
	_btn_rewind.pressed.connect(_seek_relative.bind(-seek_step))
	_btn_forward.pressed.connect(_seek_relative.bind(seek_step))
	_btn_mute.pressed.connect(_on_btn_mute_pressed)
	_btn_exit.pressed.connect(close)

## 外部调用入口：传入文件或文件夹路径，自动判断并开始播放。
## 无论组件是否已进入场景树都可安全调用（尚未 add_child 时会记下路径，_ready() 时自动播放）。
func open_video(path: String) -> void:
	video_path = path
	if not is_inside_tree():
		return

	opened.emit(path)
	_show_video()
	if _is_video_directory(path):
		_load_video_directory(path)
	else:
		_video_files.clear() # 清空可能残留的文件夹播放列表，避免误触发连续播放
		_load_video(path)
		_start_video()

## 相对路径拼接到 exe（打包后运行文件）所在目录下，绝对路径原样返回。
func _resolve_path(path: String) -> String:
	var target_path := path.simplify_path()
	var is_absolute := target_path.is_absolute_path() \
		or (OS.get_name() == "Windows" and target_path.length() >= 2 and target_path[1] == ":")

	if is_absolute:
		return target_path
	return OS.get_executable_path().get_base_dir().path_join(target_path)

## 加载单个视频文件为 FFmpeg 视频流（不会自动播放，需配合 _start_video 使用）。
func _load_video(path: String) -> void:
	if path.is_empty():
		VinoLogger.error(TAG, "video_path 为空")
		return

	var target_path := _resolve_path(path)
	if not FileAccess.file_exists(target_path):
		VinoLogger.error(TAG, "视频文件未找到: " + target_path)
		return
	if not ClassDB.class_exists("FFmpegVideoStream"):
		VinoLogger.error(TAG, "FFmpeg 插件未启用")
		return

	var stream_ff = ClassDB.instantiate("FFmpegVideoStream")
	stream_ff.file = ProjectSettings.globalize_path(target_path)
	_video.stream = stream_ff

## 从头播放当前已加载的视频流；重新赋值流以刷新 FFmpeg 解码器，防止卡死。
func _start_video() -> void:
	if _video.stream == null:
		return
	var temp_stream = _video.stream
	_video.stream = null
	_video.stream = temp_stream
	_video.stream_position = 0.0
	_video.paused = false
	_video.play()
	playback_started.emit()

## 对外暴露的关闭入口：BtnExit、外部代码都可以调用。
func close() -> void:
	closed.emit()
	if free_on_close:
		queue_free()
	else:
		_video.stop()
		_video.stream_position = 0.0
		_bar.visible = false
		visible = false
	playback_stopped.emit()

func _on_btn_pause_and_play_pressed() -> void:
	if _video.stream == null:
		return
	if _video.is_playing():
		_video.paused = not _video.paused
		(playback_paused if _video.paused else playback_resumed).emit()
	else:
		_video.play()
		playback_resumed.emit()
	_show_controls()

func _on_btn_stop_pressed() -> void:
	if _video.stream == null:
		return
	_video.stop()
	_video.stream_position = 0.0
	_video.paused = false
	var temp_stream = _video.stream
	_video.stream = null
	_video.stream = temp_stream
	_slider_playback.value = 0
	_show_controls()
	playback_stopped.emit()

## 单个视频自然播放完毕：文件夹模式下自动接力下一个；否则按 free_on_close 决定隐藏还是销毁。
func _on_video_finished() -> void:
	_slider_playback.value = 0
	_show_controls()
	playback_finished.emit()

	if not _video_files.is_empty() and _video_index < _video_files.size() - 1:
		_play_video_at_index(_video_index + 1)
		return

	if not _video_files.is_empty():
		if directory_loop_playback:
			_play_video_at_index(0)
			return
		playlist_finished.emit()

	if free_on_close:
		close()
	else:
		visible = false

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

func _show_video() -> void:
	visible = true

## 按当前组件尺寸相对 1920x1080 设计稿等比缩放工具栏布局。
func _apply_toolbar_layout() -> void:
	var ui_scale := clampf(minf(size.x / DESIGN_WIDTH, size.y / DESIGN_HEIGHT), ui_scale_min, ui_scale_max)

	_bar.scale = Vector2.ONE
	var toolbar_width := toolbar_max_width_base * ui_scale
	var toolbar_height := toolbar_height_base * ui_scale

	match toolbar_position:
		ToolbarPosition.TOP:
			_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
			_bar.offset_top = toolbar_edge_offset
			_bar.offset_bottom = toolbar_edge_offset + toolbar_height
		ToolbarPosition.BOTTOM:
			_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			_bar.offset_top = -toolbar_edge_offset - toolbar_height
			_bar.offset_bottom = -toolbar_edge_offset

	_bar.offset_left = -toolbar_width / 2.0
	_bar.offset_right = toolbar_width / 2.0

	_btn_pause_and_play.custom_minimum_size = main_button_size_base * ui_scale
	_btn_stop.custom_minimum_size = main_button_size_base * ui_scale
	_btn_exit.custom_minimum_size = main_button_size_base * ui_scale
	_btn_rewind.custom_minimum_size = seek_button_size_base * ui_scale
	_btn_forward.custom_minimum_size = seek_button_size_base * ui_scale
	_btn_mute.custom_minimum_size = mute_button_size_base * ui_scale
	_slider_playback.custom_minimum_size.x = playback_slider_min_width_base * ui_scale
	_slider_volume.custom_minimum_size.x = volume_slider_min_width_base * ui_scale

	var hbox := _bar.get_node("HBoxContainer") as HBoxContainer
	hbox.add_theme_constant_override("separation", int(button_spacing_base * ui_scale))

	hover_zone_height = toolbar_height + toolbar_edge_offset * 2.0

## 扫描目标文件夹（不含子文件夹）下所有受支持的视频，按文件名排序后写入 _video_files 并开始播放；
## 后续由 _on_video_finished 自动接力下一个。
func _load_video_directory(path: String) -> void:
	var target_path := _resolve_path(path)
	var dir := DirAccess.open(target_path)
	if dir == null:
		VinoLogger.error(TAG, "视频目录无法打开: " + target_path)
		return

	_video_files.clear()
	_video_index = 0

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() in VIDEO_EXTENSIONS:
			_video_files.append(target_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	_video_files.sort()
	if _video_files.is_empty():
		VinoLogger.error(TAG, "目录中没有找到视频: " + target_path)
		return

	_play_video_at_index(0)

func _play_video_at_index(index: int) -> void:
	if index < 0 or index >= _video_files.size():
		return
	_video_index = index
	_load_video(_video_files[_video_index])
	_start_video()

func _is_video_directory(path: String) -> bool:
	return DirAccess.dir_exists_absolute(_resolve_path(path))
