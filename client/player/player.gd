extends CharacterBody2D

# True only for this client's own player (set by world_map.gd); other players' copies leave it false.
@export var is_local := false

@export var SPEED := 300.0
@onready var body := $Skeleton
@onready var skin := $Skeleton/Skin
@onready var hair := $Skeleton/Hair
@onready var eye := $Skeleton/Eye
#@onready var top := $Skeleton/Top
#@onready var bottom := $Skeleton/Bottom

var click_pos := Vector2.ZERO
var moving := false
var step_timer := 0.0
const IDLE_FRAME := 0
const WALK_FRAME := 1
const STEP_SECONDS := 0.1
const ARRIVE := 4		#close enough to target (prevent lagging)

# Chat bubble text size; big because the whole Player is scaled to 0.345 (40 shows as ~14 px).
const BUBBLE_FONT_SIZE := 40
# Widest the bubble text gets before wrapping (before the 0.345 scale: 400 is about 138 px on screen).
const BUBBLE_MAX_TEXT_WIDTH := 400.0

# Starts with the target on the player, so nothing moves until move_to() is called.
func _ready():
	click_pos = global_position

# Sets where this player should walk to (a point in world coordinates, e.g. a mouse click).
func move_to(click: Vector2)->void:
	click_pos = click
	moving = true
const MAX_BUBBLES := 5
const BUBBLE_WAIT := 3.0
const BUBBLE_FADE := 0.5

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

# Shows a bubble text above player head
# New bubbles stack, and each fades out after a few seconds
func show_chat_bubble(text: String)->void:
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # only as wide as its text, centered over the head
		
	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color("d7d9daa6")
	bubble_style.set_corner_radius_all(30)
	bubble_style.set_content_margin_all(16)
	bubble.add_theme_stylebox_override(
		"panel",
		bubble_style
	)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.BLACK)
	# Width of the text on one line, capped at the max: short text -> small bubble, long text wraps at the max.
	var text_width := label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT_SIZE).x
	label.custom_minimum_size.x = minf(ceilf(text_width), BUBBLE_MAX_TEXT_WIDTH)
	
	bubble.add_child(label)
	$Bubbles.add_child(bubble)
	while $Bubbles.get_child_count() > MAX_BUBBLES:
		$Bubbles.get_child(0).free()
	var tween := bubble.create_tween()
	tween.tween_interval(BUBBLE_WAIT)
	tween.tween_property(bubble, "modulate:a", 0.0, BUBBLE_FADE)
	tween.tween_callback(bubble.queue_free)
	
