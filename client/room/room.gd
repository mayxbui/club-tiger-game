class_name Room
extends Node2D

# What every room shares (the campus map, world_map.gd, and every dorm, dorm_room.gd): your character, the other
# players in the room, walking by click or arrow keys, chat bubbles, clicking another player to open their card, and
# re-joining after a reconnect. A room scene needs these nodes: Players (with your Player), Walkable (a hidden
# Polygon2D of where you can walk) and HUD (client/ui/hud.tscn). Each room fills in _join_room and _play_area.
#
# Server side (world.ts): world_state, player_joined, player_moved, player_left, player_updated; chat_message
# (chat.ts) draws a bubble above the speaker. Every message only comes from players in the same room.

const PLAYER_SCENE := preload("res://client/player/player.tscn")
const KEY_SEND_SECONDS := 0.12   # how often a held key sends "move"; ~8 per second, under the server's 10
const KEY_LOOKAHEAD := 0.12      # how far ahead to aim, in seconds of walking (300 px/s * 0.12 = 36 px)
# A remote player further than this from where the server says they started walking jumps there first.
const SNAP_DISTANCE := 60.0

# Every other player in this room: userId (int) -> their Player node under $Players.
var remote_players := {}
# False while something else uses clicks on the room (the dorm's edit mode).
var walking_enabled := true

var _key_send_timer := 0.0
var _key_held := false

@onready var players: Node2D = $Players
@onready var local_player = $Players/Player
@onready var walkable: Polygon2D = $Walkable
@onready var hud: Hud = $HUD


# Draws your saved character and name, listens to the server, and joins this room.
func _ready() -> void:
	local_player.is_local = true
	local_player._apply_character(Session.character)
	local_player.set_username(Session.username)
	Network.message_received.connect(_on_message_received)
	# PlayerCard is inside the HUD scene, so its signal is connected here.
	hud.player_card.profile_saved.connect(_on_profile_saved)
	_join_room()


# --- For each room to fill in ---

# Tells the server this player is in this room (the map sends join_world, a dorm sends enter_dorm).
func _join_room() -> void:
	pass


# The area your character can stand in (the server checks the same area). Clicks and key walks are clamped into it.
func _play_area() -> Rect2:
	return Rect2(0, 0, 1920, 1080)


# --- Walking ---

# Walks your character with the arrow keys / WASD (Input Map: Left, Right, Up, Down). Each frame it aims a short
# lookahead ahead and tells the server at most every KEY_SEND_SECONDS. Releasing the key sends the stop position, so
# other screens stop at the same spot.
func _physics_process(delta: float) -> void:
	# Typing in the chat or any text box (search, username) must not walk the player.
	if not walking_enabled or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var dir := Input.get_vector("Left", "Right", "Up", "Down")
	if dir != Vector2.ZERO:
		var target := _clamp_to_play_area(local_player.global_position + dir * local_player.SPEED * KEY_LOOKAHEAD)
		if not _is_walkable(target):
			return
		local_player.move_to(target)
		_key_held = true
		_key_send_timer -= delta
		if _key_send_timer <= 0:
			Network.send({"type": "move", "x": target.x, "y": target.y})
			_key_send_timer = KEY_SEND_SECONDS
	elif _key_held:
		_stop_key_movement()


# Enter opens the chat box; a left click on the room walks there (inside the play area). _unhandled_input means
# clicks on UI (chat, cards, buttons) are used by the UI and don't move the player.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not hud.is_chatting():
		hud.focus_chat()
		if _key_held:
			_stop_key_movement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hud.release_chat()
		if not walking_enabled:
			return
		var click := _clamp_to_play_area(get_global_mouse_position())
		if not _is_walkable(click):
			return
		local_player.move_to(click)
		Network.send({"type": "move", "x": click.x, "y": click.y})
		get_viewport().set_input_as_handled()


# --- Server handler (connected in _ready; rooms extend it and call super) ---

