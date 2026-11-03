extends Node

# Dev-only playtest setup, installed by tools/run_playtest.sh; not a self-test and never ships.
# With the runner's Offline Bots (8 seats, bots keep their split-screen tiles): when a human seat readies up
# in the local lobby, every free seat fills with bots (its BOTS panel can't be driven with a GameCube pad),
# named like lobby players and dressed from everything the lobby offers; a local match plays each custom-game minigame
# once, or only those named in playlist.txt (one Globals.MinigameIdentifier name per line, written by the runner).
# Offline Bots saves its own config when it seats bots; run_playtest.sh and the headless check put back what was there.
#
# Launch mode, only while MP_LAUNCH is set ("minigame=DuckHunt;mode=split|local;bots=1-7", from run_playtest.sh
# launch): main menu to the custom-game lobby; the first seat to join (the owner's A press) is named, readied and
# joined by the bots; one minigame for LAUNCH_ROUNDS rounds, every seat re-dressed by launch_outfits.gd; a frame
# log (frame_log.gd). Back at the main menu, or on a window close, it puts the config back, writes DONE and quits.
# Headless, MP_LAUNCH with ";headless_join=<device>" runs that flow end to end after the checks below,
# the device joining as the A press would: MP_LAUNCH="minigame=DuckHunt;headless_join=100" run_selftest.sh cl_playtest ...
# ";auto=<loads>" runs a launch unattended, windowed too: a fake device (headless_join, default 100) takes the
# owner's seat, readies on each briefing and is played by Offline Bots' AI, and the run ends itself ";grace=<seconds>"
# (default AUTO_GRACE_SEC) after the minigame's Nth load: auto=2;grace=0 is exactly one round, its results included.
# ";stall=<seconds>" (default AUTO_STALL_SEC) is how long without a new load is a stall.
# ";drop=<seconds>" then disconnects that fake pad (the game's own joy_connection_changed) that long into the match.
# ";catches=1" runs Table Manners' forced catches (_check_table_catches) in the first Table Manners load, for a recording.
# ";look=hi" renders 3D at the window's size for the trailer's look test: the root window scales canvas items
# instead of the game's 960x540 viewport, and each SubViewport (the split-screen tiles) is scaled by the same factor.
# Movie Maker keeps the size it started at and records only the top-left corner of that, so with MP_LOOK_STILLS=<dir>
# the root viewport's picture is saved there every LOOK_STILL_FRAMES frames at its real size instead.
# ";difficulty=easy|normal|hard" plays the bots at that level for the launch without saving it (the saved config
# keeps its own); Offline Bots reads the level each frame.
# ";throwtest=1" measures Debris Platforms' throw (_measure_debris_throw) once play starts, headless.
# Every pad connect and disconnect during a launch is logged, with the seat's status where Overtime gives one.
# minigame=CutsceneTest (the wheat field, which only a normal session plays) runs a normal local session instead,
# with the wheat field second, after one round of the first minigame; windowed only. Unattended, the fake seat's
# character is moved to the house AUTO_HOUSE_SEC into the wheat field, so its ending plays.
# With tools/trailer_cast installed (run_playtest.sh launch --shot), every seat takes the trailer's cast in seat
# order (the fake seat is seat 1) for its name and outfit, in the lobby and the match, and that mod walks the field.
# minigame=Lobby (unattended only) holds the custom-game lobby instead of starting: the fake seat joins, unready
# (the lobby counts down and starts once every seat is ready), no bots fill it (their seats have no model in the
# room; trailer_cast joins the cast as pads), and the run ends ";grace" seconds later. minigame=Menu (unattended
# only) holds the main menu the same way, nothing pressed.
# Outside launch mode each local match writes its own frame log (<stamp>_install.csv), with a line per minigame load,
# so a couch match's frame times split by minigame (perf_summary.py).

const MOD_ID := "cl_playtest"
const LOOK_STILL_FRAMES := 30
const BOTS_CONFIG := "user://offline_bots_config.json"
const BOTS_BRAIN := "OfflineBotsBrain"
# Offline Bots' difficulty 0-2.
const BOT_LEVELS := ["easy", "normal", "hard"]
const PLAYLIST_FILE := "playlist.txt"
const LOCAL_GAME := "res://scenes/local_game/local_game.tscn"
const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const HANDLERS := [
	"res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet_local_handler.gd",
	"res://minigames/burn_recycle/scripts/burn_recycle_local_handler.gd",
	"res://minigames/knife_at_the_office/scripts/knife_at_the_office_local_handler.gd",
]
const LAUNCH_ROUNDS := 999
const LAUNCH_MODES := ["split", "local"]
const MAX_BOTS := 7
const PLAYING_STATE := "MinigamePlaying"
const AUTO_DEVICE := 100
const AUTO_GRACE_SEC := 20
# An unattended run with no new load for this long has stalled: it records that and ends.
const AUTO_STALL_SEC := 600
# The minigames whose 8-player layout a launch counts (docs/plans/2026-10-07-8p-variants.md).
const LAYOUT_MINIGAMES := ["EscalatorPit", "ForkliftCertified", "SpineBreaker", "BurnRecycle", "DuckHunt",
	"ChiselGauntlet", "KnifeAtTheOffice", "ManufactureGun", "SmokeBreak", "GreenPea", "JunkPlatform"]
# 8 Player Support plays machine-party-8p's version of these (D68); every other build plays Overtime's.
const MP8_PICKED_8P := ["EscalatorPit", "ForkliftCertified", "KnifeAtTheOffice", "ManufactureGun"]
# Offline Bots' bot devices start here (local_lobby_override.gd BOT_DEVICE_BASE).
const BOT_DEVICE_BASE := 900001
const NORMAL_SESSION_LAUNCHES := ["CutsceneTest"]
const AUTO_HOUSE_SEC := 10
const AUTO_FIELD_SEC := 2
# Within FieldHouseProximity's 30 of the house (22.5, 8.0, -10.2).
const AUTO_HOUSE_SPOT := Vector3(10.0, 0.0, 0.0)

var _loader
var _roller: GDScript
var _outfits: GDScript
var _frame_log_script: GDScript
var _filled_lobby: Node

var _launch: Dictionary = {}
var _launch_id := -1
var _normal_session := false
var _auto_load_usec := 0
var _auto_housed := false
var _auto_field_logged := false
var _phase := ""
var _phase_usec := 0
var _frame_log: Node
var _config_before = null
var _joined_lobby: Node
var _human_step := 0
var _step_frames := 0
var _pools: Dictionary = {}
var _rolled: Dictionary = {}
var _start_facts: Dictionary = {}
var _auto_minigame_id := 0
var _auto_loads := 0
var _auto_done_usec := 0
var _auto_ready_usec := 0
var _auto_dropped := false
var _auto_last_usec := 0
var _auto_bot_state: Dictionary = {}
var _traced_minigame_id := 0
var _catches_running := false
var _install_minigame_id := 0
var _look_still_failed := false
var _lobby_hold := false
var _menu_hold := false

func _mod_ready(loader) -> void:
	_loader = loader
	var dir: String = loader.dir_of(MOD_ID)
	_roller = loader.compile(dir.path_join("outfit_roller.gd"))
	if _roller == null:
		loader.note("cl_playtest: outfit_roller.gd failed to compile; bots keep Offline Bots' outfits")
	_outfits = loader.compile(dir.path_join("launch_outfits.gd"))
	_frame_log_script = loader.compile(dir.path_join("frame_log.gd"))
	get_tree().node_added.connect(_on_node_added)
	_launch = parse_launch(OS.get_environment("MP_LAUNCH"))
	loader.note("cl_playtest ready")
	if DisplayServer.get_name() == "headless":
		_check.call_deferred()
	elif not _launch.is_empty():
		_begin_launch()

# node_added fires before the node's _ready: Offline Bots sets the brain's scripts before adding it,
# and local_game builds its playlist in _ready.
func _on_node_added(node: Node) -> void:
	if node.name == BOTS_BRAIN and node.get_parent() == get_tree().root:
		_swap_roller(node)
	elif node.scene_file_path == LOCAL_GAME:
		if _launching():
			_launch_game(node)
		else:
			_one_round_each()
			_open_install_log(node)
	elif node.scene_file_path == MAIN_MENU and _launching():
		_on_main_menu()

func _process(delta: float) -> void:
	if _launch.get("look", "native") == "hi":
		_look_hi_subviewports()
		_look_hi_still()
	_fill_bots()
	_hide_seat_list()
	if _phase == "menu":
		_drive_menu()
	elif _phase == "lobby":
		_drive_lobby()
	elif _phase == "game":
		_trace_minigame_end()
		if int(_launch.get("auto", 0)) > 0:
			_drive_auto(delta)
	elif not _launching() and _frame_log != null:
		_note_install_load()
	if _launching() and int(_launch.get("auto", 0)) > 0:
		_check_auto_stall()
	if (_lobby_hold or _menu_hold) and _launching() and _auto_done_usec > 0 and Time.get_ticks_usec() - _auto_done_usec >= int(_launch["grace"]) * 1000000:
		ok("%s: held %d s" % ["lobby" if _lobby_hold else "menu", _launch["grace"]], true)
		_finish_launch()

# The local lobby with Offline Bots' override is the one with human_seat_count; a re-entered lobby fills again.
func _fill_bots() -> void:
	var lobby := get_tree().current_scene
	if lobby == null or lobby == _filled_lobby or not lobby.has_method("human_seat_count"):
		return
	var brain := get_tree().root.get_node_or_null(BOTS_BRAIN)
	if brain == null or _lobby_hold:
		return
	for seat in lobby.player_data:
		var d = lobby.player_data[seat]
		if not (d is Dictionary and d.get("is_bot", false)) and lobby.players_ready.get(seat, false):
			_filled_lobby = lobby
			if brain.identity_script == _roller:
				_widen_roller(lobby, seat)
				_roller.cast = _cast()
			brain.apply_bot_config(_launch["bots"] if _launching() else MAX_BOTS, brain.difficulty)
			if _launching() and _launch["difficulty"] >= 0:
				brain.difficulty = _launch["difficulty"]
				_loader.note("cl_playtest: bots at %s for this launch" % BOT_LEVELS[brain.difficulty])
			_loader.note("cl_playtest: %d humans, %d bots seated" % [lobby.human_seat_count(), lobby.player_data.size() - lobby.human_seat_count()])
			return

# Overtime 1.7's local game lists seats and pads top-left, over the play (local_game.gd
# _mp8_create_device_status, labels in _mp8_device_labels); the playtest hides it. 8 Player Support has none (D76).
func _hide_seat_list() -> void:
	var game := get_tree().current_scene
	if game == null or game.scene_file_path != LOCAL_GAME:
		return
	var labels = game.get("_mp8_device_labels")
	if not (labels is Dictionary) or labels.is_empty():
		return
	var canvas = (labels.values()[0] as Node).get_parent().get_parent()
	if canvas is CanvasLayer and canvas.visible:
		canvas.visible = false
		_loader.note("cl_playtest: Overtime's seat list hidden")

# The roller starts on More Cosmetics' catalog alone; at the fill it takes everything the lobby offers
# (the panel's lists, Overtime's colours, Better Couch Lobby's glasses row), so bots wear base-game items too.
func _widen_roller(lobby, seat: int) -> void:
	var pools := _offered_pools(lobby, seat)
	var hats: Array = pools["hats"].filter(func(h): return str(h) != "none")
	if not hats.is_empty():
		_roller.hats = hats
	if not pools["colors"].is_empty():
		_roller.colors = pools["colors"]
	# Without Better Couch Lobby's glasses row the lobby offers no glasses, and only its list knows the base game's blocking hats.
	var glasses: Array = pools["glasses"].filter(func(g): return str(g) != "none")
	_roller.glasses = glasses if not glasses.is_empty() else ["none"]
	for h in pools["no_glasses_hats"]:
		if not _roller.no_glasses_hats.has(h):
			_roller.no_glasses_hats.append(h)
	_loader.note("cl_playtest: bot outfits from the lobby's %d hats, %d glasses, %d colors" % [_roller.hats.size(), _roller.glasses.size(), _roller.colors.size()])

func _swap_roller(brain: Node) -> void:
	if _roller == null or brain.get("identity_script") == null:
		return
	var api = _loader.registry("more_cosmetics").get("api")
	if api == null:
		_loader.note("cl_playtest: More Cosmetics isn't installed; bots keep Offline Bots' outfits")
		return
	_roller.base = brain.identity_script
	_roller.hats = api.catalog.HATS.duplicate()
	_roller.glasses = api.catalog.GLASSES.duplicate()
	_roller.colors = api.catalog.COLORS.keys()
	_roller.no_glasses_hats = api.catalog.NO_GLASSES_HATS.duplicate()
	brain.identity_script = _roller
	_loader.note("cl_playtest: bot outfits from More Cosmetics' %d hats, %d glasses, %d colors" % [_roller.hats.size(), _roller.glasses.size(), _roller.colors.size()])

func _one_round_each() -> void:
	GameManager.custom_game = true
	GameManager.arcade_game = false
	Globals.session_playlist.clear()
	for id in _wanted(_listed_names()):
		Globals.session_playlist.append(MinigameListResource.create(id, 1))
	_loader.note("cl_playtest: %d minigames, 1 round each" % Globals.session_playlist.size())
	for p in PlayerManager.player_presences.values():
		_loader.note("cl_playtest: %s %s %s" % [p.network_name, "bot" if p.network_id >= BOT_DEVICE_BASE else "human", p.customization])

# --- Install mode's frame log: one file per local match ---

func _open_install_log(game: Node) -> void:
	if _frame_log != null or _frame_log_script == null:
		return
	_open_log("install", [
		"install: a local match, %d minigames, 1 round each" % Globals.session_playlist.size(),
	])
	if _frame_log != null:
		game.tree_exiting.connect(_close_install_log)

func _close_install_log() -> void:
	if _frame_log != null and not _launching():
		_frame_log.close()
		_frame_log.queue_free()
		_frame_log = null

func _note_install_load() -> void:
	var game := get_tree().current_scene
	var mg = game.get("minigame") if game != null and game.scene_file_path == LOCAL_GAME else null
	if not (is_instance_valid(mg) and mg is Node) or mg.get_instance_id() == _install_minigame_id:
		return
	_install_minigame_id = mg.get_instance_id()
	var presences: Array = PlayerManager.player_presences.values().filter(func(p): return p != null)
	var bots: int = presences.filter(func(p): return p.network_id >= BOT_DEVICE_BASE).size()
	_log_line(load_line(minigame_name(Globals.current_minigame_identifier, Globals.MinigameIdentifier), presences.size() - bots, bots))

# perf_summary.py groups a log's rows by these lines.
static func load_line(minigame: String, humans: int, bots: int) -> String:
	return "load: %s humans=%d bots=%d" % [minigame, humans, bots]

func _listed_names() -> PackedStringArray:
	var f := FileAccess.open(_loader.dir_of(MOD_ID).path_join(PLAYLIST_FILE), FileAccess.READ)
	return f.get_as_text().split("\n", false) if f != null else PackedStringArray()

# Unknown names and minigames outside the custom-game list are skipped; none left means all of them.
func _wanted(names: PackedStringArray) -> Array:
	var out: Array = []
	for n in names:
		var key := n.strip_edges()
		if Globals.MinigameIdentifier.has(key) and Globals.CustomMinigamesWhitelist.has(Globals.MinigameIdentifier[key]):
			out.append(Globals.MinigameIdentifier[key])
		elif not key.is_empty():
			_loader.note("cl_playtest: %s in %s is not a custom-game minigame; skipped" % [key, PLAYLIST_FILE])
	return out if not out.is_empty() else Array(Globals.CustomMinigamesWhitelist)

# --- Launch mode ---

