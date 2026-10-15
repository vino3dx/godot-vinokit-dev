class_name VinoContentBrowser
extends Control
## 通用内容浏览组件：左侧目录 + 右侧图片翻页 / 视频播放，可跨项目复用。
## 配套场景：addons/vinokit/modules/browser/vino_content_browser.tscn。
##
## 用法：
##   1. 实例化 vino_content_browser.tscn，或让项目场景继承它；
##   2. 数据二选一（后调用的覆盖先调用的）：
##      - set_sections([...])：显式数据，结构见下文「数据契约」；
##      - load_from_directory("res://content/第一章")：文件夹即内容（零配置扫描）；
##   3. set_title("第一章")：设置标题（竖排显示；也可用 Inspector 的 title_text）；
##   4. Inspector 的 show_back_button 控制返回按钮显隐；点击返回按钮只发出
##      back_requested 信号，具体返回逻辑由使用方决定；
##   5. 视频页：在 Inspector 给 video_player_scene 赋一个播放组件场景，需提供
##      open_video(path: String) 方法与 closed 信号（VinoKit 自带的
##      modules/media_player/video_player.tscn 即满足）；留空时视频页显示提示
##      文案，不报错，图片功能不受影响。
##
## 数据契约（set_sections，含 media_items 与 media_paths 简写两种写法）：
##   [{
##       "title": String,
##       "media_items": [{ "path": String, "media_type": "image" | "video" }],
##   }]
##   简写：{ "title": String, "media_type": String, "media_paths": Array }。
##
## 文件夹即内容（load_from_directory，参数传已解析好的目录）：
##   <目录>/<子文件夹>/<媒体文件>
##   - 子文件夹 = 左侧一个目录条目，标题自动剥离 "1_"、"02-"、"3." 等排序前缀，
##     排序按原始文件夹名前缀数字升序（1, 2, 3 ... 10）；
##   - 子文件夹内的 .png / .jpg / .jpeg / .mp4 按文件名自然排序组成翻页序列；
##   - 目录无效或没有可用媒体时，右侧展示「暂无内容」占位提示，不报错。
##
## 约定：常量 UPPER_CASE，变量 / 函数 snake_case，私有成员加下划线前缀。

# ------------------------------------------------------------------ 数据契约键名

const SECTION_KEY_TITLE: String = "title"
## 简写形式：章节级媒体类型 + 路径列表。
const SECTION_KEY_MEDIA_TYPE: String = "media_type"
const SECTION_KEY_MEDIA_PATHS: String = "media_paths"
## 归一化后的章节内部字段：按页码顺序排列的媒体项列表。
const SECTION_KEY_MEDIA_ITEMS: String = "media_items"
## 媒体项字段名。
const MEDIA_ITEM_KEY_PATH: String = "path"
const MEDIA_ITEM_KEY_TYPE: String = "media_type"

## 媒体类型取值：图片（右侧 TextureRect 翻页）/ 视频（右侧视频播放组件）。
const MEDIA_TYPE_IMAGE: String = "image"
const MEDIA_TYPE_VIDEO: String = "video"

## 标题与空数据时的兜底文案。
const FALLBACK_TITLE: String = "内容浏览"
const FALLBACK_MEDIA_HINT: String = "暂无内容"

# ------------------------------------------------------------------ 「文件夹即内容」扫描规则

## 参与扫描的图片扩展名（小写，不含点）。
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg"]
## 参与扫描的视频扩展名。项目素材统一为 .mp4，由 FFmpegVideoStream 解码
## （Godot 原生只内置 Theora/.ogv，播不了 mp4）。
const VIDEO_EXTENSIONS: Array[String] = ["mp4"]
## 自然排序时数字段补零到该宽度，保证 2 排在 10 前面。
const NATURAL_SORT_DIGIT_WIDTH: int = 12
## 文件夹名开头的排序前缀：数字 + 紧随其后的分隔符，生成显示标题前整段剥掉。
## 数字同时覆盖半角与全角；分隔符覆盖空格、下划线、减号、点号、
## 以及中文常见写法（、·．～—－、全角空格），写成 `等` 形式以免漏剥。
const NUMBER_PREFIX_PATTERN_TEXT: String = "^[0-9０-９]+[_\\-\\.、·．～~—－\\s　]*"

# ------------------------------------------------------------------ 目录列表样式
# 数值取自设计稿实测：条目底图 629 x 127，文字汉字字高 33~34 px（对应字号 38），
# 相邻条目首行间距 172 px，故行间距 = 172 - 127 = 45。

