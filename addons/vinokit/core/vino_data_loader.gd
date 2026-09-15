class_name VinoDataLoader
extends Node
## VinoDataLoader - 通用数据读取管理器
##
## 支持 TEXT / JSON / CSV / INI 四种格式，路径解析规则与其余 VinoKit 模块保持一致

const TAG := "VinoData"

enum DataFormat { TEXT, JSON, CSV, INI }

@export_group("基础设置")
@export var data_format: DataFormat = DataFormat.TEXT
@export_file("*.txt", "*.json", "*.csv", "*.ini") var file_path: String = ""

@export_group("高级设置")
@export var csv_delimiter: String = ","
@export var auto_load_on_ready: bool = true

## 读取后的数据；JSON/TEXT 视具体内容而定，CSV 为 Array[Dictionary]，INI 为 Dictionary
var loaded_data: Variant = null

func _ready() -> void:
	if auto_load_on_ready and not Engine.is_editor_hint():
		load_data()

func load_data() -> Variant:
	if file_path.is_empty():
		VinoLogger.warn(TAG, "未指定读取路径")
		return null

	var real_path := VinoPathResolver.resolve_via(file_path, get_node_or_null("/root/VinoConfig"))
	if not FileAccess.file_exists(real_path):
		VinoLogger.error(TAG, "文件不存在: " + real_path)
		return null

	match data_format:
		DataFormat.TEXT: loaded_data = _read_as_text(real_path)
		DataFormat.JSON: loaded_data = _read_as_json(real_path)
		DataFormat.CSV: loaded_data = _read_as_csv(real_path)
		DataFormat.INI: loaded_data = _read_as_ini(real_path)

	if loaded_data == null:
		VinoLogger.error(TAG, "数据加载失败: " + real_path)
	else:
		VinoLogger.info(TAG, "数据加载成功: " + real_path)
	return loaded_data

func reload() -> Variant:
	return load_data()

func _read_as_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file else ""

func _read_as_json(path: String) -> Variant:
	var content := _read_as_text(path)
	if content.is_empty():
		VinoLogger.error(TAG, "JSON 文件为空: " + path)
		return null
	var result: Variant = JSON.parse_string(content)
	if result == null:
		VinoLogger.error(TAG, "JSON 解析失败: " + path)
	return result

func _read_as_csv(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []

	var result: Array = []
	var headers := file.get_csv_line(csv_delimiter)
	while not file.eof_reached():
		var line := file.get_csv_line(csv_delimiter)
		if line.size() < headers.size() or line[0].is_empty():
			continue
		var entry := {}
		for i in range(headers.size()):
			entry[headers[i]] = _auto_convert(line[i])
		result.append(entry)
	return result

func _read_as_ini(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		VinoLogger.error(TAG, "INI 读取失败: " + path)
		return {}
	var dict := {}
	for section in config.get_sections():
		dict[section] = {}
		for key in config.get_section_keys(section):
			dict[section][key] = config.get_value(section, key)
	return dict

func _auto_convert(value: String) -> Variant:
	if value.is_valid_int():
		return int(value)
	if value.is_valid_float():
		return float(value)
	return value

func _get_configuration_warnings() -> PackedStringArray:
	return ["必须指定一个文件路径才能读取数据。"] if file_path.is_empty() else []
