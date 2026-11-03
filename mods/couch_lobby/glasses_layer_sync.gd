extends Node

# Child of a CustomizationAssigner during local games. Keeps the glasses on the
# same render layers as the hat.
#
# Split-screen first-person minigames (Chisel Gauntlet) hide a player's own
# head from their camera with CustomizationAssigner.set_visibility_layer(),
# which only moves hat meshes. Vanilla never had local glasses, so the glasses
# stayed on the default layer and floated in front of the player's own camera.

var assigner: Node
var _applied_layers := -1

func _ready() -> void:
	assigner = get_parent()

func _process(_delta: float) -> void:
	var layers := _hat_layers()
	if layers < 0 or layers == _applied_layers:
		return
	for mesh in assigner.bone_attachment_glasses.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = layers
	_applied_layers = layers

# Same traversal as set_visibility_layer(): bone_attachment_hat/<hat>/<mesh>.
func _hat_layers() -> int:
	for hat_parent in assigner.bone_attachment_hat.get_children():
		for hat_mesh in hat_parent.get_children():
			if hat_mesh is MeshInstance3D:
				return hat_mesh.layers
	return -1
