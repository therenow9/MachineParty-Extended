extends Node

# Child of a CustomizationAssigner. The assigner paints any color name it
# doesn't know with its blue texture; when its color is one of ours, this puts
# the recolored texture on instead. A high process_priority runs it after the
# game's nodes, so an assign made earlier in the frame is fixed before drawing.

var recolor
var colors: Dictionary

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000

func _process(_delta: float) -> void:
	var assigner := get_parent()
	var id: String = assigner.assigned_suit_color
	if not colors.has(id):
		return
	var mat: BaseMaterial3D = assigner.character_material
	if mat == null:
		return
	var tex: Texture2D = recolor.texture_for(assigner, id, colors[id])
	if tex != null and mat.albedo_texture != tex:
		mat.albedo_texture = tex
