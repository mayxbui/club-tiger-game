extends CharacterBody2D

# Another player's character was left-clicked (only after set_clickable(true); world_map.gd opens the
# other-player card).
signal clicked

# True only for this client's own player (set by world_map.gd); other players' copies leave it false.
@export var is_local := false

@export var SPEED := 300.0
# (player_skeleton.tscn). Body is flipped to face left/right, and Skin's frame swaps for walking.
@onready var skeleton: PlayerSkeleton = $Skeleton
@onready var body: Node2D = $Skeleton/Body
@onready var skin: Sprite2D = $Skeleton/Body/Skin

var click_pos := Vector2.ZERO
var moving := false
var step_timer := 0.0
const IDLE_FRAME := 0
const WALK_FRAME := 1
const STEP_SECONDS := 0.1
const ARRIVE := 4		# close enough to target (prevent lagging)

const BUBBLE_FONT_SIZE := 60
const BUBBLE_MAX_TEXT_WIDTH := 800.0
const BUBBLE_TEXTURE := preload("res://client/player/bubble_chat_texture.tres")

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


# Draws a saved character (e.g. Session.character) with the skeleton (player_skeleton.gd).
func _apply_character(character: Dictionary) -> void:
	skeleton.apply_character(character)

# Shows the chosen skin tone (create_account.gd connects the customizer's signals to these three).
func change_skin(id: int) -> void:
	skeleton.change_skin(id)

# Shows the chosen hairstyle.
func change_hair(id: int) -> void:
	skeleton.change_hair(id)

# Shows the chosen eyes.
func change_eyes(id: int) -> void:
	skeleton.change_eyes(id)

# Shows a player's name under their character; the map passes Session.username for the local player.
func set_username(username: String) -> void:
	$LabelUsername.text = username

# Turns clicking on this character on or off. world_map.gd turns it on for other players only, so clicking your
# own character still walks you there. While on, ClickArea takes the click, so it doesn't also walk you to them.
func set_clickable(on: bool) -> void:
	$ClickArea.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE

# A left click on ClickArea (connected in player.tscn) sends `clicked`.
func _on_click_area_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		$ClickArea.accept_event()
		clicked.emit()

# Shows a bubble text above player head
# New bubbles stack, and each fades out after a few seconds
func show_chat_bubble(text: String)->void:
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # only as wide as its text, centered over the head
		
	bubble.add_theme_stylebox_override(
		"panel",
		BUBBLE_TEXTURE
	)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	
