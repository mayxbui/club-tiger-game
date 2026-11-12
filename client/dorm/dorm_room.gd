extends Room

# A dorm room (#10, #11, #12): your own (Session.dorm_owner_id = 0) or a friend's. Walking, other players, chat and the
# HUD come from Room (client/room/room.gd). Everyone appears in front of the door. The owner gets the HUD's pencil
# button, which opens edit mode: the item belt (item_belt.tscn) along the bottom, and placed items (placed_item.tscn)
# that can be selected, moved, scaled, layered and removed. Save sends the whole layout; Cancel puts back the last one.
#
# Server side (dorm.ts):
#   send     {"type": "enter_dorm", "ownerId"}               ownerId 0 = your own dorm
#            {"type": "save_dorm", "items": [{itemId, x, y, z, scale}]}
#   receive  dorm_state {ownerId, ownerName, canEdit, items, you: {x, y}, catalog?}   -> draw the room, place you
#            enter_dorm_result {success: false, error}         -> back to the map with the error
#            save_dorm_result {success, error?, items?}        -> leave edit mode, or show the error on the belt
#            dorm_updated {items}                              -> the owner saved while you're visiting
#   items:   [{itemId, spriteKey, x, y, z, scale}]; catalog: [{itemId, name, category, spriteKey, minScale, maxScale,
#            owned}] (owned = copies the owner has; left = owned - placed)

# Where characters can stand: the floor, for the dorm's 0.6 character scale. Must match DORM_BOUNDS in
# server/src/world.ts (the server also picks your spawn spot in front of the door: DORM_DOOR there).
const PLAY_AREA := Rect2(80, 600, 1600, 300)
const PLACED_ITEM_SCENE := preload("res://client/dorm/placed_item.tscn")
# Where a new item from the belt appears (the middle of the floor), and the layer range the server allows
# (MIN_ITEM_Z / MAX_ITEM_Z in server/src/validation.ts).
const NEW_ITEM_POSITION := Vector2(900, 760)
const MIN_Z := -100
const MAX_Z := 100

var owner_id := 0
var can_edit := false
var editing := false

# The owner's catalog: itemId -> {itemId, name, category, spriteKey, minScale, maxScale, owned}.
var _catalog := {}
# The layout as last saved (Cancel puts it back; visitors' rooms are rebuilt from it).
var _saved_items: Array = []
var _selected: PlacedItem = null
var _dragging: PlacedItem = null

@onready var items_node: Node2D = $Items
@onready var belt: ItemBelt = $EditLayer/ItemBelt


# Hides your character and the belt until the server says where you are, then does the shared Room setup (which
# sends enter_dorm through _join_room).
func _ready() -> void:
	local_player.visible = false
	belt.visible = false
	super()


# --- Room ---

# Asks the server to enter the dorm: yours (0) or the friend's in Session.dorm_owner_id. It answers with dorm_state
# (and world_state for the players already here).
func _join_room() -> void:
	Network.send({"type": "enter_dorm", "ownerId": Session.dorm_owner_id})


# The floor (Room clamps clicks and key walks into it).
func _play_area() -> Rect2:
	return PLAY_AREA


