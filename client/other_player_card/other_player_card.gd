class_name OtherPlayerCard
extends CanvasLayer

# Other-player card: opens on the LEFT side of the map when you click another player (the player card stays on the
# right, so both can be open). Shows their username, avatar and how they relate to you, with Add friend, Block and
# Visit dorm. Every button asks first through the ConfirmDialog child.
# The room (client/room/room.gd) calls open_for(userId) on a click and close() when that player leaves the room.
#
# Messages (server/src/friends.ts):
#   send     player_info {userId}  -> player_info_result {success, error?, userId, username, character, relation}
#            friend_request {username}  -> friend_request_result {success, error?}
#            block_user {userId}        -> block_result {success, error?} (the server then removes them from the map)
#
# Close, Add friend, Block, Visit and Card.resized are connected in other_player_card.tscn; the server in _ready.

## How big the card is drawn (1 = its full design size). It shrinks toward the left edge of the screen.
@export var card_scale := 0.65

# The player this card shows (0 while closed), their name for friend_request, and their relation to you.
var _user_id := 0
var _username := ""
var _relation := ""
# The request this card sent and is waiting on ("friend_request" or "block"), so it only reacts to its own replies
# (the player card sends the same messages).
var _waiting_for := ""

@onready var card: PanelContainer = $Card
@onready var label_name: Label = $Card/Page/VBox/LabelName
@onready var avatar: PlayerSkeleton = $Card/Page/VBox/Avatar
@onready var label_status: Label = $Card/Page/VBox/LabelStatus
@onready var btn_add_friend: Button = $Card/Page/VBox/Buttons/BtnAddFriend
@onready var btn_block: Button = $Card/Page/VBox/Buttons/BtnBlock
@onready var btn_visit: Button = $Card/Page/VBox/Buttons/BtnVisit
@onready var label_notice: Label = $Card/Page/VBox/LabelNotice
@onready var confirm_dialog: ConfirmDialog = $ConfirmDialog


# --- Setup ---

# Hides the card (the scene is saved visible so it can be edited), scales it, and listens to the server.
func _ready() -> void:
	visible = false
	_apply_card_scale()
	Network.message_received.connect(_on_message_received)


# Escape closes the card (the ConfirmDialog child gets Escape first while it is open).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Called by the room (room.gd) ---

# Opens the card for one player and asks the server for their name, look and relation. The buttons stay disabled
# until the reply arrives.
func open_for(user_id: int) -> void:
	_user_id = user_id
	_username = ""
	_waiting_for = ""
	label_name.text = "..."
	avatar.visible = false
	label_notice.text = ""
	_set_relation("")
	confirm_dialog.cancel()
	visible = true
	Network.send({"type": "player_info", "userId": user_id})


# Hides the card and any open question.
func close() -> void:
	visible = false
	confirm_dialog.cancel()
	_user_id = 0
	_waiting_for = ""


# The player this card shows, or 0 if it's closed (room.gd closes the card when that player leaves).
func shown_user_id() -> int:
	return _user_id if visible else 0


# --- Button handlers (connected in other_player_card.tscn) ---

# The X button closes the card.
func _on_btn_close_pressed() -> void:
	close()


# Asks, then sends a friend request.
func _on_btn_add_friend_pressed() -> void:
	confirm_dialog.ask("Send a friend request to [color=#aa2626]%s[/color]?" % _username, "Send", _send_friend_request)


# Asks, then blocks. Blocking a friend also ends the friendship (blockUser in friends.ts), so the question says so.
func _on_btn_block_pressed() -> void:
	var message := "Block [color=#aa2626]%s[/color]? You won't see each other on the map or in chat." % _username
	if _relation == "friend":
		message += " They'll also be removed from your friends."
	confirm_dialog.ask(message, "Block", _send_block)


# Asks, then visits their dorm. Only friends can visit (the server checks too), so BtnVisit is only on for friends.
func _on_btn_visit_pressed() -> void:
	var owner_id := _user_id
	confirm_dialog.ask("Visit [color=#1c94e3]%s[/color]'s dorm?" % _username, "Visit", func(): Session.go_to_dorm(owner_id))


# Keeps the card pinned to the left edge if its size changes.
func _on_card_resized() -> void:
	if is_node_ready():  # resized can fire while the scene loads, before `card` is set
		_apply_card_scale()


# --- Server handler (connected in _ready) ---

# Fills the card from player_info_result, and reacts to the replies to this card's own friend request or block.
func _on_message_received(data: Dictionary) -> void:
	if not visible:
		return
	match data.get("type"):
		# A generic server error while the card is still loading (e.g. a server without player_info): say so
		# instead of showing "..." forever.
		"error":
			if _username.is_empty():
				label_name.text = "Player"
				label_notice.text = "Couldn't load this player. " + str(data.get("error", ""))
		"player_info_result":
			if not data.get("success", false):
				label_name.text = "Player"
				label_notice.text = str(data.get("error", "Player not found."))
				return
			if int(data.get("userId", 0)) != _user_id:
				return  # a reply for a player you clicked before this one
			_username = str(data.get("username", ""))
			label_name.text = _username
			avatar.apply_character(data.get("character", {}))
			avatar.visible = true
			_set_relation(str(data.get("relation", "none")))
		"friend_request_result":
			if _waiting_for != "friend_request":
				return
			_waiting_for = ""
			if data.get("success", false):
				label_notice.text = "Request sent!"
				Network.send({"type": "player_info", "userId": _user_id})  # shows "Request pending"
			else:
				label_notice.text = str(data.get("error", "Couldn't send the request."))
				_set_relation(_relation)
		"block_result":
			if _waiting_for != "block":
				return
			_waiting_for = ""
			if data.get("success", false):
				close()  # they're gone from the map now
			else:
				label_notice.text = str(data.get("error", "Couldn't block this player."))
				_set_relation(_relation)


# --- Helpers ---

# Sends the friend request (after Yes) and disables the buttons until the reply.
func _send_friend_request() -> void:
	_waiting_for = "friend_request"
	btn_add_friend.disabled = true
	btn_block.disabled = true
	Network.send({"type": "friend_request", "username": _username})


# Sends the block (after Yes) and disables the buttons until the reply.
func _send_block() -> void:
	_waiting_for = "block"
	btn_add_friend.disabled = true
	btn_block.disabled = true
	Network.send({"type": "block_user", "userId": _user_id})


# Shows the relation in the status line and sets the buttons for it. "" (still loading) disables both.
func _set_relation(relation: String) -> void:
	_relation = relation
	btn_add_friend.text = "Add friend"
	btn_add_friend.disabled = relation != "none"
	btn_block.disabled = relation not in ["none", "pending", "friend"]
	btn_visit.disabled = relation != "friend"
	match relation:
		"friend":
			label_status.text = "Friends"
			btn_add_friend.text = "Friends"
		"pending":
			label_status.text = "Friend request pending"
			btn_add_friend.text = "Requested"
		"blocked":
			label_status.text = "Blocked by you"
		_:
			label_status.text = ""


# Scales the card by card_scale around the middle of its left edge, so it shrinks toward the left side of the screen.
func _apply_card_scale() -> void:
	card.pivot_offset = Vector2(0, card.size.y / 2)
	card.scale = Vector2(card_scale, card_scale)
