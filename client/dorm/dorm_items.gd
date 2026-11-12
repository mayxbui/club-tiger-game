class_name DormItems
extends RefCounted

# The pictures for dorm items, looked up by the catalog's sprite_key (server/sql/schema.sql seeds item_catalog with
# the same keys). To add an item: drop its PNG in client/assets/dorm/, add a line here, and add a row to the seed.

const SPRITES := {
	"bookshelf": preload("res://client/assets/dorm/bookshelf.png"),
	"ukulele": preload("res://client/assets/dorm/guitar.png"),
	"photo-hanger": preload("res://client/assets/dorm/photo-hanger.png"),
	"string_lights": preload("res://client/assets/dorm/photo-hanger.png"),
	"wardrobe": preload("res://client/assets/dorm/wardrobe.png"),
	"drawers": preload("res://client/assets/dorm/drawers.png"),
	"teddy_bear": preload("res://client/assets/dorm/bear.png"),
	"blanket": preload("res://client/assets/dorm/blanket.png"),
	"pillow": preload("res://client/assets/dorm/pillow.png"),
	"cat_photo": preload("res://client/assets/dorm/cat-photo.png"),
	"night_sky_polaroid": preload("res://client/assets/dorm/night-sky-polaroid.png"),
	"sheep_photo": preload("res://client/assets/dorm/sheep-photo.png"),
}

# Cropped previews already made: sprite_key -> Texture2D (cropping reads the image, so it's done once per item).
static var _previews := {}
static var _placeholder: Texture2D


# Returns the full picture for an item, or a grey square if the key has no picture yet (so the room never breaks).
static func texture(key: String) -> Texture2D:
	if SPRITES.has(key):
		return SPRITES[key]
	if _placeholder == null:
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.6, 0.6, 0.6, 0.8))
		_placeholder = ImageTexture.create_from_image(image)
	return _placeholder


# Returns the item's picture cropped to its visible pixels, for the belt's boxes. Several PNGs have a lot of empty
# canvas around the drawing (the pillow is small inside 512x256), so without this the preview would be tiny.
static func preview(key: String) -> Texture2D:
	if _previews.has(key):
		return _previews[key]
	var full := texture(key)
	var result: Texture2D = full
	var image := full.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0 and used.size != image.get_size():
			var atlas := AtlasTexture.new()
			atlas.atlas = full
			atlas.region = Rect2(used)
			result = atlas
	_previews[key] = result
	return result
