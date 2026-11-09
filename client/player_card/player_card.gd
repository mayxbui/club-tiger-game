class_name PlayerCard
extends CanvasLayer

# Player card: opens from the tiger button left of the chat, on the right side of the map. Four tabs: Edit (your
# look and username), Friends, Requests and Blocked. The card owns the friends networking: it sends every request
# and handles every reply and push from server/src/friends.ts and profile.ts, then tells the pages what to show.
# The X button is connected in player_card.tscn; tab, page and server signals are connected in _ready.
# Message: see the headers of server/src/friends.ts and server/src/profile.ts.

# Save on the Edit page worked (Session is already updated): world_map.gd redraws the local player.
signal profile_saved(username: String, character: Dictionary)

enum Tab { EDIT, FRIENDS, REQUESTS, BLOCKED }

# Tab icons in tab order; the selected tab shows its -clicked version (a TabContainer has one selected style for all
# tabs, so per-tab art has to be swapped in code).
const NORMAL_ICONS := [
	preload("res://client/assets/buttons/btn-edit.png"),
	preload("res://client/assets/buttons/btn-tiger.png"),
	preload("res://client/assets/buttons/btn-bell.png"),
	preload("res://client/assets/buttons/btn-ghost.png"),
]
const CLICKED_ICONS := [
	preload("res://client/assets/buttons/btn-edit-clicked.png"),
	preload("res://client/assets/buttons/btn-tiger-clicked.png"),
	preload("res://client/assets/buttons/btn-bell-clicked.png"),
	preload("res://client/assets/buttons/btn-ghost-clicked.png"),
]

## How big the card is drawn (1 = its full 760x1020 design size). It shrinks toward the right edge of the screen, so
## it stays on the right side of the map at any scale.
@export var card_scale := 0.505

# The tab under the mouse (-1 if none); it shows its -clicked icon like the selected tab.
var _hovered_tab := -1

@onready var card: PanelContainer = $Card
@onready var tabs: TabContainer = $Card/Tabs
@onready var edit_page: EditPage = $Card/Tabs/EditPage
@onready var friend_page: ListPage = $Card/Tabs/FriendPage
@onready var request_page: ListPage = $Card/Tabs/RequestPage
@onready var blocked_page: ListPage = $Card/Tabs/BlockedPage
@onready var list_pages: Array[ListPage] = [friend_page, request_page, blocked_page]
@onready var confirm_dialog: ConfirmDialog = $ConfirmDialog


# --- Setup ---

# Hides the card, sets up the icon tabs, connects the pages and listens to the server.
func _ready() -> void:
	visible = false
	card.resized.connect(_apply_card_scale)
	_apply_card_scale()
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, "")
	tabs.tab_changed.connect(_on_tab_changed)
	var tab_bar := tabs.get_tab_bar()
	tab_bar.tab_hovered.connect(func(tab):
		_hovered_tab = tab
		_update_tab_icons())
	tab_bar.mouse_exited.connect(func():
		_hovered_tab = -1
		_update_tab_icons())
	tabs.current_tab = Tab.FRIENDS
	_on_tab_changed(Tab.FRIENDS)
	edit_page.save_requested.connect(_on_save_requested)
	for page in list_pages:
		page.row_action.connect(_on_row_action.bind(page))
		page.search_requested.connect(func(query): Network.send({"type": "search_users", "query": query}))
	Network.message_received.connect(_on_message_received)


# Escape closes the card.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Open, close and refresh (world_map.gd calls toggle and refresh) ---

# Opens the card if it's closed, closes it if it's open (world_map.gd calls this when you click your character).
func toggle() -> void:
	if visible:
		close()
	else:
		open()

# Shows the card with your saved profile on the Edit page and a fresh friends list.
func open() -> void:
	visible = true
	edit_page.reset()
	refresh()
	
# Hides the card and closes any search pop-ups.
func close() -> void:
	visible = false
	confirm_dialog.cancel()
	for page in list_pages:
		page.clear_search()

# Asks the server for the whole friends list again. The server is the one source of truth, so after any change the
# card reloads the list instead of patching it.
func refresh() -> void:
	Network.send({"type": "friends_list"})


# --- Button handlers (connected in player_card.tscn) ---

# The X button closes the card.
func _on_btn_close_pressed() -> void:
	close()


# --- Tab, page and server handlers (connected in _ready) ---