# {} when MP_LAUNCH is empty; otherwise ok, error, minigame, mode, bots, headless_join (-1: none).
static func parse_launch(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var out := {"ok": true, "error": "", "minigame": "", "mode": "split", "bots": MAX_BOTS, "headless_join": -1, "auto": 0, "drop": 0, "stall": AUTO_STALL_SEC, "grace": AUTO_GRACE_SEC, "catches": false, "throwtest": false, "look": "native", "difficulty": -1}
	for part in text.split(";", false):
		var kv: PackedStringArray = part.split("=", true, 1)
		var key: String = kv[0].strip_edges()
		var val: String = kv[1].strip_edges() if kv.size() == 2 else ""
		if key == "minigame":
			out["minigame"] = val
		elif key == "mode":
			out["mode"] = val
		elif key == "bots" and val.is_valid_int() and int(val) >= 1 and int(val) <= MAX_BOTS:
			out["bots"] = int(val)
		elif key == "headless_join" and val.is_valid_int() and int(val) >= 0:
			out["headless_join"] = int(val)
		elif key == "auto" and val.is_valid_int() and int(val) >= 1:
			out["auto"] = int(val)
		elif key == "drop" and val.is_valid_int() and int(val) >= 1:
			out["drop"] = int(val)
		elif key == "stall" and val.is_valid_int() and int(val) >= 1:
			out["stall"] = int(val)
		elif key == "grace" and val.is_valid_int() and int(val) >= 0:
			out["grace"] = int(val)
		elif key == "catches" and val == "1":
			out["catches"] = true
		elif key == "throwtest" and val == "1":
			out["throwtest"] = true
		elif key == "look" and val == "hi":
			out["look"] = val
		elif key == "difficulty" and BOT_LEVELS.has(val):
			out["difficulty"] = BOT_LEVELS.find(val)
		else:
			return _bad_launch(out, "bad entry: %s" % part.strip_edges())
	if str(out["minigame"]).is_empty():
		return _bad_launch(out, "no minigame")
	if out["auto"] > 0 and out["headless_join"] < 0:
		out["headless_join"] = AUTO_DEVICE
	if not LAUNCH_MODES.has(out["mode"]):
		return _bad_launch(out, "mode is split or local, not %s" % out["mode"])
	return out

# The game sizes its SubViewports in the 960x540 layout's pixels, and Extended sizes the tiles again on every
# relayout, so a size that differs from the one set here is the game's new one and is scaled again.
# Only a viewport a TextureRect stretches to fit (the split-screen tiles) is scaled: one holding 2D menus laid out
# in pixels (the intermission's screen), or shown at its own size (Chisel's jumbotron), would show just a corner.
# A tile can hold 2D too (Duck Hunt's hunter moves its HUD into it), so its 2D keeps the game's size, stretched.
func _look_hi_subviewports() -> void:
	var root := get_tree().root
	var factor: float = minf(float(root.size.x) / root.content_scale_size.x, float(root.size.y) / root.content_scale_size.y)
	if factor <= 1.0:
		return
	var stretched := {}
	for rect in root.find_children("*", "TextureRect", true, false):
		if rect.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and rect.texture is ViewportTexture:
			stretched[rect.texture] = true
	for vp in root.find_children("*", "SubViewport", true, false):
		if vp.get_meta("look_hi_size", Vector2i.ZERO) == vp.size or not stretched.has(vp.get_texture()):
			continue
		var base: Vector2i = vp.size
		vp.size = Vector2i(mini(int(base.x * factor), 8192), mini(int(base.y * factor), 8192))
		vp.size_2d_override = base
		vp.size_2d_override_stretch = true
		vp.set_meta("look_hi_size", vp.size)
		_loader.note("cl_playtest look=hi: %s %s -> %s" % [vp.get_path(), base, vp.size])

func _look_hi_still() -> void:
	var dir := OS.get_environment("MP_LOOK_STILLS")
	var frame := Engine.get_process_frames()
	if dir.is_empty() or frame % LOOK_STILL_FRAMES != 0:
		return
	var image := get_tree().root.get_texture().get_image()
	var err := image.save_png(dir.path_join("still_%08d.png" % frame))
	if err != OK and not _look_still_failed:
		_look_still_failed = true
		_loader.note("cl_playtest look=hi: no still saved to MP_LOOK_STILLS %s (error %d)" % [dir, err])

static func _bad_launch(out: Dictionary, error: String) -> Dictionary:
	out["ok"] = false
	out["error"] = error
	return out

# A custom-game minigame by its MinigameIdentifier name, any case; -1 for anything else.
static func minigame_id(wanted: String, identifiers: Dictionary, whitelist: Array) -> int:
	for key in identifiers:
		if str(key).to_lower() == wanted.strip_edges().to_lower() and whitelist.has(identifiers[key]):
			return int(identifiers[key])
	return -1

static func minigame_name(id: int, identifiers: Dictionary) -> String:
	for key in identifiers:
		if int(identifiers[key]) == id:
			return str(key)
	return ""

static func custom_game_names(identifiers: Dictionary, whitelist: Array) -> Array:
	return identifiers.keys().filter(func(k): return whitelist.has(identifiers[k]))

# minigame_id, or one of NORMAL_SESSION_LAUNCHES by its name, any case; -1 for anything else.
static func launch_id(wanted: String, identifiers: Dictionary, whitelist: Array) -> int:
	var id := minigame_id(wanted, identifiers, whitelist)
	for key in NORMAL_SESSION_LAUNCHES:
		if id < 0 and str(key).to_lower() == wanted.strip_edges().to_lower():
			id = int(identifiers[key])
	return id

static func launch_playlist(id: int, rounds: int) -> Array:
	return [MinigameListResource.create(id, rounds)]

func _launching() -> bool:
	return _phase != "" and _phase != "done"

func _set_phase(phase: String) -> void:
	_phase = phase
	_phase_usec = Time.get_ticks_usec()
	_loader.note("cl_playtest launch: %s" % phase)

func _begin_launch() -> void:
	_config_before = FileAccess.get_file_as_string(BOTS_CONFIG) if FileAccess.file_exists(BOTS_CONFIG) else null
	# A window close would quit before the config is back and DONE is written; _notification quits instead.
	get_tree().auto_accept_quit = false
	_set_phase("menu")
	_auto_last_usec = Time.get_ticks_usec()
	if not _launch["ok"]:
		ok("MP_LAUNCH reads", false, "%s: %s" % [_launch["error"], OS.get_environment("MP_LAUNCH")])
		_finish_launch()
		return
	if _launch["look"] == "hi":
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		_loader.note("cl_playtest look=hi: window %s, content %s" % [get_tree().root.size, get_tree().root.content_scale_size])
	_launch_id = launch_id(_launch["minigame"], Globals.MinigameIdentifier, Globals.CustomMinigamesWhitelist)
	_normal_session = NORMAL_SESSION_LAUNCHES.has(minigame_name(_launch_id, Globals.MinigameIdentifier))
	_lobby_hold = str(_launch["minigame"]).to_lower() == "lobby"
	_menu_hold = str(_launch["minigame"]).to_lower() == "menu"
	if (_lobby_hold or _menu_hold) and int(_launch["auto"]) < 1:
		ok("minigame=%s runs unattended (auto)" % _launch["minigame"], false, OS.get_environment("MP_LAUNCH"))
		_finish_launch()
		return
	if _launch_id < 0 and not (_lobby_hold or _menu_hold):
		ok("%s is a custom-game minigame" % _launch["minigame"], false,
			"valid: %s" % " ".join(custom_game_names(Globals.MinigameIdentifier, Globals.CustomMinigamesWhitelist) + NORMAL_SESSION_LAUNCHES))
		_finish_launch()
		return
	if _outfits == null or _frame_log_script == null:
		ok("launch_outfits.gd and frame_log.gd compile", false)
		_finish_launch()
		return
	_open_frame_log()
	Input.joy_connection_changed.connect(_on_joy_changed)

func _on_joy_changed(device: int, connected: bool) -> void:
	var line := "pad %d %s (%s) at %.1f s, phase %s" % [device, "connected" if connected else "disconnected",
		Input.get_joy_name(device), (Time.get_ticks_usec() - _phase_usec) / 1000000.0, _phase]
	for p in PlayerManager.player_presences.values():
		if p != null and p.device_id == device and p.has_method("mp8_local_status_text"):
			line += "; seat before: " + p.mp8_local_status_text()
	_log_line(line)
	# Presences connect to this signal after the mod does, so their reaction shows only once the frame ends.
	_log_seat_after.call_deferred(device)

func _log_seat_after(device: int) -> void:
	for p in PlayerManager.player_presences.values():
		if p != null and p.device_id == device and p.has_method("mp8_local_status_text"):
			_log_line("pad %d, seat after: %s" % [device, p.mp8_local_status_text()])

# Each step of a minigame's hand-over (finished, the old instance out, a new one in) is written and flushed, so the
# last line before a crash says which step died.
func _trace_minigame_end() -> void:
	var game := get_tree().current_scene
	var mg = game.get("minigame") if game != null and game.scene_file_path == LOCAL_GAME else null
	if is_instance_valid(mg) and mg is Node and mg.get_instance_id() != _traced_minigame_id:
		_traced_minigame_id = mg.get_instance_id()
		_trace("a minigame instance is in the tree")
		mg.minigame_finished.connect(func(_id): _trace("minigame_finished"))
		mg.tree_exiting.connect(func(): _trace("the old minigame leaves the tree"))
		if _launch.get("catches", false) and not _catches_running and mg.get("coach_handler") != null:
			_check_table_catches(mg, PlayerManager.player_presences.size())

func _trace(what: String) -> void:
	_log_line("trace: %s, frame %d, physics frame %d" % [what, Engine.get_process_frames(), Engine.get_physics_frames()])

func _log_line(line: String) -> void:
	say(line)
	_loader.note("cl_playtest: " + line)
	if _frame_log != null:
		_frame_log.comment(line)

func _open_frame_log() -> void:
	_open_log("%s_%s" % [_launch["minigame"], _launch["mode"]],
		["launch: minigame=%s mode=%s humans=1 bots=%d (asked; seated below)" % [_launch["minigame"], _launch["mode"], _launch["bots"]]])

func _open_log(kind: String, first: Array) -> void:
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	var file := OS.get_environment("TEMP").path_join("machine-party-tests/launch/%s_%s.csv" % [stamp, kind])
	_frame_log = _frame_log_script.new()
	_frame_log.name = "FrameLog"
	add_child(_frame_log)
	var mods: Array = _loader.mod_list() if _loader.has_method("mod_list") else []
	var header: Array = first + [
		"started: %s" % Time.get_datetime_string_from_system(),
		"mods: %s" % ", ".join(mods),
		"overtime: %s" % _overtime_build(),
		"window: %s, mode %d, vsync %d, max_fps %d" % [get_window().size, get_window().mode, DisplayServer.window_get_vsync_mode(), Engine.max_fps],
		"renderer: %s on %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()],
		"frame_ms: every frame's _process delta in that second; perf_summary.py counts state %s as playing" % PLAYING_STATE,
		"process_ms, physics_ms: Godot's TIME_PROCESS and TIME_PHYSICS_PROCESS, the slowest step of the previous second, not an average",
	]
	if not _frame_log.open(file, header):
		_loader.note("cl_playtest: could not write %s" % file)
		_frame_log.queue_free()
		_frame_log = null

func _overtime_build() -> String:
	var id := "overtime" if _loader.has_mod("overtime") else "mp8_support" if _loader.has_mod("mp8_support") else ""
	if id.is_empty():
		return "not installed"
	var dir: String = _loader.dir_of(id)
	var info = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("BUILDINFO.json")))
	var tag := ""
	if info is Dictionary:
		tag = "%s built %s" % [info.get("mod_tag", "?"), info.get("built_utc", "?")]
	return "%s %s, overlay sha256 %s" % [id, tag, FileAccess.get_sha256(dir.path_join(id + "_overlay.zip")).left(12)]

func _overlay_busy() -> bool:
	var t = GlobalOverlay.get("overlay_tween")
	return t is Tween and t.is_running()

func _on_main_menu() -> void:
	if _phase == "menu":
		# Read by the menu's splash in its _ready, which runs after this.
		Globals.splash_screen_viewed = true
		_phase_usec = Time.get_ticks_usec()
	else:
		_finish_launch.call_deferred()

# The Custom button's steps; the menu's own fade-in runs for about a second first.
func _drive_menu() -> void:
	var menu := get_tree().current_scene
	if menu == null or menu.scene_file_path != MAIN_MENU or _overlay_busy() or Time.get_ticks_usec() - _phase_usec < 1500000:
		return
	if _menu_hold:
		if _auto_done_usec == 0:
			_auto_done_usec = Time.get_ticks_usec()
			_log_line("menu: held for %d s" % _launch["grace"])
		return
	GameManager.custom_game = not _normal_session
	GameManager.arcade_game = false
	_set_phase("lobby")
	if menu.has_method("switch_to_local_lobby_scene"):
		menu.switch_to_local_lobby_scene()
	else:
		get_tree().change_scene_to_file(LOBBY)

# The lobby joins the pad itself (handle_join_input); this names and readies that seat, waits for the bots,
# then starts. Vanilla's countdown_end_reached sets game_started before its guards, so a call while Start is
# disabled or the overlay fades would lock the lobby: both are cleared first.
func _drive_lobby() -> void:
	var lobby := get_tree().current_scene
	if lobby == null or lobby.scene_file_path != LOBBY or not lobby.has_method("countdown_end_reached"):
		return
	if not lobby.get("active") or lobby.get("game_started"):
		return
	if _launch["headless_join"] >= 0 and _joined_lobby != lobby:
		_joined_lobby = lobby
		lobby.join(_launch["headless_join"], true)
		return
	var seat: int = _human_seat(lobby)
	if seat < 0:
		return
	var controls = lobby.local_lobby_player_controls[seat]
	_step_frames += 1
	if _step_frames < 5:
		return
	_step_frames = 0
	if _human_step == 0:
		controls._on_name_confirmed(_human_name([]))
		_human_step = 1
	elif _human_step == 1:
		_pools = _offered_pools(lobby, seat)
		_dress_cast_seat(controls, lobby.player_data[seat])
		if not _lobby_hold:
			controls.set_player_ready(true)
		_human_step = 2
	elif _human_step == 2:
		if _lobby_hold:
			_hold_lobby(lobby)
			return
		var brain := get_tree().root.get_node_or_null(BOTS_BRAIN)
		if brain != null and _filled_lobby != lobby:
			return
		if brain == null:
			_loader.note("cl_playtest: no Offline Bots; the owner plays alone")
		if _overlay_busy():
			return
		var bot_names: Array = []
		for d in lobby.player_data.values():
			if d is Dictionary and d.get("is_bot", false):
				bot_names.append(str(d.get("bot_name", "")))
		if bot_names.has(controls.player_name):
			controls.player_name = _human_name(bot_names)
			controls.name_label.text = controls.player_name
		_pools = _offered_pools(lobby, seat)
		_start_facts = {"human": controls.player_name, "ready": lobby.players_ready.get(seat, false),
			"bots": bot_names.size(), "seats": lobby.local_lobby_player_controls.size()}
		if lobby.start_button.disabled:
			lobby.start_button.disabled = false
			_loader.note("cl_playtest: Start enabled for %d seat(s)" % lobby.player_data.size())
		_set_phase("starting")
		lobby.countdown_end_reached()

# minigame=Lobby: the lobby stays as it is; _process ends the run its grace time later, wherever a shot has gone.
func _hold_lobby(lobby) -> void:
	if _auto_done_usec == 0:
		_auto_done_usec = Time.get_ticks_usec()
		_log_line("lobby: held with %d seat(s), for %d s" % [lobby.player_data.size(), _launch["grace"]])

static func _human_seat(lobby) -> int:
	var seats: Array = lobby.player_data.keys().filter(func(s): return not (lobby.player_data[s] is Dictionary and lobby.player_data[s].get("is_bot", false)))
	seats.sort()
	return int(seats[0]) if not seats.is_empty() else -1

# A name as bots get them (outfit_roller's 4 letters from Offline Bots' list), or 4 random letters.
func _human_name(taken: Array) -> String:
	if not _cast().is_empty():
		return str(_cast()[0]["short"]).to_upper()
	var nm := ""
	for i in 40:
		nm = ""
		if _roller != null and _roller.base != null:
			nm = _roller._short(_roller.base.roll_name([]))
		if nm.is_empty():
			for j in 4:
				nm += char(65 + randi() % 26)
		if not taken.has(nm):
			break
	return nm

# Everything the lobby offers: the panel's own lists (Overtime's included), More Cosmetics' items the
# character can wear (its stepper's rule), and Better Couch Lobby's glasses row when it is there (none without it).
func _offered_pools(lobby, seat: int) -> Dictionary:
	var controls = lobby.local_lobby_player_controls[seat]
	var assigner = controls.customization_assigner
	var lists: Dictionary = controls.get_script().get_script_constant_map()
	# Copies: the panel's consts are read-only, and an append to one fails without an error.
	var hats: Array = Array(lists.get("hats", ["none"])).duplicate()
	var colors: Array = Array(lists.get("suit_colors", [])).duplicate()
	var api = _loader.registry("more_cosmetics").get("api")
	if api != null:
		for h in api.catalog.HATS:
			if not hats.has(h) and assigner.bone_attachment_hat.has_node(NodePath(h)):
				hats.append(h)
		for c in api.catalog.COLORS.keys():
			if not colors.has(c):
				colors.append(c)
	var glasses: Array = ["none"]
	var blocking: Array = []
	var picker = controls.get_node_or_null("CouchLobbyGlassesPicker")
	if picker != null:
		blocking = Array(picker.no_glasses_hats)
		for g in picker.glasses:
			if str(g) != "none" and assigner.bone_attachment_glasses.has_node(NodePath(str(g))):
				glasses.append(str(g))
	return {"hats": hats, "glasses": glasses, "colors": colors, "no_glasses_hats": blocking}

func _launch_game(game: Node) -> void:
	_set_phase("game")
	GameManager.custom_game = not _normal_session
	GameManager.arcade_game = false
	GameManager.custom_shuffled = false
	if _normal_session:
		game.ready.connect(_put_launch_second.bind(game), CONNECT_ONE_SHOT)
	else:
		Globals.session_playlist.clear()
		for m in launch_playlist(_launch_id, LAUNCH_ROUNDS):
			Globals.session_playlist.append(m)
	_dress_presences()

# local_game builds its session list in _ready, before its first await (which emits ready), and plays it in order
# (debug_no_shuffle); after the first minigame's score screen it goes into a cutscene that is next in the list.
func _put_launch_second(game: Node) -> void:
	var list: Array = game.session_minigame_list
	list.erase(_launch_id)
	list.insert(1, _launch_id)
	game.session_minigame_rounds[list[0]] = 1
	_log_line("normal session: %s for 1 round, then %s" % [minigame_name(list[0], Globals.MinigameIdentifier), _launch["minigame"]])

