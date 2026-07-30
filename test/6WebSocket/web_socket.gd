extends Control

var socket := WebSocketPeer.new()

@onready var chat_box = $RichTextLabel
@onready var input = $LineEdit
@onready var button = $Button

func _ready():
	socket.connect_to_url("ws://127.0.0.1:8765")
	button.pressed.connect(send_message)

func _process(_delta):
	socket.poll()

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count():
			add_message(socket.get_packet().get_string_from_utf8())

func send_message():
	if input.text == "":
		return

	var msg = {
		"name": "玩家",
		"text": input.text
	}

	socket.send_text(JSON.stringify(msg))
	input.text = ""

func add_message(text):
	var data = JSON.parse_string(text)

	if data:
		chat_box.append_text("\n%s: %s" % [data["name"], data["text"]])
