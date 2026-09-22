extends Node2D

func _ready() -> void:
	Network.message_received.connect(_on_message_received)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.skin_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player._on_CharacterCustomizer_skin_changed)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.hair_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player._on_CharacterCustomizer_hair_changed)
	$CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.eyes_changed.connect($CanvasLayer/OuterPanel/CharacterPanel/Player._on_CharacterCustomizer_eye_changed)

func _on_message_received(data: Dictionary) -> void:
	# Server sends type "error" for crashes/malformed messages (e.g. DB failures)
	if data.get("type") == "error":
		$CanvasLayer/OuterPanel/debug.text += "Server error: " + str(data.get("error")) + "\n"
		return
	if data.get("type") != "create_account_result":
		return

	if data.get("success"):
		$CanvasLayer/OuterPanel/debug.text += "Account created! Welcome, " + str(data.get("username")) + "\n"
	else:
		$CanvasLayer/OuterPanel/debug.text += "Error: " + str(data.get("error")) + "\n"

func _on_btn_create_pressed() -> void:
	var username = $CanvasLayer/OuterPanel/CharacterPanel/input_username.text
	var email = $CanvasLayer/OuterPanel/input_email.text
	var password = $CanvasLayer/OuterPanel/input_pass.text

	if username.is_empty() or email.is_empty() or password.is_empty():
		$CanvasLayer/OuterPanel/debug.text += "Please fill out username, email, and password.\n"
		return

	if not Network.is_connected_to_server():
		$CanvasLayer/OuterPanel/debug.text += "Not connected to server yet.\n"
		return

	var character = $CanvasLayer/OuterPanel/CharacterPanel/CharacterCustomizer.get_selection()

	Network.send({
		"type": "create_account",
		"username": username,
		"email": email,
		"password": password,
		"character": character
	})

func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://client/welcome.tscn")
