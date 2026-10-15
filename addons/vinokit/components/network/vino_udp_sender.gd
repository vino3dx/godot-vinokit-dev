class_name UDPSender
extends Node
## UDPSender - 通用 UDP 数据发送节点
##
## 支持从 VinoConfig 的 [UDPSender] 小节读取目标地址，以及以 cmd_hex 为前缀的
## 预设十六进制指令（例如 cmd_hex_open = "55 01 12 00"），供 send_preset_commands() 批量下发。

const TAG := "UDPSender"

@export var config_loader: Node ## 可选，指向场景中的 VinoConfig 节点
@export var target_ip: String = "127.0.0.1"
@export var target_port: int = 6000

var udp := PacketPeerUDP.new()
var hex_commands: Array[PackedByteArray] = []

func _ready() -> void:
	udp.bind(0)
	if config_loader:
		if config_loader.get("is_loaded"):
			_sync_from_config()
		elif config_loader.has_signal("config_loaded"):
			config_loader.config_loaded.connect(_sync_from_config)

func _sync_from_config() -> void:
	target_ip = str(config_loader.get_value("UDPSender", "target_ip", target_ip))
	target_port = int(config_loader.get_value("UDPSender", "target_port", target_port))
	udp.set_dest_address(target_ip, target_port)
	VinoLogger.info(TAG, "目标地址: %s:%d" % [target_ip, target_port])

	hex_commands.clear()
	var keys: Array = config_loader.get_section_keys("UDPSender")
	keys.sort()
	for k in keys:
		if not str(k).begins_with("cmd_hex"):
			continue
		var bytes := _parse_hex(str(config_loader.get_value("UDPSender", k, "")))
		if bytes.size() > 0:
			hex_commands.append(bytes)
	VinoLogger.info(TAG, "已加载预设指令数: %d" % hex_commands.size())

func set_target(ip: String, port: int) -> void:
	target_ip = ip
	target_port = port
	udp.set_dest_address(target_ip, target_port)

func send_bytes(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		VinoLogger.warn(TAG, "尝试发送空数据")
		return
	udp.put_packet(bytes)

func send_string(text: String) -> void:
	send_bytes(text.to_utf8_buffer())

## 依次发送配置中预设的所有 cmd_hex* 指令；可绑定到按钮 pressed 等信号使用
func send_preset_commands() -> void:
	if hex_commands.is_empty():
		VinoLogger.warn(TAG, "hex_commands 为空，请检查配置")
		return
	for bytes in hex_commands:
		udp.put_packet(bytes)

func _parse_hex(hex_str: String) -> PackedByteArray:
	var result := PackedByteArray()
	for part in hex_str.strip_edges().split(" ", false):
		if not _is_hex_byte(part):
			VinoLogger.warn(TAG, "非法 HEX 字符: " + part)
			continue
		result.append(part.hex_to_int())
	return result

func _is_hex_byte(s: String) -> bool:
	if s.length() == 0 or s.length() > 2:
		return false
	for c in s:
		var code := c.unicode_at(0)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)):
			return false
	return true
