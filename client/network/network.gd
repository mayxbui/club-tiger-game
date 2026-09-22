extends Node

signal message_received(data: Dictionary)
signal connected
signal disconnected

var socket := WebSocketPeer.new()
var url := "ws://20.88.18.140:3103"
var last_state := WebSocketPeer.STATE_CLOSED

func _ready() -> void:
	socket.connect_to_url(url)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()

	if state != last_state:
		last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connected.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.emit()

	while socket.get_available_packet_count() > 0:
		var payload := socket.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(payload)
		if parsed is Dictionary:
			message_received.emit(parsed)

func send(message: Dictionary) -> void:
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())

func is_connected_to_server() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN
