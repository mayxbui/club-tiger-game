extends Node

# Autoload that keeps the logged-in player's info while scenes change.
var token: String = ""
var userId: int = 0
var username: String = ""
var character: Dictionary = {}

# Forgets the logged-in player (use on logout).
func _clear_session() -> void:
	token = ""
	userId = 0
	username = ""
	character = {}
