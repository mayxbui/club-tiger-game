class_name ListPage
extends MarginContainer

# List page of the player card (friend_page, request_page and blocked_page all inherit list_page.tscn).
# Shows 1 player row/person and search bar at the bottom: as you type a username, matching players pop up
# above it (from the server's search_users) with an Add button (Friends, Requests) or a Block button (Blocked).
# This page only shows things and reports clicks; player_card.gd does the networking.

# A button on a row or a search result was pressed (see the action names in player_row.gd).
signal row_action(action: String, info: Dictionary)
# The player paused typing in the search bar; player_card.gd sends search_users with this text.
signal search_requested(query: String)

const ROW_SCENE := preload("res://client/player-card/player_row.tscn")
# Wait this long after the last key before searching, so typing a name sends one search, not one per letter.
const SEARCH_DELAY := 0.25

@export_enum("friends", "requests", "blocked") var kind := "friends"
@export var title := "Fellow Tigers"

@onready var label_title: Label = $VBox/LabelTitle
@onready var label_count: Label = $VBox/LabelCount
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var label_empty: Label = $VBox/LabelEmpty
@onready var suggestions: PanelContainer = $VBox/Suggestions
@onready var suggestion_list: VBoxContainer = $VBox/Suggestions/SuggestionList
@onready var label_notice: Label = $VBox/LabelNotice
@onready var search_bar: LineEdit = $VBox/SearchRow/SearchBar
@onready var btn_search: TextureButton = $VBox/SearchRow/BtnSearch

var _search_timer: Timer


# Sets the title, hides the pop-up and connects the search bar (typing, Enter and the search icon).
func _ready() -> void:
	label_title.text = title
	suggestions.visible = false
	label_notice.text = ""
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect(_search_now)
	add_child(_search_timer)
	search_bar.text_changed.connect(_on_search_text_changed)
	search_bar.text_submitted.connect(func(_text): _search_now())
	btn_search.pressed.connect(_search_now)


# Rebuilds the list from a friends_list_result message: friends, incoming then outgoing requests, or blocked players.
func show_list(data: Dictionary) -> void:
	for child in list.get_children():
		child.queue_free()
	var count := 0
	match kind:
		"friends":
			for person in data.get("friends", []):
				_add_row(list, person, "friend")
			count = data.get("friends", []).size()
			label_count.text = "%d %s" % [count, "friend" if count == 1 else "friends"]
			label_empty.text = "No friends yet. Search for a username below."
		"requests":
			for person in data.get("incoming", []):
				_add_row(list, person, "incoming")
			for person in data.get("outgoing", []):
				_add_row(list, person, "outgoing")
			count = data.get("incoming", []).size() + data.get("outgoing", []).size()
			var incoming: int = data.get("incoming", []).size()
			label_count.text = "%d new %s" % [incoming, "request" if incoming == 1 else "requests"]
			label_empty.text = "No requests right now."
		"blocked":
			for person in data.get("blocked", []):
				_add_row(list, person, "blocked")
			count = data.get("blocked", []).size()
			label_count.text = "%d blocked" % count
			label_empty.text = "You haven't blocked anyone."
	label_empty.visible = count == 0


# Shows a search_users_result in the pop-up above the search bar. Ignores replies for text the player already
# changed, so a slow reply can't overwrite newer results.
func show_search_results(query: String, users: Array) -> void:
	if query != search_bar.text.strip_edges():
		return
	for child in suggestion_list.get_children():
		child.queue_free()
	if users.is_empty():
		var none := Label.new()
		none.text = "No players found."
		none.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
		suggestion_list.add_child(none)
	for person in users:
		_add_row(suggestion_list, person, "search_block" if kind == "blocked" else "search_add")
	suggestions.visible = true


# Shows a short message under the list (e.g. "Request sent" or the server's error).
func show_notice(text: String) -> void:
	label_notice.text = text


# Empties the search bar and closes the pop-up (after an Add or Block, or when the card closes).
func clear_search() -> void:
	search_bar.clear()
	_search_timer.stop()
	suggestions.visible = false


# Restarts the search delay as the player types, or closes the pop-up when the bar is empty.
func _on_search_text_changed(text: String) -> void:
	if text.strip_edges().is_empty():
		_search_timer.stop()
		suggestions.visible = false
		return
	_search_timer.start()


# Asks player_card.gd to search for what's in the bar now.
func _search_now() -> void:
	var query := search_bar.text.strip_edges()
	if query.is_empty():
		return
	search_requested.emit(query)


# Adds one player_row to a list and passes its button presses on as row_action.
func _add_row(parent: Container, person: Dictionary, row_kind: String) -> void:
	var row: PlayerRow = ROW_SCENE.instantiate()
	parent.add_child(row)
	row.setup(person, row_kind)
	row.action_pressed.connect(func(action, info): row_action.emit(action, info))
