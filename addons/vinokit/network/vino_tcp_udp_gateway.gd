class_name TcpUdpGateway
extends Node
## TcpUdpGateway - 在 TCP 服务器与局域网 UDP 设备之间做双向数据桥接的协议网关节点。
##
## [b]功能特性[/b][br]
## 双向转发：TCP（云端）↔ UDP（硬件）[br]
## 原始透传：默认按字节流直接转发，完全保留原始数据[br]
## 指令映射（可选）：内置字典替换机制，截获并翻译报文，例如
## 收到 TCP "4F50454E"(OPEN) → 转发 UDP "55 01 12 00 00 00 01 69"[br]
## 脏数据过滤：校验 UDP 包发送方 IP，屏蔽局域网内的未知干扰[br]
## 状态监听：tcp_connected / tcp_disconnected 信号[br][br]
##
## [b]适用场景[/b][br]
## 将云端长连接服务器通讯代理到本地硬件设备（继电器、传感器等短连接设备）的边缘网关。

const TAG := "Gateway"

signal tcp_connected
signal tcp_disconnected

@export_group("TCP Settings")
@export var tcp_server_ip: String = "127.0.0.1"
@export var tcp_server_port: int = 8080

@export_group("UDP Settings")
@export var udp_listen_port: int = 9001
@export var udp_target_ip: String = "" ## 目标硬件设备 IP，需按部署环境配置
@export var udp_target_port: int = 6000

@export_group("Gateway Logic")
@export var use_mapping: bool = true ## 关闭则原始字节流透传，不做指令映射

## TCP 指令(Key) → UDP 指令(Value) 映射表；收到的字节会转为大写 Hex 字符串后匹配
@export var tcp_to_udp_map: Dictionary = {
	"4F50454E": "55 01 12 00 00 00 01 69",   # 示例：OPEN → 继电器开
	"434C4F5345": "55 01 12 00 00 00 00 68", # 示例：CLOSE → 继电器关
}

## UDP 回码(Key) → TCP 回传(Value) 映射表
@export var udp_to_tcp_map: Dictionary = {
	"AA 01 00": "53554343455353", # 示例：继电器成功回码 → TCP 返回 SUCCESS
}

var tcp := StreamPeerTCP.new()
var udp := PacketPeerUDP.new()

var _was_tcp_connected := false

func _ready() -> void:
	udp.bind(udp_listen_port)
	tcp.connect_to_host(tcp_server_ip, tcp_server_port)

func _process(_delta: float) -> void:
	_process_tcp_inbound()
	_process_udp_inbound()

# ------------------------------------------
# TCP -> UDP（服务器 -> 硬件）
# ------------------------------------------
func _process_tcp_inbound() -> void:
	tcp.poll()
	var status := tcp.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTED and not _was_tcp_connected:
		_was_tcp_connected = true
		tcp_connected.emit()
	elif status != StreamPeerTCP.STATUS_CONNECTED and _was_tcp_connected:
		_was_tcp_connected = false
		tcp_disconnected.emit()

	if status != StreamPeerTCP.STATUS_CONNECTED or tcp.get_available_bytes() <= 0:
		return

	var raw_data := tcp.get_partial_data(tcp.get_available_bytes())[1]
	if not use_mapping:
		VinoLogger.info(TAG, "TCP->UDP 原始透传")
		_send_udp(raw_data)
		return

	var hex_key := raw_data.hex_encode().to_upper()
	if tcp_to_udp_map.has(hex_key):
		var mapped_hex: String = tcp_to_udp_map[hex_key].replace(" ", "")
		VinoLogger.info(TAG, "TCP->UDP 匹配转换: %s => %s" % [hex_key, mapped_hex])
		_send_udp(mapped_hex.hex_decode())
	else:
		VinoLogger.info(TAG, "TCP->UDP 未匹配，丢弃")

# ------------------------------------------
# UDP -> TCP（硬件 -> 服务器）
# ------------------------------------------
func _process_udp_inbound() -> void:
	while udp.get_available_packet_count() > 0:
		var raw_data := udp.get_packet()
		if udp.get_packet_ip() != udp_target_ip:
			continue

		if not use_mapping:
			VinoLogger.info(TAG, "UDP->TCP 原始透传")
			_send_tcp(raw_data)
			continue

		var hex_key := raw_data.hex_encode().to_upper()
		if not _find_and_send_mapped_tcp(hex_key):
			VinoLogger.info(TAG, "UDP->TCP 未匹配")

func _find_and_send_mapped_tcp(hex_key: String) -> bool:
	for k in udp_to_tcp_map.keys():
		var clean_k: String = str(k).replace(" ", "").to_upper()
		if clean_k == hex_key:
			var target_hex: String = udp_to_tcp_map[k].replace(" ", "")
			_send_tcp(target_hex.hex_decode())
			VinoLogger.info(TAG, "UDP->TCP 匹配转换: %s => %s" % [hex_key, target_hex])
			return true
	return false

func _send_udp(data: PackedByteArray) -> void:
	udp.set_dest_address(udp_target_ip, udp_target_port)
	udp.put_packet(data)

func _send_tcp(data: PackedByteArray) -> void:
	if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		tcp.put_data(data)
