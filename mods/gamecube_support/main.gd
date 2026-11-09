extends Node

# GameCube controller support for Machine Party: Nintendo-style buttons,
# full-range sticks and L click as LB on adapters in PC mode (gc_input.gd),
# plus GameCube buttons in the controller prompts.
#
# No game scripts are overridden, so mods that replace the prompt screens
# (Overtime swaps the intermission briefing and Duck Hunt scripts) stack
# cleanly. Instead the prompt textures themselves are taken over in
# _mod_init, before any scene loads them, by proxies that can point at either
# the vanilla art or our GameCube glyphs (see glyph_swapper.gd). Prompts are
# one shared set on screen, so with mixed pads the default "auto" style
# follows whichever controller pressed a button last (pad_detector.gd).

const MOD_ID := "gamecube_support"
const CONFIG_PATH := "user://gamecube_support.json"
const OLD_CONFIG_PATH := "user://gamecube_prompts.json"  # before the rename
const STYLES := ["auto", "gamecube", "xbox"]
const ARTS := ["classic", "outline", "authentic", "letters"]
const LAYOUTS := ["nintendo", "positional"]
const CALIBRATIONS := ["auto", "fixed", "off"]
# Vanilla prompt texture (under res://textures/ui/control/) -> GameCube glyph,
# for the "nintendo" button layout (B is east, the game's back/unready; X is
# west). The "positional" layout swaps east and west back, matching what the
# adapter reports on its own. Z is RB, L's full click is LB (gc_input.gd).
# config glyph_map overrides entries.
const SLOTS := {
	"controller_button_south.png": "A",
	"controller_button_east.png": "B",
	"controller_button_west.png": "X",
	"controller_button_north.png": "Y",
	"controller_left_shoulder.png": "Lclick",
	"controller_right_shoulder.png": "Z",
	"controller_left_trigger.png": "L",
	"controller_right_trigger.png": "R",
	"controller_analog_alt.png": "stick",
	"hires/controller_left_shoulder_button_wide_2x.png": "Lclick_wide",
	"hires/controller_right_shoulder_button_wide_2x.png": "Z_wide",
}
const DEFAULTS := {
	"style": "auto",
	"art": "classic",
	"auto_cooldown_sec": 1.0,
	"auto_use_sticks": false,
	"hotkey": "F9",
	"extra_gamecube_guids": [],
	"glyph_map": {},
	"button_layout": "nintendo",
	"stick_calibration": "auto",
	"stick_range": 0.75,
	"trigger_rest": 0.07,
	"l_click_from_trigger": true,
	"l_click_threshold": 0.85,
	"adapter_overrides": {},
	"warn_duplicates": true,
	"menu_pad": "first",
}
# first: the first pad to press a button steers the menus; any: every pad does;
# off: the game's own rule (directions on device 0 only).
const MENU_PADS := ["first", "any", "off"]
const MENU_DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const MAIN_MENU := "res://scenes/main_menu/scripts/main_menu.gd"
# Hooked by path, so Overtime's patched copies of these scripts get it too.
const MINIGAME_PLAYERS := {
	"res://minigames/duck_hunt/components/hunter_player/scripts/hunter_player.gd": "duck_hunt",
	"res://minigames/burn_recycle/components/player/burn_recycle_player.gd": "burn_recycle",
}
const MINIGAME_CONTROLS_NAME := "GcMinigameControls"
# A briefing's control row; no mod in the compatibility set replaces it.
const CONTROL_ROW := "res://modules/user_interface/intermission_control_input_label/intermission_control_input_label.gd"
const BRIEFING_GLYPHS_NAME := "GcBriefingGlyphs"
const LOBBY_PANEL := "res://scenes/local_lobby/scripts/local_lobby_player_controls.gd"
const DROP_OUT_NAME := "GcLobbyDropOut"
const TOAST_SECONDS := 1.5
const WARN_SECONDS := 10.0

var config := {}
var swapper
var detector: Node
var bridge: Node
var gc_input: Node
var minigame_controls: GDScript
var briefing_glyphs: GDScript
var lobby_drop_out: GDScript
var problem := ""
var _loader
var _dir := ""
var _hotkey := KEY_NONE
var _hotkey_held := false
var _toast: Label
var _toast_left := 0.0
var menu_pad := -1
var _main_menu: Node

