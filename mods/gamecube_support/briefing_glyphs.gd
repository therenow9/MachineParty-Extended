extends Node

# Child of an intermission briefing's control row (IntermissionControlInputLabel).
# The game's data gives The Filter's Burn and Recycle rows one face button each;
# X and Y burn and recycle too for a GameCube player (minigame_controls.gd), so
# "/" and their glyph follow the row's last controller glyph while GameCube
# prompts show.

const EXTRA := {
	"LOC_CONTROL_BURN": "controller_button_west.png",
	"LOC_CONTROL_RECYCLE": "controller_button_north.png",
}
const SEPARATOR := "/"

var api  # gamecube_support's main.gd

var _extra: Array[Control] = []

func _process(_delta: float) -> void:
	var row := get_parent()
	if _extra.is_empty():
		var key = row.get("keyboard_text")
		if not (key is String) or key.is_empty():
			return
		var rects: Array = row.get("controller_texture_rects")
		if not key in EXTRA or rects.is_empty():
			set_process(false)
			return
		_build(row, rects, EXTRA[key])
	var shown: bool = row.controller_texture_rects[0].visible and api.is_showing_gamecube() and api.config["button_layout"] == "nintendo"
	for c in _extra:
		c.visible = shown

# The rect copies the game's own glyph's sizing; the separator copies the row's text label.
func _build(row: Node, rects: Array, rel: String) -> void:
	var last: TextureRect = rects[rects.size() - 1]
	var at := last.get_index() + 1
	var sep: Label = row.get("icon_label").duplicate()
	sep.text = SEPARATOR
	_extra.append(sep)
	var rect := TextureRect.new()
	rect.texture = api.swapper.proxies[rel]
	rect.texture_filter = last.texture_filter
	rect.expand_mode = last.expand_mode
	rect.custom_minimum_size = last.custom_minimum_size
	_extra.append(rect)
	for c in _extra:
		row.add_child(c)
		row.move_child(c, at)
		at += 1
