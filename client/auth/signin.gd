extends Node2D

func _ready() -> void:
	Network.message_received.connect(_on_message_received)

func _on_message_received(data: Dictionary) -> void:
	# Server sends type "error" for crashes/malformed messages (e.g. DB failures)
	if data.get("type") == "error":
		$debug.text += "Server error: " + str(data.get("error")) + "\n"
		return
	if data.get("type") != "login_result":
		return

	if data.get("success"):
		$debug.text += "Logged in as " + str(data.get("username")) + "\n"
	else:
		$debug.text += "Error: " + str(data.get("error")) + "\n"

func _on_btn_create_pressed() -> void:
	get_tree().change_scene_to_file("res://client/auth/create_account.tscn")


func _on_btn_login_pressed() -> void:
	var username = $input_username.text
	var password = $input_pass.text
	var remember = $checkbox_remember.button_pressed

	if username.is_empty() or password.is_empty():
		$debug.text += "Please enter username and password.\n"
		return

	if not Network.is_connected_to_server():
		$debug.text += "Not connected to server yet.\n"
		return

	Network.send({
		"type": "login",
		"username": username,
		"password": password,
		"remember_me": remember
	})
