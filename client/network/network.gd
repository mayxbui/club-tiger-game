extends Node

signal message_received(data: Dictionary)
signal connected
signal disconnected

var socket := WebSocketPeer.new()
# TODO: itch.io serves the game over https, and browsers block plain ws:// from an https page.
# Before deploying, this must be a wss:// URL (needs a domain + TLS certificate on the VM, e.g. Caddy).
# OS.has_feature("web") returns true in the HTML5 export, so you can keep ws:// for local testing.
var url := "ws://20.88.18.140:3103"
var last_state := WebSocketPeer.STATE_CLOSED

# Starts connecting to the server when the game launches.
func _ready() -> void:
	socket.connect_to_url(url)

# Polls the socket every frame, emits connected/disconnected when the state changes, and forwards each JSON message.
func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()

	if state != last_state:
		last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			connected.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.emit()
			# TODO: reconnect automatically. Calling socket.connect_to_url(url) again restarts the same
			# WebSocketPeer. Put that in its own function (e.g. _reconnect()) and call it from here, rather
			# than awaiting inside _process. In it, wait first (`await get_tree().create_timer(2.0).timeout`)
			# so a down server isn't retried every frame. socket.get_close_code() / get_close_reason()
			# help with debugging.
			# After reconnecting, the server no longer knows who this socket is (socketUsers is per socket),
			# so if Session has a token, send resume_session again when `connected` fires.

	while socket.get_available_packet_count() > 0:
		var payload := socket.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(payload)
		if parsed is Dictionary:
			message_received.emit(parsed)

# Sends a message to the server as JSON.
func send(message: Dictionary) -> void:
	# TODO: FIX - put_packet fails if the socket isn't open, and the message is silently lost. Check
	# is_connected_to_server() first, or use socket.send_text(JSON.stringify(message)), which returns an
	# Error you can compare to OK. send_text also sends a text frame, which matches what the server's
	# JSON.parse(raw.toString()) expects.
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())

# TODO: logout helper for later (e.g. a Logout button in the map UI):
#   send {"type": "logout", "token": Session.token}, delete "user://session.txt" with
#   DirAccess.remove_absolute, call Session._clear_session(), then change_scene_to_file to the splash screen.

# Returns true when the socket is open and messages can be sent.
func is_connected_to_server() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN
