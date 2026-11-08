extends Node2D

const PLAYER_SCENE := preload("res://client/player/player.tscn")

const KEY_SEND_SECONDS := 0.12   # how often a held key sends "move"; ~8 per second, under the server's
const KEY_LOOKAHEAD := 0.12      # how far ahead to aim, in seconds of walking (300 px/s * 0.12 = 36 px)

const SNAP_DISTANCE := 60.0
const NOTICE_WAIT := 2.0
# Longest chat message; must match MAX_CHAT_LENGTH in server/src/chat.ts.
const MAX_CHAT_LENGTH := 48
const CHAT_WARN_LEFT := 10
# Where the player can walk: the 1920x1080 screen minus a margin
# Must match MAP_BOUNDS in server/src/world.ts.
const EDGE_MARGIN_SIDE := 60.0
const EDGE_MARGIN_TOP := 130.0
const EDGE_MARGIN_BOTTOM := 100.0
const PLAY_AREA := Rect2(EDGE_MARGIN_SIDE, EDGE_MARGIN_TOP, 1920.0 - 2 * EDGE_MARGIN_SIDE, 1080.0 - EDGE_MARGIN_TOP - EDGE_MARGIN_BOTTOM)
# Random spawn point along the bottom path
var spawnX = randf_range(200,1820)
var spawnY = 900
# Every other player on the map: userId (int) -> their Player node under $Players.
var remote_players := {}
var notice_tween: Tween
@onready var chat_input := $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/ChatInput
@onready var chat_notice := $ChatUI/ChatPanel/VBoxContainer/ChatNotice
@onready var player_card: PlayerCard = $PlayerCard
# Test chat on client. Set to false to test on server. 
const OFFLINE_CHAT_TEST := false

# Server side (chat.ts, chatFilter.ts):
#   send     {"type": "chat", "text": ...}
#   receive  {"type": "chat_message", "userId", "username", "text"}   -> bubble above that player (including you)
#            {"type": "chat_rejected", "reason"}                      -> red notice, only you see it

# Server side (world.ts): player_updated {userId, username, character} -> redraw that player after a profile edit.
# Friends and profile messages are handled by the player card (client/player-card/player_card.gd).

# Spawns the local player at a random point, draws their saved character and username, and joins the shared world.
func _ready() -> void:
	$Players/Player.global_position = Vector2(spawnX,spawnY)
	$Players/Player.is_local = true
	$Players/Player._apply_character(Session.character)
	$Players/Player.set_username(Session.username)
	Network.message_received.connect(_on_message_received)
	_join_world()
	chat_input.text_submitted.connect(func (text):
		_send_chat(text))
	$ChatUI/ChatPanel/VBoxContainer/HBoxContainer/BtnSend.pressed.connect(func():
		_send_chat(chat_input.text))
	chat_input.max_length = MAX_CHAT_LENGTH
	chat_input.text_changed.connect(func(text):
		_update_chat_counter(text.length()))
	_update_chat_counter(0)
	player_card.profile_saved.connect(_on_profile_saved)
	# The tiger button opens and closes the player card.
	$BtnPlayerCard.pressed.connect(player_card.toggle)

# Shows how many characters are LEFT (counts down from MAX_CHAT_LENGTH), red when only CHAT_WARN_LEFT or fewer remain.
func _update_chat_counter(length: int) -> void:
	var left := MAX_CHAT_LENGTH - length
	var counter := $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/ChatLimit
	counter.text = str(left)
	
# Sends what the player typed and server filters it.
func _send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		chat_input.release_focus()
		return
	# Offline test: skip the server , so it works without signing in or a connection.
	if OFFLINE_CHAT_TEST:
		_test_server_chat(text)
		chat_input.clear()
		_update_chat_counter(0)
		return
	if Network.send({
		"type": "chat",
		"text": text
	}):
		chat_input.clear()
		_update_chat_counter(0)
	else:
		_show_chat_notice("Message not sent.")

# Pretends to be the server: rejects a test word, otherwise sends the message back like chat_message would.
func _test_server_chat(text: String) -> void:
	if "bad" in text.to_lower():
		_on_message_received({"type": "chat_rejected", "reason": "Your message wasn't sent because it contains blocked language."})
	else:
		_on_message_received({"type": "chat_message", "userId": Session.userId, "username": Session.username, "text": text})
	
# Tells the server this player is on the map and where they're standing; it answers with world_state.
func _join_world() -> void:
	var pos: Vector2 = $Players/Player.global_position
	Network.send({"type": "join_world", "x": pos.x, "y": pos.y})

# Keyboard: key_held is true while an arrow/WASD key moves the player; key_send_timer spaces out the "move" sends.
var key_send_timer := 0.0
var key_held := false

# Ends keyboard focus: stops the player where they stand and tells the server, so every screen stops at the same spot.
func _stop_key_movement():
	var player = $Players/Player
	player.move_to(player.global_position)
	key_held = false
	key_send_timer = 0.0
	Network.send({
		"type":"move",
		"x": player.global_position.x,
		"y": player.global_position.y
	})