## 条目高度按设计稿固定 127；宽度交给容器决定（面板宽度随时可能被调整，
## 写死 629 会在变窄的面板上横向溢出，导致文字贴边甚至被裁掉）。
const DIRECTORY_ITEM_HEIGHT: float = 127.0
## 目录项之间的行间距，统一由代码下发的 separation 控制（场景里不保留重复值）。
const DIRECTORY_ITEM_SEPARATION: int = 45
## 目录项统一字号，由 add_theme_font_size_override 下发。
## 52 高的两行文字（38 * 1.37 行高）加垂直留白仍在 127 内，不会撑破底图。
const DIRECTORY_ITEM_FONT_SIZE: int = 40
## 目录项文字与底图边缘的留白：设计稿文字水平范围约 477 / 底图 629，左右各留 76；
## 水平取 60 更适合变窄后的面板，垂直取 8 保证两行文字居中且不贴边。
const DIRECTORY_ITEM_TEXT_MARGIN_H: int = 60
const DIRECTORY_ITEM_TEXT_MARGIN_V: int = 8
const DIRECTORY_ITEM_FONT_COLOR: Color = Color(0.16, 0.29, 0.36, 1.0)
## 悬停时高亮的不透明度，低于选中态，避免与「已选中」混淆。
const DIRECTORY_ITEM_HOVER_ALPHA: float = 0.45
## 未配置 highlight_texture 时的兜底高亮色（不透明度由代码按状态叠加）。
const DIRECTORY_ITEM_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
## 目录项之间的分割线尺寸（分割线贴图原始尺寸）。
const DIRECTORY_SEPARATOR_SIZE: Vector2 = Vector2(543.0, 3.0)
## 上下箭头按钮一次滚动的可视高度比例。
const DIRECTORY_SCROLL_STEP_RATIO: float = 0.9

# ------------------------------------------------------------------ 竖排标题样式

const MODULE_TITLE_FONT_SIZE: int = 72
const MODULE_TITLE_FONT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

# ------------------------------------------------------------------ 翻页控件样式

const PAGE_INDICATOR_FORMAT: String = "%d / %d"
const PAGE_INDICATOR_FONT_SIZE: int = 56
const PAGE_INDICATOR_FONT_COLOR: Color = Color(0.20, 0.34, 0.42, 1.0)
## 翻页按钮到达首尾时的置灰透明度。
const PAGE_BUTTON_DISABLED_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.25)
const PAGE_BUTTON_ENABLED_MODULATE: Color = Color(1.0, 1.0, 1.0, 1.0)

# ------------------------------------------------------------------ 视频播放组件
# 播放组件经 Inspector 的 video_player_scene 注入，按鸭子类型接入：只要提供
# open_video(path) 方法与 closed 信号即可，不绑定具体类。
# VinoKit 自带的 VideoOverlayPlayer（modules/media_player/video_player.tscn）
# 即满足该契约，其内部用 FFmpegVideoStream 解码，自带整套工具栏
# （播放/暂停、停止、快进快退、进度条、音量、退出）。

## 组件内部节点路径，用于嵌进内容区后做布局归一化。
const VIDEO_TOOLBAR_NODE_PATH: String = "VideoToolBar"
const VIDEO_PLAYBACK_SLIDER_NODE_PATH: String = "VideoToolBar/HBoxContainer/HSliderPlayback"
## 工具栏归一化后贴住内容区底部的高度，以及进度条的最小宽度。
const VIDEO_TOOLBAR_HEIGHT: float = 170.0
const VIDEO_PLAYBACK_SLIDER_MIN_WIDTH: float = 420.0
## ffmpeg 扩展注册的视频流类名，取不到说明扩展没加载成功。
const FFMPEG_STREAM_CLASS_NAME: String = "FFmpegVideoStream"
## 视频组件关闭后（点退出按钮 / 播放结束自动关闭）内容区的提示文案。
const VIDEO_CLOSED_HINT: String = "视频已关闭"
## ffmpeg 扩展缺失时的提示文案。
const VIDEO_PLUGIN_MISSING_HINT: String = "视频组件未就绪"
## 未配置 video_player_scene 时视频页的提示文案。
const VIDEO_PLAYER_MISSING_HINT: String = "未配置视频播放组件"
## video_player_scene 不满足鸭子类型时视频页的提示文案。
const VIDEO_PLAYER_INVALID_HINT: String = "视频播放组件不兼容"

## 日志标签，由 VinoLogger 统一附加 [TAG] 前缀。
const TAG := "VinoContentBrowser"

# ------------------------------------------------------------------ 对外信号

