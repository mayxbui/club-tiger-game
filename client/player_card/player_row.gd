class_name PlayerRow
extends HBoxContainer

# One person in a player-card list: avatar, name, a status line and action buttons on the right. Used by the
# Friends, Requests and Blocked pages and by the search pop-up, so every list looks the same.
#
# kind decides the status text and buttons (the action names are what action_pressed sends):
#   "friend"        Online/Offline     Visit -> "visit" (their dorm), Unfriend -> "unfriend", Star -> "star"/"unstar",
#                                      Block -> "block"
#   "incoming"      wants to be friends    Add -> "accept", Nope -> "decline"
#   "outgoing"      request sent           (no buttons)
#   "blocked"       blocked by you         Unblock -> "unblock", Report (disabled until reports exist)
#   "search_add"    search result          Add -> "add" (disabled if already friends, pending or blocked)
#   "search_block"  search result          Block -> "block" (disabled if already blocked)

signal action_pressed(action: String, info: Dictionary)

# Yellow buttons for the main action, dark for the other one (same themes as the rest of the UI).
const YELLOW_THEME := preload("res://client/assets/sub-theme-2.tres")
const DARK_THEME := preload("res://client/assets/base-theme.tres")

# The person this row shows (one entry from friends_list_result or search_users_result).
var info: Dictionary = {}

@onready var avatar: PlayerSkeleton = $Identity/Avatar
@onready var label_name: Label = $Identity/Info/LabelName
@onready var label_status: Label = $Identity/Info/LabelStatus
@onready var actions: HBoxContainer = $Actions
@onready var friend_actions: VBoxContainer = $FriendActions
@onready var visit_actions: HBoxContainer = $FriendActions/Visit
@onready var manage_actions: HBoxContainer = $FriendActions/Manage
@onready var favorite: CenterContainer = $Favorite


# Fills the row for one person and builds the buttons for this kind of list (see the table at the top).
func setup(person: Dictionary, kind: String) -> void:
	if not is_node_ready():
		await ready
	info = person
	avatar.apply_character(person.get("character", {}))
	label_name.text = str(person.get("username", ""))
	var is_friend := kind == "friend"
	actions.visible = not is_friend
	friend_actions.visible = is_friend
	favorite.visible = is_friend
	for container in [actions, visit_actions, manage_actions, favorite]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

	match kind:
		"friend":
			label_status.text = "Online" if person.get("online", false) else "Offline"
			var visit := _add_button("Visit", "visit", YELLOW_THEME, visit_actions)
			visit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_add_button("Unfriend", "unfriend", DARK_THEME, manage_actions)
			_add_button("Block", "block", DARK_THEME, manage_actions)
			if person.get("starred", false):
				_add_button("Starred", "unstar", YELLOW_THEME, favorite)
			else:
				_add_button("Star", "star", DARK_THEME, favorite)
		"incoming":
			label_status.text = "wants to be friends"
			_add_button("Add", "accept", YELLOW_THEME)
			_add_button("Nope", "decline", DARK_THEME)
		"outgoing":
			label_status.text = "request sent"
		"blocked":
			label_status.text = "blocked by you"
			_add_button("Unblock", "unblock", YELLOW_THEME)
			var report := _add_button("Report", "report", DARK_THEME)
			report.disabled = true
			report.tooltip_text = "Reports are coming soon."
		"search_add":
			var relation := str(person.get("relation", "none"))
			label_status.text = _relation_text(relation)
			var add := _add_button("Add", "add", YELLOW_THEME)
			add.disabled = relation != "none"
		"search_block":
			var relation := str(person.get("relation", "none"))
			label_status.text = _relation_text(relation)
			var block := _add_button("Block", "block", DARK_THEME)
			block.disabled = relation == "blocked"


# Returns the status line for a search result's relation to you.
func _relation_text(relation: String) -> String:
	match relation:
		"friend": return "already friends"
		"pending": return "request pending"
		"blocked": return "blocked by you"
	return ""


# Adds a button to its action column and forwards presses with the player's info.
func _add_button(text: String, action: String, button_theme: Theme, target: Container = null) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = button_theme
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): action_pressed.emit(action, info))
	if target != null:
		button.add_theme_font_size_override("font_size", 16)
		target.add_child(button)
	else:
		actions.add_child(button)
	return button
