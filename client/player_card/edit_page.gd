class_name EditPage
extends MarginContainer

# Edit page: change your look and username, then Save or Cancel
# Changes only touch a draft (and the preview) until Save. player_card.gd sends update_profile with save_requested's
# changes and passes the reply back to show_save_result.
# Button signals (pencil, Enter in the name box, Cancel, Save) are connected in edit_page.tscn.

# Save was pressed with these changes: only the fields that differ from the saved profile, {username?, character?}.
signal save_requested(changes: Dictionary)

# Same rule as USERNAME_PATTERN in server/src/validation.ts and create_account.gd.
const USERNAME_RULE := "^[A-Za-z0-9_]{3,20}$"
const USERNAME_HINT := "Username must be 3 to 20 letters, numbers, or underscores."

# The look and name being edited (Session keeps the saved ones until Save succeeds).
var _draft_character := {"skin": 0, "hair": 0, "eyes": 0}
var _draft_username := ""
var _username_check := RegEx.new()
# True while the name box can be typed in (after the pencil was clicked).
var _editing_name := false

@onready var preview: PlayerSkeleton = $VBox/Content/Preview
@onready var customizer = $VBox/Content/CharacterCustomizer
@onready var input_username: LineEdit = $VBox/NameRow/InputUsername
@onready var label_notice: Label = $VBox/LabelNotice
@onready var btn_save: Button = $VBox/Buttons/BtnSave


# --- Setup ---

# Compiles the username rule, links the customizer to the draft, and shows the saved profile.
func _ready() -> void:
	_username_check.compile(USERNAME_RULE)
	customizer.skin_changed.connect(func(id): _set_part("skin", id))
	customizer.hair_changed.connect(func(id): _set_part("hair", id))
	customizer.eyes_changed.connect(func(id): _set_part("eyes", id))
	reset()


# --- Called by player_card.gd ---

# Copies the saved look and name from Session into the draft and shows them. Runs when the card opens, on Cancel
# and after a successful save.
func reset() -> void:
	_draft_character = _saved_character()
	_draft_username = Session.username
	preview.apply_character(_draft_character)
	customizer.set_selection(_draft_character)
	input_username.text = _draft_username
	_set_name_editing(false)
	label_notice.text = ""
	btn_save.disabled = false


# Shows the server's update_profile_result: on success the page shows the new saved profile (player_card.gd has
# already updated Session), otherwise the error.
func show_save_result(data: Dictionary) -> void:
	btn_save.disabled = false
	if data.get("success", false):
		reset()
		label_notice.text = "Saved!"
	else:
		label_notice.text = str(data.get("error", "Couldn't save. Please try again."))


# --- Button and input handlers (connected in edit_page.tscn) ---

# The pencil button: starts editing the name, or checks and keeps the typed name.
func _on_btn_edit_name_pressed() -> void:
	_toggle_name_edit()


# Enter in the name box does the same as the pencil.
func _on_input_username_text_submitted(_new_text: String) -> void:
	_toggle_name_edit()


# Cancel throws away the draft and shows the saved profile again.
func _on_btn_cancel_pressed() -> void:
	reset()


# Sends only what changed (a still-open name box counts). Save stays disabled until show_save_result.
func _on_btn_save_pressed() -> void:
	if _editing_name and not _toggle_name_edit():
		return
	var changes := {}
	if _draft_username != Session.username:
		changes["username"] = _draft_username
	var saved := _saved_character()
	for key in saved:
		if int(_draft_character[key]) != saved[key]:
			changes["character"] = _draft_character.duplicate()
			break
	if changes.is_empty():
		label_notice.text = "Nothing to save."
		return
	btn_save.disabled = true
	label_notice.text = "Saving..."
	save_requested.emit(changes)


# --- Helpers ---

# Starts editing the name, or (if already editing) checks the typed name and stops editing. Returns false if the
# typed name breaks the username rule, so editing continues (Save uses this to stop).
func _toggle_name_edit() -> bool:
	if not _editing_name:
		_set_name_editing(true)
		return true
	var typed := input_username.text.strip_edges()
	if _username_check.search(typed) == null:
		label_notice.text = USERNAME_HINT
		return false
	_draft_username = typed
	input_username.text = typed
	_set_name_editing(false)
	label_notice.text = ""
	return true


# Switches the name box between showing the name (flat, no box, can't type) and editing it (a normal text box with
# the cursor at the end of the name).
func _set_name_editing(on: bool) -> void:
	_editing_name = on
	input_username.editable = on
	input_username.flat = not on
	input_username.selecting_enabled = on
	if on:
		input_username.grab_focus()
		input_username.caret_column = input_username.text.length()
	else:
		input_username.release_focus()


# Records one changed part from the customizer and redraws the preview.
func _set_part(key: String, id: int) -> void:
	_draft_character[key] = id
	preview.apply_character(_draft_character)


# The saved look from Session as whole numbers (JSON numbers arrive as floats; missing parts are 0).
func _saved_character() -> Dictionary:
	return {
		"skin": int(Session.character.get("skin", 0)),
		"hair": int(Session.character.get("hair", 0)),
		"eyes": int(Session.character.get("eyes", 0)),
	}