## 点击返回按钮时触发；返回逻辑（切场景 / 上级菜单）由使用方决定。
signal back_requested
## 用户点击左侧目录项时触发，index 为条目下标（程序化切换不触发）。
signal section_selected(index: int)
## 右侧展示的页码变化时触发（含初始定位与切换条目）；page_index 从 0 开始。
signal page_changed(section_index: int, page_index: int)

# ------------------------------------------------------------------ 对外配置（Inspector）

@export var show_back_button := true ## 是否显示返回按钮
@export var title_text := "" ## 初始标题，留空则用场景默认文案
@export var video_player_scene: PackedScene = null ## 视频播放组件场景，用法见文件头第 5 条
## 目录项字体；为空时用主题默认字体。
@export var directory_font: Font = null
## 目录项选中 / 悬停高亮贴图；为空时用 StyleBoxFlat 纯色兜底。
@export var highlight_texture: Texture2D = null
## 目录项之间的分割线贴图；为空时不创建分割线。
@export var separator_texture: Texture2D = null

# ------------------------------------------------------------------ 节点引用

@onready var _module_title_label: Label = $TitleBar/ModuleTitle
@onready var _directory_scroll: ScrollContainer = $DirectoryPanel/ScrollContainer
@onready var _directory_list: VBoxContainer = $DirectoryPanel/ScrollContainer/DirectoryList
@onready var _directory_scroll_up_button: Button = $DirectoryPanel/ScrollUpButton
@onready var _directory_scroll_down_button: Button = $DirectoryPanel/ScrollDownButton
@onready var _content_panel: Control = $ContentPanel
@onready var _image_page: TextureRect = $ContentPanel/ImagePage
@onready var _empty_hint: Label = $ContentPanel/EmptyHint
@onready var _previous_page_button: Button = $ContentPanel/PreviousPageButton
@onready var _next_page_button: Button = $ContentPanel/NextPageButton
@onready var _page_indicator: Label = $ContentPanel/PageIndicator
@onready var _back_button: Button = $BackButton

# ------------------------------------------------------------------ 运行时状态

## 当前章节列表（已归一化，字段齐全）。
var _sections: Array[Dictionary] = []
## 左侧目录项按钮，下标与 _sections 一一对应。
var _directory_items: Array[Button] = []
## 目录按钮互斥组：保证任何时刻恰有一个目录项处于选中态。
var _directory_button_group: ButtonGroup = ButtonGroup.new()
## 当前选中的章节下标，-1 表示未选中任何章节。
var _selected_section_index: int = -1
## 当前章节内的页码下标（从 0 开始）。
var _current_page_index: int = 0
## 当前挂在内容区里的视频播放组件实例；当前页不是视频时为 null。
var _video_player: Node = null
## 排序前缀匹配器（编译自 NUMBER_PREFIX_PATTERN_TEXT），只匹配开头，不做全文替换。
var _number_prefix_pattern: RegEx = RegEx.create_from_string(NUMBER_PREFIX_PATTERN_TEXT)


# ------------------------------------------------------------------ 生命周期

func _ready() -> void:
	_apply_directory_list_theme()
	_connect_signals()
	_back_button.visible = show_back_button
	if not title_text.is_empty():
		set_title(title_text)
	_refresh_content()


## 左侧目录列表的容器级样式：行间距统一由代码下发，避免场景与脚本两处维护同一数值。
func _apply_directory_list_theme() -> void:
	_directory_list.add_theme_constant_override("separation", DIRECTORY_ITEM_SEPARATION)


func _connect_signals() -> void:
	_back_button.pressed.connect(_on_back_button_pressed)
	_previous_page_button.pressed.connect(_on_previous_page_button_pressed)
	_next_page_button.pressed.connect(_on_next_page_button_pressed)
	_directory_scroll_up_button.pressed.connect(_on_directory_scroll_up_button_pressed)
	_directory_scroll_down_button.pressed.connect(_on_directory_scroll_down_button_pressed)


# ------------------------------------------------------------------ 对外 API

## 设置显式章节数据（结构详见文件头「数据契约」）；传入空数组等同清空展示。
func set_sections(sections: Array) -> void:
	_sections = _normalize_sections(sections)
	_rebuild_after_data_change()


## 「文件夹即内容」：扫描已解析好的目录（一级子文件夹 = 目录条目，
## 子文件夹内的图片 / 视频 = 翻页内容）；目录无效时展示占位提示，不报错。
func load_from_directory(dir_path: String) -> void:
	if dir_path.is_empty():
		VinoLogger.warn(TAG, "load_from_directory 传入了空目录路径")
		_sections = []
		_rebuild_after_data_change()
		return
	_sections = _scan_directory(dir_path.trim_suffix("/"))
	_rebuild_after_data_change()


