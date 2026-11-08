extends Control
class_name SpriteSelector

signal sprite_changed(texture, index)
var _sprites := []
var _index := 0

@onready var texture_rect: TextureRect = $HBoxContainer/PanelContainer/TextureRect

# Loads the option images into this selector and shows option start_index (the first one by default).
func setup(sprite_textures: Array, start_index := 0) -> void:
	_sprites = sprite_textures
	_set_index(start_index)

# Shows the option at index and emits sprite_changed, as if the player had clicked the arrows to it.
func select(index: int) -> void:
	_set_index(index)

# Shows the option at `value` (wrapping around at either end) and emits sprite_changed with it.
func _set_index(value: int) -> void:
	_index = wrapi(value, 0, _sprites.size())
	var texture: Texture2D = _sprites[_index]
	texture_rect.texture = texture
	sprite_changed.emit(texture, _index)

# Shows the previous option.
func _on_btn_prev_pressed() -> void:
	_set_index(_index - 1)

# Shows the next option.
func _on_btn_next_pressed() -> void:
	_set_index(_index + 1)
