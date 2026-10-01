extends Node

# Spawns the local player at the center of the middle map and draws their saved character and username.
func _ready() -> void:
	$Player.position = $Map.position
	$Player.is_local = true
	$Player._apply_character(Session.character)
	$Player.set_username(Session.username)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