# Walks the local player with the arrow keys / WASD (Input Map: Left, Right, Up, Down). 
func _physics_process(delta: float) -> void:
	# Typing in the chat or a player-card text box (search, username) must not walk the player.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	else:
		var dir := Input.get_vector("Left","Right","Up","Down")
		if dir != Vector2.ZERO:
			var player = $Players/Player
			var target: Vector2 = _clamp_to_play_area(player.global_position + dir * player.SPEED * KEY_LOOKAHEAD)
			if not Geometry2D.is_point_in_polygon($Walkable.to_local(target), $Walkable.polygon):
				return
			player.move_to(target)
			key_held = true
			key_send_timer -= delta
			if key_send_timer <= 0:
				Network.send({
					"type":"move",
					"x": target.x,
					"y": target.y
				})
				key_send_timer = KEY_SEND_SECONDS
		elif key_held:
			_stop_key_movement()

# Walks the local player to a left click inside the walkable area.
# _unhandled_input (not _input): clicks on UI like the chat box are used by the UI and don't move the player.

# Press Enter to open the chat box; click the map to exit.
func _unhandled_input(event: InputEvent) -> void:
	if(event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not chat_input.has_focus()):
		chat_input.grab_focus()
		if key_held:
			_stop_key_movement()
		get_viewport().set_input_as_handled()
		return
		
	if(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		chat_input.release_focus()
		var click := get_global_mouse_position()
		click = _clamp_to_play_area(click)
		if not Geometry2D.is_point_in_polygon($Walkable.to_local(click), $Walkable.polygon):
			return
		$Players/Player.move_to(click)
		Network.send({
			"type": "move",
			"x": click.x,
			"y": click.y
		})
		get_viewport().set_input_as_handled()

# Handles the server's world: who is on the map, who joined, who moved, who left.
func _on_message_received(data: Dictionary) -> void:
	match data.get("type"):
		# Reply to join_world: everyone else already on the map.
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
		# After dropping connection, Network.gd logs back in with resume_session; once that works, the server has
		# forgotten this player was on the map, so join again (world_state then rebuilds the list).
		"resume_session_result":
			if data.get("success", false):
				_join_world()
				# Requests may have arrived while the connection was down (their pushes were lost), so reload the list.
				player_card.refresh()
		# Show chat as a bubble above that player.
		"chat_message":
			var id := int(data.get("userId",0))
			var speaker = $Players/Player if id == Session.userId else remote_players.get(id)
			if speaker != null:           # null if they left a moment ago
				speaker.show_chat_bubble(str(data.get("text", "")))
		# Only this player gets this (blocked word, too long, too fast): show the reason as a red notice.
		"chat_rejected":
			_show_chat_notice(str(data.get("reason", "Message not sent.")))
		# Another player saved a new look or username on their player card.
		"player_updated":
			var updated = remote_players.get(int(data.get("userId", 0)))
			if updated != null:
				updated._apply_character(data.get("character", {}))
				updated.set_username(str(data.get("username", "")))

# Creates another player's character from the server's PlayerInfo ({userId, username, character, x, y, toX, toY}).
func _add_remote_player(info: Dictionary) -> void:
	var user_id := int(info.get("userId", 0))
	if user_id == Session.userId:
		return  # this player is already on screen
	if remote_players.has(user_id):
		_remove_remote_player(user_id)  # an old connection: replace it

	var player = PLAYER_SCENE.instantiate()
	player.is_local = false
	player.scale = $Players/Player.scale
	$Players.add_child(player)  # under Players
	# These need the player in the tree first
	player.global_position = Vector2(info.get("x", 0.0), info.get("y", 0.0))
	player._apply_character(info.get("character", {}))
	player.set_username(str(info.get("username", "")))
	# If they were already walking when we joined, carry on toward where they were going.
	var target := Vector2(info.get("toX", info.get("x", 0.0)), info.get("toY", info.get("y", 0.0)))
	if target != player.global_position:
		player.move_to(target)
	remote_players[user_id] = player

# Removes another player's character (left, disconnected or logged out).
func _remove_remote_player(user_id: int) -> void:
	var player = remote_players.get(user_id)
	if player != null:
		player.queue_free()
		remote_players.erase(user_id)

# Removes every other player's character, before world_state redraws the list.
func _clear_remote_players() -> void:
	for user_id in remote_players.keys():
		_remove_remote_player(user_id)

# Shows a short notice by the chat box for NOTICE_WAIT seconds, then fades it out; a new notice replaces the old one.
func _show_chat_notice(text:String)-> void:
	if notice_tween:
		notice_tween.kill()
	chat_notice.text = text
	chat_notice.visible = true
	chat_notice.modulate.a = 1.0
	notice_tween = chat_notice.create_tween()
	notice_tween.tween_interval(NOTICE_WAIT)
	notice_tween.tween_property(chat_notice, "modulate:a", 0.0, 0.5)
	notice_tween.tween_callback(func(): chat_notice.visible = false)

# Logs the player out (server session, "remember me", map) and goes back to the splash screen.
func _on_btn_logout_pressed() -> void:
	Network.logout()

# Moves a point inside PLAY_AREA, so a click or key walk near the edge stops where the character is fully on screen (the server rejects points outside the same area).
func _clamp_to_play_area(point: Vector2) -> Vector2:
	return point.clamp(PLAY_AREA.position, PLAY_AREA.end)

# Redraws your own character after the player card saved a new look or username (Session is already updated).
func _on_profile_saved(username: String, character: Dictionary) -> void:
	$Players/Player._apply_character(character)
	$Players/Player.set_username(username)