## 设置标题（竖排显示）；传空串时退回兜底文案。
func set_title(text: String) -> void:
	var title: String = FALLBACK_TITLE if text.is_empty() else text
	_module_title_label.text = _build_vertical_title(title)


## 数据变化后重建左侧目录，并定位到第一个章节（无数据时展示占位提示）。
func _rebuild_after_data_change() -> void:
	_build_directory_list()
	if _sections.is_empty():
		_selected_section_index = -1
		_refresh_content()
		return
	_select_section(0)


## 把标题转成竖排文字（每个字符后换行），供左侧标题条显示。
func _build_vertical_title(title: String) -> String:
	var characters := PackedStringArray()
	for index: int in title.length():
		characters.append(title[index])
	return "\n".join(characters)


## 把显式下发的 sections 归一化成内部统一模型（title + media_items）；
## 传入非数组时告警并返回空列表。
func _normalize_sections(raw_sections: Variant) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	if typeof(raw_sections) != TYPE_ARRAY:
		VinoLogger.warn(TAG, "sections 不是数组，已忽略：%s" % str(raw_sections))
		return sections

	var section_list: Array = raw_sections
	for raw_section: Variant in section_list:
		if typeof(raw_section) != TYPE_DICTIONARY:
			VinoLogger.warn(TAG, "存在非字典的章节数据，已忽略：%s" % str(raw_section))
			continue
		var section: Dictionary = raw_section
		sections.append({
			SECTION_KEY_TITLE: String(section.get(SECTION_KEY_TITLE, "")),
			SECTION_KEY_MEDIA_ITEMS: _normalize_media_items(section),
		})
	return sections