# Better Couch Lobby's own local_game hook runs after this one (the loader connects node_added after every
# _mod_ready) and writes each lobby seat's pick from its device map: the map gets the rolled glasses too.
func _dress_presences() -> void:
	if not _cast().is_empty():
		_dress_cast()
		return
	if _pools.is_empty():
		_loader.note("cl_playtest: no lobby lists read; outfits left as the lobby made them")
		return
	var presences: Array = PlayerManager.player_presences.values()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var outfits: Array = _outfits.roll(presences.size(), _pools["hats"], _pools["glasses"], _pools["colors"], _pools["no_glasses_hats"], rng)
	var picks: Dictionary = _loader.registry("couch_lobby").get("glasses", {})
	_rolled.clear()
	var lines: Array = []
	for i in presences.size():
		var p = presences[i]
		var o: Array = outfits[i]
		p.customization = o.duplicate()
		_rolled[p.device_id] = o
		if picks.has(p.device_id):
			picks[p.device_id] = o[1]
		lines.append("%s %s %s" % [p.network_name, "bot" if p.network_id >= 900001 else "human", o])
	var real: int = _outfits.real_hats(_pools["hats"]).size()
	var short: String = "" if real >= presences.size() else "; only %d hats for %d seats, so some repeat" % [real, presences.size()]
	var note := "match: %d seats from %d hats, %d glasses, %d colors%s" % [presences.size(), real, _pools["glasses"].size(), _pools["colors"].size(), short]
	for line in [note] + lines:
		_loader.note("cl_playtest: " + line)
		if _frame_log != null:
			_frame_log.comment(line)

# The trailer's cast (tools/trailer_cast's registry, D123), in seat order; empty without that dev mod.
func _cast() -> Array:
	return _loader.registry("trailer_cast").get("cast", [])

# The cast's first entry on the fake seat, in the lobby already, so its model and Polaroid wear it.
func _dress_cast_seat(controls, data) -> void:
	if _cast().is_empty():
		return
	var c: Dictionary = _cast()[0]
	var a = controls.customization_assigner
	a.assign_hat(str(c["hat"]))
	a.assign_glasses(str(c["glasses"]))
	a.assign_suit_color(str(c["suit"]))
	var picks: Dictionary = _loader.registry("couch_lobby").get("glasses", {})
	if data is Dictionary and data.has("device"):
		picks[data["device"]] = str(c["glasses"])
	_loader.note("cl_playtest: the fake seat dressed as cast seat 1, %s" % [[c["hat"], c["glasses"], c["suit"]]])

# Each presence takes its cast outfit by name; one the cast doesn't name keeps the lobby's.
func _dress_cast() -> void:
	var picks: Dictionary = _loader.registry("couch_lobby").get("glasses", {})
	var lines: Array = []
	for p in PlayerManager.player_presences.values():
		var found: Array = _cast().filter(func(c): return str(c["short"]).to_upper() == str(p.network_name).to_upper())
		if found.is_empty():
			lines.append("%s not in the cast, keeps %s" % [p.network_name, p.customization])
			continue
		var o: Array = [str(found[0]["hat"]), str(found[0]["glasses"]), str(found[0]["suit"])]
		p.customization = o.duplicate()
		_rolled[p.device_id] = o
		if picks.has(p.device_id):
			picks[p.device_id] = o[1]
		lines.append("%s %s %s" % [p.network_name, "bot" if p.network_id >= BOT_DEVICE_BASE else "human", o])
	for line in ["match: the trailer's cast"] + lines:
		_loader.note("cl_playtest: " + line)
		if _frame_log != null:
			_frame_log.comment(line)

# Unattended: the fake seat readies whenever the briefing waits and Offline Bots' AI plays it, each new minigame
# instance is logged (flushed, so a crash still shows how far it got), and the run ends after the Nth load's grace time.
func _drive_auto(delta: float) -> void:
	var game := get_tree().current_scene
	if game == null or game.scene_file_path != LOCAL_GAME:
		return
	var now := Time.get_ticks_usec()
	var im = game.get("intermission_manager")
	var briefing = im.get("screen_briefing") if im != null else null
	# A trailer shot can hold the briefing (tools/trailer_cast's "controls").
	var held: bool = _loader.registry("trailer_cast").get("holds_briefing", false)
	if briefing != null and briefing.get("active") and briefing.get("ready_button_press_allowed") and not held and now - _auto_ready_usec > 1000000:
		_auto_ready_usec = now
		briefing.set_ready_rpc(_launch["headless_join"], true)
	var drop: int = int(_launch.get("drop", 0))
	if drop > 0 and not _auto_dropped and now - _phase_usec > drop * 1000000:
		_auto_dropped = true
		say("auto: dropping pad %d" % _launch["headless_join"])
		Input.joy_connection_changed.emit(_launch["headless_join"], false)
	var mg = game.get("minigame")
	if is_instance_valid(mg) and mg is Node and mg.get_instance_id() != _auto_minigame_id:
		_auto_minigame_id = mg.get_instance_id()
		_auto_load_usec = now
		_auto_field_logged = false
		_auto_loads += 1
		# The drawn-frame count is the position in a --write-movie recording (one movie frame per drawn frame).
		say("auto: load %d of %s at %.1f s, frame %d, round %s" % [_auto_loads, _launch["minigame"], (now - _phase_usec) / 1000000.0, Engine.get_frames_drawn(), str(game.get("session_current_minigame_round"))])
		_auto_last_usec = now
		_auto_bot_state.clear()
		if _auto_loads >= int(_launch["auto"]):
			_auto_done_usec = now
	if is_instance_valid(mg) and mg is Node:
		_drive_fake_seat(mg, delta)
		_walk_to_house(mg, now)
	if _auto_done_usec > 0 and now - _auto_done_usec >= int(_launch["grace"]) * 1000000:
		ok("auto: %d loads of %s, then %d s of play" % [_auto_loads, _launch["minigame"], _launch["grace"]], true)
		_finish_launch()

# Offline Bots' _drive_bots for the fake seat's node alone, through the brain's own (private) helpers. Adding the
# seat to the brain's _bot_ids instead would also spoof its player_loaded, so a local match would see an extra
# all_players_loaded. Only nodes of the classes its AI plays are touched.
func _drive_fake_seat(mg: Node, delta: float) -> void:
	var brain := get_tree().root.get_node_or_null(BOTS_BRAIN)
	var ai = brain.get("_ai") if brain != null else null
	if ai == null or not ai.has_method("drive") or not ai.has_method("player_classes") or not brain.has_method("_ensure_bot_node_driven"):
		return
	var mg_class: String = brain._class_of(mg)
	var nodes: Array = []
	for c in ai.player_classes(mg_class):
		brain._find_all_by_class(mg, StringName(c), nodes)
	for node in nodes:
		var pres = node.get("player_presence")
		if pres != null and int(pres.network_id) == _launch["headless_join"]:
			brain._ensure_bot_node_driven(node)
			brain._kill_bot_cameras(node)
			ai.drive(mg, mg_class, node, _launch["headless_join"], _auto_bot_state, brain.difficulty, delta)

# Offline Bots' AI doesn't play the wheat field, whose ending starts when someone reaches the house.
func _walk_to_house(mg: Node, now: int) -> void:
	if _auto_housed or Globals.current_minigame_identifier != Globals.MinigameIdentifier.CutsceneTest:
		return
	# A trailer shot walks the field itself (tools/trailer_cast).
	if _loader.registry("trailer_cast").get("walks_field", false):
		return
	var players = mg.get("players")
	if not (players is Dictionary):
		return
	if not _auto_field_logged and now - _auto_load_usec >= AUTO_FIELD_SEC * 1000000:
		_auto_field_logged = true
		_log_line("auto: the field at %d s, %s" % [AUTO_FIELD_SEC, _field_positions(players)])
	var character = players.get(_launch["headless_join"])
	if now - _auto_load_usec >= AUTO_HOUSE_SEC * 1000000 and is_instance_valid(character) and character.has_method("teleport_rpc"):
		_auto_housed = true
		_log_line("auto: the fake seat's character moved to the house; the field before, %s" % _field_positions(players))
		character.teleport_rpc(AUTO_HOUSE_SPOT)

static func _field_positions(players: Dictionary) -> String:
	var at: Array = players.values().map(func(c): return "(%.1f, %.1f, %.1f)" % [c.global_position.x, c.global_position.y, c.global_position.z])
	return "%d characters at %s" % [players.size(), " ".join(at)]

# In any phase, from the launch on: no new minigame load for the stall time ends an unattended run with a FAIL.
func _check_auto_stall() -> void:
	if _auto_done_usec > 0 or Time.get_ticks_usec() - _auto_last_usec <= int(_launch["stall"]) * 1000000:
		return
	var where := "phase %s" % _phase
	var game := get_tree().current_scene
	if game != null:
		where += ", scene %s" % game.scene_file_path.get_file()
		var mg = game.get("minigame")
		if is_instance_valid(mg) and mg is Node and mg.get("state_machine") != null and mg.state_machine.get("current_state") != null:
			where += ", minigame state %s" % mg.state_machine.current_state.name
	ok("auto: a new load within %d s" % _launch["stall"], false, "stalled after %d load(s), %s" % [_auto_loads, where])
	_finish_launch()

func _finish_launch(quit := true) -> void:
	if _phase == "done":
		return
	_set_phase("done")
	if _frame_log != null:
		_frame_log.close()
	if _config_before == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BOTS_CONFIG))
	else:
		var f := FileAccess.open(BOTS_CONFIG, FileAccess.WRITE)
		if f != null:
			f.store_string(_config_before)
			f.close()
	var config_after = FileAccess.get_file_as_string(BOTS_CONFIG) if FileAccess.file_exists(BOTS_CONFIG) else null
	ok("Offline Bots' config put back as it was at launch", config_after == _config_before, [_config_before, config_after])
	say("DONE fails=%d" % fails)
	if quit:
		get_tree().quit()

# The quit is queued before the clean-up, so the window closes even if the clean-up fails part-way.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _phase != "":
		get_tree().quit.call_deferred()
		_finish_launch(false)

# A quit that bypasses both (the pause menu's quit to desktop) still restores the config and writes DONE.
func _exit_tree() -> void:
	if _launching():
		_finish_launch(false)
	elif _frame_log != null:
		_frame_log.close()

# Headless (run_selftest.sh cl_playtest --overtime=fork <dir>/offline_bots, after run_playtest.sh copy <dir>):
# the wiring and the rules above, without a match unless MP_LAUNCH asks for one.
var fails := 0
var out: FileAccess
var _said: Array = []  # every line said, for checks on the log

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_playtest/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()
	_said.append(msg)

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func _check() -> void:
	await get_tree().create_timer(1.0).timeout
	var brain := get_tree().root.get_node_or_null(BOTS_BRAIN)
	ok("Offline Bots' brain found", brain != null)
	ok("brain rolls with our roller", brain != null and brain.identity_script == _roller)
	if _roller != null:
		var outfits: Array = []
		for i in 7:
			outfits.append(_roller.roll_outfit(outfits))
		say("outfits: %s" % [outfits])
		var hats := outfits.map(func(o): return o[0])
		var unique := {}
		for h in hats: unique[h] = true
		ok("7 different hats, all ours", unique.size() == 7 and hats.all(func(h): return h.begins_with("xc_")), hats)
		for slot in [1, 2]:
			var pool: Array = _roller.glasses if slot == 1 else _roller.colors
			var vals := outfits.map(func(o): return o[slot])
			ok("slot %d uses every item of ours" % slot, pool.all(func(x): return vals.has(x)), vals)
			ok("slot %d holds only our items" % slot, vals.all(func(v): return pool.has(v) or (slot == 1 and v == "none")), vals)
		ok("a glasses-blocking hat only without glasses",
			outfits.all(func(o): return o[1] == "none" or not _roller.no_glasses_hats.has(o[0])), outfits)
		ok("glasses only where the hat blocks them", outfits.all(func(o): return o[1] != "none" or _roller.no_glasses_hats.has(o[0])), outfits)
		var names: Array = _roller.assign_names([], 7)
		var named := {}
		for n in names: named[n] = true
		ok("7 different names of up to 4 letters", named.size() == 7 and names.all(func(n): return n.length() >= 1 and n.length() <= 4 and n == n.to_upper()), names)
	# A launch in local mode runs the copy that keeps Offline Bots' overrides, so bots play off-screen.
	var tiles: bool = _launch.is_empty() or _launch.get("mode", "split") == "split"
	for h in HANDLERS:
		var own: bool = (load(h) as GDScript).get_base_script() == null
		ok("bots %s: %s" % ["keep their tiles" if tiles else "play off-screen", h.get_file()], own == tiles)
	var M = Globals.MinigameIdentifier
	var list_path: String = _loader.dir_of(MOD_ID).path_join(PLAYLIST_FILE)
	var list := FileAccess.open(list_path, FileAccess.WRITE)
	list.store_string("DiscoDodge\n GreenPea \nNope\nCutsceneTest\n")
	list.close()
	var picked := _wanted(_listed_names())
	DirAccess.remove_absolute(list_path)
	ok("a playlist file picks its minigames", picked == [M.DiscoDodge, M.GreenPea], picked)
	ok("no playlist file means all of them", _wanted(_listed_names()).size() == Globals.CustomMinigamesWhitelist.size())
	var config_before = FileAccess.get_file_as_string(BOTS_CONFIG) if FileAccess.file_exists(BOTS_CONFIG) else null
	await _check_fill(brain)
	if config_before == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BOTS_CONFIG))
	else:
		FileAccess.open(BOTS_CONFIG, FileAccess.WRITE).store_string(config_before)
	var config_after = FileAccess.get_file_as_string(BOTS_CONFIG) if FileAccess.file_exists(BOTS_CONFIG) else null
	ok("Offline Bots' config put back as it was", config_after == config_before, [config_before, config_after])
	_one_round_each()
	var ids := Globals.session_playlist.map(func(m): return m.game_identifier)
	ok("every custom-game minigame once", ids.size() == Globals.CustomMinigamesWhitelist.size() and Globals.CustomMinigamesWhitelist.all(func(i): return ids.has(i)), ids.size())
	ok("1 round each", Globals.session_playlist.all(func(m): return m.total_rounds == 1))
	_check_launch_rules()
	if _launch.is_empty():
		await _check_install_log()
		say("DONE fails=%d" % fails)
		get_tree().quit()
	else:
		await _check_launch()

# Seats are the lobby's own (4 vanilla, 8 under Overtime); Offline Bots fills every free one.
func _check_fill(brain: Node) -> void:
	get_tree().change_scene_to_file(LOBBY)
	for i in 30: await get_tree().process_frame
	var lobby := get_tree().current_scene
	lobby.join(-1, false)
	for i in 5: await get_tree().process_frame
	ok("no bots before the human is ready", lobby.player_data.size() == 1, lobby.player_data.size())
	lobby.local_lobby_player_controls[0].customization_assigner.assign_hat("xc_sombrero")
	lobby._on_player_ready_changed(0, true)
	for i in 5: await get_tree().process_frame
	var seats: int = lobby.local_lobby_player_controls.size()
	var want: int = mini(MAX_BOTS, seats - 1)
	var bots: Array = lobby.player_data.values().filter(func(d): return d.get("is_bot", false))
	ok("%d bots seated once the human is ready (%d seats)" % [want, seats], bots.size() == want and lobby.player_data.size() == want + 1, [bots.size(), lobby.player_data.size()])
	var hats := bots.map(func(d): return d["bot_customization"][0])
	var others: Array = _roller.hats.filter(func(h): return h != "xc_sombrero")
	var distinct := {}
	for h in hats: distinct[h] = true
	var first: bool = distinct.size() == bots.size() and hats.all(func(h): return others.has(h))
	if bots.size() >= others.size():
		first = others.all(func(h): return hats.has(h))
	ok("bots wear each of the lobby's other hats before a repeat", first, hats)
	ok("all %d ready" % (want + 1), lobby.players_ready.values().all(func(r): return r), lobby.players_ready)
	ok("bots roll from the lobby's hats, base game's and ours, never none",
		_roller.hats.has("tophat") and _roller.hats.any(func(h): return str(h).begins_with("xc_")) and not _roller.hats.has("none"), _roller.hats)
	ok("bots roll from the lobby's colours, base game's and ours",
		_roller.colors.has("red") and _roller.colors.any(func(c): return str(c).begins_with("xc_")), _roller.colors)
	_pools = _offered_pools(lobby, 0)
	say("offered: %s" % [_pools])

