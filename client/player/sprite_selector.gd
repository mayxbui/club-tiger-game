extends Control
class_name SpriteSelector

signal sprite_changed(texture, index)
var _sprites := []
var _index := 0

@onready var texture_rect: TextureRect = $HBoxContainer/PanelContainer/TextureRect

func setup(sprite_textures: Array) -> void:
	_sprites = sprite_textures
	_set_index(0)

func _set_index(value: int) -> void:
	_index = wrapi(value, 0, _sprites.size())
	var texture: Texture2D = _sprites[_index]
	texture_rect.texture = texture
	sprite_changed.emit(texture, _index)

func _on_btn_prev_pressed() -> void:
	_set_index(_index - 1)

func _on_btn_next_pressed() -> void:
	_set_index(_index + 1)
