extends Node2D

# Username rule (same as the server), compiled once in _ready
var username_check: RegEx
# Compiles the username rule, listens for server replies, and links the customizer's choices to the preview player.
func _ready() -> void:
	username_check = RegEx.new()
	username_check.compile("^[A-Za-z0-9_]{3,20}$")
	Network.message_received.connect(_on_message_received)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.skin_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_skin)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.hair_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_hair)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.eyes_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player.change_eyes)

# Handles the server's create_account_result: re-enables the buttons, then goes to the map on success or shows the error.
func _on_message_received(data: Dictionary) -> void:
	# Server sends type "error" for crashes/malformed messages (e.g. DB failures); re-enable the buttons so the player can retry.
	if data.get("type") == "error":
		$CanvasLayer/OuterPanel/debug.text += "Server error: " + str(data.get("error")) + "\n"
		$CanvasLayer/OuterPanel/btn_create.disabled = false
		$CanvasLayer/OuterPanel/btn_back.disabled = false
		return
	if data.get("type") != "create_account_result":
		return

	$CanvasLayer/OuterPanel/btn_create.disabled = false
	$CanvasLayer/OuterPanel/btn_back.disabled = false
	if data.get("success"):
		$CanvasLayer/OuterPanel/debug.text += "Account created! Welcome, " + str(data.get("username")) + "\n"
		# Save the new login to Session for the map. The character comes from the customizer
		Session.token = data.get("token")
		Session.userId = int(data.get("userId"))
		Session.username = data.get("username")
		Session.character = $CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.get_selection()
		get_tree().change_scene_to_file("res://client/map/map.tscn")
	else:
		$CanvasLayer/OuterPanel/debug.text += "Error: " + str(data.get("error")) + "\n"
		$CanvasLayer/OuterPanel/input_pass.clear()



# Checks the username and password against the server's rules and returns an error message, or "" if both are fine.
func validate_creds(username: String, password: String) -> String:
	if username_check.search(username.strip_edges()) == null:
		return "Username must be 3-20 characters: letters, numbers, or underscores."
	if password.length() < 8 or password.length() > 72:
		return "Password must be 8-72 characters."
	return ""


# Checks the form and sends the new account and character choices to the server.
func _on_btn_create_pressed() -> void:
	var username = $CanvasLayer/OuterPanel/CharacterPanel/input_username.text
	var email = $CanvasLayer/OuterPanel/input_email.text
	var password = $CanvasLayer/OuterPanel/input_pass.text
	# Blank fields are caught here; the server trims the username and email and lowercases the email.
	if username.strip_edges().is_empty() or email.strip_edges().is_empty() or password.is_empty():
		$CanvasLayer/OuterPanel/debug.text += "Please fill out username, email, and password.\n"
		return
	# Same rules as the server, so the player sees the problem right away instead of after a round trip.
	var validation_err = validate_creds(username, password)
	if not validation_err.is_empty():
		$CanvasLayer/OuterPanel/debug.text += validation_err + "\n"
		return
	if not Network.is_connected_to_server():
		$CanvasLayer/OuterPanel/debug.text += "Not connected to server yet.\n"
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
	$CanvasLayer/OuterPanel/btn_create.disabled = true
	$CanvasLayer/OuterPanel/btn_back.disabled = true

# Goes back to the splash screen.
func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://client/splash_screen.tscn")
