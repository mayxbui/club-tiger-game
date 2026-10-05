extends Node2D

const SESSION_FILE := "user://session.txt"

# Shows one message in LabelDebug and restarts TimerDebug, which clears it a few seconds later.
func show_message(msg: String) -> void:
	$LabelDebug.text = msg
	$TimerDebug.start()

# Listens for server replies while the sign-in screen is open, and clears LabelDebug when TimerDebug runs out.
func _ready() -> void:
	Network.message_received.connect(_on_message_received)
	$TimerDebug.timeout.connect(func(): $LabelDebug.text = "")

# Handles the server's login_result: goes to the map on success, shows the error otherwise.
func _on_message_received(data: Dictionary) -> void:
	# Server sends type "error" for crashes/malformed messages (e.g. DB failures)
	if data.get("type") == "error":
		show_message("Server error: " + str(data.get("error")) + "\n")
		$BtnLogin.disabled = false
		return
	if data.get("type") != "login_result":
		return

	$BtnLogin.disabled = false
	if data.get("success"):
		show_message("Logged in as " + str(data.get("username")) + "\n")
		# Keep the login in the Session autoload so the map can use it after this scene is freed.
		# JSON numbers arrive as floats, so userId is converted with int(); character holds skin/hair/eyes.
		Session.token = str(data.get("token", ""))
		Session.userId = int(data.get("userId", 0))
		Session.username = str(data.get("username", ""))
		Session.email = str(data.get("email"), "")
		Session.character = data.get("character", {})

		if $HBoxContainer/CheckboxRemember.button_pressed:
			var file = FileAccess.open(SESSION_FILE, FileAccess.WRITE)
			if file:
				file.store_string(Session.token)
			else:
				print("Failed to save session token. Error: ", FileAccess.get_open_error())
		elif FileAccess.file_exists(SESSION_FILE):
			# "Remember me" is off, so forget any session saved by an earlier login.
			DirAccess.remove_absolute(SESSION_FILE)

		get_tree().change_scene_to_file("res://client/map/world_map.tscn")
	else:
		show_message("Error: " + str(data.get("error")) + "\n")
		$VBoxContainer/InputPassword.clear()

# Opens the create-account screen.
func _on_btn_create_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/create_account.tscn")


# Checks the form, sends the login request to the server and waits for login_result.
func _on_btn_login_pressed() -> void:
	var username = $VBoxContainer/InputUsername.text.strip_edges()
	var email = $VBoxContainer/InputUsername.text.strip_edges()
	var password = $VBoxContainer/InputPassword.text
	var remember = $HBoxContainer/CheckboxRemember.button_pressed

	if username.is_empty() or password.is_empty():
		show_message("Please enter username and password.\n")
		return

	if not Network.is_connected_to_server():
		show_message("Not connected to server yet.\n")
		return

	Network.send({
		"type": "login",
		"username": username,
		"email": email,
		"password": password,
		"remember_me": remember
	})
	$BtnLogin.disabled = true

# Opens the reset-password screen.
func _on_btn_forgot_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/reset_password.tscn")