func _mod_init(loader) -> void:
	_loader = loader
	# Hosted in Extended's bundle, the folder comes as meta: dir_of() knows only top-level mods.
	_dir = get_meta("mpml_dir") if has_meta("mpml_dir") else loader.dir_of(MOD_ID)
	config = load_config()
	loader.registry(MOD_ID)["menu_pad"] = -1
	if config["menu_pad"] != "off":
		note("menu directions take any pad (%d pad bindings changed)" % open_menu_directions())
	if loader.has_api("on_scene_script"):
		loader.on_scene_script(MAIN_MENU, _on_main_menu)
	var swapper_script: GDScript = loader.compile(_dir.path_join("glyph_swapper.gd"))
	if swapper_script == null:
		note("failed to load, prompts left unchanged")
		return
	swapper = swapper_script.new()
	swapper.install(SLOTS.keys())
	swapper.load_glyphs(_dir.path_join("glyphs"), ARTS)
	for p in swapper.problems:
		note(p)
	for p in swapper.size_mismatches(slot_keys()):
		note("size mismatch, slot keeps vanilla: " + p)
	if not swapper.precached.is_empty():
		note("loaded before takeover, those users keep vanilla: " + ", ".join(swapper.precached))
	loader.registry(MOD_ID)["api"] = self
	_apply()
	note("%d prompt textures taken over (style %s, art %s)" % [swapper.proxies.size(), config["style"], config["art"]])
	_hook_minigames(loader)
	_hook_lobby(loader)

# Deferred past the loader's _mod_ready loop: hosted in Extended's bundle this mod starts at
# Extended's priority, before the Debug Console has built its input line.
func _attach_bridge() -> void:
	if bridge.attach(_loader.get_node_or_null("console")):
		add_child(bridge)
	else:
		bridge.free()
		bridge = null

func _mod_ready(loader) -> void:
	if swapper == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS

	detector = _make("pad_detector.gd")
	if detector != null:
		detector.name = "PadDetector"
		detector.cooldown_ms = int(config["auto_cooldown_sec"] * 1000.0)
		detector.use_sticks = config["auto_use_sticks"]
		detector.extra_guids = config["extra_gamecube_guids"]
		detector.gamecube = detector.all_connected_gamecube()
		detector.type_changed.connect(_on_auto_type_changed)
		detector.button_pressed.connect(_on_pad_pressed)
		add_child.call_deferred(detector)
	Input.joy_connection_changed.connect(_on_menu_pad_connection)

	bridge = _make("console_bridge.gd")
	if bridge != null:
		bridge.name = "ConsoleBridge"
		bridge.api = self
		_attach_bridge.call_deferred()

	gc_input = _make("gc_input.gd")
	if gc_input != null:
		gc_input.name = "GcInput"
		gc_input.layout = config["button_layout"]
		gc_input.calibration = config["stick_calibration"]
		gc_input.stick_range = clampf(config["stick_range"], 0.3, 1.0)
		gc_input.trigger_rest = clampf(config["trigger_rest"], 0.0, 0.5)
		gc_input.l_click = config["l_click_from_trigger"]
		gc_input.l_click_threshold = clampf(config["l_click_threshold"], 0.2, 1.0)
		gc_input.overrides = config["adapter_overrides"]
		add_child.call_deferred(gc_input)
		_check_duplicates.call_deferred()

	var key: String = config["hotkey"]
	_hotkey = OS.find_keycode_from_string(key) if not key.is_empty() else KEY_NONE

	var lost: PackedStringArray = swapper.lost_paths()
	if not lost.is_empty():
		note("another load took back: " + ", ".join(lost))
	_apply()

# SDL connects pads over the first frames, so look once things settle.
func _check_duplicates() -> void:
	await get_tree().create_timer(1.5, true, false, true).timeout
	problem = gc_input.current_problem()
	if problem.is_empty():
		return
	note("%s; %s" % [problem, _duplicate_hint()])
	if config["warn_duplicates"]:
		var lang := _lang()
		show_toast(duplicate_toast(lang, gc_input.current_problem(lang)), WARN_SECONDS)

# what: duplicate_problem()'s text, in the same language.
func duplicate_toast(lang: String, what: String) -> String:
	return _pick(lang, "GameCube adapter: %s.\nTo fix: %s.", "GameCube 适配器：%s。\n解决方法：%s。",
		"GameCube 轉接器：%s。\n解決方法：%s。") % [what, _duplicate_hint(lang)]

# The .bat sits in this mod's folder: mods/gamecube_support, or inside Extended's bundle folder.
func _duplicate_hint(lang := "EN") -> String:
	var folder := _dir.get_file()
	if has_meta("mpml_dir"):
		folder = _dir.get_base_dir().get_file().path_join(folder)
	return _pick(lang, "run fix-gamecube-adapter.bat in the mods/%s folder, then fully restart Steam",
		"运行 mods/%s 文件夹中的 fix-gamecube-adapter.bat，然后完全重启 Steam",
		"執行 mods/%s 資料夾中的 fix-gamecube-adapter.bat，然後完全重新啟動 Steam") % folder

