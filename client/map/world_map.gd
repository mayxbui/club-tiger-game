extends Node2D

const PLAYER_SCENE := preload("res://client/player/player.tscn")
# If another player's copy here is further than this from where the server says they started walking
# (e.g. after lag or a missed message), jump it there first instead of letting it walk from the wrong place.
const SNAP_DISTANCE := 60.0

# Random spawn point along the bottom path, so players who join at the same time don't stand on top of each other.
var spawnX = randf_range(200,930)
var spawnY = 430
# Every other player on the map: userId (int) -> their Player node under $Players.
var remote_players := {}

# TODO (chat 1) - SCENE: in world_map.tscn add a CanvasLayer "ChatUI" (a CanvasLayer stays fixed on screen and is
#   drawn above the map and players), containing:
#     PanelContainer "ChatPanel"   bottom-left corner, e.g. position (16, 440), size (380, 190); mouse_filter = Stop
#       VBoxContainer
#         RichTextLabel "ChatLog"   custom_minimum_size (360, 140), scroll_following = true,
#                                   bbcode_enabled = FALSE (otherwise a player could type [img] or [url] tags)
#         HBoxContainer
#           LineEdit "ChatInput"   size_flags_horizontal = Expand Fill, max_length = 120,
#                                  placeholder_text = "Press Enter to chat"
#           Button "BtnSend"       text = "Send"
#   mouse_filter = Stop on the panel is what makes clicks on the chat box NOT reach _unhandled_input below,
#   so clicking the chat box doesn't also walk the player there.
#   Style it like the auth screens (the black StyleBoxFlat for the input, Ribeye font for the log).
#   Shorter paths for the code below:  @onready var chat_log := $ChatUI/ChatPanel/VBoxContainer/ChatLog
#                                      @onready var chat_input := $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/ChatInput
#   const MAX_CHAT_LINES := 50   # older lines are removed so the log doesn't grow forever

# Spawns the local player at a random point, draws their saved character and username, and joins the shared world.
func _ready() -> void:
	$Players/Player.global_position = Vector2(spawnX,spawnY)
	$Players/Player.is_local = true
	$Players/Player._apply_character(Session.character)
	$Players/Player.set_username(Session.username)
	Network.message_received.connect(_on_message_received)
	_join_world()
	# TODO (chat 2): hook up the chat box:
	#   chat_input.text_submitted.connect(func(text): _send_chat(text))     # Enter sends
	#   $ChatUI/ChatPanel/VBoxContainer/HBoxContainer/BtnSend.pressed.connect(func(): _send_chat(chat_input.text))

# TODO (chat 3): add _send_chat - sends what the player typed; the server checks and filters it, then sends it
#   back to everyone (including this player) as chat_message, so don't add it to the log here.
#   func _send_chat(text: String) -> void:
#       text = text.strip_edges()
#       if text.is_empty():
#           chat_input.release_focus()     # Enter on an empty box closes the chat, so the player can go back to clicking
#           return
#       if Network.send({"type": "chat", "text": text}):
#           chat_input.clear()             # keep focus so they can type the next message straight away
#       else:
#           _add_system_line("Not connected - message not sent.")

# Tells the server this player is on the map and where they're standing; it answers with world_state.
func _join_world() -> void:
	var pos: Vector2 = $Players/Player.global_position
	Network.send({"type": "join_world", "x": pos.x, "y": pos.y})

# Walks the local player to a left click inside the walkable area and tells the server about the move.
# _unhandled_input (not _input) means clicks on UI like the chat box are used by the UI and don't move the player.
func _unhandled_input(event: InputEvent) -> void:
	# TODO (chat 4): pressing Enter anywhere on the map opens the chat box:
	#   if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not chat_input.has_focus():
	#       chat_input.grab_focus()
	#       get_viewport().set_input_as_handled()
	#       return
	#   And when the player clicks the map (inside the if below), call chat_input.release_focus() so the
	#   box stops taking keys once they're walking around again.
	if(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		var click := get_global_mouse_position()
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

# Creates another player's character from the server's PlayerInfo ({userId, username, character, x, y, toX, toY}).
func _add_remote_player(info: Dictionary) -> void:
	var user_id := int(info.get("userId", 0))
	if user_id == Session.userId:
		return  # this player is already on screen
	if remote_players.has(user_id):
		_remove_remote_player(user_id)  # an old copy (e.g. reconnected): replace it

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
