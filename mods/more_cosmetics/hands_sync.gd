extends Node

# Child of a Chisel Gauntlet or Duck Hunt player. Their set_player_presence
# paints the first-person hands with assigner.get_suit_texture(color), the blue
# fallback for our colors, as a surface override; this swaps in our recolor.
# The color comes from player_presence because the hunter never assigns it.

var recolor
var colors: Dictionary

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000

func _process(_delta: float) -> void:
	var player := get_parent()
	var presence = player.player_presence
	if presence == null or presence.customization.size() < 3:
		return
	var id = presence.customization[2]
	if not colors.has(id):
		return
	var assigner = player.customization_assigner
	if assigner == null:
		return
	for hm in player.hand_meshes:
		# No override means the game hasn't painted these hands (a remote
		# player); the mesh's own material is shared by every player.
		var mat: BaseMaterial3D = (hm.get_surface_override_material(0) as BaseMaterial3D) if hm != null else null
		if mat == null:
			continue
		var tex: Texture2D = recolor.texture_for(assigner, id, colors[id])
		if tex != null and mat.albedo_texture != tex:
			mat.albedo_texture = tex
