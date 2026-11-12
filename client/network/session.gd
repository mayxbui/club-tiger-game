extends Node

# Autoload that keeps the logged-in player's info while scenes change.
var token: String = ""
var userId: int = 0
var username: String = ""
var email: String = ""
var character: Dictionary = {}
# Whose dorm the dorm scene opens: 0 = your own, otherwise a friend's user id (set by go_to_dorm).
var dorm_owner_id: int = 0
# A message for the next room's HUD to show once it loads (e.g. why a dorm visit didn't work).
var pending_notice: String = ""

const MAP_SCENE := "res://client/map/world_map.tscn"
const DORM_SCENE := "res://client/dorm/dorm_room.tscn"


# Forgets the logged-in player (use on logout).
func _clear_session() -> void:
	token = ""
	userId = 0
	username = ""
	email = ""
	character = {}
	dorm_owner_id = 0
	pending_notice = ""


# Opens a dorm: your own (owner_id 0) or a friend's. The dorm scene asks the server to enter it when it loads.
func go_to_dorm(owner_id: int = 0) -> void:
	dorm_owner_id = owner_id
	get_tree().change_scene_to_file(DORM_SCENE)


# Goes back to the campus map, optionally with a notice for the map's HUD to show.
func go_to_map(notice: String = "") -> void:
	dorm_owner_id = 0
	pending_notice = notice
	get_tree().change_scene_to_file(MAP_SCENE)
