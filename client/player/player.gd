extends CharacterBody2D

@export var SPEED := 300.0
@onready var body := $Skeleton
@onready var skin := $Skeleton/Skin
@onready var hair := $Skeleton/Hair
@onready var eye := $Skeleton/Eye
#@onready var top := $Skeleton/Top
#@onready var bottom := $Skeleton/Bottom

# Only the player the map spawns for this client reacts to the keyboard; the create-account preview and other
# players leave this false.
@export var is_local := false

const IDLE_FRAME := 0
const WALK_FRAME := 1
const STEP_SECONDS := 0.2
var step_timer := 0.0


# Moves the local player left/right with the arrow keys, switches between the walk and idle poses every STEP_SECONDS, and faces the direction of movement (placeholder until click-to-move in Week 4).
func _physics_process(delta: float) -> void:
	if not is_local:
		return
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
		step_timer += delta
		if step_timer >= STEP_SECONDS:
			step_timer = 0.0
			skin.frame = WALK_FRAME if skin.frame == IDLE_FRAME else IDLE_FRAME
		body.scale.x = -1 if direction > 0 else 1
	else:
		skin.frame = IDLE_FRAME
		step_timer = 0.0
		velocity.x = move_toward(velocity.x, 0, SPEED)
	move_and_slide()


# Draws a saved character (e.g. Session.character); JSON numbers arrive as floats, so int() converts them, and missing keys fall back to 0.
# Call it after add_child(), since the @onready sprite variables are only set once the player is in the tree.
func _apply_character(character: Dictionary) -> void:
	change_skin(int(character.get("skin", 0)))
	change_hair(int(character.get("hair", 0)))
	change_eyes(int(character.get("eyes", 0)))
	# Next checkpoint: once the Top and Bottom Sprite2D nodes exist (and their @onready lines above are uncommented),
	# add matching handlers for them and call them here with character.get("top", 0) and character.get("bottom", 0).

# TODO: FIX - player.tscn: the Skin's texture is saved as an embedded "CompressedTexture2D" that points into
# Godot's import cache (res://.godot/imported/shade1.png-....ctex), not to res://client/assets/skin/shade1.png.
# The cache isn't part of your project files (and usually isn't committed), so on a fresh clone, or whenever
# Godot rebuilds the cache, the Skin loses its texture. In the Inspector, click the Skin's Texture > Clear, then
# drag shade0.png from the FileSystem dock onto it. It should show as a file path, not "CompressedTexture2D".
# (At runtime change_skin() replaces it anyway, so the game still looks right; this is about the scene file.)
# Optional cleanup: clear the leftover region_rect values (they do nothing, Region is off), and delete files
# nothing uses anymore: hair_sprite_sheet.png, eyes_sprite_sheet.png, skin1/3/5/7.png, "sprite - Copy.png",
# and the shadeN-1/shadeN-2 files if they were only drafts.

# Shows the chosen skin tone by swapping the skin texture (the frame stays under the walk animation's control).
func change_skin(id: int) -> void:
	skin.texture = CharacterPresets.get_texture(CharacterPresets.SKIN, id)

# Shows the chosen hairstyle by swapping the hair texture.
func change_hair(id:int) -> void:
	hair.texture = CharacterPresets.get_texture(CharacterPresets.HAIR, id)

# Shows the chosen eyes by swapping the eye texture.
func change_eyes(id: int) -> void:
	eye.texture = CharacterPresets.get_texture(CharacterPresets.EYES, id)

# Shows a player's name under their character; the map passes Session.username for the local player.
func _set_username(username: String) -> void:
	$Skeleton/Username_label.text = username
