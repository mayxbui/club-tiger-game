class_name ItemSlot
extends PanelContainer

# One square box on the dorm's item belt: the item's picture scaled to fit the box, how many copies are left in the
# top-right corner, and the item's name next to the cursor on hover (a tooltip). Greyed out when none are left.

# The box was clicked while copies are left: the belt places a new copy in the room.
signal chosen(item_id: int)

var item_id := 0
var item_name := ""
var category := ""
var left := 0

@onready var picture: TextureRect = $Picture
@onready var label_count: Label = $LabelCount


# --- Public ---

# Fills the box from a catalog item ({itemId, name, category, spriteKey}).
func setup(item: Dictionary) -> void:
	if not is_node_ready():
		await ready
	item_id = int(item.get("itemId", 0))
	item_name = str(item.get("name", ""))
	category = str(item.get("category", ""))
	tooltip_text = item_name
	picture.texture = DormItems.preview(str(item.get("spriteKey", "")))


# Shows how many copies are left; at 0 the box is greyed out and can't be clicked.
func set_left(count: int) -> void:
	if not is_node_ready():
		await ready
	left = count
	label_count.text = str(count)
	modulate = Color(1, 1, 1, 1) if count > 0 else Color(1, 1, 1, 0.4)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if count > 0 else Control.CURSOR_ARROW


# --- Scene signals (connected in item_slot.tscn) ---

# A left click on the box chooses the item if a copy is left.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and left > 0:
		chosen.emit(item_id)
		accept_event()
