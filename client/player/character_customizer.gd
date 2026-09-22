extends Control

# Each signal carries the frame index on the player's sprite sheet (0-based).
signal skin_changed(frame: int)
signal hair_changed(frame: int)
signal eyes_changed(frame: int)

# "preview" is the standalone image shown in the selector.
# "frame" is that same look's frame on the sprite sheet: file N -> frame N - 1.
const PRESETS := {
	"skin": [
		{"preview": preload("res://client/assets/skin/skin1.png"), "frame": 1},
		{"preview": preload("res://client/assets/skin/skin3.png"), "frame": 2},
		{"preview": preload("res://client/assets/skin/skin7.png"), "frame": 6},
		{"preview": preload("res://client/assets/skin/skin5.png"), "frame": 4},
	],
	"hair": [
		{"preview": preload("res://client/assets/hair/hair6.png"), "frame": 0},
		{"preview": preload("res://client/assets/hair/hair5.png"), "frame": 1},
		{"preview": preload("res://client/assets/hair/hair1.png"), "frame": 2},
		{"preview": preload("res://client/assets/hair/hair4.png"), "frame": 3},
		{"preview": preload("res://client/assets/hair/hair3.png"), "frame": 4},
		{"preview": preload("res://client/assets/hair/hair2.png"), "frame": 5},
	],
	"eyes": [
		{"preview": preload("res://client/assets/eyes/eye5.png"), "frame": 4},
		{"preview": preload("res://client/assets/eyes/eye4.png"), "frame": 3},
		{"preview": preload("res://client/assets/eyes/eye2.png"), "frame": 1},
		{"preview": preload("res://client/assets/eyes/eye3.png"), "frame": 2},
		{"preview": preload("res://client/assets/eyes/eye1.png"), "frame": 0},
	]
}

@onready var selectors := {
	"skin": $Panel/VBoxContainer/SpriteSelector,
	"hair": $Panel/VBoxContainer/SpriteSelector2,
	"eyes": $Panel/VBoxContainer/SpriteSelector3,
}

var selection := {"skin": 0, "hair": 0, "eyes": 0}

func _ready() -> void:
	_initialize_selectors.call_deferred()

func _initialize_selectors() -> void:
	for key in selectors:
		var sprite_selector: SpriteSelector = selectors[key]
		sprite_selector.sprite_changed.connect(_on_sprite_selector_sprite_changed.bind(key))
		var previews := []
		for preset in PRESETS[key]:
			previews.append(preset["preview"])
		sprite_selector.setup(previews)

func _on_sprite_selector_sprite_changed(_texture: Texture2D, index: int, key: String) -> void:
	var frame: int = PRESETS[key][index]["frame"]
	selection[key] = frame
	match key:
		"skin":
			skin_changed.emit(frame)
		"hair":
			hair_changed.emit(frame)
		"eyes":
			eyes_changed.emit(frame)

func get_selection() -> Dictionary:
	return selection.duplicate()