# The launch lane's pure rules: MP_LAUNCH, the minigame name, the playlist, the outfit roll, frame-log rows.
func _check_launch_rules() -> void:
	var good: Dictionary = parse_launch("minigame=DuckHunt;mode=local;bots=3;headless_join=100")
	ok("MP_LAUNCH: a full entry reads", good.get("ok") == true and good["minigame"] == "DuckHunt" and good["mode"] == "local" and good["bots"] == 3 and good["headless_join"] == 100, good)
	var short: Dictionary = parse_launch(" minigame = duckhunt ")
	ok("MP_LAUNCH: defaults split, 7 bots, no headless join", short.get("ok") == true and short["mode"] == "split" and short["bots"] == 7 and short["headless_join"] == -1, short)
	ok("MP_LAUNCH: empty is launch mode off", parse_launch("").is_empty() and parse_launch("  ").is_empty())
	var auto: Dictionary = parse_launch("minigame=DuckHunt;auto=2;drop=40")
	ok("MP_LAUNCH: auto and drop read, auto seats the fake device %d" % AUTO_DEVICE, auto.get("ok") == true and auto["auto"] == 2 and auto["drop"] == 40 and auto["headless_join"] == AUTO_DEVICE, auto)
	ok("MP_LAUNCH: auto keeps a given headless_join", parse_launch("minigame=DuckHunt;auto=1;headless_join=7")["headless_join"] == 7)
	ok("MP_LAUNCH: look=hi reads, native by default", parse_launch("minigame=ChiselGauntlet;look=hi")["look"] == "hi" and parse_launch("minigame=ChiselGauntlet")["look"] == "native" and parse_launch("minigame=ChiselGauntlet;look=4k")["ok"] == false)
	ok("MP_LAUNCH: difficulty reads, off by default", parse_launch("minigame=DuckHunt;difficulty=hard")["difficulty"] == 2 and parse_launch("minigame=DuckHunt;difficulty=easy")["difficulty"] == 0 and short["difficulty"] == -1, short)
	ok("MP_LAUNCH: catches=1 reads, off by default", parse_launch("minigame=GreenPea;catches=1")["catches"] == true and parse_launch("minigame=GreenPea")["catches"] == false)
	ok("MP_LAUNCH: stall reads, %d s by default" % AUTO_STALL_SEC, parse_launch("minigame=DuckHunt;auto=1;stall=45")["stall"] == 45 and auto["stall"] == AUTO_STALL_SEC, auto)
	ok("MP_LAUNCH: grace reads, 0 allowed, %d s by default" % AUTO_GRACE_SEC, parse_launch("minigame=DuckHunt;auto=2;grace=0")["grace"] == 0 and auto["grace"] == AUTO_GRACE_SEC, auto)
	var hold: Dictionary = parse_launch("minigame=Lobby;auto=1;grace=8")
	ok("MP_LAUNCH: minigame=Lobby reads, and is no minigame's name", hold.get("ok") == true and hold["grace"] == 8 and launch_id("Lobby", Globals.MinigameIdentifier, Globals.CustomMinigamesWhitelist) == -1, hold)
	ok("MP_LAUNCH: minigame=Menu is no minigame's name", launch_id("Menu", Globals.MinigameIdentifier, Globals.CustomMinigamesWhitelist) == -1)
	ok("a minigame's name from its id", minigame_name(Globals.MinigameIdentifier.SpineBreaker, Globals.MinigameIdentifier) == "SpineBreaker")
	for bad in ["minigame=DuckHunt;variant=8p", "mode=split;bots=3", "minigame=DuckHunt;bots=8", "minigame=DuckHunt;bots=0", "minigame=DuckHunt;bots=x", "minigame=DuckHunt;mode=tiles", "minigame=DuckHunt;speed=2", "minigame=DuckHunt;headless_join=-3", "minigame=DuckHunt;auto=0", "minigame=DuckHunt;auto=x", "minigame=DuckHunt;auto=2;drop=0", "minigame=DuckHunt;auto=2;drop=x", "minigame=DuckHunt;auto=2;stall=0", "minigame=DuckHunt;auto=2;stall=x", "minigame=DuckHunt;auto=2;grace=-1", "minigame=DuckHunt;auto=2;grace=x", "minigame=DuckHunt;difficulty=Hard", "minigame=DuckHunt;difficulty=4"]:
		var r: Dictionary = parse_launch(bad)
		ok("MP_LAUNCH refused: %s" % bad, r.get("ok") == false and not str(r.get("error", "")).is_empty(), r)
	var M = Globals.MinigameIdentifier
	var W: Array = Array(Globals.CustomMinigamesWhitelist)
	ok("minigame names match in any case", minigame_id("duckhunt", M, W) == M.DuckHunt and minigame_id("DUCKHUNT", M, W) == M.DuckHunt)
	ok("unknown and non-custom-game names are refused", minigame_id("Nope", M, W) == -1 and minigame_id("CutsceneTest", M, W) == -1 and minigame_id("", M, W) == -1)
	var names: Array = custom_game_names(M, W)
	ok("the valid names are the custom-game list", names.size() == W.size() and names.has("DuckHunt") and not names.has("CutsceneTest"), names)
	ok("a launch takes the custom-game names and the wheat field, nothing else",
		launch_id("cutscenetest", M, W) == M.CutsceneTest and launch_id("DuckHunt", M, W) == M.DuckHunt and launch_id("CutsceneGame02", M, W) == -1 and launch_id("Nope", M, W) == -1)
	var playlist: Array = launch_playlist(M.DuckHunt, LAUNCH_ROUNDS)
	ok("the playlist is the one minigame for %d rounds" % LAUNCH_ROUNDS, playlist.size() == 1 and playlist[0].game_identifier == M.DuckHunt and playlist[0].total_rounds == LAUNCH_ROUNDS, playlist.size())
	if _outfits == null or _frame_log_script == null:
		ok("launch_outfits.gd and frame_log.gd compile", false)
		return
	_check_outfit_rules()
	_check_frame_rows()

func _check_outfit_rules() -> void:
	ok("the lobby's lists were read", not _pools.is_empty(), _pools)
	if _pools.is_empty():
		return
	var lists: Dictionary = (load("res://scenes/local_lobby/scripts/local_lobby_player_controls.gd") as GDScript).get_script_constant_map()
	var api = _loader.registry("more_cosmetics").get("api")
	var theirs: Array = [] if api == null else api.catalog.HATS + api.catalog.COLORS.keys()
	ok("the offered hats and colours are the lobby's and More Cosmetics'",
		(lists["hats"] + lists["suit_colors"] + theirs).all(func(x): return _pools["hats"].has(x) or _pools["colors"].has(x)), theirs)
	var hats: Array = _pools["hats"]
	var real: Array = _outfits.real_hats(hats)
	var blocking: Array = _pools["no_glasses_hats"]
	var n: int = mini(8, real.size())
	var all_distinct := true
	var glasses_rule := true
	var seen_hats := {}
	var seen_glasses := {}
	var colors_distinct := true
	var rng := RandomNumberGenerator.new()
	for s in 1000:
		rng.seed = s
		var outfits: Array = _outfits.roll(n, hats, _pools["glasses"], _pools["colors"], blocking, rng)
		var h := {}
		var c := {}
		for o in outfits:
			h[o[0]] = true
			c[o[2]] = true
			seen_hats[o[0]] = true
			seen_glasses[o[1]] = true
			if blocking.has(o[0]) and o[1] != "none":
				glasses_rule = false
		all_distinct = all_distinct and h.size() == n and not h.has("none")
		colors_distinct = colors_distinct and c.size() == mini(n, _pools["colors"].size())
	ok("%d different hats in each of 1000 rolls from the %d offered" % [n, real.size()], all_distinct)
	ok("over the rolls, every offered hat is worn", real.all(func(x): return seen_hats.has(x)), seen_hats.keys())
	ok("over the rolls, every offered pair of glasses and none", _pools["glasses"].all(func(x): return seen_glasses.has(x)), seen_glasses.keys())
	ok("no glasses under a hat that blocks them", glasses_rule, blocking)
	ok("suit colours differ while they last", colors_distinct)
	rng.seed = 7
	var a: Array = _outfits.roll(8, hats, _pools["glasses"], _pools["colors"], blocking, rng)
	rng.seed = 7
	ok("the same seed rolls the same outfits", a == _outfits.roll(8, hats, _pools["glasses"], _pools["colors"], blocking, rng), a)
	var few: Array = _outfits.roll(5, ["none", "a", "b"], ["none", "g"], ["red", "blue"], ["b"], rng)
	var few_hats: Array = few.map(func(o): return o[0])
	var few_colors: Array = few.map(func(o): return o[2])
	ok("past the hats, none once, then repeats", few_hats.slice(0, 3).has("a") and few_hats.slice(0, 3).has("b") and few_hats.slice(0, 3).has("none") and few_hats.size() == 5, few_hats)
	ok("past the colours, each again before any third time", few_colors.count("red") >= 2 and few_colors.count("blue") >= 2 and few_colors.slice(0, 2).has("red") and few_colors.slice(0, 2).has("blue"), few_colors)
	ok("a blocking hat in the small list goes without glasses", few.all(func(o): return o[0] != "b" or o[1] == "none"), few)

func _check_frame_rows() -> void:
	var times: Array = []
	for i in 99: times.append(10.0)
	times.append(100.0)
	var s: Dictionary = _frame_log_script.stats(times)
	ok("frame stats: 100 frames, avg 10.9, p99 10, max 100, fps 91.7",
		s["frames"] == 100 and is_equal_approx(s["avg_ms"], 10.9) and is_equal_approx(s["p99_ms"], 10.0) and is_equal_approx(s["max_ms"], 100.0) and absf(s["fps"] - 91.743) < 0.01, s)
	times.append(100.0)
	s = _frame_log_script.stats(times)
	ok("frame stats: 2 spikes in 101 frames reach p99", is_equal_approx(s["p99_ms"], 100.0), s)
	ok("frame stats: no frames is all zero", _frame_log_script.stats([])["frames"] == 0)
	var line: String = _frame_log_script.row(["1.00", "local_game", "MinigamePlaying", "", "1", 3, "60.0", "16.67", "16.70", "16.70", "1.00", "0.50", "2.00", "8.00", 10, 20, 30, "1.0", 4, "2.07", "16.60 16.70 16.70"])
	ok("a row has every column, frame times in the last", line.split(",").size() == _frame_log_script.COLUMNS.size() and line.ends_with(",16.60 16.70 16.70"), line)
	ok("a field with a comma is quoted", _frame_log_script.row(["a,b", "c"]) == "\"a,b\",c")
	ok("a load line names the minigame, its humans and its bots", load_line("DuckHunt", 3, 5) == "load: DuckHunt humans=3 bots=5", load_line("DuckHunt", 3, 5))

# A stand-in node plays the local match: its log opens with the header, takes a load line, and closes when it leaves.
func _check_install_log() -> void:
	var match_node := Node.new()
	add_child(match_node)
	_open_install_log(match_node)
	var path: String = _frame_log.path if _frame_log != null else ""
	ok("a local match opens its frame log", path.ends_with("_install.csv"), path)
	if _frame_log != null:
		_frame_log.comment(load_line("GreenPea", 3, 5))
	match_node.queue_free()
	await get_tree().process_frame
	ok("the log closes when the match leaves", _frame_log == null)
	var text: String = FileAccess.get_file_as_string(path) if not path.is_empty() else ""
	ok("the log names the match and the load",
		text.contains("# install: a local match") and text.contains("# load: GreenPea humans=3 bots=5")
		and text.contains("t,scene,state"), text.left(400))
	DirAccess.remove_absolute(path)

# The launch flow end to end, the headless device standing in for the owner's A press.
func _check_launch() -> void:
	_begin_launch()
	if _phase != "menu":
		return
	if _normal_session:
		ok("a normal-session launch runs windowed only (run_playtest.sh launch %s)" % _launch["minigame"], false)
		_finish_launch()
		return
	ok("MP_LAUNCH names a headless device", _launch["headless_join"] >= 0, _launch)
	get_tree().change_scene_to_file(MAIN_MENU)
	ok("main menu, then the custom-game lobby", await _wait(func(): return _scene_is(LOBBY) and GameManager.custom_game and not GameManager.arcade_game, 30.0))
	ok("the lobby starts the local game", await _wait(func(): return _phase == "game", 60.0), _phase)
	var seats: int = int(_start_facts.get("seats", 0))
	var want_bots: int = mini(int(_launch["bots"]), seats - 1)
	ok("the human was named and readied", str(_start_facts.get("human", "")).length() in [1, 2, 3, 4] and _start_facts.get("ready") == true, _start_facts)
	ok("%d bots seated" % want_bots, _start_facts.get("bots") == want_bots, _start_facts)
	var game := get_tree().current_scene
	# The briefing waits for every seat's ready; Offline Bots readies the bots, the owner presses for the human.
	var briefing = game.intermission_manager.screen_briefing if game != null and game.get("intermission_manager") != null else null
	ok("the briefing opens", await _wait(func(): return briefing != null and briefing.active and briefing.ready_button_press_allowed, 60.0))
	if briefing != null:
		briefing.set_ready_rpc(_launch["headless_join"], true)
	ok("%s loads" % _launch["minigame"], await _wait(func(): return _scene_is(LOCAL_GAME) and game.get("minigame") != null and Globals.current_minigame_identifier == _launch_id, 120.0),
		[Globals.current_minigame_identifier, _launch_id])
	ok("the playlist is that minigame for %d rounds" % LAUNCH_ROUNDS, Globals.session_playlist.size() == 1 and Globals.session_playlist[0].total_rounds == LAUNCH_ROUNDS and not GameManager.custom_shuffled)
	var presences: Array = PlayerManager.player_presences.values()
	var outfits: Array = presences.map(func(p): return p.customization)
	say("presences: %s" % [outfits])
	var hats := {}
	var colors := {}
	for o in outfits:
		hats[o[0]] = true
		colors[o[2]] = true
	ok("%d presences, the human and the bots" % (want_bots + 1), presences.size() == want_bots + 1, presences.size())
	ok("every presence has its own hat", hats.size() == presences.size() and not hats.has("none"), hats.keys())
	ok("every presence has its own suit colour", colors.size() == presences.size(), colors.keys())
	ok("no glasses under a blocking hat", outfits.all(func(o): return o[1] == "none" or not _pools["no_glasses_hats"].has(o[0])), outfits)
	ok("every presence wears its roll, Better Couch Lobby's hook included", presences.all(func(p): return _rolled.get(p.device_id) == p.customization), _rolled)
	var mg_name := minigame_name(_launch_id, Globals.MinigameIdentifier)
	if LAYOUT_MINIGAMES.has(mg_name):
		await _check_layout(game.get("minigame"), mg_name, presences.size())
	if mg_name == "ChiselGauntlet":
		_check_dead_lobby(game.get("minigame"))
	if mg_name in ["ChiselGauntlet", "KnifeAtTheOffice"]:
		await _check_omni_shadows(game.get("minigame"), mg_name, presences.size())
	if mg_name == "JunkPlatform" and _launch.get("throwtest", false):
		await _measure_debris_throw(game.get("minigame"))
	var dev: int = _launch["headless_join"]
	var seat = presences.filter(func(p): return p.device_id == dev)
	if not seat.is_empty() and seat[0].has_method("mp8_local_status_text"):
		# The fake seat starts disconnected, so a connect is what changes its status: before and after must differ.
		var said := _said.size()
		Input.joy_connection_changed.emit(dev, true)
		for i in 2: await get_tree().process_frame
		var lines_now: Array = _said.slice(said)
		var before: Array = lines_now.filter(func(l): return l.begins_with("pad %d connected" % dev))
		var after: Array = lines_now.filter(func(l): return l.begins_with("pad %d, seat after:" % dev))
		ok("a pad's connect is logged with the seat's status before and after the game handled it",
			before.size() == 1 and before[0].contains("DISCONNECTED") and after.size() == 1 and after[0].contains("A / CROSS to confirm"), lines_now)
		said = _said.size()
		Input.joy_connection_changed.emit(dev, false)
		for i in 2: await get_tree().process_frame
		after = _said.slice(said).filter(func(l): return l.begins_with("pad %d, seat after:" % dev))
		ok("a pad's drop is logged with the seat disconnected after", after.size() == 1 and after[0].contains("DISCONNECTED"), after)
		await _check_reconnect(seat[0], dev)
	else:
		say("NOTE no seat status here (Overtime's mp8_local_status_text is the fork's): the pad-log status checks skipped")
	if _launch_id == Globals.MinigameIdentifier.DuckHunt:
		await _check_hunter_views(game.get("minigame"))
	if _launch_id in [Globals.MinigameIdentifier.BurnRecycle, Globals.MinigameIdentifier.KnifeAtTheOffice]:
		await _check_tile_views(game.get("minigame"))
	if _launch_id == Globals.MinigameIdentifier.KnifeAtTheOffice:
		await _check_hunt_names(game.get("minigame"))
	await get_tree().create_timer(2.5).timeout
	var path: String = _frame_log.path if _frame_log != null else ""
	var lines: Array = Array(FileAccess.get_file_as_string(path).split("\n", false)) if not path.is_empty() else []
	var data: Array = lines.filter(func(l): return not l.begins_with("#"))
	ok("the frame log has rows", data.size() >= 3 and data[0].begins_with("t,scene,state"), [path, data.size()])
	ok("the frame log names the match", lines.any(func(l): return l.begins_with("# match: ")))
	ok("rows from the local game", data.any(func(l): return l.contains(",local_game,")), data.size())
	# Unattended, the match plays on until _drive_auto or the stall check ends the run.
	if int(_launch["auto"]) == 0:
		get_tree().change_scene_to_file(MAIN_MENU)

# 8 Player Support 0.8.0 (D89): a local game never shows Chisel Gauntlet's dead lobby, so its camera never draws.
func _check_dead_lobby(mg) -> void:
	if not is_instance_valid(mg) or not mg.has_method("mp8_show_dead_lobby"):
		say("NOTE ChiselGauntlet: no mp8_show_dead_lobby in this build; the dead lobby check skipped")
		return
	var mode: int = mg.dead_camera.get_viewport().render_target_update_mode
	ok("Chisel Gauntlet: the dead lobby's camera does not draw in a local game", mode == SubViewport.UPDATE_DISABLED, mode)

