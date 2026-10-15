class_name UDPReceiver
extends Node
## UDPReceiver - 通用 UDP 数据接收节点
##
## 监听指定端口，将收到的原始字节、以及（若能解码为 UTF-8 文本时）文本内容
## 通过信号广播出去，交由外部逻辑处理。

const TAG := "UDPReceiver"

signal packet_received(data: PackedByteArray)
signal string_received(text: String)

@export var config_loader: Node ## 可选，指向场景中的 VinoConfig 节点
@export var listen_port: int = 6000
@export var auto_start: bool = true

var udp := PacketPeerUDP.new()
var _is_listening: bool = false

func _ready() -> void:
	if config_loader:
		if config_loader.get("is_loaded"):
			_sync_from_config()
		elif config_loader.has_signal("config_loaded"):
			config_loader.config_loaded.connect(_sync_from_config)

	if auto_start:
		start_listening()

## 从 [UDPReceiver] 小节读取 listen_port；若已在监听中则重启以应用新端口
func _sync_from_config() -> void:
	listen_port = int(config_loader.get_value("UDPReceiver", "listen_port", listen_port))
	VinoLogger.info(TAG, "配置同步完成，监听端口: %d" % listen_port)
	if _is_listening:
		stop_listening()
		start_listening()

func start_listening() -> bool:
	if _is_listening:
		VinoLogger.warn(TAG, "已在监听中，请先调用 stop_listening()")
		return false
	var err := udp.bind(listen_port)
	if err != OK:
		VinoLogger.error(TAG, "绑定端口 %d 失败，错误码 %d" % [listen_port, err])
		return false
	_is_listening = true
	VinoLogger.info(TAG, "开始监听端口 %d" % listen_port)
	return true

func stop_listening() -> void:
	if not _is_listening:
		return
	udp.close()
	_is_listening = false
	VinoLogger.info(TAG, "停止监听")

func _process(_delta: float) -> void:
	if not _is_listening:
		return
	while udp.get_available_packet_count() > 0:
		var data := udp.get_packet()
		VinoLogger.info(TAG, "← [%s:%d] bytes=%d" % [udp.get_packet_ip(), udp.get_packet_port(), data.size()])
		packet_received.emit(data)
		var text := data.get_string_from_utf8()
		if not text.is_empty():
			string_received.emit(text)

## 工具：将字节数组转为空格分隔的十六进制字符串，便于调试打印
static func bytes_to_hex_string(data: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in data:
		parts.append("%02X" % b)
	return " ".join(parts)