# In edit mode a click picks and drags items instead of walking: the topmost item under the mouse is selected (a
# corner handle of the selected item scales it, anywhere else on it moves it), and a click on empty space deselects.
func _unhandled_input(event: InputEvent) -> void:
	if not editing:
		super(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := get_global_mouse_position()
		if event.pressed:
			var hit := _item_at(point)
			_select(hit["item"])
			if hit["item"] != null:
				_dragging = hit["item"]
				_dragging.begin_drag(point, "scale" if hit["part"] == "corner" else "move")
		elif _dragging != null:
			_dragging.end_drag()
			_dragging = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging != null:
		_dragging.drag_to(get_global_mouse_position())
		get_viewport().set_input_as_handled()


# --- Server handler (extends Room's) ---

# Handles the dorm's own messages on top of Room's (players, chat).
func _on_message_received(data: Dictionary) -> void:
	super(data)
	match data.get("type"):
		"dorm_state":
			owner_id = int(data.get("ownerId", 0))
			can_edit = bool(data.get("canEdit", false))
			var you: Dictionary = data.get("you", {})
			local_player.global_position = Vector2(float(you.get("x", 120.0)), float(you.get("y", 640.0)))
			local_player.move_to(local_player.global_position)
			local_player.visible = true
			_catalog.clear()
			for item in data.get("catalog", []):
				_catalog[int(item.get("itemId", 0))] = item
			_saved_items = data.get("items", [])
			# After a reconnect while editing, keep the unsaved changes instead of redrawing the saved layout.
			if not editing:
				_build_items(_saved_items)
			hud.set_edit_available(can_edit)
			hud.btn_my_dorm.visible = owner_id != Session.userId
			if can_edit:
				belt.setup(data.get("catalog", []))
		"enter_dorm_result":
			if not data.get("success", false):
				Session.go_to_map(str(data.get("error", "Couldn't open that dorm.")))
		"dorm_updated":
			_saved_items = data.get("items", [])
			if not editing:
				_build_items(_saved_items)
		"save_dorm_result":
			belt.set_saving(false)
			if data.get("success", false):
				_saved_items = data.get("items", [])
				_set_editing(false)
				hud.show_notice("Dorm saved!")
			else:
				belt.show_notice(str(data.get("error", "Couldn't save. Please try again.")))


# --- Scene signals (connected in dorm_room.tscn) ---

# The HUD's "Map" button goes back to the campus map (unsaved edits are dropped).
func _on_hud_place_pressed() -> void:
	Session.go_to_map()


# The HUD's pencil button starts edit mode (only shown to the owner).
func _on_hud_edit_pressed() -> void:
	if can_edit:
		_set_editing(true)


# A box on the belt was clicked: a new copy appears in the middle of the floor, in front of everything, selected.
func _on_item_belt_item_chosen(item_id: int) -> void:
	var info: Dictionary = _catalog.get(item_id, {})
	if info.is_empty() or _copies_left(item_id) <= 0:
		return
	var scale_value := clampf(1.0, float(info.get("minScale", 0.1)), float(info.get("maxScale", 10.0)))
	var item := _add_item({
		"itemId": item_id, "spriteKey": info.get("spriteKey", ""),
		"x": NEW_ITEM_POSITION.x, "y": NEW_ITEM_POSITION.y, "z": mini(_top_z() + 1, MAX_Z), "scale": scale_value,
	})
	_sort_items()
	_select(item)
	_update_counts()


# Save sends the whole layout; the belt stays open until save_dorm_result.
func _on_item_belt_save_pressed() -> void:
	var layout := []
	for item: PlacedItem in items_node.get_children():
		layout.append(item.to_dict())
	if Network.send({"type": "save_dorm", "items": layout}):
		belt.set_saving(true)
		belt.show_notice("Saving...")
	else:
		belt.show_notice("Not connected. Try again in a moment.")


# Cancel throws away the changes: the last saved layout comes back and edit mode closes.
func _on_item_belt_cancel_pressed() -> void:
	_build_items(_saved_items)
	_set_editing(false)


# A placed item's toolbar button: remove it (its copy goes back to the belt), or move it one layer up or down.
func _on_item_action(action: String, item: PlacedItem) -> void:
	match action:
		"remove":
			if _selected == item:
				_select(null)
			items_node.remove_child(item)
			item.queue_free()
			_update_counts()
		"up", "down":
			_restack(item, action == "up")


# --- Helpers ---

# Turns edit mode on or off: the belt replaces the chat and room buttons, clicks pick items instead of walking, and
# the copies-left numbers are refreshed.
func _set_editing(on: bool) -> void:
	editing = on
	walking_enabled = not on
	hud.set_editing(on)
	belt.visible = on
	if on:
		local_player.move_to(local_player.global_position)   # stop walking
		belt.reset_filter()
		belt.show_notice("")
		_update_counts()
	else:
		_select(null)
		_dragging = null


# Replaces every placed item with a layout from the server.
func _build_items(layout: Array) -> void:
	_select(null)
	for child in items_node.get_children():
		items_node.remove_child(child)
		child.queue_free()
	for data in layout:
		_add_item(data)
	_sort_items()


# Adds one placed item ({itemId, spriteKey, x, y, z, scale}) to the room and listens to its toolbar.
func _add_item(data: Dictionary) -> PlacedItem:
	var item: PlacedItem = PLACED_ITEM_SCENE.instantiate()
	items_node.add_child(item)
	item.setup(data, _catalog.get(int(data.get("itemId", 0)), {}))
	item.action_pressed.connect(_on_item_action.bind(item))   # runtime node, so connected in code
	return item


# Draws items back to front by their layer (z), so a higher z is drawn on top. The draw order of children is used
# instead of z_index, so items always stay behind the players.
func _sort_items() -> void:
	var items := items_node.get_children()
	items.sort_custom(func(a, b): return a.z < b.z)
	for i in items.size():
		items_node.move_child(items[i], i)


# Selects one item (or none) and shows its frame, handles and toolbar.
func _select(item: PlacedItem) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = item
	if item != null:
		item.set_selected(true)


# The topmost item under a point and which part was hit: {"item": PlacedItem or null, "part": "corner" / "body"}.
# The selected item's handles win, since they can stick out past other items.
func _item_at(point: Vector2) -> Dictionary:
	if _selected != null and _selected.hit_test(point) == "corner":
		return {"item": _selected, "part": "corner"}
	var children := items_node.get_children()
	for i in range(children.size() - 1, -1, -1):
		var part: String = children[i].hit_test(point)
		if part != "":
			return {"item": children[i], "part": part}
	return {"item": null, "part": ""}


# Moves an item one step forward (up) or back among the items it overlaps: just in front of the lowest overlapping
# item above it, or just behind the highest one below it. Items it doesn't touch aren't affected.
func _restack(item: PlacedItem, up: bool) -> void:
	var rect := item.room_rect()
	var target = null
	for other: PlacedItem in items_node.get_children():
		if other == item or not rect.intersects(other.room_rect()):
			continue
		if up and other.z >= item.z and other.get_index() > item.get_index():
			target = other.z if target == null else mini(target, other.z)
		elif not up and other.z <= item.z and other.get_index() < item.get_index():
			target = other.z if target == null else maxi(target, other.z)
	if target == null:
		belt.show_notice("Already in front." if up else "Already at the back.")
		return
	item.z = clampi(target + 1 if up else target - 1, MIN_Z, MAX_Z)
	_sort_items()


# The highest layer in the room (0 if empty), so a new item goes in front of everything.
func _top_z() -> int:
	var top := 0
	for item: PlacedItem in items_node.get_children():
		top = maxi(top, item.z)
	return top


# How many copies of an item are left to place: the copies owned minus the ones in the room.
func _copies_left(item_id: int) -> int:
	var placed := 0
	for item: PlacedItem in items_node.get_children():
		if item.item_id == item_id:
			placed += 1
	return int(_catalog.get(item_id, {}).get("owned", 0)) - placed


# Refreshes every box's copies-left number on the belt.
func _update_counts() -> void:
	var left := {}
	for item_id in _catalog:
		left[item_id] = _copies_left(item_id)
	belt.set_counts(left)
