class_name VinoAssetLoader
extends Node
## [b]VinoAssetLoader - 多媒体资源加载管理器[/b]
##
## 建议 Autoload 挂载名称：[b]VinoAssets[/b]
## 支持图片 (Texture2D)、音频 (AudioStream)、视频 (VideoStream) 自适应加载与缓存

const SECTION := "AssetLoader"

@export var base_path: String = ""
@export var image_dir: String = "images"
@export var audio_dir: String = "audio"
@export var video_dir: String = "video"

# 资源缓存字典
var _cache: Dictionary = {}

func _ready() -> void:
	_try_sync_config()

## 软依赖读取配置（若不存在 VinoConfig 则保留脚本默认值）
func _try_sync_config() -> void:
	var config_node = get_node_or_null("/root/VinoConfig")
	if config_node and config_node.has_method("get_value"):
		base_path = config_node.get_value(SECTION, "base_path", base_path)
		image_dir = config_node.get_value(SECTION, "image_dir", image_dir)
		audio_dir = config_node.get_value(SECTION, "audio_dir", audio_dir)
		video_dir = config_node.get_value(SECTION, "video_dir", video_dir)

# ==============================
# 路径自适应构建
# ==============================
func _build_path(sub_dir: String, file_name: String) -> String:
	var combined: String
	if sub_dir.is_empty():
		combined = base_path.path_join(file_name)
	else:
		combined = base_path.path_join(sub_dir).path_join(file_name)
		
	# 优先从 VinoConfig 解析路径，若无配置单例则自行自适应解析
	var config_node = get_node_or_null("/root/VinoConfig")
	if config_node and config_node.has_method("resolve_path"):
		return config_node.resolve_path(combined)
	
	# 自立寻址逻辑
	if combined.is_absolute_path():
		return combined
	if OS.has_feature("editor"):
		return "res://".path_join(combined) if not combined.begins_with("res://") else combined
	else:
		var exe_dir := OS.get_executable_path().get_base_dir()
		var ext_path := exe_dir.path_join(combined.replace("res://", ""))
		return ext_path if FileAccess.file_exists(ext_path) else combined

# ==============================
# 资源加载接口 (带缓存)
# ==============================
## 加载图片
func load_texture(file_name: String) -> Texture2D:
	var path := _build_path(image_dir, file_name)
	if _cache.has(path):
		return _cache[path]

	var tex: Texture2D = null
	# 项目内部资源路径
	if path.begins_with("res://") and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	# 外部磁盘文件 [cite: 6]
	elif FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)

	if tex:
		_cache[path] = tex
		return tex

	push_error("[VinoAssetLoader] 图片加载失败: " + path)
	return null

## 加载音频 (OGV/WAV/MP3) [cite: 6]
func load_audio(file_name: String) -> AudioStream:
	var path := _build_path(audio_dir, file_name)
	if _cache.has(path):
		return _cache[path]

	var stream: AudioStream = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
			"wav": stream = AudioStreamWAV.load_from_file(path)
			"mp3": stream = AudioStreamMP3.load_from_file(path)

	if stream:
		_cache[path] = stream
		return stream

	push_error("[VinoAssetLoader] 音频加载失败: " + path)
	return null

## 加载视频 (.ogv / Theora)
func load_video(file_name: String) -> VideoStream:
	var path := _build_path(video_dir, file_name)
	if _cache.has(path):
		return _cache[path]

	var stream: VideoStream = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		stream = load(path) as VideoStream
	elif FileAccess.file_exists(path):
		var v_stream := VideoStreamTheora.new()
		v_stream.file = path
		stream = v_stream

	if stream:
		_cache[path] = stream
		return stream

	push_error("[VinoAssetLoader] 视频加载失败: " + path)
	return null

## 清理资源缓存 [cite: 6]
func clear_cache() -> void:
	_cache.clear()
