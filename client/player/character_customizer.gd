extends Control

# Each signal carries the chosen option's ID (its position in the CharacterPresets lists).
signal skin_changed(id: int)
signal hair_changed(id: int)
signal eyes_changed(id: int)
# TODO: (until next checkpoint) add top and bottom
#      (duplicate SpriteSelector3), add TOPS/BOTTOMS to CharacterPresets, then add them to `selectors`,
#      `selection`, new signals, and connect those signals in create_account.gd like the other three.
var selection := {"skin": 0, "hair": 0, "eyes": 0}
# True once the selectors have their images (set_selection before that just remembers the choice).
var _initialized := false
@onready var selectors := {
	"skin": $VBoxContainer/SpriteSelector,
	"hair": $VBoxContainer/SpriteSelector2,
	"eyes": $VBoxContainer/SpriteSelector3,
}


# Sets up the selectors after the scene finishes loading, so the preview player's signals are already connected.
func _ready() -> void:
	_initialize_selectors.call_deferred()


# Fills each selector with its preview images and connects it; setup() also emits the current selection (option 0
# unless set_selection was called first), so the preview player starts matching what the selectors show.
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
		sprite_selector.setup(previews[i], selection[i])
	_initialized = true


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

# Shows the saved look (e.g. Session.character) on the selectors and emits the change signals, so a preview connected
# to them matches. Used by the player card's edit page; JSON floats converted to int.
func set_selection(character: Dictionary) -> void:
	for key in selection:
		selection[key] = int(character.get(key, 0))
	if _initialized:
		for key in selectors:
			selectors[key].select(selection[key])
