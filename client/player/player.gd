extends CharacterBody2D

@export var SPEED := 300.0
@onready var body := $Skeleton

@onready var skin := $Skeleton/Skin
@onready var hair := $Skeleton/Hair
@onready var eye := $Skeleton/Eye

func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()


# The customizer sends frame numbers; the textures stay as the sprite sheets.
func _on_CharacterCustomizer_skin_changed(frame: int) -> void:
	skin.frame = frame

func _on_CharacterCustomizer_hair_changed(frame: int) -> void:
	hair.frame = frame

func _on_CharacterCustomizer_eye_changed(frame: int) -> void:
	eye.frame = frame