# 8 Player Support 0.9.0 (D90): in a local game Chisel's and Knife's omni lights draw dual-paraboloid shadows,
# except Knife's fog-of-war lights, whose shadow is each player's line of sight. Overtime keeps the cube.
func _check_omni_shadows(mg, mg_name: String, n: int) -> void:
	if _loader.has_mod("overtime") or not _loader.has_mod("mp8_support") or not is_instance_valid(mg):
		say("NOTE %s: not 8 Player Support; the omni shadow check skipped" % mg_name)
		return
	await _wait(func(): return mg.players.size() == n, 60.0)
	await get_tree().process_frame
	var fog: Array = []
	if mg_name == "KnifeAtTheOffice":
		fog = mg.players.values().map(func(p): return p.fog_of_war.fog_of_war_light)
	var lights: Array = mg.find_children("*", "OmniLight3D", true, false)
	var wrong: Array = lights.filter(func(l): return l.omni_shadow_mode != (OmniLight3D.SHADOW_CUBE if fog.has(l) else OmniLight3D.SHADOW_DUAL_PARABOLOID))
	ok("%s: %d omni lights dual paraboloid in a local game, %d fog-of-war lights cube" % [mg_name, lights.size() - fog.size(), fog.size()],
		lights.size() > fog.size() and fog.size() == (n if mg_name == "KnifeAtTheOffice" else 0) and wrong.is_empty(),
		wrong.map(func(l): return "%s mode %d" % [mg.get_path_to(l), l.omni_shadow_mode]))

# 8 Player Support 0.9.0: a local hunt hides every name over a head, the syringe holder's too. Calls the hunt's
# start directly with the first player marked infected, so it runs after the tile checks: the music, the projector
# loop and the uninfected cameras' 3 s zoom start with it.
func _check_hunt_names(mg) -> void:
	if _loader.has_mod("overtime") or not _loader.has_mod("mp8_support") or not is_instance_valid(mg):
		say("NOTE KnifeAtTheOffice: not 8 Player Support; the hunt names check skipped")
		return
	var players: Array = mg.players.values()
	var holder = players[0]
	var was: bool = holder.is_infected
	holder.is_infected = true
	mg.start_projector_hide_hunt_loop_rpc()
	await get_tree().process_frame
	holder.is_infected = was
	var shown: Array = players.filter(func(p): return p.player_name_label.animation_player.assigned_animation != "hide name")
	ok("Inside Job: the hunt hides all %d names over heads in a local game, the infected one's too" % players.size(),
		shown.is_empty(), shown.map(func(p): return p.player_presence.network_name))

# Wrong Way's hand IKs pull the hands onto the handrails: off where the eight-strip build hid them, as shipped
# at 4 seats. The torso lean is kept at both (the owner's pick, D101).
func _check_wrong_way_arms(mg, n: int, rails_hidden: bool) -> void:
	ok("Wrong Way: the players are spawned", await _wait(func(): return mg.player_characters.size() == n, 60.0), mg.player_characters.size())
	await get_tree().process_frame
	var hand: float = 0.0 if rails_hidden else 1.0
	var wrong := func(p): return p.ik_left_hand.influence != hand or p.ik_right_hand.influence != hand or p.ik_torso.influence != 1.0
	var off: Array = mg.player_characters.values().filter(wrong)
	var said := func(ps): return ps.map(func(p): return [p.player_presence.network_name, p.ik_left_hand.influence, p.ik_right_hand.influence, p.ik_torso.influence])
	var state: String = "off (no rails)" if rails_hidden else "on (the rails are there)"
	ok("Wrong Way: at %d seats the hand IKs are %s, the torso lean kept" % [n, state], off.is_empty(), said.call(off))
	# Again mid-run: the run blend and the countdown's start come after the spawn.
	ok("Wrong Way: the players start running", await _wait(func(): return mg.player_characters.values().all(func(p): return p.active), 60.0))
	await get_tree().create_timer(1.0).timeout
	off = mg.player_characters.values().filter(wrong)
	ok("Wrong Way: a second into the run the hand IKs are still %s" % state, off.is_empty(), said.call(off))

# Debris Platforms on the couch (D102): at 5-8 seats the decks on the 34 x 18 oval at one height, each compactor
# hung from its deck's lift node, the stock floor collider off; at 4 seats or fewer the octagon stays.
func _check_debris_couch(mg, n: int) -> void:
	if not "_mp8_couch" in mg:
		ok("Debris Platforms: this build has the couch layout (0.13.0 or later)", false)
		return
	if n <= 4:
		ok("Debris Platforms: at %d seats the couch layout is off" % n, mg._mp8_couch == Vector3.ZERO, mg._mp8_couch)
		return
	var off_oval: Array = []
	for p in mg.platforms:
		var g: Vector3 = p.global_position
		if absf(pow(g.x / 34.0, 2.0) + pow(g.z / 18.0, 2.0) - 1.0) > 0.01 or absf(g.y) > 0.01:
			off_oval.append(g)
	var lifts: int = mg.get_node("junk platform compactors").get_children().filter(func(c): return String(c.name).begins_with("MP8CompactorLift")).size()
	var stock_floor = mg.get_node_or_null("junk platform base collider blockout3/StaticBody3D/CollisionShape3D")
	ok("Debris Platforms: at %d seats the 8 decks on the 34 x 18 couch oval at one height, 8 compactors on lifts, the stock floor off" % n,
		mg._mp8_couch == Vector3(34.0, 18.0, 0.0) and mg.platforms.size() == 8 and off_oval.is_empty() and lifts == 8 and stock_floor != null and stock_floor.disabled,
		[mg._mp8_couch, off_oval, lifts, stock_floor.disabled if stock_floor != null else "no floor shape"])

# Debris Platforms' throw, measured: throw_rpc's impulse (update_interaction's 20 degrees up) at throw_power and
# four multiples. Fired from SKY above the arena, where nothing is in its way (scenery and players stop throws at
# deck height), from the grab position's height over its "deck". Logs where the rock comes down past the capsule's
# top (5), middle (2.5) and the deck, beside a stepped prediction.
const JUNK_CUBE := "res://minigames/junk_platform/components/junk_cube_rigidbody/junk_platform_cube_rigidbody.tscn"
const THROW_MULTS := [1.0, 1.25, 1.5, 1.75, 2.0]
const THROW_LIFT := 20.0
const THROW_SKY := Vector3(0.0, 300.0, 0.0)

func _measure_debris_throw(mg) -> void:
	ok("Debris Platforms throw test: play starts", await _wait(func(): return mg.junk_handler.active, 120.0))
	var thrower = mg.players.values()[0]
	var lift: float = thrower.grab_position.global_position.y - thrower.global_position.y
	var scene: PackedScene = load(JUNK_CUBE)
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var damp: float = float(ProjectSettings.get_setting("physics/3d/default_linear_damp"))
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var deck_y: float = THROW_SKY.y - lift
	say("throw test: grab position %.2f above the player, throw_power %.0f, gravity %.2f, default damp %.3f, %d ticks" % [
		lift, thrower.throw_power, g, damp, Engine.physics_ticks_per_second])
	var dir := Vector3(cos(deg_to_rad(THROW_LIFT)), sin(deg_to_rad(THROW_LIFT)), 0.0)
	for mult in THROW_MULTS:
		var power: float = thrower.throw_power * mult
		var cube: RigidBody3D = scene.instantiate()
		mg.add_child(cube)
		cube.global_position = THROW_SKY
		cube.freeze = false
		cube.linear_velocity = Vector3.ZERO
		cube.angular_velocity = Vector3.ZERO
		cube.apply_central_impulse(dir * power)
		var marks := {5.0: -1.0, 2.5: -1.0, 0.0: -1.0}
		var top := -INF
		var t := 0.0
		while t < 8.0:
			await get_tree().physics_frame
			t += dt
			var h: float = cube.global_position.y - deck_y
			top = maxf(top, h)
			for k in marks:
				if marks[k] < 0.0 and cube.linear_velocity.y < 0.0 and h <= k:
					marks[k] = cube.global_position.x - THROW_SKY.x
			if h <= -2.0:
				break
		cube.queue_free()
		var pred: Dictionary = _predict_throw(lift, power / cube.mass, g * cube.gravity_scale, damp + cube.linear_damp, dt)
		say("throw test: power %.0f (x%.2f), peak %.2f above the deck: down past 5 at %.1f, 2.5 at %.1f, the deck at %.1f; predicted %.1f / %.1f / %.1f" % [
			power, mult, top, marks[5.0], marks[2.5], marks[0.0], pred[5.0], pred[2.5], pred[0.0]])
		ok("Debris Platforms throw test: x%.2f lands within 0.5 of the prediction" % mult,
			marks[0.0] > 0.0 and absf(marks[0.0] - pred[0.0]) <= 0.5, [marks, pred])
		if mg.has_method("_mp8_throw_reach"):
			var game_pred: float = mg._mp8_throw_reach(lift, power / cube.mass, deg_to_rad(THROW_LIFT), g * cube.gravity_scale, damp + cube.linear_damp)
			ok("Debris Platforms throw test: x%.2f, the minigame's aim predicts the landing within 0.5" % mult,
				absf(marks[0.0] - game_pred) <= 0.5, [marks[0.0], game_pred])
			# The aim solves for the target's chest, 2.5 above its deck.
			var chest_pred: float = mg._mp8_throw_reach(lift - 2.5, power / cube.mass, deg_to_rad(THROW_LIFT), g * cube.gravity_scale, damp + cube.linear_damp)
			ok("Debris Platforms throw test: x%.2f, the minigame's aim predicts the chest-height crossing within 0.5" % mult,
				absf(marks[2.5] - chest_pred) <= 0.5, [marks[2.5], chest_pred])

# Godot Physics' rigid body step: gravity, then the damping factor, then the move.
static func _predict_throw(h0: float, speed: float, g: float, damp: float, dt: float) -> Dictionary:
	var v := Vector2(cos(deg_to_rad(THROW_LIFT)), sin(deg_to_rad(THROW_LIFT))) * speed
	var p := Vector2(0.0, h0)
	var out := {5.0: -1.0, 2.5: -1.0, 0.0: -1.0}
	for i in 2000:
		v.y -= g * dt
		v *= maxf(1.0 - damp * dt, 0.0)
		p += v * dt
		for k in out:
			if out[k] < 0.0 and v.y < 0.0 and p.y <= k:
				out[k] = p.x
		if p.y <= -2.0:
			break
	return out

# Aimed throws (D113): on at 5-8 seats, off at 4 (local; online at 5-8 is owed to the two-machine check). Every
# player finds the minigame among its ancestors. A throw from one end of the oval at the other is strengthened
# past stock, below the cap, to reach the target's chest; at 4 seats the same throw keeps stock. Needs play: only
# active players are targets.
func _check_debris_aim(mg, n: int) -> void:
	if not await _wait(func(): return mg.players.size() == n, 60.0):
		ok("Debris Platforms aim: the players are spawned", false, mg.players.size())
		return
	if not "_mp8_aim_on" in mg:
		ok("Debris Platforms: this build has aimed throws (0.20.0 or later)", false)
		return
	ok("Debris Platforms: at %d seats aimed throws are %s" % [n, "on" if n > 4 else "off"], mg._mp8_aim_on == (n > 4))
	ok("Debris Platforms: every player finds the minigame among its ancestors",
		mg.has_method("mp8_aimed_throw_power") and mg.players.values().all(func(p): return mg.is_ancestor_of(p) and "mp8_aim" in p))
	ok("Debris Platforms aim: play starts", await _wait(func(): return mg.junk_handler.active, 120.0))
	var alive: Array = mg.players.values().filter(func(p): return p.active)
	alive.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	if alive.size() < 2:
		ok("Debris Platforms aim: two players alive at the ends", false, alive.size())
		return
	var thrower = alive.front()
	var target = alive.back()
	var from: Vector3 = thrower.grab_position.global_position
	var flat := Vector3(target.global_position.x - from.x, 0.0, target.global_position.z - from.z)
	var dir: Vector3 = flat.normalized() * cos(deg_to_rad(THROW_LIFT)) + Vector3.UP * sin(deg_to_rad(THROW_LIFT))
	var rock: RigidBody3D = (load(JUNK_CUBE) as PackedScene).instantiate()
	var kept = thrower.held_item
	thrower.held_item = rock
	var power: float = mg.mp8_aimed_throw_power(thrower, dir, thrower.throw_power)
	thrower.held_item = kept
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * rock.gravity_scale
	var damp: float = float(ProjectSettings.get_setting("physics/3d/default_linear_damp")) + rock.linear_damp
	var drop: float = from.y - (target.global_position.y + 2.5)
	var reach: float = mg._mp8_throw_reach(drop, power / rock.mass, deg_to_rad(THROW_LIFT), g, damp)
	rock.free()
	var dist: float = Vector2(flat.x, flat.z).length()
	if n <= 4:
		ok("Debris Platforms aim: at %d seats %s at %s, %.1f apart, keeps stock" % [n, thrower.name, target.name, dist],
			power == thrower.throw_power, power)
		return
	ok("Debris Platforms aim: %s at %s, %.1f apart, gets more than stock and less than the cap, reaching their chest" % [thrower.name, target.name, dist],
		power > thrower.throw_power and power < thrower.throw_power * 1.75 and absf(reach - dist) < 0.5, [power, reach, dist])

# The second spider's look (D103): device 2 near black with the hourglass on its body bone, device 1
# neither. On a player's back the hourglass comes with the tint, is scaled to nothing while the back
# visual is hidden (bone 34's pose scale), and leaves with the white tint.
func _check_spider_look(mg, n: int) -> void:
	var consts: Dictionary = mg.get_script().get_script_constant_map()
	if not consts.has("MP8_DEVICE_MARK"):
		ok("Spine Breaker: this build has the second spider's hourglass (0.14.0 or later)", false)
		return
	var devs: Array = mg._mp8_devices
	var marks: Array = devs.map(func(d): return d.skeleton.get_node_or_null("MP8Mark"))
	if n < 6:
		ok("Spine Breaker: at %d seats one device, no hourglass" % n, devs.size() == 1 and marks[0] == null, marks)
		return
	var bodies: Array = []
	for d in devs:
		var mi = d.skeleton.get_children().filter(func(c): return c is MeshInstance3D and c.visible and c.mesh != null).front()
		bodies.append(mi.get_surface_override_material(0) if mi != null else null)
	var tint: Color = consts["MP8_DEVICE_TINT"][1]
	var m2 = marks[1]
	# As on every later round's mp8_ensure_devices_rpc: the body is already tinted, the hourglass keeps its own material.
	var repaint: int = mg._mp8_tint_device(devs[1], tint)
	ok("Spine Breaker: at %d seats device 2 tinted %s with one hourglass on its main body bone, a second tint paints nothing; device 1 untinted, none" % [n, tint],
		bodies[1] is StandardMaterial3D and bodies[1].albedo_color == tint and devs[1].mp8_tint == tint
			and m2 != null and m2.bone_name == "main body" and m2.get_child_count() == 1 and repaint == 0
			and bodies[0] == null and marks[0] == null and devs[0].mp8_tint == Color.WHITE,
		[bodies[1].albedo_color if bodies[1] is StandardMaterial3D else bodies[1], m2, repaint, bodies[0], marks[0]])
	var free_players: Array = mg.players.values().filter(func(p): return not p.has_spine_breaker)
	if free_players.is_empty():
		ok("Spine Breaker: a player without a device to try the back's hourglass on", false)
		return
	var p = free_players[0]
	var d2 = devs[1]
	p.mp8_set_visual_tint(d2.mp8_tint, d2.mp8_tex_key, d2.mp8_make_mark())
	var ba = p._mp8_back_mark
	for i in 3:
		await get_tree().process_frame
	var hidden: float = ba.get_child(0).global_basis.get_scale().length() if ba != null and ba.get_child_count() == 1 else -1.0
	var on_back: bool = ba != null and ba.get_parent() == p.skeleton_attached and ba.bone_name == "main body"
	p.mp8_set_visual_tint(Color.WHITE)
	var left: Array = p.skeleton_attached.get_children().filter(func(c): return String(c.name).begins_with("MP8Mark"))
	ok("Spine Breaker: the hourglass goes on %s's back on bone 34's main body, scaled to nothing while the back is hidden, and leaves with the white tint" % p.name,
		on_back and hidden >= 0.0 and hidden < 0.01 and p._mp8_back_mark == null and left.is_empty(),
		[on_back, hidden, left])

