extends Node2D

# Username rule (same as the server), compiled once in _ready
var username_check: RegEx

# Compiles the username rule, listens for server replies, and links the customizer's choices to the preview player.
func _ready() -> void:
	username_check = RegEx.new()
	username_check.compile("^[A-Za-z0-9_]{3,20}$")
	$TimerDebug.timeout.connect(func(): $CanvasLayer/OuterPanel/LabelDebug.text = "")
	Network.message_received.connect(_on_message_received)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.skin_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_skin)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.hair_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_hair)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.eyes_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_eyes)

# Shows one message in LabelDebug and restarts TimerDebug, which clears it a few seconds later.
func show_message(msg: String) -> void:
	$CanvasLayer/OuterPanel/LabelDebug.text = msg
	$TimerDebug.start()

# Handles the server's create_account_result: re-enables the buttons, then goes to the map on success or shows the error.
func _on_message_received(data: Dictionary) -> void:
	# Server sends type "error" for crashes/malformed messages (e.g. DB failures); re-enable the buttons so the player can retry.
	if data.get("type") == "error":
		show_message("Server error: " + str(data.get("error"))+ "\n")
		$CanvasLayer/OuterPanel/BtnCreate.disabled = false
		$CanvasLayer/OuterPanel/BtnBack.disabled = false
		return
	if data.get("type") != "create_account_result":
		return

	$CanvasLayer/OuterPanel/BtnCreate.disabled = false
	$CanvasLayer/OuterPanel/BtnBack.disabled = false
	if data.get("success"):
		show_message("Account created! Welcome, " + str(data.get("username"))+"\n")
		# Save the new login to Session for the map. The character comes from the customizer
		Session.token = data.get("token")
		Session.userId = int(data.get("userId"))
		Session.username = data.get("username")
		Session.character = $CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.get_selection()
		get_tree().change_scene_to_file("res://client/map/world_map.tscn")
	else:
		show_message("Error: " + str(data.get("error")) + "\n")
		$CanvasLayer/OuterPanel/InputPassword.clear()



# Checks the username and password against the server's rules and returns an error message, or "" if both are fine.
func validate_creds(username: String, password: String) -> String:
	if username_check.search(username.strip_edges()) == null:
		return "Username must be minimum 3 (include letters, numbers, or underscores)"
	if password.length() < 8 or password.length() > 72:
		return "Password must be 8 to 72 characters long"
	return ""


# Checks the form and sends the new account and character choices to the server.
func _on_btn_create_pressed() -> void:
	var username = $CanvasLayer/OuterPanel/CharacterPanel/InputUsername.text
	var email = $CanvasLayer/OuterPanel/InputEmail.text
	var password = $CanvasLayer/OuterPanel/InputPassword.text
	# Blank fields are caught here; the server trims the username and email and lowercases the email.
	if username.strip_edges().is_empty() or email.strip_edges().is_empty() or password.is_empty():
		show_message("Please fill out username, email, and password.\n")
		return
	# Same rules as the server, so the player sees the problem right away instead of after a round trip.
	var validation_err = validate_creds(username, password)
	if not validation_err.is_empty():
		show_message(validation_err + "\n")
		return
	if not Network.is_connected_to_server():
		show_message("Not connected to server yet.\n")
		return
	# Next checkpoint: once the customizer has top and bottom (see the TODO at the top of
	# character_customizer.gd), get_selection() will include them too.
	var character = $CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.get_selection()

	Network.send({
		"type": "create_account",
		"username": username,
		"email": email,
		"password": password,
		"character": character
	})
	# Disabled until create_account_result arrives, so double clicks can't send two signups.
	$CanvasLayer/OuterPanel/BtnCreate.disabled = true
	$CanvasLayer/OuterPanel/BtnBack.disabled = true

# Goes back to the splash screen.
func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://client/splash_screen.tscn")

# Updates the preview player's name tag as the player types their username (the scene connects text_changed here).
func _on_input_username_text_changed(new_username: String) -> void:
	$CanvasLayer/OuterPanel/CharacterPanel/Player.set_username(new_username)


func _on_btn_login_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/signin.tscn")
