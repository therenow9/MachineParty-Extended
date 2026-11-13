extends Node

# The local lobby's panels are the hook for both the close-ups and the glasses row:
# Offline Bots replaces local_lobby.gd with a subclass, and replacing the panel script
# would fail the lobby's Array[LocalLobbyPlayerControls] check and leave it empty.
# Glasses are recorded by input device in registry(MOD_ID)["glasses"].

const MOD_ID := "couch_lobby"
const CONTROLS_PATH := "res://scenes/local_lobby/scripts/local_lobby_player_controls.gd"
const LOCAL_GAME_PATH := "res://scenes/local_game/script/local_game.gd"
const ASSIGNER_PATH := "res://scripts/components/character customization/customization_assigner.gd"
const CLOSE_UPS_NAME := "CouchLobbyCloseUps"
const BUTTONS_NAME := "CouchLobbyButtons"
const SEAT_ORDER_META := &"couch_lobby_seat_order"
# GameCube Controller Support publishes the pad that owns the menus here.
const GCS_ID := "gamecube_support"
# Another mod's glasses join the row when it publishes them here; read when a
# picker is attached, by which time every mod's _mod_init has run.
const COSMETICS_ID := "more_cosmetics"
# A leftover Local Glasses install would add a second glasses row to every panel.
const RETIRED_ID := "local_glasses"
const NAMES_PATH := "user://couch_lobby.json"
# The saved names' page sits under the main menu's Options, the only settings menu a mod can reach.
const MAIN_MENU_PATH := "res://scenes/main_menu/scripts/main_menu.gd"
const OPTIONS_NAME := "CouchLobbySavedNames"

var _loader
var _close_ups_script: GDScript
var _buttons_script: GDScript
var _picker_script: GDScript
var _layer_sync_script: GDScript
var _name_panel_script: GDScript
var _options_script: GDScript
var _names
var _pencil: Texture2D
var _icon_path: String
var _glasses_by_device: Dictionary
var _extra_noted := false

func _mod_init(loader) -> void:
	_loader = loader
	if not loader.has_api("on_scene_script"):
		loader.note("couch_lobby: needs mod loader v3+ (on_scene_script), disabled")
		return
	# Hosted in Extended's bundle, the folder comes as meta: dir_of() knows only top-level mods.
	var hosted := has_meta("mpml_dir")
	var dir: String = get_meta("mpml_dir") if hosted else loader.dir_of(MOD_ID)
	var reg: Dictionary = loader.registry(MOD_ID)
	if not reg.has("glasses"):
		reg["glasses"] = {}
	_glasses_by_device = reg["glasses"]

	_close_ups_script = loader.compile(dir.path_join("close_ups.gd"))
	if _close_ups_script == null:
		loader.note("couch_lobby: close_ups.gd failed to load; close-ups off")
	_buttons_script = loader.compile(dir.path_join("lobby_buttons.gd"))
	if _buttons_script == null:
		loader.note("couch_lobby: lobby_buttons.gd failed to load; the lobby's buttons take any pad's A")
	_load_names(dir, reg)
	var mods_dir := dir.get_base_dir().get_base_dir() if hosted else dir.get_base_dir()
	var retired := installed_folder(mods_dir, RETIRED_ID)
	if not retired.is_empty():
		loader.note("couch_lobby: mods/%s (Local Glasses) adds its own glasses row; remove it, Better Couch Lobby replaces it. Glasses row left to it" % retired)
	else:
		_icon_path = dir.path_join("glasses_selection.png")
		_picker_script = loader.compile(dir.path_join("glasses_picker.gd"))
		_layer_sync_script = loader.compile(dir.path_join("glasses_layer_sync.gd"))
		if _picker_script == null or _layer_sync_script == null:
			loader.note("couch_lobby: the glasses scripts failed to load; glasses row off")
			_picker_script = null
			_layer_sync_script = null

	loader.on_scene_script(CONTROLS_PATH, _on_controls)
	if _options_script:
		loader.on_scene_script(MAIN_MENU_PATH, _attach_options)
	if _picker_script:
		loader.on_scene_script(LOCAL_GAME_PATH, _apply_to_presences)
		loader.on_scene_script(ASSIGNER_PATH, _attach_layer_sync)
	loader.note("couch_lobby: close-ups %s, glasses row %s, lobby buttons %s, saved names %s" % ["on" if _close_ups_script else "off", "on" if _picker_script else "off", "host only" if _buttons_script else "off", "on" if _name_panel_script else "off"])

# The saved names are shared by every seat: registry(MOD_ID)["names"] holds the store.
func _load_names(dir: String, reg: Dictionary) -> void:
	var tags: GDScript = _loader.compile(dir.path_join("name_tags.gd"))
	_name_panel_script = _loader.compile(dir.path_join("name_panel.gd"))
	if tags == null or _name_panel_script == null:
		_loader.note("couch_lobby: the name scripts failed to load; saved names, 7-letter names and back to LEAVE in an empty lobby off")
		_name_panel_script = null
		return
	_names = tags.new()
	_options_script = _loader.compile(dir.path_join("names_options.gd"))
	if _options_script == null:
		_loader.note("couch_lobby: names_options.gd failed to load; no Saved names page in Options")
	var image := Image.load_from_file(dir.path_join("name_new.png"))
	_pencil = ImageTexture.create_from_image(image) if image else null
	if _pencil == null:
		_loader.note("couch_lobby: name_new.png failed to load; the saved names' pencil row shows no icon")
	if not _names.load_from(NAMES_PATH):
		_loader.note("couch_lobby: %s could not be read, or has repeats, entries that are not 1-%d letters A-Z, or more than %d; those are ignored, and the file is kept as %s.bad when the list next changes" % [NAMES_PATH, tags.MAX_LETTERS, tags.CAP, NAMES_PATH.get_file()])
	reg["names"] = _names

