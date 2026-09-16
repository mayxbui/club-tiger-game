extends Node

var socket = WebSocketPeer.new()
var url = "ws://20.88.18.140:3103"
var last_state = WebSocketPeer.STATE_CLOSED

func _ready():
	var err = socket.connect_to_url(url)
	if err != OK:
		print("Test fail")
		set_process(false)

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()

	if state != last_state:
		last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			$debug.text += "Connected to server\n"
		elif state == WebSocketPeer.STATE_CLOSED:
			$debug.text += "Disconnected from server\n"
			set_process(false)

	while socket.get_available_packet_count() > 0:
		data_received(socket.get_packet().get_string_from_utf8())

func data_received(payload: String):
	$debug.text += "Message from server: " + payload + "\n"

func send(message):
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())

func _on_button_create_acc_pressed() -> void:
	var username = $input_username.text
	var email = $input_email.text
	var password = $input_pass.text

	if username.is_empty() or email.is_empty() or password.is_empty():
		$debug.text += "Please fill out username, email, and password.\n"
		return

	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		$debug.text += "Not connected to server yet.\n"
		return

	send({
		"type": "create_account",
		"username": username,
		"email": email,
		"password": password
	})
