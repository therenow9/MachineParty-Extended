extends Node

# Child of a LocalLobbyPlayerControls panel. The game steps only through the
# panel's const lists, so right after the panel's _process (tree order) this
# swaps the game's pick for its neighbour in that list followed by ours, before
# anything reads or renders it.

const HAT_UNKNOWN_INDEX := 0
const COLOR_UNKNOWN_INDEX := -1

# Set by main.gd on every hook call: a duplicate()d panel brings this node
# along without its variables.
var hats: Array = []
var colors: Array = []

var _set_up := false
var _tween = null
var _hat := ""
var _color := ""

func _process(_delta: float) -> void:
	var controls := get_parent()
	var assigner = controls.get("customization_assigner")
	if assigner == null:
		_set_up = false
		return
	var hat := str(assigner.get_assigned_hat())
	var color := str(assigner.assigned_suit_color)
	# Only change_hat/change_color write tween_buttons, always as a new Tween. The
	# value before a step is last frame's: assign and step in one frame read as one step.
	var tween = controls.get("tween_buttons")
	if _set_up and tween != null and tween != _tween:
		var lists: Dictionary = controls.get_script().get_script_constant_map()
		if hat != _hat and lists.has("hats"):
			var ours := hats.filter(func(id): return assigner.bone_attachment_hat.has_node(NodePath(id)))
			var new_hat := remap_step(lists["hats"], ours, HAT_UNKNOWN_INDEX, _hat, hat)
			if new_hat != hat:
				assigner.assign_hat(new_hat)
				hat = str(assigner.get_assigned_hat())
		if color != _color and lists.has("suit_colors"):
			var new_color := remap_step(lists["suit_colors"], colors, COLOR_UNKNOWN_INDEX, _color, color)
			if new_color != color:
				assigner.assign_suit_color(new_color)
				color = str(assigner.assigned_suit_color)
	_set_up = true
	_tween = tween
	_hat = hat
	_color = color

# The game's step: an unknown current item counts as `unknown_index`.
static func game_step(list: Array, current: String, dir: int, unknown_index: int) -> String:
	if list.is_empty():
		return current
	var i := list.find(current)
	if i < 0:
		i = unknown_index
	return str(list[wrapi(i + dir, 0, list.size())])

static func extended(list: Array, ours: Array) -> Array:
	return list + ours.filter(func(id): return not list.has(id))

# What the step from `before` that the game turned into `after` should give in
# the extended list. Anything that is not exactly one game step is left alone.
static func remap_step(list: Array, ours: Array, unknown_index: int, before: String, after: String) -> String:
	if before == after or list.is_empty():
		return after
	var ext := extended(list, ours)
	var at := ext.find(before)
	if at < 0:
		return after
	var dirs := [-1, 1].filter(func(d): return game_step(list, before, d, unknown_index) == after)
	if dirs.size() != 1:
		return after
	return str(ext[wrapi(at + dirs[0], 0, ext.size())])