func _on_controls(controls: Node) -> void:
	# Runs while the scene is entering the tree; wait until it has finished.
	if _close_ups_script:
		_attach_close_ups.call_deferred(controls)
	if _buttons_script:
		_attach_buttons.call_deferred(controls)
	if _picker_script:
		_attach_picker(controls)
	if _name_panel_script:
		_attach_name_panel(controls)
	_attach_seat_order.call_deferred(controls)

# The lobby's own script may be another mod's subclass, so the panels are the
# hook, and whichever panel gets there first adds the lobby's one node.
static func lobby_of(controls: Node) -> Node:
	var lobby := controls.get_parent()
	while lobby != null and not ("local_lobby_player_controls" in lobby and "players_node" in lobby):
		lobby = lobby.get_parent()
	return lobby

func _attach_close_ups(controls: Node) -> void:
	var lobby := lobby_of(controls)
	if lobby == null or lobby.get_node_or_null(CLOSE_UPS_NAME) != null:
		return
	var close_ups: Node = _close_ups_script.new()
	close_ups.name = CLOSE_UPS_NAME
	close_ups.note = _loader.note
	lobby.add_child(close_ups)

func _attach_buttons(controls: Node) -> void:
	var lobby := lobby_of(controls)
	if lobby == null or lobby.get_node_or_null(BUTTONS_NAME) != null:
		return
	var buttons: Node = _buttons_script.new()
	buttons.name = BUTTONS_NAME
	buttons.lobby = lobby
	buttons.menu_pad = func(): return int(_loader.registry(GCS_ID).get("menu_pad", -1))
	buttons.names_script = _name_panel_script
	buttons.registry = _loader.registry
	lobby.add_child(buttons)

# The game builds its players from player_data in insertion order (update_player_manager,
# Offline Bots' too), and the minigames seat and list them in that order, so a player who
# left seat 0 and joined it again would play last. Kept every frame, not on player_joined:
# Offline Bots' add_bot fills a seat without that signal.
func _attach_seat_order(controls: Node) -> void:
	var lobby := lobby_of(controls)
	if lobby == null or lobby.has_meta(SEAT_ORDER_META) or not "player_data" in lobby:
		return
	lobby.set_meta(SEAT_ORDER_META, true)
	var tree := lobby.get_tree()
	var keep := func(): in_seat_order(lobby.player_data)
	tree.process_frame.connect(keep)
	lobby.tree_exiting.connect(func(): tree.process_frame.disconnect(keep), CONNECT_ONE_SHOT)

static func in_seat_order(seats: Dictionary) -> void:
	var keys := seats.keys()
	keys.sort()
	if keys == seats.keys():
		return
	var by_seat := seats.duplicate()
	seats.clear()
	for k in keys:
		seats[k] = by_seat[k]

func _attach_picker(controls: Node) -> void:
	var picker: Node = _picker_script.new()
	picker.name = "CouchLobbyGlassesPicker"
	picker.icon_path = _icon_path
	picker.glasses_by_device = _glasses_by_device
	var extra: Dictionary = _loader.registry(COSMETICS_ID)
	var glasses: Dictionary = _picker_script.merged(_picker_script.GLASSES, extra.get("glasses"))
	var blocking: Dictionary = _picker_script.merged(_picker_script.NO_GLASSES_HATS, extra.get("no_glasses_hats"))
	picker.glasses = glasses["list"]
	picker.no_glasses_hats = blocking["list"]
	if not (glasses["ok"] and blocking["ok"]) and not _extra_noted:
		_extra_noted = true
		_loader.note("couch_lobby: ignored malformed entries in %s's glasses lists" % COSMETICS_ID)
	controls.add_child.call_deferred(picker)

func _attach_name_panel(controls: Node) -> void:
	var panel: Node = _name_panel_script.new()
	panel.name = "CouchLobbyNamePanel"
	panel.store = _names
	panel.pencil = _pencil
	panel.note = _loader.note
	panel.registry = _loader.registry
	controls.add_child.call_deferred(panel)

func _attach_options(menu: Node) -> void:
	if menu.get_node_or_null(OPTIONS_NAME) != null:
		return
	var page: Node = _options_script.new()
	page.name = OPTIONS_NAME
	page.store = _names
	menu.add_child.call_deferred(page)

# The lobby has already built the presences by the time the local game scene
# enters the tree; minigames read them later.
func _apply_to_presences(_local_game: Node) -> void:
	for presence in PlayerManager.player_presences.values():
		if presence == null or not presence.local or presence.customization.size() < 2:
			continue
		if _glasses_by_device.has(presence.device_id):
			presence.customization[1] = _glasses_by_device[presence.device_id]

# The loader starts mods by priority, then id, so has_mod() misses one that starts
# after this one; the mods folder is read instead (8 Player Support does the same).
static func installed_folder(mods_dir: String, id: String) -> String:
	for sub in DirAccess.get_directories_at(mods_dir):
		if sub.begins_with("."):
			continue
		var path := mods_dir.path_join(sub).path_join("mod.json")
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("id", sub)) == id:
			return sub
	return ""

func _attach_layer_sync(assigner: Node) -> void:
	if not _loader.is_local_couch():
		return
	var sync: Node = _layer_sync_script.new()
	sync.name = "CouchLobbyGlassesLayerSync"
	assigner.add_child.call_deferred(sync)