# The minigame built its 8-player layout: seats, markers, rooms, desks and devices counted, for n players (above 4).
# On 8 Player Support (0.2.0 or later) the MP8_PICKED_8P four are machine-party-8p's version; elsewhere all are Overtime's.
# Beside Overtime it refuses to mount (D51) though has_mod still reports it, so Overtime is checked first.
func _check_layout(mg, mg_name: String, n: int) -> void:
	if not is_instance_valid(mg):
		ok("%s: the minigame is there to count" % mg_name, false)
		return
	var on_mp8: bool = not _loader.has_mod("overtime") and _loader.has_mod("mp8_support")
	var want_8p: bool = on_mp8 and MP8_PICKED_8P.has(mg_name)
	if n <= 4:
		if want_8p and mg_name == "EscalatorPit":
			await _check_wrong_way_arms(mg, n, false)
		if on_mp8 and mg_name == "JunkPlatform":
			_check_debris_couch(mg, n)
			await _check_debris_aim(mg, n)
		if want_8p and mg_name == "ForkliftCertified":
			_check_forklift_yard(mg, n)
		if on_mp8 and mg_name == "BurnRecycle":
			_watch_filter_rounds(mg, n)
		if on_mp8 and mg_name == "GreenPea":
			await _check_table_catches(mg, n)
		if on_mp8 and mg_name == "SmokeBreak":
			await _check_smoke_toss(mg, n)
		if on_mp8 and mg_name == "ManufactureGun":
			await _check_bench_drop(mg)
		say("NOTE %s: %d players play the shipped layout; the layout counts skipped" % [mg_name, n])
		return
	match mg_name:
		"EscalatorPit":
			var xs: Array = mg.stair_handler.paths_parent.get_children().filter(func(c): return c is Path3D).map(func(c): return c.position.x)
			xs.sort()
			var gaps: Array = range(1, xs.size()).map(func(i): return snappedf(xs[i] - xs[i - 1], 0.01))
			if want_8p:
				var rail = mg.get_node_or_null("escalator pit art11/Plane_003")
				ok("Wrong Way 8p: 8 strips about 3.2 apart, 8 spawns, the handrails hidden",
					xs.size() == 8 and gaps.all(func(g): return absf(g - 3.2) < 0.1) and mg.player_spawn_positions.size() == 8 and rail != null and not rail.visible,
					[gaps, mg.player_spawn_positions.size(), rail.visible if rail != null else "no Plane_003"])
				await _check_wrong_way_arms(mg, n, true)
			else:
				ok("Wrong Way: Overtime's 8 lanes in pairs 12.8 apart, the survival belt",
					xs.size() == 8 and is_equal_approx(mg._mp8_step, 12.8) and mg._mp8_survival, [gaps, mg._mp8_step, mg._mp8_survival])
		"ForkliftCertified":
			ok("Forklift: the players are seated", await _wait(func(): return not mg._mp8_area_members.is_empty(), 60.0))
			var sizes: Array = mg._mp8_area_members.map(func(m): return m.size())
			var bays: int = mg.delivery_area_parent.get_child_count()
			if want_8p:
				ok("Forklift 8p: 8 bays, one player in each of %d" % n,
					bays == 8 and mg.delivery_areas.size() == 8 and sizes.count(1) == n and sizes.count(0) == 8 - n, [bays, mg.delivery_areas.size(), sizes])
				ok("Forklift 8p: crates in the centre cell, 10 at most", mg.crate_manager.mp8_spawn_region.has_area() and mg.crate_manager.mp8_crate_cap == 10,
					[mg.crate_manager.mp8_spawn_region, mg.crate_manager.mp8_crate_cap])
				_check_forklift_yard(mg, n)
			else:
				ok("Forklift: Overtime's 4 bays, teams of up to 2", bays == 4 and sizes.reduce(func(a, b): return a + b, 0) == n and sizes.max() == 2, [bays, sizes])
		"SpineBreaker":
			ok("Spine Breaker: the players are spawned", await _wait(func(): return mg.players.size() == n, 60.0), mg.players.size())
			var devices: int = mg._mp8_devices.size()
			ok("Spine Breaker: Overtime's %d devices at %d players" % [2 if n >= 6 else 1, n], devices == (2 if n >= 6 else 1), devices)
			if on_mp8:
				await _check_spider_look(mg, n)
		"JunkPlatform":
			var added: int = mg.player_spawn_position_node.get_children().filter(func(m): return String(m.name).ends_with("_MP8V")).size()
			ok("Debris Platforms: the players are spawned", await _wait(func(): return mg.players.size() == n, 60.0), mg.players.size())
			var decks := {}
			for p in mg.players.values():
				var k: int = mg._mp8_nearest_platform(p.global_position)
				decks[k] = int(decks.get(k, 0)) + 1
			ok("Debris Platforms: Overtime's 8 platforms, one player on each", mg.platforms.size() == 8 and added == 0 and decks.size() == n and decks.values().max() == 1,
				[mg.platforms.size(), added, decks])
			if on_mp8:
				_check_debris_couch(mg, n)
				await _check_debris_aim(mg, n)
		"BurnRecycle":
			ok("The Filter: the players are spawned", await _wait(func(): return mg.players.size() == n, 60.0), mg.players.size())
			var in_b: int = mg.players.values().filter(func(p): return p.global_position.z > 100.0).size()
			ok("The Filter: Overtime's one ring of %d stations" % mg.mp8_seats, mg.mp8_seats == 8 and in_b == 0 and mg.get_node_or_null("RoomB_MP8V") == null,
				[mg.mp8_seats, in_b])
			if on_mp8:
				_watch_filter_rounds(mg, n)
				_check_filter_stations(mg, n)
		"DuckHunt":
			ok("Duck Hunt: the hunters are spawned", await _wait(func(): return not mg.hunter_players.is_empty(), 60.0))
			var hunters: int = mg.hunter_players.size()
			var ducks: int = mg.duck_players.size()
			ok("Duck Hunt: Overtime's %d hunters" % (2 if n >= 6 else 1), hunters == (2 if n >= 6 else 1) and ducks == n - hunters, [hunters, ducks])
		"ManufactureGun":
			ok("Firearm Factory: desks and items are out", await _wait(func(): return mg.workstations.size() == n and mg.items.size() > 0, 60.0), [mg.workstations.size(), mg.items.size()])
			var desks: Node = mg.get_node("WorkstationSpawns")
			var gun = mg.player_characters.values()[0] if not mg.player_characters.is_empty() else null
			if want_8p:
				ok("Firearm Factory 8p: 2 of each ingredient (52)", mg.items.size() == 52, mg.items.size())
				await _check_bench_layout(mg, n)
				ok("Firearm Factory 8p: the vanilla gun (3.0 s, full size)", gun != null and is_equal_approx(gun.shoot_cooldown, 3.0) and is_equal_approx(gun.gun_shot_area.scale.x, 1.0),
					[gun.shoot_cooldown if gun != null else null])
			else:
				ok("Firearm Factory: Overtime's ring and its weakened gun at %d" % n,
					desks.get_node_or_null("Marker3D5_MP8V") == null and gun != null and gun.shoot_cooldown > 3.0,
					[desks.get_child_count(), mg.items.size(), gun.shoot_cooldown if gun != null else null])
			if on_mp8:
				await _check_bench_drop(mg)
		"ChiselGauntlet":
			ok("Chisel Gauntlet: the players are spawned", await _wait(func(): return mg.players.size() == n, 60.0), mg.players.size())
			var art: Node = mg.get_node("chisel gauntlet art2")
			var barrels: bool = art.get_node("walls/barrel_001").visible and art.get_node("walls/barrel_002").visible
			var holes: bool = art.has_node("control panel hole mesh_MP8V") and art.has_node("control panel hole wires_MP8V")
			ok("Chisel Gauntlet: Overtime's sweep over the %d seats, its own markers and dressing" % n,
				mg.shotgun_check_order.size() == n and not mg.spectate_position_parent.has_node("Marker3D_MP8V") and not holes and barrels,
				[mg.shotgun_check_order, holes, barrels])
		"GreenPea":
			var markers: Node = mg.player_spawn_positions
			var walls: Node = mg.get_node("pea dinner scene4/walls")
			var chairs := func() -> Array: return walls.get_children().filter(func(c): return String(c.name).begins_with("chair player") and c.visible)
			ok("Table Manners: the players are spawned", await _wait(func(): return mg.player_characters.size() == n, 60.0), mg.player_characters.size())
			ok("Table Manners: Overtime's seats and chairs, the camera as shipped",
				not markers.has_node("Marker3D_MOD5_MP8V") and chairs.call().size() == 4 and not is_equal_approx(mg.camera.fov, 50.0),
				[markers.get_child_count(), chairs.call().size(), mg.camera.fov])
			ok("Table Manners: the coach has a shot and a blood set for all 8 seats",
				mg.coach_handler.coach.mp8_anim_by_seat.size() == 8 and mg.coach_handler.coach.decals_by_seat_index.size() == 8,
				[mg.coach_handler.coach.mp8_anim_by_seat, mg.coach_handler.coach.decals_by_seat_index.size()])
			if on_mp8:
				await _check_table_catches(mg, n)
		"KnifeAtTheOffice":
			ok("Inside Job: the players are spawned", await _wait(func(): return mg.players.size() == n, 60.0), mg.players.size())
			var spawns: Node = mg.player_spawn_positions_node
			var added: int = spawns.get_children().filter(func(m): return String(m.name).ends_with("_MP8V")).size()
			if want_8p:
				ok("Inside Job 8p rules: the search target stops 2 short of the reachable count, and never below 1",
					mg._mp8v_clamp_target(46, 34) == 32 and mg._mp8v_clamp_target(20, 34) == 20 and mg._mp8v_clamp_target(5, 2) == 1)
				ok("Inside Job 8p: 8 markers (4 added)", spawns.get_child_count() == 8 and added == 4, [spawns.get_child_count(), added])
				ok("Inside Job 8p: the find comes at most 2 before the last reachable container",
					mg.guaranteed_search_result >= 1 and mg.guaranteed_search_result <= mg.searchables.size() - 2, [mg.guaranteed_search_result, mg.searchables.size()])
			else:
				ok("Inside Job: Overtime's spawns, 2 syringes, survivor +2", added == 0 and mg.mp8_syringes_needed == 2 and mg.mp8_survivor_bonus == 2,
					[added, mg.mp8_syringes_needed, mg.mp8_survivor_bonus])
		"SmokeBreak":
			var trolley = mg._mp8_find_trolley()
			ok("Smoke Break: Overtime's %d seats" % n, mg.player_spawn_positions.size() == n
				and trolley != null and trolley.rot_by_seat_index_array.size() == n, [mg.player_spawn_positions.size()])
			if on_mp8:
				await _check_smoke_toss(mg, n)

# PD13: every seat's finished cigarette plays a toss look; seats 5-8 the look of the original seat
# nearest them, worked out here from the seats' positions, not from the code's own pick.
func _check_smoke_toss(mg, n: int) -> void:
	if not await _wait(func(): return mg.active_players.size() == n, 60.0):
		ok("Smoke Break: the players are seated, to finish their cigarettes", false, mg.active_players.size())
		return
	const LOOKS := ["finish_look_left", "finish_look_right", "finish_look_right", "finish_look_left"]
	var got := []
	var wrong := []
	for i in n:
		var p = mg.active_players[i]
		var nearest := 0
		for k in mini(4, mg.player_spawn_positions.size()):
			if p.global_position.distance_to(mg.player_spawn_positions[k].global_position) < p.global_position.distance_to(mg.player_spawn_positions[nearest].global_position):
				nearest = k
		var want: String = LOOKS[i] if i < 4 else LOOKS[nearest]
		p.anim_handler.cigarette_finished(i)
		var playing: String = p.anim_handler.anim_player.current_animation
		got.append("%d:%s" % [i + 1, playing])
		if playing != want:
			wrong.append("%d wants %s" % [i + 1, want])
	ok("Smoke Break: every seat's finish plays its toss look (%d seats)" % n, wrong.is_empty(), [got, wrong])

# D128, the owner's bench layout at 5-8, as picked from in-game renders: [x, z, yaw] in seat order, the 6 layout for
# 5-6 players and the 8 layout for 7-8, the unused far-right corner keeping one empty desk. The room loses three
# props and their collision, the right wall's pipe run goes up over the lamps (D133), and the recipe hologram stays down.
const FF_BENCHES_6 := [[-8.00, -7.50, 0.0], [-8.00, 7.50, 0.0], [1.75, -10.70, 90.0], [1.75, 10.70, 90.0], [11.75, -8.00, 0.0], [11.75, 8.00, 0.0]]
const FF_BENCHES_8 := [[-7.75, -7.75, 0.0], [-7.75, 7.75, 0.0], [-1.50, -10.70, 90.0], [-1.50, 10.70, 90.0], [5.50, -10.70, 90.0], [5.50, 10.70, 90.0], [11.75, -8.00, 0.0], [11.75, 8.00, 0.0]]
const FF_GONE := ["manufacture gun artwork pass2/desk left", "manufacture gun artwork pass2/desk trolley", "manufacture gun artwork pass2/pallet"]
const FF_GONE_SHAPES := ["Colliders/StaticBody3D/CollisionShape3D2", "Colliders/StaticBody3D/CollisionShape3D4", "Colliders/StaticBody3D2/CollisionShape3D", "Colliders/StaticBody3D2/CollisionShape3D3"]
const FF_LAMP_Y := -6.01142   # the workstation scene's lamp, under its lamp parent
const FF_PIPES := ["manufacture gun artwork pass2/pipe wall", "manufacture gun artwork pass2/pipe wall mount", "manufacture gun artwork pass2/pipe wall mount_001", "manufacture gun artwork pass2/pipe wall mount_002"]

func _check_bench_layout(mg, n: int) -> void:
	var lay: Array = FF_BENCHES_6 if n <= 6 else FF_BENCHES_8
	await get_tree().physics_frame
	await get_tree().process_frame
	var off := []
	for i in mg.workstations.size():
		var w: Node3D = mg.workstations[i]
		var e: Array = lay[i]
		if Vector2(w.global_position.x - e[0], w.global_position.z - e[1]).length() > 0.05 or absf(absf(w.rotation_degrees.y) - absf(e[2])) > 1.0:
			off.append("%d at %s yaw %.0f" % [i + 1, w.global_position, w.rotation_degrees.y])
	ok("Firearm Factory 8p: %d benches at the picked %d layout's spots" % [n, lay.size()], mg.workstations.size() == n and off.is_empty(), off)
	var empties: Array = mg.empty_desk_array.filter(func(d): return d != null and is_instance_valid(d) and not d.is_queued_for_deletion())
	var want_empty: bool = n < lay.size()
	var corner_ok: bool = not want_empty or (empties.size() == 1 and Vector2(empties[0].global_position.x - 11.75, empties[0].global_position.z - 8.0).length() < 0.05)
	ok("Firearm Factory 8p: %s" % ("one empty desk, in the far-right corner" if want_empty else "no empty desk"),
		empties.size() == (1 if want_empty else 0) and corner_ok, empties.map(func(d): return d.global_position))
	var props_left: Array = FF_GONE.filter(func(p): return mg.get_node(p).visible)
	var shapes_left: Array = FF_GONE_SHAPES.filter(func(p): return not mg.get_node(p).disabled)
	ok("Firearm Factory 8p: the two side desks and the pallet are gone, with their collision", props_left.is_empty() and shapes_left.is_empty(), [props_left, shapes_left])
	var lamps := []
	for w in mg.workstations:
		var lamp: Node3D = w.get_node("workstation lamp parent/workstation lamp")
		if absf(lamp.position.y - FF_LAMP_Y) > 0.01:
			lamps.append([w.global_position, lamp.position.y])
	ok("Firearm Factory 8p: every bench's lamp at the game's height", lamps.is_empty(), lamps)
	# The shade mesh's AABB runs up its cord, so only its bottom is read; its node sits at the shade's top.
	var clash := []
	for w in mg.workstations:
		var shade: MeshInstance3D = w.get_node("workstation lamp parent/workstation lamp/workstation_lamp")
		var sb: AABB = shade.global_transform * shade.get_aabb()
		var holo_top := -INF
		for m in w.get_node("local_recipe_item_preview").get_children():
			if m is MeshInstance3D:
				holo_top = maxf(holo_top, (m.global_transform * m.get_aabb()).end.y)
		if holo_top == -INF:
			clash.append([w.global_position, "no hologram mesh"])
		elif sb.position.y <= holo_top:
			clash.append([w.global_position, "hologram", snappedf(sb.position.y, 0.01), snappedf(holo_top, 0.01)])
		var shade_xz := Rect2(sb.position.x, sb.position.z, sb.size.x, sb.size.z)
		for path in FF_PIPES:
			var pipe: MeshInstance3D = mg.get_node(path)
			var pb: AABB = pipe.global_transform * pipe.get_aabb()
			if Rect2(pb.position.x, pb.position.z, pb.size.x, pb.size.z).intersects(shade_xz) and pb.position.y <= shade.global_position.y:
				clash.append([w.global_position, path.get_file(), snappedf(pb.position.y, 0.01), snappedf(shade.global_position.y, 0.01)])
	ok("Firearm Factory 8p: every lamp's shade clears its recipe hologram below and the wall's pipes above", clash.is_empty(), clash)
	var holo: Node3D = mg.item_sequence_preview_node_parent.get_parent()
	ok("Firearm Factory 8p: the recipe hologram at the game's height", is_zero_approx(holo.position.y), holo.position.y)
	var spots := {"part_010": [[0.72, -8.75], [0.72, -8.75]], "part_013": [[5.46, 10.53], [4.46, 8.78]], "part_014": [[2.98, 8.77], [2.98, 8.77]]}
	var parts := []
	for part in spots:
		var m: Node3D = mg.get_node("ItemSpawner/ItemSpawns/" + part)
		var at: Array = spots[part][0 if n <= 6 else 1]
		if not is_zero_approx(m.global_position.y) or Vector2(m.global_position.x - at[0], m.global_position.z - at[1]).length() > 0.05:
			parts.append([part, m.global_position])
	ok("Firearm Factory 8p: the desk tops' three part spots are on the floor in front of the side benches", parts.is_empty(), parts)
	var spawns: Array = mg.get_node("SpawnPositions").get_children()
	var far := []
	for i in n:
		var d: float = Vector2(spawns[i].global_position.x - lay[i][0], spawns[i].global_position.z - lay[i][1]).length()
		if absf(d - 3.5) > 0.05:
			far.append([i + 1, snappedf(d, 0.01)])
	ok("Firearm Factory 8p: every spawn 3.5 m from its own bench", spawns.size() >= n and far.is_empty(), far)
	# A spawn faces its own bench along -Z, as the game's own spawn markers face theirs.
	var turned := []
	for i in n:
		var ahead: Vector3 = -spawns[i].global_basis.z
		var to_bench := Vector2(lay[i][0] - spawns[i].global_position.x, lay[i][1] - spawns[i].global_position.z)
		var angle: float = rad_to_deg(absf(Vector2(ahead.x, ahead.z).angle_to(to_bench)))
		if angle > 5.0:
			turned.append([i + 1, snappedf(angle, 0.1)])
	ok("Firearm Factory 8p: every spawn faces its own bench", turned.is_empty(), turned)
	var nearest := []
	for w in mg.workstations:
		var d := INF
		for o in mg.workstations:
			if o != w:
				d = minf(d, Vector2(w.global_position.x - o.global_position.x, w.global_position.z - o.global_position.z).length())
		nearest.append(d)
	var want_gap: float = 10.2 if n <= 6 else 6.8
	ok("Firearm Factory 8p: no bench nearer than %.1f m to another" % want_gap, nearest.min() >= want_gap, nearest.map(func(d): return snappedf(d, 0.01)))
	# The start-of-game stuck check runs two physics frames after the spawns; nobody moves before play starts.
	await get_tree().create_timer(0.5).timeout
	var moved := []
	for i in mg.workstations.size():
		var nid: int = mg.workstations[i].player_presence.network_id
		var pc: Node3D = mg.player_characters.get(nid)
		if pc != null and Vector2(pc.global_position.x - spawns[i].global_position.x, pc.global_position.z - spawns[i].global_position.z).length() > 0.3:
			moved.append([i + 1, pc.global_position])
	ok("Firearm Factory 8p: every player starts on their own spawn (the stuck check moves nobody)", moved.is_empty(), moved)

