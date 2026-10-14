extends CharacterBody2D

@export var SPEED := 300.0
@onready var body := $Skeleton
@onready var skin := $Skeleton/Skin
@onready var hair := $Skeleton/Hair
@onready var eye := $Skeleton/Eye
#@onready var top := $Skeleton/Top
#@onready var bottom := $Skeleton/Bottom

# True only for this client's own player (set by world_map.gd); other players' copies leave it false.
@export var is_local := false

const IDLE_FRAME := 0
const WALK_FRAME := 1
const STEP_SECONDS := 0.1
const ARRIVE := 4		#close enough to target (prevent lagging)
var click_pos := Vector2.ZERO
var moving := false
var step_timer := 0.0

# Starts with the target on the player, so nothing moves until move_to() is called.
func _ready():
	click_pos = global_position

# Sets where this player should walk to (a point in world coordinates, e.g. a mouse click).
func move_to(click: Vector2)->void:
	click_pos = click
	moving = true

# Walks toward click_pos at SPEED, swapping walk/idle frames and facing left or right, then stops on arrival or at wall
func _physics_process(delta: float) -> void:
	if moving and global_position.distance_to(click_pos)>ARRIVE:
		var direction := global_position.direction_to(click_pos)
		velocity = direction * SPEED
		step_timer += delta
		if step_timer >= STEP_SECONDS:
			step_timer = 0.0
			skin.frame = WALK_FRAME if skin.frame == IDLE_FRAME else IDLE_FRAME
		if absf(direction.x)>0.1:
			body.scale.x = 1 if direction.x > 0 else -1
	else:
		moving = false
		velocity = Vector2.ZERO
		skin.frame = IDLE_FRAME
		step_timer = 0.0
	move_and_slide()
	# Blocked by walls before reaching the target
	if moving and get_slide_collision_count()>0 and get_real_velocity().length() <5.0:
		moving = false


# Draws a saved character (e.g. Session.character); JSON numbers arrive as floats, so int() converts them, and missing keys fall back to 0.
func _apply_character(character: Dictionary) -> void:
	change_skin(int(character.get("skin", 0)))
	change_hair(int(character.get("hair", 0)))
	change_eyes(int(character.get("eyes", 0)))
	# Next checkpoint: once the Top and Bottom Sprite2D nodes exist (and their @onready lines above are uncommented),
	# add matching handlers for them and call them here with character.get("top", 0) and character.get("bottom", 0).

# Shows the chosen skin tone by swapping the skin texture.
func change_skin(id: int) -> void:
	skin.texture = CharacterPresets.get_texture(CharacterPresets.SKIN, id)

# Shows the chosen hairstyle by swapping the hair texture.
func change_hair(id:int) -> void:
	hair.texture = CharacterPresets.get_texture(CharacterPresets.HAIR, id)

# Shows the chosen eyes by swapping the eye texture.
func change_eyes(id: int) -> void:
	eye.texture = CharacterPresets.get_texture(CharacterPresets.EYES, id)

# Shows a player's name under their character; the map passes Session.username for the local player.
func set_username(username: String) -> void:
	$LabelUsername.text = username
