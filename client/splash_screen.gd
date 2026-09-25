extends Node2D

const SESSION_FILE := "user://session.txt"
const CONNECT_TIMEOUT_SECONDS := 3.0
const CONNECT_CHECK_SECONDS := 0.1

# Token read from SESSION_FILE; kept here because the server doesn't send it back in resume_session_result.
var token := ""

# Tries to resume session so returning players skip sign-in; otherwise shows the buttons.
func _ready() -> void:
	if not FileAccess.file_exists(SESSION_FILE):
		_show_auth_buttons()
		return
	token = FileAccess.get_file_as_string(SESSION_FILE).strip_edges()
	if token.is_empty():
		_show_auth_buttons()
		return

	$btn_create.visible = false
	$btn_login.visible = false
	Network.message_received.connect(_on_network_message_received)

	# Wait up to CONNECT_TIMEOUT_SECONDS for the connection, checking every CONNECT_CHECK_SECONDS.
	var waited := 0.0
	while not Network.is_connected_to_server() and waited < CONNECT_TIMEOUT_SECONDS:
		await get_tree().create_timer(CONNECT_CHECK_SECONDS).timeout
		waited += CONNECT_CHECK_SECONDS
	if not Network.is_connected_to_server():
		_show_auth_buttons()
		return

	Network.send({"type": "resume_session", "token": token})

# Shows the create-account and sign-in buttons.
func _show_auth_buttons() -> void:
	$btn_create.visible = true
	$btn_login.visible = true

# Handles resume_session_result: goes to the map if the saved session is still valid, otherwise forgets it.
func _on_network_message_received(data: Dictionary) -> void:
	# A server error means the resume didn't go through, so let the player sign in manually.
	if data.get("type") == "error":
		_show_auth_buttons()
		return
	if data.get("type") != "resume_session_result":
		return

	if data.get("success", false):
		Session.token = token
		Session.userId = int(data.get("userId", 0))
		# username and character stay empty until the server's resume_session_result includes them.
		Session.username = str(data.get("username", ""))
		Session.character = data.get("character", {})
		get_tree().change_scene_to_file("res://client/map/map.tscn")
	else:
		DirAccess.remove_absolute(SESSION_FILE)
		_show_auth_buttons()


# Opens the create-account screen.
func _on_btn_create_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/create_account.tscn")

# Opens the sign-in screen.
func _on_btn_login_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/signin.tscn")