# PD14: the drop's ray (Dropcast: 2.5 up, straight down, mask 3) over another player's bench meets that bench's
# body and the drop is refused; over your own bench and beside the other one it isn't.
func _check_bench_drop(mg) -> void:
	if not await _wait(func(): return mg.workstations.size() >= 2 and mg.workstations.all(func(w): return w.player_presence != null), 60.0):
		ok("Firearm Factory: two owned benches to drop on", false, mg.workstations.size())
		return
	var P: GDScript = load("res://minigames/manufacture_gun/components/player/scripts/manufacture_gun_player.gd")
	var mine: Node3D = mg.workstations[0]
	var theirs: Node3D = mg.workstations[1]
	var me: int = mine.player_presence.network_id
	await get_tree().physics_frame
	var space := mine.get_world_3d().direct_space_state
	var on_theirs = _down_hit(space, theirs.global_transform * Vector3(0, 2.5, 0))
	var on_mine = _down_hit(space, mine.global_transform * Vector3(0, 2.5, 0))
	var beside = _down_hit(space, theirs.global_transform * Vector3(2.5, 2.5, 0))
	ok("Firearm Factory: over another player's bench the ray meets it, and the drop is refused",
		on_theirs != null and on_theirs.get_parent() == theirs and P.mp8_lands_on_other_bench(on_theirs, me), on_theirs)
	ok("Firearm Factory: over your own bench the drop isn't refused", on_mine != null and not P.mp8_lands_on_other_bench(on_mine, me), on_mine)
	ok("Firearm Factory: beside another player's bench the floor takes the part", beside != null and not P.mp8_lands_on_other_bench(beside, me), beside)

func _down_hit(space: PhysicsDirectSpaceState3D, from: Vector3):
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -10, 0), 3))
	return hit.get("collider")

# Table Manners' catches (D107, D114) on forced glances once the round plays. A round of 6 or more catches two
# a glance to its end: each is frozen at its press and nobody is shot until the second press or the glance's end,
# then both fall in catch order MP8_NEXT_SHOT (1.6 s) apart. At 1-5, the game's instant shot of the first press only.
# Runs once per launch: a headless catches=1 launch would otherwise start it from both paths.
func _check_table_catches(mg, n: int) -> void:
	if _catches_running:
		return
	_catches_running = true
	if not await _wait(func(): return mg.player_characters.size() == n and mg.player_characters.values().all(func(p): return p.active), 90.0):
		ok("Table Manners: the round starts, to force the coach's glances", false, mg.player_characters.size())
		return
	if n >= 6:
		await _table_single_catch(mg)
		await _table_double_catch(mg)
		await _table_double_late(mg)
	else:
		await _table_instant_catch(mg)

func _table_single_catch(mg) -> void:
	var g: Dictionary = await _table_glance(mg, 1.0, 1, true)
	if not g["ok"]:
		ok("Table Manners: a glance to force for one catch", false, g)
		return
	ok("Table Manners: one catch at %d still eating waits frozen, the coach still looking" % g["eating"],
		g["paused1"] and not g["exec1"] and not g["reading1"], g)
	var deaths: Array = await _table_deaths(mg, 2, 5.0)
	var after: float = (deaths[0][1] - g["t0"]) / 1000.0 if deaths.size() > 0 else -1.0
	ok("Table Manners: the one catch is shot alone when the glance ends (%.2f s after the press; the game's instant shot is 2.0 s)" % after,
		deaths.map(func(d): return d[0]) == g["ids"] and after > 2.6 and after < 3.6, [deaths, g["ids"]])

func _table_double_catch(mg) -> void:
	if mg.active_players.size() < 3:
		say("NOTE Table Manners: %d still eating, the double-catch check skipped" % mg.active_players.size())
		return
	var g: Dictionary = await _table_glance(mg, 3.0, 3, false)
	if not g["ok"]:
		ok("Table Manners: a glance to force for two catches", false, g)
		return
	ok("Table Manners: at %d still eating the first catch is frozen, the coach still looking, and the second frozen too" % g["eating"],
		g["paused1"] and not g["exec1"] and not g["reading1"] and g["paused2"], g)
	var deaths: Array = await _table_deaths(mg, 3, 7.0)
	var gap: float = (deaths[1][1] - deaths[0][1]) / 1000.0 if deaths.size() > 1 else -1.0
	ok("Table Manners: two caught in one glance and shot in catch order, the third press ignored",
		deaths.map(func(d): return d[0]) == g["ids"].slice(0, 2), [deaths, g["ids"]])
	ok("Table Manners: the second shot %.2f s after the first (1.6 s)" % gap, absf(gap - 1.6) < 0.25, deaths)
	var h = mg.coach_handler
	ok("Table Manners: the coach reads again after the two shots", await _wait(func(): return h.reading and not h.executing, 8.0),
		[h.reading, h.executing])
	ok("Table Manners: the third press's player eats again", await _wait(func(): return not mg.player_characters[g["ids"][2]].is_player_being_executed, 4.0))

# The limit is the round's start, not who is still eating (the owner's pick): with the rest marked finished down
# to 3 still eating, a glance still catches two and shoots both. Shot players already don't eat, so only the rest need marking.
func _table_double_late(mg) -> void:
	var eating: Array = mg.player_characters.values().filter(_table_still_eating)
	if eating.size() < 3:
		say("NOTE Table Manners: %d still eating, the late double-catch check skipped" % eating.size())
		return
	var marked: Array = eating.slice(3)
	for p in marked:
		p.is_finished = true
	var g: Dictionary = await _table_glance(mg, 3.0, 2, false)
	var still: int = mg.player_characters.values().filter(_table_still_eating).size()
	var deaths: Array = await _table_deaths(mg, 2, 6.0) if g["ok"] else []
	# The marks never left active_players, so unmarked they play on and the match can still end.
	for p in marked:
		if is_instance_valid(p):
			p.is_finished = false
	if not g["ok"]:
		ok("Table Manners: a glance to force late in the round", false, g)
		return
	ok("Table Manners: %d still eating of %d seated: both catches frozen and shot in catch order" % [still, mg.player_characters.size()],
		g["paused1"] and g["paused2"] and deaths.map(func(d): return d[0]) == g["ids"], [g, deaths])

func _table_still_eating(p) -> bool:
	return is_instance_valid(p) and not p.is_dead and not p.is_finished

func _table_instant_catch(mg) -> void:
	var g: Dictionary = await _table_glance(mg, 3.0, 2, false)
	if not g["ok"]:
		ok("Table Manners: a glance to force for the game's catch", false, g)
		return
	var deaths: Array = await _table_deaths(mg, 2, 4.0)
	ok("Table Manners: at %d still eating the game's catch, the first press shot at once and alone" % g["eating"],
		g["exec1"] and deaths.map(func(d): return d[0]) == g["ids"].slice(0, 1), [g, deaths])

# Forces a glance of `seconds` from the coach's reading, then presses for `presses` players still eating, all
# in that one frame, so no bot slips in between. `hold` keeps every other player still for the glance, as the
# coach's pause does. Returns the pressers in order and what the first press left.
func _table_glance(mg, seconds: float, presses: int, hold: bool) -> Dictionary:
	var h = mg.coach_handler
	var out := {"ok": false}
	if not await _wait(_table_glance_ready.bind(mg, presses), 30.0):
		out["why"] = "the coach never read with time left and %d free to press" % presses
		return out
	var who: Array = mg.player_characters.values().filter(_table_can_press).slice(0, presses)
	if hold:
		for p in mg.player_characters.values():
			if is_instance_valid(p) and not who.has(p):
				p.is_player_being_executed = true
	out["eating"] = mg.active_players.size()
	h.stop_reading_rpc.rpc()
	h.reading = false
	h.timer.start(seconds)
	out["t0"] = Time.get_ticks_msec()
	out["ids"] = who.map(func(p): return p.player_presence.network_id)
	for i in who.size():
		who[i].try_fork_plate_rpc.rpc()
		if i == 0:
			out["exec1"] = h.executing
			out["reading1"] = h.reading
			out["paused1"] = who[0].is_player_being_executed
		elif i == 1:
			out["paused2"] = who[1].is_player_being_executed
	out["ok"] = true
	return out

# The coach reading with time left, and enough players free to press: after a shot they thaw over about 1.7 s.
func _table_glance_ready(mg, presses: int) -> bool:
	var h = mg.coach_handler
	return h.reading and not h.executing and not h.timer.is_stopped() and h.timer.time_left > 0.3 \
		and mg.player_characters.values().filter(_table_can_press).size() >= presses

func _table_can_press(p) -> bool:
	return is_instance_valid(p) and p.active and not p.is_dead and not p.is_finished and not p.is_currently_eating and not p.is_player_being_executed

# Up to k more shot players within `seconds`, as [network id, ms] in the order they fell.
func _table_deaths(mg, k: int, seconds: float) -> Array:
	var start: int = mg._mp8_dead_order.size()
	var out: Array = []
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while out.size() < k and Time.get_ticks_msec() < end:
		await get_tree().process_frame
		while mg._mp8_dead_order.size() > start + out.size():
			out.append([mg._mp8_dead_order[start + out.size()], Time.get_ticks_msec()])
	return out

# The Filter's rounds (D105), over a whole match: run unattended (auto=2) to see one. Each round's pick is read
# right after the game makes it, on the server, before the crushes zero the victims' counts: above 4 players
# mp8_elim_slots says how many go out; at 4 or fewer one, as the game. Fewer out only on a tie at the cut.
func _watch_filter_rounds(mg, n: int) -> void:
	if mg.get("_mp8_rounds_played") == null:
		say("NOTE The Filter: no _mp8_rounds_played in this build; the round checks skipped")
		return
	var rounds: Array = []
	mg.player_item_queues_cleared.connect(_on_filter_pick.bind(mg, n, rounds))
	mg.player_scores_finalized.connect(_on_filter_scores.bind(n, rounds))

# One round's pick: rounds holds [slots, out] per round so far, shared with _on_filter_scores.
func _on_filter_pick(mg, n: int, rounds: Array) -> void:
	var out: Array = mg.dead_players.slice(rounds.reduce(func(a, r): return a + r[1], 0))
	var scores := {}
	for id in mg.active_players.keys():
		scores[id] = mg.active_players[id].valid_burns + mg.active_players[id].valid_recycles
	var played: int = mg._mp8_rounds_played if n > 4 else rounds.size() + 1
	var slots: int = mg.mp8_elim_slots(scores.size(), played - 1) if n > 4 else 1
	var rest: Array = scores.keys().filter(func(id): return not out.has(id))
	var low_out: int = out.map(func(id): return scores[id]).max() if not out.is_empty() else -1
	var low_rest: int = rest.map(func(id): return scores[id]).min() if not rest.is_empty() else 1 << 30
	var tied_cut: bool = low_rest > 0 and rest.filter(func(id): return scores[id] == low_rest).size() > slots - out.size()
	ok("The Filter round %d at %d: %d of %d slots out, none above a survivor%s" % [rounds.size() + 1, n, out.size(), slots,
		"" if out.size() == slots else ", a tie at the cut"],
		out.size() <= slots and low_out <= low_rest and (out.size() == slots or tied_cut), [out, scores])
	rounds.append([slots, out.size()])
	if n > 4:
		for i in out.size():
			_check_filter_aim(mg, out[i], 1.3 + 3.0 * i)
		if out.size() > 1:
			_check_filter_turn(mg)

func _on_filter_scores(player_scores: Dictionary, n: int, rounds: Array) -> void:
	var pts: Array = player_scores.values()
	pts.sort()
	var want: Array = range(n - 1)
	want.append(n)
	var ties: int = rounds.filter(func(r): return r[1] < r[0]).size()
	ok("The Filter at %d: %d rounds (%d with fewer out on a tie), [slots, out] %s" % [n, rounds.size(), ties, rounds],
		ties > 0 or rounds.size() == (4 if n > 4 else n - 1), rounds)
	ok("The Filter at %d: placements distinct, the survivor at %d" % [n, n], pts == want, pts)

# The Filter's aimed looks above 4 seats (D105): once every view has turned to a victim (1.07 s after its camera
# call: at the pick, then 3 s apart), its console top is near the middle of every other player's camera.
func _check_filter_aim(mg, victim: int, wait: float) -> void:
	var players: Array = mg.player_parent_node.get_children().filter(func(c): return c.get("camera") is Camera3D)
	var target = mg.players.get(victim)
	if players.is_empty() or target == null:
		ok("The Filter: the first victim and the views are there to check the aim", false, [victim, players.size()])
		return
	# Before 0.16.0 the build has no aim point; the same 2.6 m is used, so an older build fails here.
	var tweened: bool = target.has_method("_mp8_tween_look")
	var height: float = target.MP8_LOOK_HEIGHT if tweened else 2.6
	var point: Vector3 = target.global_transform * Vector3(0.0, height, mg.mp8_station_radial())
	await get_tree().create_timer(wait).timeout
	var off: Array = []
	for p in players:
		if p == target or not is_instance_valid(p):
			continue
		var cam: Camera3D = p.camera
		var size: Vector2 = cam.get_viewport().get_visible_rect().size
		var at: Vector2 = cam.unproject_position(point) / size
		if cam.is_position_behind(point) or absf(at.x - 0.5) > 0.12 or absf(at.y - 0.5) > 0.12:
			off.append("seat %d sees it at (%.2f, %.2f)%s" % [p.active_seat_index, at.x, at.y, " behind" if cam.is_position_behind(point) else ""])
	ok("The Filter: %d views aimed at seat %d's console" % [players.size() - 1, target.active_seat_index], off.is_empty(), off)
	# The victim's own view holds "look self"'s pose and zoom, sampled where the build samples it.
	var a: Animation = target.anim_camera_movement.get_animation("look self")
	var held: float = target.MP8_LOOK_HELD if tweened else 2.4
	var want_rot: Vector3 = a.value_track_interpolate(a.find_track(^"camera parent/camera sub parent:rotation", Animation.TYPE_VALUE), held)
	var want_fov: float = a.value_track_interpolate(a.find_track(^"camera parent/camera sub parent/Camera3D:fov", Animation.TYPE_VALUE), held)
	var rot: Vector3 = target.camera.get_parent().rotation
	var fov: float = target.camera.fov
	var d: Vector3 = (rot - want_rot).abs()
	ok("The Filter: seat %d's own view holds look self's pose and zoom" % target.active_seat_index,
		maxf(d.x, maxf(d.y, d.z)) < 0.05 and absf(fov - want_fov) < 0.5, [rot, want_rot, fov, want_fov])

