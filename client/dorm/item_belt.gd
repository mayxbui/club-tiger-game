class_name ItemBelt
extends PanelContainer

# The bar along the bottom of the screen in a dorm's edit mode: a search box on the left, category tabs (text
# placeholders until they get sprites), a scrolling row of item boxes (item_slot.tscn), and Save / Cancel on the right.
# It only shows things and reports clicks; dorm_room.gd places items and talks to the server.

# A box was clicked while copies of its item are left.
signal item_chosen(item_id: int)
signal save_pressed
signal cancel_pressed

const SLOT_SCENE := preload("res://client/dorm/item_slot.tscn")
# How close a misspelled search must be to a name (or one word of it) to still match, from 0 to 1.
const SIMILAR_ENOUGH := 0.5

var _category := "all"
var _query := ""
var _slots: Array[ItemSlot] = []

@onready var search_bar: LineEdit = $HBox/Left/SearchBar
@onready var label_notice: Label = $HBox/Left/LabelNotice
@onready var slots_row: HBoxContainer = $HBox/Middle/Scroll/Slots
@onready var label_empty: Label = $HBox/Left/LabelEmpty
@onready var btn_save: Button = $HBox/Right/BtnSave


# --- Public ---

# Makes one box per catalog item ({itemId, name, category, spriteKey}), in catalog order.
func setup(catalog: Array) -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	for item in catalog:
		var slot: ItemSlot = SLOT_SCENE.instantiate()
		slots_row.add_child(slot)
		slot.setup(item)
		slot.chosen.connect(func(id): item_chosen.emit(id))   # runtime node, so connected in code
		_slots.append(slot)
	_apply_filter()


# Updates every box's "copies left" number: item_id -> count.
func set_counts(left: Dictionary) -> void:
	for slot in _slots:
		slot.set_left(int(left.get(slot.item_id, 0)))


# Clears the search and goes back to the All tab (when edit mode opens).
func reset_filter() -> void:
	search_bar.clear()
	_query = ""
	_category = "all"
	$HBox/Middle/Tabs/BtnAll.button_pressed = true
	_apply_filter()


# Shows a short message under the search box (the server's error, "Saving...").
func show_notice(text: String) -> void:
	label_notice.text = text


# Turns Save off while a save is on its way.
func set_saving(on: bool) -> void:
	btn_save.disabled = on


# --- Scene signals (connected in item_belt.tscn) ---

# Filters the boxes as the player types.
func _on_search_bar_text_changed(text: String) -> void:
	_query = text.strip_edges().to_lower()
	_apply_filter()


# A category tab was picked ("all", "furniture", "decoration" or "plant"; bound in item_belt.tscn).
func _on_category_pressed(category: String) -> void:
	_category = category
	_apply_filter()


# Save sends the layout (dorm_room.gd).
func _on_btn_save_pressed() -> void:
	save_pressed.emit()


# Cancel puts back the last saved layout (dorm_room.gd).
func _on_btn_cancel_pressed() -> void:
	cancel_pressed.emit()


# --- Helpers ---

# Shows only the boxes in the picked category whose name matches the search, and a message if none do.
func _apply_filter() -> void:
	var shown := 0
	for slot in _slots:
		var visible_now := (_category == "all" or slot.category == _category) and _matches(slot.item_name)
		slot.visible = visible_now
		if visible_now:
			shown += 1
	label_empty.visible = shown == 0
	label_empty.text = "No items match." if not _query.is_empty() else "No items here yet."


# True if an item name matches the search: it contains the text, or the text is spelled close to the name or to one
# of its words ("bookshelve" finds Bookshelf, "polaroid" finds Night Sky Polaroid).
func _matches(item_name: String) -> bool:
	if _query.is_empty():
		return true
	var name_lower := item_name.to_lower()
	if name_lower.contains(_query) or name_lower.similarity(_query) >= SIMILAR_ENOUGH:
		return true
	for word in name_lower.split(" ", false):
		if word.similarity(_query) >= SIMILAR_ENOUGH:
			return true
	return false
