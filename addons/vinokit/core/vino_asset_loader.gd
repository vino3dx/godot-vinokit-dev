class_name VinoAssetLoader
extends Node
## VinoAssetLoader - 多媒体资源加载管理器
##
## 建议 Autoload 挂载名称：[b]VinoAssets[/b]
## 支持图片(Texture2D) / 音频(AudioStream) / 视频(VideoStream) 的自适应加载与缓存

const TAG := "VinoAssets"
const SECTION := "AssetLoader"

@export var base_path: String = ""
@export var image_dir: String = "images"
@export var audio_dir: String = "audio"
@export var video_dir: String = "video"

var _cache: Dictionary = {}

func _ready() -> void:
	_sync_from_config()

## 软依赖读取 VinoConfig；若场景中未挂载该单例，则保留脚本 / Inspector 中的默认值
func _sync_from_config() -> void:
	var config := get_node_or_null("/root/VinoConfig")
	if not (config and config.has_method("get_value")):
		return
	base_path = config.get_value(SECTION, "base_path", base_path)
	image_dir = config.get_value(SECTION, "image_dir", image_dir)
	audio_dir = config.get_value(SECTION, "audio_dir", audio_dir)
	video_dir = config.get_value(SECTION, "video_dir", video_dir)

func load_texture(file_name: String) -> Texture2D:
	return _load_cached(image_dir, file_name, func(path: String):
		if path.begins_with("res://") and ResourceLoader.exists(path):
			return load(path) as Texture2D
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				return ImageTexture.create_from_image(img)
		return null
	)

func load_audio(file_name: String) -> AudioStream:
	return _load_cached(audio_dir, file_name, func(path: String):
		if path.begins_with("res://") and ResourceLoader.exists(path):
			return load(path) as AudioStream
		if FileAccess.file_exists(path):
			match path.get_extension().to_lower():
				"ogg": return AudioStreamOggVorbis.load_from_file(path)
				"wav": return AudioStreamWAV.load_from_file(path)
				"mp3": return AudioStreamMP3.load_from_file(path)
		return null
	)

func load_video(file_name: String) -> VideoStream:
	return _load_cached(video_dir, file_name, func(path: String):
		if path.begins_with("res://") and ResourceLoader.exists(path):
			return load(path) as VideoStream
		if FileAccess.file_exists(path):
			var stream := VideoStreamTheora.new()
			stream.file = path
			return stream
		return null
	)

## 清空资源缓存（如需强制重新读取磁盘上已被替换的文件）
func clear_cache() -> void:
	_cache.clear()

func _build_path(sub_dir: String, file_name: String) -> String:
	var combined := base_path.path_join(sub_dir).path_join(file_name) if not sub_dir.is_empty() \
		else base_path.path_join(file_name)
	return VinoPathResolver.resolve_via(combined, get_node_or_null("/root/VinoConfig"))

## 三类资源共用的“查缓存 -> 未命中则加载 -> 写入缓存”流程；
## loader 只需描述“怎么把一个具体路径变成资源”这一件事。
func _load_cached(sub_dir: String, file_name: String, loader: Callable) -> Variant:
	var path := _build_path(sub_dir, file_name)
	if _cache.has(path):
		return _cache[path]

	var result: Variant = loader.call(path)
	if result:
		_cache[path] = result
	else:
		VinoLogger.error(TAG, "资源加载失败: " + path)
	return result
