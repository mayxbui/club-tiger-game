class_name PlayerSkeleton
extends Control

# Draws player (skin, hair, eyes) from a saved data. Used on the map (player.tscn, fit_to_size off) and in
# the UI (edit page, friend rows, search pop-up, fit_to_size on), so a player looks the same everywhere.

## On: Body is centered and scaled to fit this Control's size (UI). Off: Body stays at (0, 0) at full size (map).
@export var fit_to_size := false

# Size and center of the drawing at scale 1 (the skin frame is 227x425, the hair sticks out above it).
const DRAWING_SIZE := Vector2(240, 440)
const DRAWING_CENTER := Vector2(0, -5)

@onready var body: Node2D = $Body
@onready var skin: Sprite2D = $Body/Skin
@onready var hair: Sprite2D = $Body/Hair
@onready var eye: Sprite2D = $Body/Eye

# A character set before this node was ready (e.g. right after instantiate()); drawn in _ready.
var _pending_character = null


# Fits the drawing now and whenever a Container resizes this Control, and draws any character set before ready.
func _ready() -> void:
	resized.connect(_fit)
	_fit()
	if _pending_character != null:
		apply_character(_pending_character)
		_pending_character = null


# Centers Body and scales it so the whole drawing fits inside this Control (only when fit_to_size is on).
func _fit() -> void:
	if not fit_to_size or size.x <= 0 or size.y <= 0:
		return
	var s := minf(size.x / DRAWING_SIZE.x, size.y / DRAWING_SIZE.y)
	body.scale = Vector2(s, s)
	body.position = size / 2 - DRAWING_CENTER * s


# Draws a saved character ({skin, hair, eyes}); JSON numbers arrive as floats, so int() converts them, and missing
# keys fall back to 0.
func apply_character(character: Dictionary) -> void:
	if not is_node_ready():
		_pending_character = character
		return
	change_skin(int(character.get("skin", 0)))
	change_hair(int(character.get("hair", 0)))
	change_eyes(int(character.get("eyes", 0)))
	# Next checkpoint: add change_top / change_bottom here once the Top and Bottom sprites exist.


# Shows the chosen skin tone by swapping the skin texture.
func change_skin(id: int) -> void:
	skin.texture = CharacterPresets.get_texture(CharacterPresets.SKIN, id)


# Shows the chosen hairstyle by swapping the hair texture.
func change_hair(id: int) -> void:
	hair.texture = CharacterPresets.get_texture(CharacterPresets.HAIR, id)


# Shows the chosen eyes by swapping the eye texture.
func change_eyes(id: int) -> void:
	eye.texture = CharacterPresets.get_texture(CharacterPresets.EYES, id)