# Updates the tab icons, and reloads the lists when a list tab opens.
func _on_tab_changed(tab: int) -> void:
	_update_tab_icons()
	if tab != Tab.EDIT and visible:
		refresh()


# Sends the Edit page's changes (only the changed fields) to the server.
func _on_save_requested(changes: Dictionary) -> void:
	var message := {"type": "update_profile"}
	message.merge(changes)
	Network.send(message)


# Turns a button press on a row or a search result into the matching server message (see player_row.gd for the
# action names). Ids come from the server as floats, so int() converts them.
func _on_row_action(action: String, info: Dictionary, page: ListPage) -> void:
	var user_id := int(info.get("userId", 0))
	var username := str(info.get("username", ""))
	match action:
		"accept", "decline":
			Network.send({"type": "friend_respond", "requestId": int(info.get("requestId", 0)), "accept": action == "accept"})
		"unfriend":
			# Asks first: unfriending can't be undone (they'd need a new request).
			confirm_dialog.ask("Remove [color=#aa2626]%s[/color] from your friends?" % username, "Unfriend",
				func(): Network.send({"type": "unfriend", "userId": user_id}))
		"star", "unstar":
			Network.send({"type": "star_friend", "userId": user_id, "starred": action == "star"})
		"unblock":
			Network.send({"type": "unblock_user", "userId": user_id})
		"add":
			Network.send({"type": "friend_request", "username": str(info.get("username", ""))})
			page.clear_search()
		"block":
			# Asks first: blocking also ends the friendship on the server (blockUser in friends.ts), and unblocking
			# doesn't bring it back.
			var message := "Block [color=#aa2626]%s[/color]? You won't see each other on the map or in chat." % username
			if info.get("relation", "") == "friend" or page == friend_page:
				message += " They'll also be removed from your friends."
			confirm_dialog.ask(message, "Block", func():
				Network.send({"type": "block_user", "userId": user_id})
				page.clear_search())


# Handles the server's friends and profile messages: rebuilds the lists, shows search results and notices, and
# saves a successful profile edit into Session.
func _on_message_received(data: Dictionary) -> void:
	match data.get("type"):
		"friends_list_result":
			for page in list_pages:
				page.show_list(data)
		"search_users_result":
			# Each page ignores results for text that isn't in its own search bar, so all pages can be given them.
			for page in list_pages:
				page.show_search_results(str(data.get("query", "")), data.get("users", []))
		"friend_request_result":
			_notice("Request sent!" if data.get("success", false) else str(data.get("error", "")))
			refresh()
		"friend_respond_result", "unfriend_result", "star_friend_result", "block_result", "unblock_result":
			if not data.get("success", false):
				_notice(str(data.get("error", "Something went wrong.")))
			refresh()
		"friend_request_received":
			request_page.show_notice("[color=#1c94e3]%s[/color] wants to be friends!" % str(data.get("fromUsername", "Someone")))
			refresh()
		"friend_request_answered":
			var answer := "accepted" if data.get("accepted", false) else "declined"
			_notice("[color=#1c94e3]%s[/color] %s your request." % [str(data.get("username", "Someone")), answer])
			refresh()
		"friend_removed":
			refresh()
		"update_profile_result":
			if data.get("success", false):
				Session.username = str(data.get("username", Session.username))
				Session.character = data.get("character", Session.character)
				profile_saved.emit(Session.username, Session.character)
			edit_page.show_save_result(data)


# --- Helpers ---

# Scales the card by card_scale around the middle of its right edge, so it shrinks toward the right side of the
# screen. Runs again if the card's size changes.
func _apply_card_scale() -> void:
	card.pivot_offset = Vector2(card.size.x, card.size.y / 2)
	card.scale = Vector2(card_scale, card_scale)


# Shows the -clicked icon on the selected tab and on the tab under the mouse, the normal icon on the others.
func _update_tab_icons() -> void:
	for i in tabs.get_tab_count():
		var lit := i == tabs.current_tab or i == _hovered_tab
		tabs.set_tab_icon(i, CLICKED_ICONS[i] if lit else NORMAL_ICONS[i])


# Shows a notice on the list page that's open (or on Friends if the Edit tab is open).
func _notice(text: String) -> void:
	var page: ListPage = friend_page
	match tabs.current_tab:
		Tab.REQUESTS: page = request_page
		Tab.BLOCKED: page = blocked_page
	page.show_notice(text)
