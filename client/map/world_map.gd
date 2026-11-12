extends Room

# The campus map. Walking, other players, chat and the HUD come from Room (client/room/room.gd); this file only says
# where the map's edges are, where you appear, and that the HUD's room button goes to your dorm.
#
# Server side (world.ts): join_world {x, y} puts you in the "map" room; world_state / player_* as in room.gd.

# Where the player can walk: the 1920x1080 screen minus a margin, so the character (head above, name tag below) is
# never cut off at the edge. Must match MAP_BOUNDS in server/src/world.ts.
const EDGE_MARGIN_SIDE := 60.0
const EDGE_MARGIN_TOP := 130.0
const EDGE_MARGIN_BOTTOM := 100.0
const PLAY_AREA := Rect2(EDGE_MARGIN_SIDE, EDGE_MARGIN_TOP, 1920.0 - 2 * EDGE_MARGIN_SIDE, 1080.0 - EDGE_MARGIN_TOP - EDGE_MARGIN_BOTTOM)
# You appear at a random spot along the bottom path.
const SPAWN_MIN_X := 800.0
const SPAWN_MAX_X := 1120.0
const SPAWN_Y := 900.0


# Puts you at a random spot on the bottom path and tells the server you're on the map (it answers with world_state).
func _join_room() -> void:
	local_player.global_position = Vector2(randf_range(SPAWN_MIN_X, SPAWN_MAX_X), SPAWN_Y)
	local_player.move_to(local_player.global_position)
	Network.send({"type": "join_world", "x": local_player.global_position.x, "y": local_player.global_position.y})


# The map's walkable area (Room clamps clicks and key walks into it).
func _play_area() -> Rect2:
	return PLAY_AREA


# The HUD's "My Dorm" button opens your own dorm (connected in world_map.tscn).
func _on_hud_place_pressed() -> void:
	Session.go_to_dorm()
