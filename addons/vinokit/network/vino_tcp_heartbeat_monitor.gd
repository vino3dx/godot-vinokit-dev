class_name HeartbeatMonitor
extends Node
## HeartbeatMonitor - TCP 长连接心跳监控器：自动连接、注册、状态同步、断线重连。
##
## [b]用法[/b][br]
## 1. 添加节点（建议 Autoload 或主场景），配置 host / port / device_id[br]
## 2. 调用 set_state() 同步状态[br]
## 3. 监听信号：connected / disconnected / state_changed[br]
##
## [b]通信协议（项目相关，接入不同后端时需按实际协议调整）[/b][br]
## 注册：ID:&lt;id&gt;:Md5[br]
## 心跳：State:&lt;id&gt;:&lt;state&gt;[br]
##
## [b]特性[/b][br]
## 自动重连（reconnect_delay）/ 心跳间隔控制（heartbeat_interval）/
## 防重复重连与重复注册 / 仅在注册成功后才开始发送心跳

const TAG := "Heartbeat"

signal connected
signal disconnected
signal state_changed(new_state: int)

@export var host: String = "" ## 服务器主机 IP，需按部署环境配置
@export var port: int = 8080
@export var device_id: int = 1
@export var heartbeat_interval: float = 2.0
@export var reconnect_delay: float = 3.0

var client := StreamPeerTCP.new()
var current_state: int = 0

var _connected := false
var _is_reconnecting := false
var _heartbeat_timer: Timer
var _reconnect_timer: Timer

func _ready() -> void:
	_setup_timers()
	if host.is_empty():
		VinoLogger.warn(TAG, "host 未配置，跳过自动连接")
		return
	_connect_to_server()

func _connect_to_server() -> void:
	_is_reconnecting = false
	VinoLogger.info(TAG, "连接服务器 %s:%d" % [host, port])
	client = StreamPeerTCP.new() # 每次新建，避免旧状态残留
	if client.connect_to_host(host, port) != OK:
		VinoLogger.error(TAG, "connect_to_host 失败")
		_schedule_reconnect()

func _process(_delta: float) -> void:
	if host.is_empty():
		return
	client.poll()
	_check_connection_state()
	_read_incoming()

func _check_connection_state() -> void:
	match client.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not _connected:
				_connected = true
				_is_reconnecting = false
				VinoLogger.info(TAG, "连接成功，发送注册")
				connected.emit()
				_send_register()

		StreamPeerTCP.STATUS_CONNECTING:
			pass # 正在握手，等待

		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			if _connected:
				_connected = false
				VinoLogger.info(TAG, "连接断开")
				_heartbeat_timer.stop() # 断线期间停止心跳，避免乱发
				disconnected.emit()
				client.disconnect_from_host()
			_schedule_reconnect()

func _read_incoming() -> void:
	if not _connected or client.get_available_bytes() <= 0:
		return

	var msg := client.get_data(client.get_available_bytes())[1].get_string_from_utf8().strip_edges()
	if msg.is_empty():
		return
	VinoLogger.info(TAG, "收到: %s" % msg)

	if msg.contains("未注册ID:"):
		VinoLogger.info(TAG, "检测到未注册，重新发送注册包")
		_heartbeat_timer.stop()
		_send_register()
	elif msg.contains("注册成功") or msg.contains("ID:%d:" % device_id):
		VinoLogger.info(TAG, "注册确认，启动心跳")
		_heartbeat_timer.stop() # 防止重复 start
		_heartbeat_timer.start()
	elif msg.begins_with("Success"):
		set_state(1)

func _on_heartbeat_timer() -> void:
	if _connected:
		_send_state_packet()

## 切换业务状态并同步给服务器（状态未变化时不重复发送）
func set_state(state: int) -> void:
	if current_state == state:
		return
	current_state = state
	VinoLogger.info(TAG, "状态切换 → %d" % state)
	state_changed.emit(state)
	if _connected:
		_send_state_packet()

func _send_state_packet() -> void:
	var msg := "State:%d:%d" % [device_id, current_state]
	client.put_data(msg.to_utf8_buffer())
	VinoLogger.info(TAG, "发送: %s" % msg)

func _send_register() -> void:
	var msg := "ID:%d:Md5" % device_id
	client.put_data(msg.to_utf8_buffer())
	VinoLogger.info(TAG, "注册: %s" % msg)
	await get_tree().create_timer(0.5).timeout # 给服务器留出处理注册的时间
	_heartbeat_timer.start()

func _schedule_reconnect() -> void:
	if _is_reconnecting:
		return
	_is_reconnecting = true
	VinoLogger.info(TAG, "%s 秒后重连" % reconnect_delay)
	_reconnect_timer.start()

func _on_reconnect_timer() -> void:
	_is_reconnecting = false
	_connect_to_server()

func _setup_timers() -> void:
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = heartbeat_interval
	_heartbeat_timer.autostart = false # 注册成功后才启动心跳
	_heartbeat_timer.timeout.connect(_on_heartbeat_timer)
	add_child(_heartbeat_timer)

	_reconnect_timer = Timer.new()
	_reconnect_timer.wait_time = reconnect_delay
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timer)
	add_child(_reconnect_timer)