# Handles who is in the room, who joined, moved, left or changed their look, chat bubbles, and re-joining after a
# reconnect.
func _on_message_received(data: Dictionary) -> void:
	match data.get("type"):
		# Sent on joining: everyone else already in this room.
		"world_state":
			_clear_remote_players()
			for info in data.get("players", []):
				_add_remote_player(info)
		"player_joined":
			_add_remote_player(data)
		"player_moved":
			var player = remote_players.get(int(data.get("userId", 0)))
			if player == null:
				return
			var from := Vector2(data.get("fromX", 0.0), data.get("fromY", 0.0))
			if player.global_position.distance_to(from) > SNAP_DISTANCE:
				player.global_position = from
			player.move_to(Vector2(data.get("toX", 0.0), data.get("toY", 0.0)))
		"player_left":
			_remove_remote_player(int(data.get("userId", 0)))
		# After a dropped connection Network.gd resumes the session; the server forgot which room we were in, so join
		# again. Friend requests may have arrived meanwhile (their pushes were lost), so reload the card's list too.
		"resume_session_result":
			if data.get("success", false):
				_join_room()
				hud.player_card.refresh()
		# A bubble above the speaker (you included).
		"chat_message":
			var id := int(data.get("userId", 0))
			var speaker = local_player if id == Session.userId else remote_players.get(id)
			if speaker != null:   # null if they left a moment ago
				speaker.show_chat_bubble(str(data.get("text", "")))
		# Another player saved a new look or username on their player card.
		"player_updated":
			var updated = remote_players.get(int(data.get("userId", 0)))
			if updated != null:
				updated._apply_character(data.get("character", {}))
				updated.set_username(str(data.get("username", "")))


# Redraws your own character after the player card saved a new look or username (Session is already updated).
func _on_profile_saved(username: String, character: Dictionary) -> void:
	local_player._apply_character(character)
	local_player.set_username(username)


# Opens the other-player card for the player that was clicked (connected in _add_remote_player).
func _on_remote_player_clicked(user_id: int) -> void:
	hud.other_player_card.open_for(user_id)


# --- Helpers ---

# Creates another player's character from the server's PlayerInfo ({userId, username, character, x, y, toX, toY}).
func _add_remote_player(info: Dictionary) -> void:
	var user_id := int(info.get("userId", 0))
	if user_id == Session.userId:
		return  # this player is already on screen
	if remote_players.has(user_id):
		_remove_remote_player(user_id)  # an old connection: replace it

	var player = PLAYER_SCENE.instantiate()
	player.is_local = false
	player.scale = local_player.scale
	players.add_child(player)
	# These need the player in the tree first
	player.global_position = Vector2(info.get("x", 0.0), info.get("y", 0.0))
	player._apply_character(info.get("character", {}))
	player.set_username(str(info.get("username", "")))
	# If they were already walking when we joined, carry on toward where they were going.
	var target := Vector2(info.get("toX", info.get("x", 0.0)), info.get("toY", info.get("y", 0.0)))
	if target != player.global_position:
		player.move_to(target)
	# Clicking them opens the other-player card. Remote players are made at runtime, so this is connected in code.
	player.set_clickable(true)
	player.clicked.connect(_on_remote_player_clicked.bind(user_id))
	remote_players[user_id] = player


# Removes another player's character (left, disconnected, logged out or blocked).
func _remove_remote_player(user_id: int) -> void:
	var player = remote_players.get(user_id)
	if player != null:
		player.queue_free()
		remote_players.erase(user_id)
	# Their card can't act on someone who left (or was just blocked), so close it.
	if hud.other_player_card.shown_user_id() == user_id:
		hud.other_player_card.close()


# Removes every other player's character, before world_state redraws the list.
func _clear_remote_players() -> void:
	for user_id in remote_players.keys():
		_remove_remote_player(user_id)


# Ends a keyboard walk: stops your character where it stands and tells the server, so every screen stops there too.
func _stop_key_movement() -> void:
	local_player.move_to(local_player.global_position)
	_key_held = false
	_key_send_timer = 0.0
	Network.send({"type": "move", "x": local_player.global_position.x, "y": local_player.global_position.y})


# Moves a point inside the room's play area, so a click or key walk near the edge stops where the character is
# fully on screen (the server rejects points outside the same area).
func _clamp_to_play_area(point: Vector2) -> Vector2:
	var area := _play_area()
	return point.clamp(area.position, area.end)


# True if a point (global) is inside the Walkable polygon.
func _is_walkable(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(walkable.to_local(point), walkable.polygon)
