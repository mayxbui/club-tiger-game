class_name PlayerRow
extends HBoxContainer

# One person in a player-card list: avatar, name, a status line and action buttons on the right. Used by the
# Friends, Requests and Blocked pages and by the search pop-up, so every list looks the same.
#
# kind decides the status text and buttons (the action names are what action_pressed sends):
#   "friend"        Online/Offline     Visit (disabled until dorms, #12), Unfriend -> "unfriend", Star -> "star"/"unstar"
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

@onready var avatar: PlayerSkeleton = $Avatar
@onready var label_name: Label = $Info/LabelName
@onready var label_status: Label = $Info/LabelStatus
@onready var actions: HBoxContainer = $Actions


# Fills the row for one person and builds the buttons for this kind of list (see the table at the top).
func setup(person: Dictionary, kind: String) -> void:
	if not is_node_ready():
		await ready
	info = person
	avatar.apply_character(person.get("character", {}))
	label_name.text = str(person.get("username", ""))
	for child in actions.get_children():
		child.queue_free()

	match kind:
		"friend":
			label_status.text = "Online" if person.get("online", false) else "Offline"
			var visit := _add_button("Visit", "visit", YELLOW_THEME)
			visit.disabled = true
			visit.tooltip_text = "Dorm visits are coming soon."
			_add_button("Unfriend", "unfriend", DARK_THEME)
			if person.get("starred", false):
				_add_button("Starred", "unstar", YELLOW_THEME)
			else:
				_add_button("Star", "star", DARK_THEME)
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


# Adds one button to the right side; pressing it sends action_pressed(action, info).
func _add_button(text: String, action: String, button_theme: Theme) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = button_theme
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): action_pressed.emit(action, info))
	actions.add_child(button)
	return button
