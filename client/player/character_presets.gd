class_name CharacterPresets
extends Node

# The one shared list of character options, used by both the customizer and player.gd.
# The saved number for each part is the option's ID = its position in these arrays.
# Rules:
#   - Only ADD new options at the end. Never reorder or delete, or every saved character changes look.
#   - The server's SKIN_COUNT / HAIR_COUNT / EYES_COUNT in server/src/auth.ts must equal SKIN.size(),
#     HAIR.size() and EYES.size() (4, 6, 5).

# TODO: art - all four shades are now the same size (good), but 451 is odd: hframes = 2 splits it into two
# 225.5 px poses, so each pose is cut mid-pixel and can look blurry or show a thin line from the other pose
# (the customizer preview's get_width()/2 also rounds down to 225). Re-export at an EVEN width, e.g. 452x451.
# Skins size: 451x451
const SKIN := [ # 2 frames each: walk + idle
	preload("res://client/assets/skin/shade0.png"),
	preload("res://client/assets/skin/shade1.png"),
	preload("res://client/assets/skin/shade2.png"),
	preload("res://client/assets/skin/shade3.png"),
  ]
const HAIR := [
	preload("res://client/assets/hair/hair1.png"),
	preload("res://client/assets/hair/hair2.png"),
	preload("res://client/assets/hair/hair3.png"),
	preload("res://client/assets/hair/hair4.png"),
	preload("res://client/assets/hair/hair5.png"),
	preload("res://client/assets/hair/hair6.png"),
]

const EYES  := [
	preload("res://client/assets/eyes/eye1.png"),
	preload("res://client/assets/eyes/eye2.png"),
	preload("res://client/assets/eyes/eye3.png"),
	preload("res://client/assets/eyes/eye4.png"),
	preload("res://client/assets/eyes/eye5.png"),
]

# Returns the texture for a part and ID, or the ID 0 texture if the ID is out of range, so the player never shows up blank.
static func get_texture(list: Array, id: int) -> Texture2D:
	if id <0 or id > list.size()-1:
		return list[0]
	return list[id]
