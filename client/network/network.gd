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

const SESSION_FILE := "user://session.txt"
const RECONNECT_DELAY_SECONDS := 2.0
# True while a reconnect is waiting out its delay, so a second one isn't started.
var reconnecting := false
# True after a reconnect sent resume_session, so its reply (handled here, not by a scene) is recognized.
var resuming := false

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
			# The server forgets who a socket is when it closes, so a logged-in player resumes their session.
			if not Session.token.is_empty():
				resuming = true
				send({"type": "resume_session", "token": Session.token})
		elif state == WebSocketPeer.STATE_CLOSED:
			print("Disconnected from server (code %d: %s)" % [socket.get_close_code(), socket.get_close_reason()])
			disconnected.emit()
			_reconnect()

	while socket.get_available_packet_count() > 0:
		var payload := socket.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(payload)
		if parsed is Dictionary:
			_handle_session_message(parsed)
			message_received.emit(parsed)

# Waits RECONNECT_DELAY_SECONDS (so a down server isn't retried every frame), then connects again.
# If that attempt fails, the socket goes back to STATE_CLOSED and _process calls this again.
func _reconnect() -> void:
	if reconnecting:
		return
	reconnecting = true
	await get_tree().create_timer(RECONNECT_DELAY_SECONDS).timeout
	reconnecting = false
	if socket.connect_to_url(url) != OK:
		_reconnect()

# Handles the messages that can arrive on any scene: the reply to a reconnect's resume_session, and "kicked"
# (this account logged in somewhere else). Either way, if the session is no longer good, go back to the splash screen.
func _handle_session_message(data: Dictionary) -> void:
	if data.get("type") == "kicked":
		print("Kicked: ", data.get("reason", ""))
		_return_to_splash()
	elif data.get("type") == "resume_session_result" and resuming:
		resuming = false
		if not data.get("success", false):
			_return_to_splash()

# Forgets the saved login (so the splash screen doesn't auto-resume it) and shows the splash screen.
func _return_to_splash() -> void:
	resuming = false
	Session._clear_session()
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(SESSION_FILE)
	get_tree().change_scene_to_file("res://client/splash_screen.tscn")

# Sends a message to the server as a JSON text frame. Returns false (and warns) if it couldn't be sent,
# e.g. while reconnecting. Only the message type is logged, since login messages carry a password.
func send(message: Dictionary) -> bool:
	if not is_connected_to_server():
		push_warning("Not connected to server; dropped message: %s" % message.get("type"))
		return false
	var err := socket.send_text(JSON.stringify(message))
	if err != OK:
		push_warning("Failed to send message %s (error %d)" % [message.get("type"), err])
		return false
	return true

# TODO: logout helper for later (e.g. a Logout button in the map UI):
#   send {"type": "logout", "token": Session.token}, delete "user://session.txt" with
#   DirAccess.remove_absolute, call Session._clear_session(), then change_scene_to_file to the splash screen.

# Returns true when the socket is open and messages can be sent.
func is_connected_to_server() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN
