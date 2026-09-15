class_name VinoWindowController
extends Node
## VinoWindowController - 窗口与显示器控制器
##
## 功能：多显示器切换、窗口定位、居中、边界夹紧，以及窗口化/无边框/全屏/独占全屏模式切换。
## 支持在 config.ini 的 [WindowController]（或兼容旧版 [Window]）小节中配置。

const TAG := "VinoWindow"

enum WindowMode {
	WINDOWED,             ## 普通窗口
	BORDERLESS,           ## 无边框窗口
	FULLSCREEN,           ## 桌面全屏
	EXCLUSIVE_FULLSCREEN, ## 独占全屏
}

@export_group("窗口基础设置")
@export var window_mode: WindowMode = WindowMode.WINDOWED ## 启动时的窗口模式

@export_group("显示器与位置覆盖")
@export var screen: int = 0              ## 目标显示器索引（0 为主显示器）
@export var pos_x: int = 0               ## X 轴偏移（仅在 center = false 时生效）
@export var pos_y: int = 0               ## Y 轴偏移（仅在 center = false 时生效）
@export var center: bool = true          ## 是否在目标显示器居中
@export var clamp_to_screen: bool = true ## 是否防止窗口超出屏幕可视范围

@export_group("尺寸覆盖")
@export var override_size: bool = false ## 是否自定义窗口宽高
@export var override_width: int = 1280
@export var override_height: int = 720

func _ready() -> void:
	var config := get_node_or_null("/root/VinoConfig")
	if not config:
		_apply_window_position()
		return

	if config.is_loaded:
		_apply_from_config()
	elif config.has_signal("config_loaded"):
		config.config_loaded.connect(_apply_from_config)

# =========================
# 对外公开 API
# =========================

## 切换窗口模式
func apply_window_mode(mode: WindowMode = window_mode) -> void:
	window_mode = mode
	match mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

## 切换目标显示器并应用位置（0=主屏，1=副屏……）
func move_to_screen(target_screen: int) -> void:
	screen = target_screen
	await _apply_window_position()

## 将窗口在当前目标显示器居中
func center_on_screen() -> void:
	center = true
	await _apply_window_position()

## 动态改变窗口大小
func set_window_size(width: int, height: int) -> void:
	override_size = true
	override_width = width
	override_height = height
	await _apply_window_position()

# =========================
# 配置注入与应用
# =========================
func _apply_from_config() -> void:
	var config := get_node_or_null("/root/VinoConfig")
	if not config or not config.has_method("get_value"):
		_apply_window_position()
		return

	var sec := "WindowController"
	if not config.has_section(sec) and config.has_section("Window"):
		sec = "Window" # 兼容旧版配置小节名

	screen = int(config.get_value(sec, "screen", screen))
	pos_x = int(config.get_value(sec, "pos_x", pos_x))
	pos_y = int(config.get_value(sec, "pos_y", pos_y))
	center = _parse_bool(config.get_value(sec, "center", center))
	clamp_to_screen = _parse_bool(config.get_value(sec, "clamp_to_screen", clamp_to_screen))
	override_size = _parse_bool(config.get_value(sec, "override_size", override_size))
	override_width = int(config.get_value(sec, "override_width", override_width))
	override_height = int(config.get_value(sec, "override_height", override_height))

	match str(config.get_value(sec, "window_mode", "")).strip_edges().to_lower():
		"borderless": window_mode = WindowMode.BORDERLESS
		"fullscreen": window_mode = WindowMode.FULLSCREEN
		"exclusive_fullscreen": window_mode = WindowMode.EXCLUSIVE_FULLSCREEN
		"windowed": window_mode = WindowMode.WINDOWED
		_: pass # 配置未写 window_mode 时，保持代码/检视面板默认值

	_apply_window_position()

func _apply_window_position() -> void:
	await get_tree().process_frame

	# 防止配置写了 screen=2 但实际只有 1 个显示器导致越界
	var screen_count := DisplayServer.get_screen_count()
	if screen < 0 or screen >= screen_count:
		VinoLogger.warn(TAG, "目标显示器 %d 不存在，已回退到主屏" % screen)
		screen = 0

	if window_mode in [WindowMode.FULLSCREEN, WindowMode.EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_current_screen(screen)
		apply_window_mode(window_mode)
		return

	apply_window_mode(window_mode)
	DisplayServer.window_set_current_screen(screen)

	await get_tree().process_frame
	await get_tree().process_frame

	if override_size:
		DisplayServer.window_set_size(Vector2i(override_width, override_height))
		await get_tree().process_frame
		await get_tree().process_frame

	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var window_size := DisplayServer.window_get_size()

	var final_pos := screen_pos
	if center:
		final_pos += Vector2i((screen_size - window_size) / 2.0)
	else:
		final_pos += Vector2i(pos_x, pos_y)

	if clamp_to_screen:
		var min_pos := screen_pos
		var max_pos := screen_pos + screen_size - window_size
		if window_size.x > screen_size.x:
			max_pos.x = min_pos.x
		if window_size.y > screen_size.y:
			max_pos.y = min_pos.y
		final_pos.x = clamp(final_pos.x, min_pos.x, max_pos.x)
		final_pos.y = clamp(final_pos.y, min_pos.y, max_pos.y)

	DisplayServer.window_set_position(final_pos)

func _parse_bool(value: Variant) -> bool:
	return value if value is bool else str(value).strip_edges().to_lower() == "true"