# The game's language for the toasts; English if gc_input, which holds the mapping, failed to load.
func _lang() -> String:
	return gc_input.lang_of(TranslationServer.get_locale()) if gc_input != null else "EN"

func _pick(lang: String, en: String, zhs: String, zht: String) -> String:
	return gc_input.pick(lang, en, zhs, zht) if gc_input != null else en

func _make(file: String) -> Node:
	var s: GDScript = _loader.compile(_dir.path_join(file))
	if s == null:
		note("failed to load " + file)
		return null
	return s.new()

# --- minigames -----------------------------------------------------------------

func _hook_minigames(loader) -> void:
	if not loader.has_api("on_scene_script"):
		note("loader has no on_scene_script, minigame controls unchanged")
		return
	minigame_controls = loader.compile(_dir.path_join("minigame_controls.gd"))
	if minigame_controls == null:
		note("failed to load minigame_controls.gd, minigame controls unchanged")
		return
	for path in MINIGAME_PLAYERS:
		loader.on_scene_script(path, _attach_controls.bind(MINIGAME_PLAYERS[path]))
	# After minigame_controls on purpose: without it X and Y don't burn or recycle.
	briefing_glyphs = loader.compile(_dir.path_join("briefing_glyphs.gd"))
	if briefing_glyphs == null:
		note("failed to load briefing_glyphs.gd, briefing glyphs unchanged")
		return
	loader.on_scene_script(CONTROL_ROW, _on_control_row)

func _on_control_row(row: Node) -> void:
	if row.get_node_or_null(BRIEFING_GLYPHS_NAME) != null:
		return
	var helper: Node = briefing_glyphs.new()
	helper.name = BRIEFING_GLYPHS_NAME
	helper.api = self
	row.add_child(helper)

func _hook_lobby(loader) -> void:
	if not loader.has_api("on_scene_script"):
		return
	lobby_drop_out = loader.compile(_dir.path_join("lobby_drop_out.gd"))
	if lobby_drop_out == null:
		note("failed to load lobby_drop_out.gd, B doesn't drop out of the lobby")
		return
	loader.on_scene_script(LOBBY_PANEL, _on_lobby_panel)

# Runs while the scene is entering the tree; the helper is added once it has finished.
func _on_lobby_panel(panel: Node) -> void:
	if panel.get_node_or_null(DROP_OUT_NAME) != null:
		return
	var helper: Node = lobby_drop_out.new()
	helper.name = DROP_OUT_NAME
	helper.api = self
	panel.add_child.call_deferred(helper)

# On a minigame player or the main menu. The hook fires again when the node
# re-enters the tree; one helper is kept.
func _attach_controls(node: Node, kind: String) -> void:
	var helper := node.get_node_or_null(MINIGAME_CONTROLS_NAME)
	if helper == null:
		helper = minigame_controls.new()
		helper.name = MINIGAME_CONTROLS_NAME
		node.add_child(helper)
	helper.kind = kind
	helper.api = self

func _process(delta: float) -> void:
	if _hotkey != KEY_NONE:
		var down := Input.is_key_pressed(_hotkey) and get_window().has_focus()
		if down and not _hotkey_held:
			cycle_style()
		_hotkey_held = down
	if _toast != null and _toast.visible:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false

# --- menus -------------------------------------------------------------------

# The game keeps Godot's built-in menu directions, whose pad events listen to
# device 0 only, so an adapter port can't steer menus. InputMap reloads share
# these event objects with ProjectSettings, so one edit lasts; a local lobby's
# set_ui_action_device still narrows them to the host, as it does A.
func open_menu_directions() -> int:
	var changed := 0
	for action in MENU_DIRECTIONS:
		var setting: String = "input/" + action
		if ProjectSettings.has_setting(setting):
			changed += widen_to_any_pad(ProjectSettings.get_setting(setting).get("events", []))
		if InputMap.has_action(action):
			changed += widen_to_any_pad(InputMap.action_get_events(action))
	return changed

static func widen_to_any_pad(events: Array) -> int:
	var changed := 0
	for e in events:
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device == 0:
			e.device = -1
			changed += 1
	return changed

static func narrow_to(events: Array, device: int) -> int:
	var changed := 0
	for e in events:
		if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device != device:
			e.device = device
			changed += 1
	return changed

