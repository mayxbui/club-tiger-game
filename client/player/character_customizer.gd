extends Control


# Each signal carries the chosen option's ID (its position in the CharacterPresets lists).
signal skin_changed(id: int)
signal hair_changed(id: int)
signal eyes_changed(id: int)
# TODO: (until next checkpoint) add top and bottom
#      (duplicate SpriteSelector3), add TOPS/BOTTOMS to CharacterPresets, then add them to `selectors`,
#      `selection`, new signals, and connect those signals in create_account.gd like the other three.
var selection := {"skin": 0, "hair": 0, "eyes": 0}
@onready var selectors := {
	"skin": $VBoxContainer/SpriteSelector,
	"hair": $VBoxContainer/SpriteSelector2,
	"eyes": $VBoxContainer/SpriteSelector3,
}


# Sets up the selectors after the scene finishes loading, so the preview player's signals are already connected.
func _ready() -> void:
	_initialize_selectors.call_deferred()


# Fills each selector with its preview images and connects it; setup() also emits option 0, so the player starts matching the first option shown.
# Skin previews show the left half of each shade file (the idle pose, IDLE_FRAME = 0 in player.gd).
func _initialize_selectors() -> void:
	var skin_preview = []
	for skin in CharacterPresets.SKIN:
		var atlas = AtlasTexture.new()
		atlas.atlas = skin
		var half_width = skin.get_width()/2
		atlas.region = Rect2(0, 0, half_width, skin.get_height())
		skin_preview.append(atlas)
	var previews = {
		"skin": skin_preview,
		"hair": CharacterPresets.HAIR,
		"eyes": CharacterPresets.EYES
	}
	for i in selectors:
		var sprite_selector: SpriteSelector = selectors[i]
		sprite_selector.sprite_changed.connect(_on_sprite_selector_sprite_changed.bind(i))
		sprite_selector.setup(previews[i])


# Records the chosen option's ID and emits the matching signal so the preview player updates.
func _on_sprite_selector_sprite_changed(_texture: Texture2D, index: int, key: String) -> void:
	selection[key] = index
	match key:
		"skin": skin_changed.emit(index)
		"hair": hair_changed.emit(index)
		"eyes": eyes_changed.emit(index)

# Returns a copy of the current choices, which create_account.gd sends to the server.
func get_selection() -> Dictionary:
	return selection.duplicate()
