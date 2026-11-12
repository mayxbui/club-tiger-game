class_name Hud
extends CanvasLayer

# The on-screen layout every room shares (the map and every dorm): Logout top left, the player-card button top right,
# the chat box bottom center, and the room buttons bottom right (BtnPlace = "My Dorm" / "Map", BtnEdit = the dorm
# owner's pencil). It also holds both cards. The room (room.gd) listens to place_pressed / edit_pressed and draws chat
# bubbles; the HUD sends chat and shows the red notice when a message is rejected.
#
# Server side (chat.ts):
#   send     {"type": "chat", "text": ...}
#   receive  {"type": "chat_rejected", "reason"}   -> red notice, only you see it
#            chat_message is handled by the room (a bubble above the speaker)

# The bottom-right room button was pressed ("My Dorm" on the map, "Map" in a dorm).
signal place_pressed
# The pencil button was pressed (only shown to a dorm's owner).
signal edit_pressed

# Longest chat message; must match MAX_CHAT_LENGTH in server/src/chat.ts.
const MAX_CHAT_LENGTH := 48
const NOTICE_WAIT := 2.0
# Test chat on the client. Set to false to test on the server.
const OFFLINE_CHAT_TEST := false

## Text of the bottom-right room button (placeholder until it gets a texture).
@export var place_text := "My Dorm"

var _notice_tween: Tween

@onready var chat_panel: PanelContainer = $ChatPanel
@onready var chat_input: LineEdit = $ChatPanel/VBox/HBox/ChatInput
@onready var chat_limit: Label = $ChatPanel/VBox/HBox/ChatLimit
@onready var chat_notice: Label = $ChatPanel/VBox/ChatNotice
@onready var btn_place: Button = $RoomButtons/BtnPlace
@onready var btn_my_dorm: Button = $RoomButtons/BtnMyDorm
@onready var btn_edit: Button = $RoomButtons/BtnEdit
@onready var room_buttons: HBoxContainer = $RoomButtons
@onready var player_card: PlayerCard = $PlayerCard
@onready var other_player_card: OtherPlayerCard = $OtherPlayerCard


# Sets the room button's text, hides the pencil until a dorm says you own it, and shows any notice left by the last
# room (Session.pending_notice).
func _ready() -> void:
	btn_place.text = place_text
	btn_edit.visible = false
	chat_input.max_length = MAX_CHAT_LENGTH
	_update_chat_counter(0)
	Network.message_received.connect(_on_message_received)
	if not Session.pending_notice.is_empty():
		show_notice(Session.pending_notice)
		Session.pending_notice = ""


# --- Public ---

# Shows or hides the pencil button (only a dorm's owner gets it).
func set_edit_available(on: bool) -> void:
	btn_edit.visible = on


# Edit mode in a dorm: the item belt takes the bottom of the screen, so the chat box and room buttons step aside.
func set_editing(on: bool) -> void:
	chat_panel.visible = not on
	room_buttons.visible = not on


# Puts the cursor in the chat box (Enter on the map).
func focus_chat() -> void:
	chat_input.grab_focus()


# Takes the cursor out of the chat box (clicking the room).
func release_chat() -> void:
	chat_input.release_focus()


# True while the player is typing in the chat box.
func is_chatting() -> bool:
	return chat_input.has_focus()


# Shows a short notice by the chat box for NOTICE_WAIT seconds, then fades it out; a new notice replaces the old one.
func show_notice(text: String) -> void:
	if _notice_tween:
		_notice_tween.kill()
	chat_notice.text = text
	chat_notice.visible = true
	chat_notice.modulate.a = 1.0
	_notice_tween = chat_notice.create_tween()
	_notice_tween.tween_interval(NOTICE_WAIT)
	_notice_tween.tween_property(chat_notice, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(func(): chat_notice.visible = false)


# --- Scene signals (connected in hud.tscn) ---

# Logs the player out (server session, "remember me", room) and goes back to the splash screen.
func _on_btn_logout_pressed() -> void:
	Network.logout()


# The tiger button opens and closes the player card.
func _on_btn_player_card_pressed() -> void:
	player_card.toggle()


# Tells the room to go to the other place (dorm or map).
func _on_btn_place_pressed() -> void:
	place_pressed.emit()


# Takes a visitor directly to their own dorm.
func _on_btn_my_dorm_pressed() -> void:
	Session.go_to_dorm()


# Tells the dorm to start edit mode.
func _on_btn_edit_pressed() -> void:
	edit_pressed.emit()


# Enter in the chat box sends the message.
func _on_chat_input_text_submitted(text: String) -> void:
	_send_chat(text)


# Keeps the "characters left" counter up to date while typing.
func _on_chat_input_text_changed(text: String) -> void:
	_update_chat_counter(text.length())


# The Send button sends the message.
func _on_btn_send_pressed() -> void:
	_send_chat(chat_input.text)


# --- Server handler (connected in _ready) ---

# Only this player gets chat_rejected (blocked word, too long, too fast): show the reason as a red notice.
func _on_message_received(data: Dictionary) -> void:
	if data.get("type") == "chat_rejected":
		show_notice(str(data.get("reason", "Message not sent.")))


# --- Helpers ---

# Shows how many characters are LEFT (counts down from MAX_CHAT_LENGTH).
func _update_chat_counter(length: int) -> void:
	chat_limit.text = str(MAX_CHAT_LENGTH - length)


# Sends what the player typed; the server filters it and sends chat_message back to everyone in the room.
func _send_chat(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		chat_input.release_focus()
		return
	# Offline test: pretend the server answered, so it works without signing in or a connection.
	if OFFLINE_CHAT_TEST:
		var fake := {"type": "chat_message", "userId": Session.userId, "username": Session.username, "text": text}
		if "bad" in text.to_lower():
			fake = {"type": "chat_rejected", "reason": "Your message wasn't sent because it contains blocked language."}
		Network.message_received.emit(fake)
	elif not Network.send({"type": "chat", "text": text}):
		show_notice("Message not sent.")
		return
	chat_input.clear()
	_update_chat_counter(0)