# The game's own menu actions (MultiplayerInput.is_ui_action). Pad events the
# local lobby erased when its host pad left are put back from ProjectSettings,
# whose event objects the InputMap shares; device -1 is every pad.
func set_menu_device(device: int) -> int:
	var changed := 0
	for action in InputMap.get_actions():
		var a := String(action)
		if not (a.begins_with("ui_") or a.begins_with("playlist_")):
			continue
		var stored: Array = ProjectSettings.get_setting("input/" + a, {}).get("events", [])
		changed += narrow_to(stored, device) + narrow_to(InputMap.action_get_events(action), device)
		for e in stored:
			if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and not InputMap.action_has_event(action, e):
				InputMap.action_add_event(action, e)
				changed += 1
	return changed

# The local lobby hands the menus to its host pad and keeps them there after it
# closes; the main menu takes them back.
func _on_main_menu(menu: Node) -> void:
	_main_menu = menu
	if config["menu_pad"] == "first":
		set_menu_device(menu_pad)
	if minigame_controls != null:
		_attach_controls(menu, minigame_controls.MAIN_MENU)

func _at_main_menu() -> bool:
	return is_instance_valid(_main_menu) and _main_menu.is_inside_tree()

func _on_pad_pressed(device: int, now: int) -> void:
	if config["menu_pad"] != "first" or menu_pad >= 0 or not detector.may_claim(now):
		return
	_set_menu_pad(device)

func _on_menu_pad_connection(device: int, connected: bool) -> void:
	if not connected and device == menu_pad:
		_set_menu_pad(-1)

func _set_menu_pad(device: int) -> void:
	menu_pad = device
	_loader.registry(MOD_ID)["menu_pad"] = device
	note("menus follow pad %d" % device if device >= 0 else "menu pad gone, the next pad to press takes the menus")
	if _at_main_menu():
		set_menu_device(device)

# --- style -------------------------------------------------------------------

func is_showing_gamecube() -> bool:
	match config["style"]:
		"gamecube":
			return true
		"xbox":
			return false
	return detector != null and detector.gamecube

func slot_keys() -> Dictionary:
	var keys := SLOTS.duplicate()
	if config["button_layout"] == "positional":
		keys["controller_button_east.png"] = "X"
		keys["controller_button_west.png"] = "B"
	var overrides: Dictionary = config["glyph_map"]
	for rel in overrides:
		if keys.has(rel):
			keys[rel] = str(overrides[rel])
	return keys

func _apply() -> void:
	if swapper != null:
		swapper.apply(is_showing_gamecube(), config["art"], slot_keys())

func _on_auto_type_changed(_gamecube: bool) -> void:
	if config["style"] == "auto":
		_apply()

func set_style(style: String, persist := true) -> bool:
	if not style in STYLES:
		return false
	config["style"] = style
	if persist:
		save_config()
	_apply()
	return true

func set_art(art: String, persist := true) -> bool:
	if not art in ARTS:
		return false
	config["art"] = art
	if persist:
		save_config()
	_apply()
	return true

func set_layout(layout: String, persist := true) -> bool:
	if not layout in LAYOUTS:
		return false
	config["button_layout"] = layout
	if persist:
		save_config()
	if gc_input != null:
		gc_input.layout = layout
		gc_input.apply_layout()
	_apply()
	return true

func cycle_style() -> void:
	set_style(STYLES[(STYLES.find(config["style"]) + 1) % STYLES.size()])
	show_toast(style_toast(_lang()))

func style_toast(lang: String) -> String:
	return _pick(lang, "Button prompts: ", "按键提示：", "按鍵提示：") + _style_label(lang)

func _style_label(lang := "EN") -> String:
	var showing := "GameCube" if is_showing_gamecube() else _pick(lang, "vanilla", "原版", "原版")
	if config["style"] == "auto":
		return _pick(lang, "auto (now %s)", "自动（当前 %s）", "自動（目前 %s）") % showing
	return showing

func get_status() -> Dictionary:
	return {
		"style": config["style"],
		"art": config["art"],
		"layout": config["button_layout"],
		"calibration": config["stick_calibration"],
		"showing": "gamecube" if is_showing_gamecube() else "vanilla",
		"textures": swapper.proxies.size() if swapper != null else 0,
		"last_device": detector.last_device if detector != null else -1,
	}

# --- console -----------------------------------------------------------------

