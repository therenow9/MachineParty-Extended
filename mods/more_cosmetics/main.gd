extends Node

# More Cosmetics: new hats, glasses and suit colors for every character.
#
# No game scripts are overridden; Overtime replaces the assigner, the online
# customization screen and the lobby controls at their own paths. Our items are
# added as nodes beside the vanilla ones, which the game finds by name
# (models.gd), and our suit colors are painted over the blue fallback the game
# gives any name it doesn't know: on the body (suit_sync.gd), the first-person
# hands (hands_sync.gd) and the collar race's cut-off legs (legs.gd). The local
# lobby steps onto ours after vanilla's (lobby_stepper.gd), and the online
# screen redoes the presses the game mishandles for ours (online_picker.gd).
# A player without the mod sees that fallback: no hat, no glasses, a blue suit.

const MOD_ID := "more_cosmetics"
const ASSIGNER_PATH := "res://scripts/components/character customization/customization_assigner.gd"
const HAT_GIB_PATH := "res://modules/prop_manager/scripts/hat_gib_prop.gd"
const TILE_PATH := "res://scripts/components/character customization/customization_selection_instance.gd"
const HANDS_PATHS := [
	"res://minigames/chisel_gauntlet_multiplayer/components/player/scripts/chisel_gauntlet_player.gd",
	"res://minigames/duck_hunt/components/hunter_player/scripts/hunter_player.gd",
]
const COLLAR_PLAYER_PATH := "res://minigames/exploding_collar_race/components/player/scripts/exploding_collar_race_player.gd"
const LEGS_PATH := "res://minigames/exploding_collar_race/components/legs cut off/customization_assigner_legs.gd"
const CONTROLS_PATH := "res://scenes/local_lobby/scripts/local_lobby_player_controls.gd"
const SELECTION_PATH := "res://scripts/components/character customization/customization_selection.gd"
const SYNC_NAME := "XcSuitSync"
const HANDS_SYNC_NAME := "XcHandsSync"
const STEPPER_NAME := "XcLobbyStepper"
const PICKER_NAME := "XcOnlinePicker"

var catalog
var models
var recolor
var legs
var _sync_script: GDScript
var _hands_script: GDScript
var _stepper_script: GDScript
var _picker_script: GDScript
var _tween_checked := false
var _note: Callable

func _mod_init(loader) -> void:
	if not loader.has_api("on_scene_script"):
		loader.note("more_cosmetics: needs mod loader v3+ (on_scene_script), disabled")
		return
	# Hosted in Extended's bundle, the folder comes as meta: dir_of() knows only top-level mods.
	var dir: String = get_meta("mpml_dir") if has_meta("mpml_dir") else loader.dir_of(MOD_ID)
	var scripts := {}
	for file in ["catalog.gd", "models.gd", "suit_recolor.gd", "suit_sync.gd", "hands_sync.gd", "legs.gd", "lobby_stepper.gd", "online_picker.gd"]:
		scripts[file] = loader.compile(dir.path_join(file))
		if scripts[file] == null:
			loader.note("more_cosmetics: failed to load, cosmetics left unchanged")
			return
	catalog = scripts["catalog.gd"].new()
	models = scripts["models.gd"].new()
	models.catalog = catalog
	models.items_dir = dir.path_join("items")
	models.note = loader.note
	recolor = scripts["suit_recolor.gd"].new()
	_sync_script = scripts["suit_sync.gd"]
	_hands_script = scripts["hands_sync.gd"]
	_stepper_script = scripts["lobby_stepper.gd"]
	_picker_script = scripts["online_picker.gd"]
	_note = loader.note
	legs = scripts["legs.gd"].new()
	legs.recolor = recolor
	legs.colors = catalog.COLORS

	# For other mods' pickers: our glasses, and the hats that block glasses.
	var reg: Dictionary = loader.registry(MOD_ID)
	reg["glasses"] = catalog.GLASSES
	reg["no_glasses_hats"] = catalog.NO_GLASSES_HATS
	reg["api"] = self

	loader.on_scene_script(ASSIGNER_PATH, _on_assigner)
	loader.on_scene_script(HAT_GIB_PATH, models.inject_gib)
	loader.on_scene_script(TILE_PATH, models.inject_tile)
	for path in HANDS_PATHS:
		loader.on_scene_script(path, _on_hands_player)
	loader.on_scene_script(COLLAR_PLAYER_PATH, legs.on_player)
	loader.on_scene_script(LEGS_PATH, legs.on_legs)
	loader.on_scene_script(CONTROLS_PATH, _on_controls)
	loader.on_scene_script(SELECTION_PATH, _on_selection)
	loader.note("more_cosmetics: %d hats, %d glasses, %d suit colors" % [catalog.HATS.size(), catalog.GLASSES.size(), catalog.COLORS.size()])

func _on_assigner(assigner: Node) -> void:
	models.inject_assigner(assigner)
	# A duplicate()d slot brings our helper along without its script variables.
	var sync := assigner.get_node_or_null(SYNC_NAME)
	if sync == null:
		sync = _sync_script.new()
		sync.name = SYNC_NAME
		assigner.add_child(sync)
	sync.recolor = recolor
	sync.colors = catalog.COLORS

func _on_hands_player(player: Node) -> void:
	var sync := player.get_node_or_null(HANDS_SYNC_NAME)
	if sync == null:
		sync = _hands_script.new()
		sync.name = HANDS_SYNC_NAME
		player.add_child(sync)
	sync.recolor = recolor
	sync.colors = catalog.COLORS

func _on_controls(controls: Node) -> void:
	if not _tween_checked:
		_tween_checked = true
		if not "tween_buttons" in controls:
			_note.call("more_cosmetics: lobby controls have no tween_buttons; new items can't be picked in the local lobby")
	# Added now, not deferred, so it runs before Better Couch Lobby's glasses picker sees the hat.
	var stepper := controls.get_node_or_null(STEPPER_NAME)
	if stepper == null:
		stepper = _stepper_script.new()
		stepper.name = STEPPER_NAME
		controls.add_child(stepper)
	stepper.hats = catalog.HATS
	stepper.colors = catalog.COLORS.keys()

func _on_selection(selection: Node) -> void:
	var picker := selection.get_node_or_null(PICKER_NAME)
	if picker == null:
		picker = _picker_script.new()
		picker.name = PICKER_NAME
		selection.add_child(picker)
	picker.hats = catalog.HATS
	picker.glasses = catalog.GLASSES
	picker.no_glasses_hats = catalog.NO_GLASSES_HATS
	picker.colors = catalog.COLORS
	picker.note = _note