# Every station the same above 4 seats (D132): a frame at each of the 8 seats, each in the same place against its
# seat's press, no other frame's housing through its pusher, and no belt or last slot on another seat's belt; on the
# couch a light of its own at each seat, all alike; and at 7-8 each narrow tile's view shifted.
func _check_filter_stations(mg, n: int) -> void:
	var presses: Array = mg.presses.filter(func(p): return p != null)
	var root: Node = mg.find_child("burn recycle visuals final", true, false)
	var frames: Array = [] if root == null else root.get_children().filter(
		func(c): return c is Node3D and c.visible and String(c.name).begins_with("conveyor control panel main parent"))
	var frame_at: Array = frames.map(func(f): return _filter_mesh_centre(f))
	ok("The Filter at %d: a frame at each of the 8 seats, alike" % n, _filter_one_per_press(frame_at, presses),
		[frames.size(), presses.size()])
	# Uncut, a frame's housing runs on to the outer wall, through the next added seat's pusher (_mp8_cut_housing).
	var crossed: Array = []
	var housings: int = frames.reduce(func(k, f): return k + f.find_children("conveyor frame*", "MeshInstance3D", true, false).size(), 0)
	for p in mg.players.values():
		var inv: Transform3D = p.global_transform.affine_inverse()
		# Its own frame is the one whose static piston sits on the player's own.
		var at: Vector3 = _filter_mesh_centre(p.piston)
		var own = null
		var own_d: float = INF
		for f in frames:
			for m in f.find_children("piston*", "MeshInstance3D", true, false):
				var d: float = _filter_mesh_centre(m).distance_to(at)
				if d < own_d:
					own_d = d
					own = f
		for f in frames:
			if f == own:
				continue
			for h in f.find_children("conveyor frame*", "MeshInstance3D", true, false):
				if _filter_tris_hit(h, inv, FILTER_PUSHER_ZONE):
					crossed.append("seat %d: %s" % [p.active_seat_index, f.name])
	ok("The Filter at %d: no other station's housing through a seat's pusher" % n,
		crossed.is_empty() and housings == 8 and mg.players.size() == n, [housings, mg.players.size(), crossed])
	# A conveyor's tail at 45 degrees reaches the next seat: its belt, in the same plane, flashes against that seat's,
	# and its last slot lands on that seat's belt (MP8_SLOT_COUNT).
	var belts: Array = mg.belts.filter(func(b): return b != null and b.mesh != null)
	var overlaps: Array = []
	for i in belts.size():
		for j in range(i + 1, belts.size()):
			if _filter_tris_hit(belts[i], belts[j].global_transform.affine_inverse(), belts[j].mesh.get_aabb()):
				overlaps.append("%s / %s" % [belts[i].name, belts[j].name])
	ok("The Filter at %d: no two stations' belts overlap" % n, overlaps.size() == 0 and belts.size() == 8, [belts.size(), overlaps])
	var landed: Array = []
	for p in mg.players.values():
		var end: Vector3 = p.item_positions[-1].global_position
		for b in belts:
			if b != p.active_belt and b.mesh.get_aabb().grow(0.3).has_point(b.global_transform.affine_inverse() * end):
				landed.append("seat %d on %s" % [p.active_seat_index, b.name])
	ok("The Filter at %d: every seat's last slot is off the other seats' belts" % n, landed.is_empty(), landed)
	if GameManager.local_game:
		# The room's own lights (the minigame's children and the clientside set), not the players' penalty lights.
		var lights: Array = (mg.get_children() + mg.clientside_visuals_parent.get_children()).filter(
			func(l): return l is OmniLight3D and l.is_visible_in_tree() and Vector2(l.global_position.x, l.global_position.z).length() > 5.0)
		var energies: Array = lights.map(func(l): return snappedf(l.light_energy, 0.01))
		ok("The Filter at %d: a station light at each of the 8 seats, alike" % n,
			_filter_one_per_press(lights.map(func(l): return l.global_position), presses) and energies.all(func(e): return e == energies[0]),
			[lights.size(), energies])
		var want: float = 1.2 if n >= 7 else 0.0
		var shifts: Array = mg.players.values().map(func(p): return p.local_camera.h_offset)
		ok("The Filter at %d: every tile's view shifted %.1f" % [n, want], shifts.all(func(h): return is_equal_approx(h, want)), shifts)

# The pusher at rest and at full stroke, in the player's frame: the piston mesh, and its 0.747 m stroke along its
# parent's x, which the scene turns inward and up (0.665 m in, 0.34 m up).
const FILTER_PUSHER_ZONE := AABB(Vector3(-0.63, 2.17, 5.17), Vector3(1.26, 1.27, 1.82))

# Whether any of the mesh's triangles, taken into `inv`'s frame, meets the box: an edge through it, or a box
# diagonal through the triangle (a large face spanning the box).
func _filter_tris_hit(m: MeshInstance3D, inv: Transform3D, box: AABB) -> bool:
	var t: Transform3D = inv * m.global_transform
	var faces: PackedVector3Array = m.mesh.get_faces()
	var diag: Array = [[box.position, box.end], [box.get_endpoint(1), box.get_endpoint(6)],
		[box.get_endpoint(2), box.get_endpoint(5)], [box.get_endpoint(3), box.get_endpoint(4)]]
	for i in range(0, faces.size() - 2, 3):
		var a: Vector3 = t * faces[i]
		var b: Vector3 = t * faces[i + 1]
		var c: Vector3 = t * faces[i + 2]
		if not AABB(a, Vector3.ZERO).expand(b).expand(c).intersects(box):
			continue
		if box.has_point(a) or box.intersects_segment(a, b) or box.intersects_segment(b, c) or box.intersects_segment(c, a):
			return true
		for d in diag:
			if Geometry3D.segment_intersects_triangle(d[0], d[1], a, b, c) != null:
				return true
	return false

func _filter_mesh_centre(node: Node) -> Vector3:
	var box := AABB()
	for m in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	return box.get_center()

# 8 points, one per press, each at the same place in its press's frame (within 0.2 m). The place is taken from the
# first point against each press in turn, since which press it belongs to is not known.
func _filter_one_per_press(points: Array, presses: Array) -> bool:
	if points.size() != 8 or presses.size() != 8:
		return false
	for first in presses:
		var want: Vector3 = first.global_transform.affine_inverse() * points[0]
		var taken := {}
		for pt in points:
			for p in presses:
				if not taken.has(p) and (p.global_transform.affine_inverse() * pt).distance_to(want) < 0.2:
					taken[p] = true
					break
		if taken.size() == 8:
			return true
	return false

# The second victim's camera call comes 3 s after the pick, while every view still holds on the first: no view,
# the second victim's own included, jumps back to straight ahead (a baked look restarted at its first key).
func _check_filter_turn(mg) -> void:
	var subs: Array = mg.player_parent_node.get_children().filter(func(c): return c.get("camera") is Camera3D).map(func(c): return c.camera.get_parent())
	await get_tree().create_timer(2.85).timeout
	var before: Array = subs.map(func(n): return n.rotation if is_instance_valid(n) else Vector3.ZERO)
	await get_tree().create_timer(0.3).timeout
	var jumps: Array = []
	for i in subs.size():
		if is_instance_valid(subs[i]):
			var d: Vector3 = (subs[i].rotation - before[i]).abs()
			if maxf(d.x, maxf(d.y, d.z)) > 0.15:
				jumps.append("%s %s -> %s" % [subs[i].get_parent().get_parent().get_parent().name, before[i], subs[i].rotation])
	ok("The Filter: no view jumps as the second victim's turn starts (%d views)" % subs.size(), jumps.is_empty(), jumps)

# Forklift Certified's yard (D104): above 4 seats the build's pick scales the walls, bays and camera; at 4 or
# fewer the shipped yard is untouched. The stock walls are 53.57 x 58.57 in the scene.
func _check_forklift_yard(mg, n: int) -> void:
	var walls: CSGBox3D = mg.get_node_or_null(mg.MP8V_WALLS) as CSGBox3D
	var holder: Node3D = mg.get_node_or_null("Placeholder") as Node3D
	if walls == null or holder == null:
		ok("Forklift: the walls and the camera's parent are there", false)
		return
	var stock := Vector2(53.568542, 58.57263)
	var size := Vector2(walls.size.x, walls.size.z)
	if n <= 4:
		ok("Forklift: the shipped yard at %d seats" % n,
			mg._mp8v_yard == Vector2.ONE and size.is_equal_approx(stock) and holder.position.is_zero_approx(),
			[mg._mp8v_yard, size, holder.position])
		return
	var yard: Vector2 = mg._mp8v_yard
	ok("Forklift 8p: the yard is the build's pick, grown", yard == mg.MP8V_YARD_SCALE and yard.x > 1.0 and yard.y > 1.0, [yard, mg.MP8V_YARD_SCALE])
	ok("Forklift 8p: the walls scaled with it", size.is_equal_approx(stock * yard), [size, stock * yard])
	var c: Vector3 = walls.global_position
	var inside := Rect2(c.x - size.x * 0.5, c.z - size.y * 0.5, size.x, size.y)
	var rects: Array = mg.delivery_area_parent.get_children().map(func(a): return mg._mp8v_zone_rect(a))
	var overlaps: int = 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlaps += 1
	ok("Forklift 8p: 8 bays inside the walls, none overlapping",
		rects.size() == 8 and rects.all(func(r): return inside.encloses(r)) and overlaps == 0, [rects.size(), overlaps, inside])
	var bays: Array = mg.delivery_area_parent.get_children()
	var homeless: Array = []
	for i in mg._mp8_spawns.size():
		var at: Vector3 = mg._mp8_spawns[i][0]
		if i >= bays.size() or not (mg._mp8v_zone_rect(bays[i]) as Rect2).has_point(Vector2(at.x, at.z)):
			homeless.append(i)
	ok("Forklift 8p: every spawn lies in its own bay", mg._mp8_spawns.size() == 8 and homeless.is_empty(), [mg._mp8_spawns.size(), homeless])
	# The magnet's beam rests at z 46.38 and its home marker at 43.74 in the stock scene; both move out by z.
	var magnet = mg.crate_manager.magnet
	var beam_z: float = magnet.axis_vertical.global_position.z
	ok("Forklift 8p: the camera moved back and the magnet rests out of shot",
		holder.position.z > 0.0 and absf(beam_z - 46.375 * yard.y) < 0.1 and absf(magnet.pos_home.global_position.z - 43.741 * yard.y) < 0.1,
		[holder.position, beam_z, magnet.pos_home.global_position])

# PD4: a pad that comes back on its own id is confirmed with A, then released, as the owner does at the couch.
# Overtime's presence runs both steps in its _physics_process.
func _check_reconnect(pres, dev: int) -> void:
	var a := -1
	for e in InputMap.action_get_events("action_1"):
		if e is InputEventJoypadButton:
			a = e.button_index
	var press := func(down: bool) -> void:
		var e := InputEventJoypadButton.new()
		e.device = dev
		e.button_index = a
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	var state := func() -> String:
		return "%s; in tree %s, A held %s" % [pres.mp8_local_status_text(), pres.is_inside_tree(), Input.is_action_pressed("%daction_1" % dev)]
	Input.joy_connection_changed.emit(dev, true)
	for i in 3: await get_tree().physics_frame
	var steps := ["back: " + state.call()]
	press.call(true)
	for i in 3: await get_tree().physics_frame
	steps.append("A down: " + state.call())
	press.call(false)
	for i in 3: await get_tree().physics_frame
	steps.append("A up: " + state.call())
	ok("a pad back on its own id plays again after A is pressed and released", pres.local_controller_connected, steps)

# PD3: a hunter's split-screen tile is its local_camera, which follows its aim camera in hunter_player's _process.
# Offline Bots switches a bot's _process off (the --auto seat's too), and scopes it by zoom_fov_index alone (no
# update_zoom), so the tile of a hunter whose _process is off takes its zoom from zoom_fovs, as the fork does. Each frame's sync runs before that frame's aim changes (the hunter's
# own update_look, Offline Bots' brain), so a tile may show the previous frame's aim and scope, never older.
const HUNTER_SAMPLE_SEC := 8.0

func _check_hunter_views(mg) -> void:
	var hunters := func() -> Array:
		var list = mg.get("hunter_players") if is_instance_valid(mg) else null
		if not (list is Array) and is_instance_valid(mg) and mg.get("hunter_player") != null:
			list = [mg.hunter_player]
		return (list if list is Array else []).filter(func(h): return is_instance_valid(h))
	ok("Duck Hunt's hunters go active", await _wait(func(): return not hunters.call().is_empty() and hunters.call().all(func(h): return h.active), 60.0))
	var first := {}
	var last := {}  # hunter -> [aim transform, wanted fov] at the previous sample
	var wrong := {}  # hunter -> [frames wrong, the first wrong one]
	var scoped := {}
	for h in hunters.call():
		first[h] = h.camera.global_transform
		last[h] = [h.camera.global_transform, h.zoom_fovs[clampi(int(h.zoom_fov_index), 0, h.zoom_fovs.size() - 1)] if not h.is_processing() else h.camera.fov]
		wrong[h] = [0, ""]
		scoped[h] = 0
	var end := Time.get_ticks_msec() + int(HUNTER_SAMPLE_SEC * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		for h in hunters.call():
			if not wrong.has(h):
				continue
			var zoom: int = clampi(int(h.zoom_fov_index), 0, h.zoom_fovs.size() - 1)
			var now: Array = [h.camera.global_transform, h.zoom_fovs[zoom] if not h.is_processing() else h.camera.fov]
			if zoom > 0:
				scoped[h] += 1
			var tile: Array = [h.local_camera.global_transform, h.local_camera.fov]
			var shows := func(want: Array) -> bool: return tile[0].is_equal_approx(want[0]) and is_equal_approx(tile[1], want[1])
			if not shows.call(now) and not (last.has(h) and shows.call(last[h])):
				wrong[h][0] += 1
				if wrong[h][1].is_empty():
					wrong[h][1] = "first: tile at %s fov %.1f, aim at %s, scope %d (fov %.1f)" % [tile[0].origin, tile[1], now[0].origin, zoom, now[1]]
			last[h] = now
	ok("every sampled hunter is still there at the end", wrong.keys().all(func(h): return is_instance_valid(h)), wrong.size())
	for h in wrong:
		if not is_instance_valid(h):
			continue
		var bot: bool = h.player_presence.network_id >= 900001
		ok("%s hunter %s: its tile follows its aim and scope, at most a frame behind" % ["bot" if bot else "human", h.player_presence.network_name], wrong[h][0] == 0,
			"%d frames wrong%s; aim moved %s, processing %s, scoped in %d frames" % [wrong[h][0], (", " + wrong[h][1]) if wrong[h][0] > 0 else "",
			not h.camera.global_transform.is_equal_approx(first[h]), h.is_processing(), scoped[h]])
	if not scoped.values().any(func(n): return n > 0):
		say("NOTE no hunter scoped in while sampled: the zoom part of the check didn't run")

# PD7: in The Filter and Knife at the Office a player's tile is its local_camera, which follows its camera only in
# the player's _process, and Offline Bots switches a bot's _process off. Sampled as the hunters are: a tile may show
# the previous frame's view. The Filter's look animation moves a camera after both syncs now and then, so a tile
# synced by its own player misses a frame too (1 of about 580 measured): TILE_OFF_FRAMES allows that, not a frozen tile.
# The fix is 8 Player Support's (b3 and up), so on the fork, stock Overtime or vanilla this check FAILs by design.
const TILE_SAMPLE_SEC := 4.0
const TILE_OFF_FRAMES := 3

func _check_tile_views(mg) -> void:
	var players := func() -> Array:
		var out: Array = []
		if is_instance_valid(mg):
			for n in mg.find_children("*", "", true, false):
				if n.get("local_camera") is Camera3D and n.get("camera") is Camera3D and n.get("player_presence") != null:
					out.append(n)
		return out
	ok("the minigame's players are there", await _wait(func(): return players.call().size() >= 2, 60.0), players.call().size())
	ok("Offline Bots has switched some player's _process off", await _wait(func(): return players.call().any(func(p): return not p.is_processing()), 30.0))
	var last := {}
	var wrong := {}
	for p in players.call():
		last[p] = p.camera.global_transform
		wrong[p] = [0, ""]
	var end := Time.get_ticks_msec() + int(TILE_SAMPLE_SEC * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		for p in wrong:
			if not is_instance_valid(p):
				continue
			var now: Transform3D = p.camera.global_transform
			var tile: Transform3D = p.local_camera.global_transform
			if not tile.is_equal_approx(now) and not tile.is_equal_approx(last[p]):
				wrong[p][0] += 1
				if wrong[p][1].is_empty():
					wrong[p][1] = "first: tile at %s, camera at %s" % [tile.origin, now.origin]
			last[p] = now
	# A player still processing syncs its own tile, ahead of its camera's look animation now and then: the game's
	# timing, not PD7's, so only the tiles the minigame drives are judged.
	for p in wrong:
		if not is_instance_valid(p):
			continue
		var detail := "%d frames wrong%s" % [wrong[p][0], (", " + wrong[p][1]) if wrong[p][0] > 0 else ""]
		if p.is_processing():
			say("NOTE %s syncs its own tile (_process on): %s" % [p.player_presence.network_name, detail])
			continue
		ok("%s, _process off: its tile shows its own camera, at most a frame behind (%d off frames allowed)" % [p.player_presence.network_name, TILE_OFF_FRAMES],
			wrong[p][0] <= TILE_OFF_FRAMES, detail)

func _scene_is(path: String) -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == path

func _wait(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true