func run_command(args: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var cmd: String = str(args[0]).to_lower() if not args.is_empty() else ""
	var arg: String = str(args[1]).to_lower() if args.size() > 1 else ""
	match cmd:
		"":
			out.append("style %s, art %s, showing %s, %d textures" % [config["style"], config["art"], get_status()["showing"], get_status()["textures"]])
			out.append("buttons %s, sticks %s, L click as LB %s" % [config["button_layout"], config["stick_calibration"], "on" if config["l_click_from_trigger"] else "off"])
		"style":
			if set_style(arg):
				out.append("style: " + _style_label())
			else:
				out.append("usage: gc style auto|gamecube|xbox")
		"art":
			if set_art(arg):
				out.append("art: " + arg)
			else:
				out.append("usage: gc art classic|outline|authentic|letters")
		"layout":
			if set_layout(arg):
				out.append("buttons: " + arg)
			else:
				out.append("usage: gc layout nintendo|positional")
		"pads":
			var pads := Input.get_connected_joypads()
			if pads.is_empty():
				out.append("no controllers connected")
			for d in pads:
				var mark := "  <- last button" if detector != null and d == detector.last_device else ""
				if d == menu_pad:
					mark += "  <- menus"
				var how: String = gc_input.describe(d) if gc_input != null else ""
				out.append((detector.describe(d) if detector != null else str(d)) + ("  [%s]" % how if not how.is_empty() else "") + mark)
			if not problem.is_empty():
				out.append("WARNING: %s; %s" % [problem, _duplicate_hint()])
		_:
			out.append("gc                  show current settings")
			out.append("gc style <s>        prompts: auto | gamecube | xbox  (hotkey %s cycles)" % config["hotkey"])
			out.append("gc art <a>          classic | outline | authentic | letters")
			out.append("gc layout <l>       nintendo (B = back) | positional (X = back)")
			out.append("gc pads             list controllers and how each is handled")
	return out

func show_toast(text: String, seconds := TOAST_SECONDS) -> void:
	if _toast == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		add_child(layer)
		_toast = Label.new()
		_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_toast.offset_top = 24
		# The adapter warning is longer than the screen is wide, in every language.
		_toast.offset_left = 24
		_toast.offset_right = -24
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_theme_font_size_override("font_size", 22)
		_toast.add_theme_constant_override("outline_size", 8)
		_toast.add_theme_color_override("font_outline_color", Color.BLACK)
		layer.add_child(_toast)
	_toast.text = text
	_toast.visible = true
	_toast_left = seconds

# --- config ------------------------------------------------------------------

func load_config() -> Dictionary:
	var cfg := DEFAULTS.duplicate(true)
	var path := CONFIG_PATH
	if not FileAccess.file_exists(path):
		if not FileAccess.file_exists(OLD_CONFIG_PATH):
			_write(cfg)  # so players can find and edit it
			return cfg
		path = OLD_CONFIG_PATH
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		note("%s is not valid JSON, using defaults" % path)
		return cfg
	for k in DEFAULTS:
		if parsed.has(k):
			cfg[k] = _coerce(parsed[k], DEFAULTS[k])
	if not cfg["style"] in STYLES:
		cfg["style"] = DEFAULTS["style"]
	if not cfg["art"] in ARTS:
		cfg["art"] = DEFAULTS["art"]
	if not cfg["button_layout"] in LAYOUTS:
		cfg["button_layout"] = DEFAULTS["button_layout"]
	if not cfg["stick_calibration"] in CALIBRATIONS:
		cfg["stick_calibration"] = DEFAULTS["stick_calibration"]
	if not cfg["menu_pad"] in MENU_PADS:
		cfg["menu_pad"] = DEFAULTS["menu_pad"]
	var migrated: bool = parsed.has("menus_any_pad") and not parsed.has("menu_pad")
	if migrated:
		cfg["menu_pad"] = menu_pad_from(parsed["menus_any_pad"])
		note("menus_any_pad is now menu_pad: \"%s\"" % cfg["menu_pad"])
	if path == OLD_CONFIG_PATH:
		note("settings carried over from " + OLD_CONFIG_PATH)
	if migrated or path == OLD_CONFIG_PATH:
		_write(cfg)
	return cfg

# The old key's true was its default, so it maps to the new default.
static func menu_pad_from(any_pad) -> String:
	return "off" if any_pad is bool and not any_pad else DEFAULTS["menu_pad"]

func save_config() -> void:
	_write(config)

func _write(cfg: Dictionary) -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		note("cannot write " + CONFIG_PATH)
		return
	f.store_string(JSON.stringify(cfg, "  ", false))
	f.close()

static func _coerce(value, default):
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(default) in numbers and typeof(value) in numbers:
		return int(value) if typeof(default) == TYPE_INT else float(value)
	return value if typeof(value) == typeof(default) else default

func note(msg: String) -> void:
	if _loader != null:
		_loader.note("gamecube_support: " + msg)
	else:
		print("gamecube_support: " + msg)
