class_name PlacedItem
extends Node2D

# One item placed in a dorm. In edit mode the owner can select it: a frame with a handle on each of its 4 corners is
# drawn around it (drag a corner to scale, drag the item to move), and a small toolbar above it has Remove, Up and
# Down (placeholder buttons until they get icons). dorm_room.gd decides which item a click hits and does the
# dragging through hit_test / begin_drag / drag_to; this script only draws and keeps the item's numbers.

# A toolbar button was pressed: "remove", "up" or "down" (dorm_room.gd acts on it).
signal action_pressed(action: String)

# Size of a corner handle and how close a click must be to grab it, in screen pixels.
const HANDLE_SIZE := 18.0
const FRAME_COLOR := Color(0.11, 0.58, 0.89)
# The whole room picture: an item's center can be anywhere on it (posters go on the wall). Must match DORM_WIDTH /
# DORM_HEIGHT in server/src/validation.ts.
const ROOM_RECT := Rect2(0, 0, 1920, 1080)

var item_id := 0
var sprite_key := ""
# Layer order: higher is drawn in front. dorm_room.gd keeps the Items children sorted by it.
var z := 0
var item_scale := 1.0
var min_scale := 0.1
var max_scale := 10.0
var selected := false

var _drag_mode := ""          # "move", "scale" or "" when not dragging
var _drag_offset := Vector2.ZERO
var _drag_start_scale := 1.0
var _drag_start_distance := 1.0

@onready var sprite: Sprite2D = $Sprite
@onready var toolbar: HBoxContainer = $Toolbar


# Hides the toolbar until the item is selected.
func _ready() -> void:
	toolbar.visible = false


# --- Public ---

# Fills the item from a placed item ({itemId, spriteKey, x, y, z, scale}) and its catalog limits (minScale /
# maxScale; visitors don't get the catalog, so the limits are optional).
func setup(data: Dictionary, limits: Dictionary = {}) -> void:
	if not is_node_ready():
		await ready
	item_id = int(data.get("itemId", 0))
	sprite_key = str(data.get("spriteKey", ""))
	z = int(data.get("z", 0))
	min_scale = float(limits.get("minScale", 0.1))
	max_scale = float(limits.get("maxScale", 10.0))
	position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	sprite.texture = DormItems.texture(sprite_key)
	_set_item_scale(float(data.get("scale", 1.0)))


# This item as the server stores it, for save_dorm.
func to_dict() -> Dictionary:
	return {"itemId": item_id, "x": position.x, "y": position.y, "z": z, "scale": item_scale}


# Shows or hides the frame, handles and toolbar.
func set_selected(on: bool) -> void:
	selected = on
	toolbar.visible = on
	_place_toolbar()
	queue_redraw()


# What a point (in room coordinates) is over: "corner" (a handle of the selected item), "body", or "" (missed).
func hit_test(point: Vector2) -> String:
	var local := point - position
	var rect := _frame_rect()
	if selected:
		for corner in _corners(rect):
			if local.distance_to(corner) <= HANDLE_SIZE:
				return "corner"
	return "body" if rect.has_point(local) else ""


# Starts dragging from a point: "move" keeps the grab point under the mouse, "scale" grows or shrinks the item as the
# mouse moves away from or toward its center.
func begin_drag(point: Vector2, mode: String) -> void:
	_drag_mode = mode
	_drag_offset = position - point
	_drag_start_scale = item_scale
	_drag_start_distance = maxf(point.distance_to(position), 1.0)


# Follows the mouse while dragging (moves stay inside the room, scales stay inside the item's limits).
func drag_to(point: Vector2) -> void:
	match _drag_mode:
		"move":
			position = (point + _drag_offset).clamp(ROOM_RECT.position, ROOM_RECT.end)
		"scale":
			_set_item_scale(_drag_start_scale * point.distance_to(position) / _drag_start_distance)


# Stops dragging.
func end_drag() -> void:
	_drag_mode = ""


# True while the mouse is moving or scaling this item.
func is_dragging() -> bool:
	return _drag_mode != ""


# The item's picture as a rectangle in room coordinates (dorm_room.gd uses it to find overlapping items for Up/Down).
func room_rect() -> Rect2:
	var rect := _frame_rect()
	rect.position += position
	return rect


# --- Scene signals (connected in placed_item.tscn) ---

# Toolbar: take this item out of the room (its copy goes back to the belt).
func _on_btn_remove_pressed() -> void:
	action_pressed.emit("remove")


# Toolbar: bring this item in front of the item it overlaps.
func _on_btn_up_pressed() -> void:
	action_pressed.emit("up")


# Toolbar: send this item behind the item it overlaps.
func _on_btn_down_pressed() -> void:
	action_pressed.emit("down")


# --- Drawing ---

# Draws the selection frame and its 4 corner handles.
func _draw() -> void:
	if not selected:
		return
	var rect := _frame_rect()
	draw_rect(rect, FRAME_COLOR, false, 2.0)
	for corner in _corners(rect):
		var handle := Rect2(corner - Vector2.ONE * HANDLE_SIZE / 2, Vector2.ONE * HANDLE_SIZE)
		draw_rect(handle, Color.WHITE)
		draw_rect(handle, FRAME_COLOR, false, 2.0)


# --- Helpers ---

# Sets the item's size (kept inside its limits) and redraws the frame.
func _set_item_scale(value: float) -> void:
	item_scale = clampf(value, min_scale, max_scale)
	sprite.scale = Vector2(item_scale, item_scale)
	_place_toolbar()
	queue_redraw()


# The item's picture as a rectangle around its center, at its current size.
func _frame_rect() -> Rect2:
	var size := sprite.texture.get_size() * item_scale if sprite.texture else Vector2.ONE * 64
	return Rect2(-size / 2, size)


# The 4 corners of a rectangle.
func _corners(rect: Rect2) -> Array[Vector2]:
	return [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]


# Keeps the toolbar centered just above the item's frame.
func _place_toolbar() -> void:
	if not is_node_ready():
		return
	var rect := _frame_rect()
	toolbar.position = Vector2(-toolbar.size.x / 2, rect.position.y - toolbar.size.y - 12)