## 归一化章节内的媒体项，统一成 [{path, media_type}]；
## 同时兼容 media_items 列表与 media_type + media_paths 简写两种写法。
func _normalize_media_items(section: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	# 默认值取 null：只有调用方真的写了 media_items 才走这一支，否则回退到简写形式。
	var raw_items: Variant = section.get(SECTION_KEY_MEDIA_ITEMS, null)
	if typeof(raw_items) == TYPE_ARRAY:
		var item_list: Array = raw_items
		for raw_item: Variant in item_list:
			if typeof(raw_item) != TYPE_DICTIONARY:
				VinoLogger.warn(TAG, "存在非字典的媒体项，已忽略：%s" % str(raw_item))
				continue
			var item: Dictionary = raw_item
			var path: String = String(item.get(MEDIA_ITEM_KEY_PATH, ""))
			if path.is_empty():
				continue
			items.append({
				MEDIA_ITEM_KEY_PATH: path,
				MEDIA_ITEM_KEY_TYPE: String(item.get(MEDIA_ITEM_KEY_TYPE, MEDIA_TYPE_IMAGE)),
			})
		return items

	var section_type: String = String(section.get(SECTION_KEY_MEDIA_TYPE, MEDIA_TYPE_IMAGE))
	var raw_paths: Variant = section.get(SECTION_KEY_MEDIA_PATHS, [])
	if typeof(raw_paths) != TYPE_ARRAY:
		VinoLogger.warn(TAG, "media_paths 字段不是数组，已忽略：%s" % str(raw_paths))
		return items

	var path_list: Array = raw_paths
	for raw_path: Variant in path_list:
		var path: String = String(raw_path)
		if path.is_empty():
			continue
		items.append({
			MEDIA_ITEM_KEY_PATH: path,
			MEDIA_ITEM_KEY_TYPE: section_type,
		})
	return items


# ------------------------------------------------------------------ 文件夹即内容（DirAccess）

## 扫描内容目录：一级子文件夹即左侧目录条目，文件夹内的图片 / 视频即该条目的内容。
func _scan_directory(directory_path: String) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	for subfolder_name: String in _list_subdirectory_names(directory_path):
		var subfolder_path: String = "%s/%s" % [directory_path, subfolder_name]
		sections.append({
			SECTION_KEY_TITLE: _build_section_title(subfolder_name),
			SECTION_KEY_MEDIA_ITEMS: _scan_media_items(subfolder_path),
		})
	return sections


## 列出目录下的子文件夹名，按文件夹名开头的数字升序排列（1, 2, 3 ... 10）。
## 排序依据是原始文件夹名而非剥离前缀后的标题，因此剥离序号只影响显示、不影响顺序。
func _list_subdirectory_names(directory_path: String) -> Array[String]:
	var subfolder_names: Array[String] = []
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		VinoLogger.warn(TAG, "目录无法访问：%s" % directory_path)
		return subfolder_names

	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		# 以 "." 开头的隐藏项（含 . 与 ..）与非目录项一律跳过。
		if not entry_name.begins_with(".") and directory.current_is_dir():
			subfolder_names.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return _sort_names_naturally(subfolder_names)


## 扫描一个条目文件夹，产出按自然顺序排列的媒体项列表。
func _scan_media_items(directory_path: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for file_name: String in _list_media_file_names(directory_path):
		items.append({
			MEDIA_ITEM_KEY_PATH: "%s/%s" % [directory_path, file_name],
			MEDIA_ITEM_KEY_TYPE: _resolve_media_type(file_name),
		})
	return items


## 列出目录下的媒体文件名，按自然顺序排序；.import 等附属文件会被扩展名过滤掉。
func _list_media_file_names(directory_path: String) -> Array[String]:
	var file_names: Array[String] = []
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		VinoLogger.warn(TAG, "目录无法访问：%s" % directory_path)
		return file_names

	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		var is_media: bool = (not entry_name.begins_with(".")) \
			and (not directory.current_is_dir()) and _is_media_file(entry_name)
		if is_media:
			file_names.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return _sort_names_naturally(file_names)


## 是否是本页可展示的媒体文件（按扩展名判断）。
func _is_media_file(file_name: String) -> bool:
	var extension: String = file_name.get_extension().to_lower()
	return IMAGE_EXTENSIONS.has(extension) or VIDEO_EXTENSIONS.has(extension)


## 按扩展名判定媒体类型：视频扩展名以外的一律按图片处理。
func _resolve_media_type(file_name: String) -> String:
	if VIDEO_EXTENSIONS.has(file_name.get_extension().to_lower()):
		return MEDIA_TYPE_VIDEO
	return MEDIA_TYPE_IMAGE


## 剥掉文件夹名开头的排序前缀（"1_"、"02-"、"3."、"10 "、"5、"...），得到干净的显示标题；
## 整串都是前缀（如 "1_"、"2"）时退回原名，避免出现空标题。
## 只剥离开头，名称中间的分隔符原样保留（"1_农业部-长江流域..." → "农业部-长江流域..."）。
func _build_section_title(subfolder_name: String) -> String:
	var title: String = _number_prefix_pattern.sub(subfolder_name, "", true).strip_edges()
	return title if not title.is_empty() else subfolder_name


## 自然排序：把名称中的数字段补零后再比较，保证 2 排在 10 前面。
func _sort_names_naturally(names: Array[String]) -> Array[String]:
	var sort_entries: Array[Dictionary] = []
	@warning_ignore("shadowed_variable_base_class")
	for name: String in names:
		sort_entries.append({"name": name, "key": _build_natural_sort_key(name)})
	sort_entries.sort_custom(_is_natural_order_before)

	var sorted_names: Array[String] = []
	for entry: Dictionary in sort_entries:
		sorted_names.append(String(entry["name"]))
	return sorted_names


func _is_natural_order_before(left: Dictionary, right: Dictionary) -> bool:
	return String(left["key"]) < String(right["key"])


## 生成自然排序键：数字段补零到固定宽度，其余字符小写后原样保留。
func _build_natural_sort_key(source_name: String) -> String:
	var sort_key: String = ""
	var digit_buffer: String = ""
	for character: String in source_name.to_lower():
		if character >= "0" and character <= "9":
			digit_buffer += character
			continue
		if not digit_buffer.is_empty():
			sort_key += digit_buffer.lpad(NATURAL_SORT_DIGIT_WIDTH, "0")
			digit_buffer = ""
		sort_key += character
	if not digit_buffer.is_empty():
		sort_key += digit_buffer.lpad(NATURAL_SORT_DIGIT_WIDTH, "0")
	return sort_key


# ------------------------------------------------------------------ 左侧目录

## 按章节数据动态生成目录项；数据变化时先清空旧项，避免重复叠加。
func _build_directory_list() -> void:
	for item: Button in _directory_items:
		_directory_list.remove_child(item)
		item.queue_free()
	_directory_items.clear()

	for index: int in _sections.size():
		var item: Button = _create_directory_item(index)
		_directory_items.append(item)
		_directory_list.add_child(item)


## 依据一个章节创建目录项按钮：高亮底图来自 highlight_texture（未配置时纯色兜底），
## 配置了 separator_texture 时底部带分割线。
func _create_directory_item(index: int) -> Button:
	var section: Dictionary = _sections[index]
	var item := Button.new()
	item.name = "DirectoryItem%d" % index
	item.text = String(section[SECTION_KEY_TITLE])
	# 只给高度下限，宽度交给 VBoxContainer 拉满，避免超出目录面板边界。
	item.custom_minimum_size = Vector2(0.0, DIRECTORY_ITEM_HEIGHT)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.toggle_mode = true
	item.button_group = _directory_button_group
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if directory_font != null:
		item.add_theme_font_override("font", directory_font)
	item.add_theme_font_size_override("font_size", DIRECTORY_ITEM_FONT_SIZE)
	item.add_theme_color_override("font_color", DIRECTORY_ITEM_FONT_COLOR)
	item.add_theme_color_override("font_hover_color", DIRECTORY_ITEM_FONT_COLOR)
	item.add_theme_color_override("font_pressed_color", DIRECTORY_ITEM_FONT_COLOR)
	item.add_theme_color_override("font_hover_pressed_color", DIRECTORY_ITEM_FONT_COLOR)
	item.add_theme_color_override("font_focus_color", DIRECTORY_ITEM_FONT_COLOR)

	# 未选中态保持透明；悬停态半透明、选中态全亮。
	var empty_style_box := _create_transparent_style_box()
	item.add_theme_stylebox_override("normal", empty_style_box)
	item.add_theme_stylebox_override("focus", empty_style_box)
	item.add_theme_stylebox_override(
		"hover", _create_highlight_style_box(DIRECTORY_ITEM_HOVER_ALPHA)
	)
	item.add_theme_stylebox_override("pressed", _create_highlight_style_box(1.0))

	var separator: TextureRect = _create_directory_separator()
	if separator != null:
		item.add_child(separator)
	item.pressed.connect(_on_directory_item_pressed.bind(index))
	return item


## 未选中态底图：完全透明，只负责撑出与其他状态一致的内边距。
func _create_transparent_style_box() -> StyleBoxEmpty:
	var style_box := StyleBoxEmpty.new()
	_apply_directory_item_margin(style_box)
	return style_box


## 选中态 / 悬停态底图：配置了 highlight_texture 时用贴图 + 整体透明度区分强弱；
## 未配置时用 StyleBoxFlat 纯色兜底。
func _create_highlight_style_box(alpha: float) -> StyleBox:
	if highlight_texture != null:
		var texture_style_box := StyleBoxTexture.new()
		texture_style_box.texture = highlight_texture
		texture_style_box.modulate_color = Color(1.0, 1.0, 1.0, alpha)
		_apply_directory_item_margin(texture_style_box)
		return texture_style_box
	var flat_style_box := StyleBoxFlat.new()
	flat_style_box.bg_color = Color(DIRECTORY_ITEM_HIGHLIGHT_COLOR, alpha)
	_apply_directory_item_margin(flat_style_box)
	return flat_style_box


## 四种按钮状态统一的内边距：文字不贴边、不越界，且切换选中态时位置不跳动。
func _apply_directory_item_margin(style_box: StyleBox) -> void:
	style_box.content_margin_left = DIRECTORY_ITEM_TEXT_MARGIN_H
	style_box.content_margin_right = DIRECTORY_ITEM_TEXT_MARGIN_H
	style_box.content_margin_top = DIRECTORY_ITEM_TEXT_MARGIN_V
	style_box.content_margin_bottom = DIRECTORY_ITEM_TEXT_MARGIN_V


## 目录项底部的分割线，贴齐按钮下沿居中摆放，且不拦截鼠标事件；
## 未配置 separator_texture 时不创建，返回 null。
func _create_directory_separator() -> TextureRect:
	if separator_texture == null:
		return null
	var separator := TextureRect.new()
	separator.name = "Separator"
	separator.texture = separator_texture
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	separator.anchor_left = 0.5
	separator.anchor_right = 0.5
	separator.anchor_top = 1.0
	separator.anchor_bottom = 1.0
	separator.offset_left = -DIRECTORY_SEPARATOR_SIZE.x * 0.5
	separator.offset_right = DIRECTORY_SEPARATOR_SIZE.x * 0.5
	separator.offset_top = -DIRECTORY_SEPARATOR_SIZE.y
	separator.offset_bottom = 0.0
	return separator


## 目录项点击：切换到对应章节，右侧内容随之前往该章节第一页。
func _on_directory_item_pressed(index: int) -> void:
	_select_section(index)
	section_selected.emit(index)


## 切换选中章节：同步目录项选中态，并把内容重置到该章节第一页。
func _select_section(index: int) -> void:
	if index < 0 or index >= _sections.size():
		VinoLogger.warn(TAG, "章节下标越界，已忽略：%d" % index)
		return
	_selected_section_index = index
	_apply_directory_selection(index)
	_current_page_index = 0
	_refresh_content()


## 目录项选中态与 _selected_section_index 保持一致。
func _apply_directory_selection(selected_index: int) -> void:
	for index: int in _directory_items.size():
		_directory_items[index].set_pressed_no_signal(index == selected_index)


# ------------------------------------------------------------------ 右侧内容

## 按当前章节 / 页码刷新右侧展示：图片、视频或占位提示三选一。
func _refresh_content() -> void:
	var page_count: int = _get_page_count()
	if page_count <= 0:
		_show_media_hint(FALLBACK_MEDIA_HINT)
		_page_indicator.text = ""
		_set_page_buttons_enabled(false, false)
		return

	_current_page_index = clampi(_current_page_index, 0, page_count - 1)
	var media_item: Dictionary = _get_current_media_items()[_current_page_index]
	var media_path: String = String(media_item[MEDIA_ITEM_KEY_PATH])
	if String(media_item[MEDIA_ITEM_KEY_TYPE]) == MEDIA_TYPE_VIDEO:
		_show_video_page(media_path)
	else:
		_show_image_page(media_path)
	_update_page_indicator(page_count)
	page_changed.emit(_selected_section_index, _current_page_index)


## 图片页：先回收视频组件，再原地换贴图；加载失败时退回占位提示，不中断页面。
func _show_image_page(path: String) -> void:
	_release_video_player()
	var texture: Texture2D = _load_texture(path)
	if texture == null:
		_show_media_hint(FALLBACK_MEDIA_HINT)
		return
	_image_page.texture = texture
	_image_page.visible = true
	_empty_hint.visible = false


## 视频页：在内容区里实例化 video_player_scene 配置的播放组件并从头播放。
## 组件内部用 FFmpegVideoStream 解码 .mp4，自带播放/暂停、进度条、音量等 UI。
func _show_video_page(path: String) -> void:
	_release_video_player()
	_image_page.texture = null
	_image_page.visible = false
	_empty_hint.visible = false

	if video_player_scene == null:
		_show_media_hint(VIDEO_PLAYER_MISSING_HINT)
		return

	# ffmpeg 走原生解码，必须喂系统绝对路径，所以先把 res:// 转成真实路径。
	var play_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(play_path):
		VinoLogger.warn(TAG, "视频文件不存在：%s" % path)
		_show_media_hint(FALLBACK_MEDIA_HINT)
		return
	if not ClassDB.class_exists(FFMPEG_STREAM_CLASS_NAME):
		VinoLogger.error(
			TAG,
			"ffmpeg 扩展未加载（%s 不可用），无法播放：%s" % [FFMPEG_STREAM_CLASS_NAME, path]
		)
		_show_media_hint(VIDEO_PLUGIN_MISSING_HINT)
		return

	var player: Node = video_player_scene.instantiate()
	if not _is_compatible_video_player(player):
		if player != null:
			player.free()
		VinoLogger.error(
			TAG,
			"视频播放组件不兼容（需提供 open_video 方法与 closed 信号）：%s"
			% video_player_scene.resource_path
		)
		_show_media_hint(VIDEO_PLAYER_INVALID_HINT)
		return

	# 组件场景里可能预填了示例路径，先清空，避免 _ready() 去加载那个不存在的文件。
	player.set("video_path", "")
	_content_panel.add_child(player)
	# 压到最底层：左右翻页箭头浮在播放器之上，翻页按钮始终可点。
	_content_panel.move_child(player, 0)
	_apply_video_player_layout(player)
	player.connect("closed", _on_video_player_closed)
	_video_player = player
	player.call("open_video", play_path)


## 鸭子类型检查：使用方的播放组件只要提供 open_video(path) 方法与 closed 信号
## 即可接入，不强制依赖某个具体类。
func _is_compatible_video_player(player: Node) -> bool:
	return player != null and player.has_method("open_video") and player.has_signal("closed")


## 组件原本是给「全屏弹出」写的：本体铺满父节点、底部工具栏按 3840 宽屏幕预置了
## 1.765 倍缩放，直接嵌进内容区会横向溢出。这里做两处归一化：
##   1. 本体对齐 ImagePage 的媒体矩形，图片 / 视频切换时画面位置与尺寸完全一致；
##   2. 工具栏改成贴底通栏 + 1 倍缩放，进度条弹性伸缩吃掉多余宽度。
func _apply_video_player_layout(player: Node) -> void:
	var player_control := player as Control
	if player_control == null:
		VinoLogger.warn(TAG, "视频播放组件不是 Control，跳过布局归一化")
		return
	player_control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player_control.position = _image_page.position
	player_control.size = _image_page.size

	var toolbar: Control = player_control.get_node_or_null(VIDEO_TOOLBAR_NODE_PATH) as Control
	if toolbar == null:
		VinoLogger.warn(
			TAG, "视频组件缺少 %s 节点，保留其原始工具栏布局" % VIDEO_TOOLBAR_NODE_PATH
		)
		return
	toolbar.anchor_left = 0.0
	toolbar.anchor_right = 1.0
	toolbar.anchor_top = 1.0
	toolbar.anchor_bottom = 1.0
	toolbar.offset_left = 0.0
	toolbar.offset_right = 0.0
	toolbar.offset_top = -VIDEO_TOOLBAR_HEIGHT
	toolbar.offset_bottom = 0.0
	toolbar.scale = Vector2.ONE
	toolbar.pivot_offset = Vector2.ZERO

	var playback_slider: Control = player_control.get_node_or_null(
		VIDEO_PLAYBACK_SLIDER_NODE_PATH
	) as Control
	if playback_slider != null:
		playback_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		playback_slider.custom_minimum_size.x = VIDEO_PLAYBACK_SLIDER_MIN_WIDTH


## 回收视频播放组件。queue_free 不会触发组件的 closed 信号，因此不会回灌到关闭回调。
func _release_video_player() -> void:
	if is_instance_valid(_video_player):
		_video_player.queue_free()
	_video_player = null


## 组件自行关闭（点工具栏退出按钮，或播放结束由 auto_close_on_finish 关闭）后的收尾。
func _on_video_player_closed() -> void:
	_video_player = null
	_show_media_hint(VIDEO_CLOSED_HINT)


## 占位提示：数据为空或资源加载失败时展示，保证页面始终有反馈。
func _show_media_hint(text: String) -> void:
	_release_video_player()
	_image_page.texture = null
	_image_page.visible = false
	_empty_hint.text = text
	_empty_hint.visible = true


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		VinoLogger.warn(TAG, "图片资源不存在：%s" % path)
		return null
	return load(path) as Texture2D


# ------------------------------------------------------------------ 翻页

func _on_previous_page_button_pressed() -> void:
	_go_to_page(-1)


func _on_next_page_button_pressed() -> void:
	_go_to_page(1)


## 相对翻页；越界时直接返回，实现首尾边界保护。
func _go_to_page(offset: int) -> void:
	var page_count: int = _get_page_count()
	var target_page: int = _current_page_index + offset
	if target_page < 0 or target_page >= page_count:
		return
	_current_page_index = target_page
	_refresh_content()


## 当前章节的页数：每个媒体文件（图片或视频）各占一页。
func _get_page_count() -> int:
	return _get_current_media_items().size()


func _update_page_indicator(page_count: int) -> void:
	_page_indicator.text = PAGE_INDICATOR_FORMAT % [_current_page_index + 1, page_count]
	_set_page_buttons_enabled(_current_page_index > 0, _current_page_index < page_count - 1)


## 首 / 尾页时禁用对应按钮并置灰（置灰透明度由代码下发，不依赖贴图）。
func _set_page_buttons_enabled(previous_enabled: bool, next_enabled: bool) -> void:
	_apply_page_button_state(_previous_page_button, previous_enabled)
	_apply_page_button_state(_next_page_button, next_enabled)


func _apply_page_button_state(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.modulate = PAGE_BUTTON_ENABLED_MODULATE if enabled else PAGE_BUTTON_DISABLED_MODULATE


# ------------------------------------------------------------------ 目录滚动

func _on_directory_scroll_up_button_pressed() -> void:
	_scroll_directory(-1)


func _on_directory_scroll_down_button_pressed() -> void:
	_scroll_directory(1)


## 目录列表按可视高度滚动一屏；direction 为 -1 向上、1 向下。
func _scroll_directory(direction: int) -> void:
	var scroll_bar: VScrollBar = _directory_scroll.get_v_scroll_bar()
	var step: float = _directory_scroll.size.y * DIRECTORY_SCROLL_STEP_RATIO
	scroll_bar.value += float(direction) * step


# ------------------------------------------------------------------ 其它

## 当前选中章节数据；未选中或越界时返回空字典。
func _get_current_section() -> Dictionary:
	if _selected_section_index < 0 or _selected_section_index >= _sections.size():
		return {}
	return _sections[_selected_section_index]


## 当前章节的媒体项列表；未选中章节时返回空数组。
func _get_current_media_items() -> Array:
	var raw_items: Variant = _get_current_section().get(SECTION_KEY_MEDIA_ITEMS, [])
	if typeof(raw_items) != TYPE_ARRAY:
		return []
	return raw_items


## 返回按钮：只发信号，具体返回逻辑由使用方连接 back_requested 实现。
func _on_back_button_pressed() -> void:
	back_requested.emit()
