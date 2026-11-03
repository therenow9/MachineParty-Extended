extends RefCounted

# Exploding Collar Race leaves a pair of cut-off legs where a player loses
# their first life. spawn_legs hands the legs only the color name, which they
# don't keep, and paints any name it doesn't know blue; so blue legs are
# repainted with the color of the player standing where they were spawned.

const GROUP := &"xc_collar_race_players"
const MATCH_DISTANCE := 0.5

var recolor
var colors: Dictionary

func on_player(player: Node) -> void:
	player.add_to_group(GROUP)

# spawn_legs adds the legs first and places and colors them afterwards, in the
# same call; deferred calls run before the frame is drawn.
func on_legs(legs: Node) -> void:
	paint.call_deferred(legs)

func paint(legs: Node) -> void:
	if not is_instance_valid(legs) or not legs.is_inside_tree():
		return
	var mat: BaseMaterial3D = legs.character_material
	var root := legs.get_parent() as Node3D
	if mat == null or root == null or mat.albedo_texture != legs.suit_texture_blue:
		return
	var players: Array = legs.get_tree().get_nodes_in_group(GROUP)
	# The nearest of any color, so true blue legs stay blue beside our colors.
	var i := nearest(players.map(func(p): return p.global_position), root.global_position, MATCH_DISTANCE)
	if i < 0 or players[i].customization_assigner == null:
		return
	var id: String = players[i].customization_assigner.assigned_suit_color
	if not colors.has(id):
		return
	var tex: Texture2D = recolor.texture_for_pair(legs.suit_texture_red, legs.suit_texture_blue, id, colors[id])
	if tex != null:
		mat.albedo_texture = tex

# Index of the position nearest to `at` within max_distance, or -1.
static func nearest(positions: Array, at: Vector3, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance
	for i in positions.size():
		var d: float = at.distance_to(positions[i])
		if d <= best_d:
			best = i
			best_d = d
	return best
