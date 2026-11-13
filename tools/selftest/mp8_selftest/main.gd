extends Node

# Dev-only test of 8 Player Support (extended/'s build).
# With mp8_support alone it checks the mount, the tag, the handshake parsing and Duck Hunt's
# MAG/RATE line, the intro's rack, the wheat field's spawn spots, 0.8.0's skipped renders and Chisel's pad
# steps; with Overtime
# installed too, that mp8_support refused and Overtime runs as itself.

const TAG := "mp-extended-1.1"
const HUNTER := "res://minigames/duck_hunt/components/hunter_player/hunter_player.tscn"
const INTERMISSION := "res://minigames/intermission_new/intermission_new.tscn"
const WHEAT_FIELD := "res://minigames/cutscene_test/cutscene_test.tscn"
const CHISEL_HANDLER := "res://minigames/chisel_gauntlet_multiplayer/components/player/components/interaction_handler/interaction_handler.gd"
# Chisel's 19 cubes, SUBMIT (-1) and RESET (-2) where an 8-seat tile shows them (tools/selftest/chisel_map,
# mp8 b21 and b23, device 100).
const CHISEL_CUBES := {-1: Vector2(-29.2, 63.7), -2: Vector2(140.5, 63.6), 0: Vector2(53.0, 24.7), 1: Vector2(66.4, 31.3), 2: Vector2(81.3, 38.6), 3: Vector2(39.7, 31.3),
	4: Vector2(53.0, 38.6), 5: Vector2(68.0, 46.9), 6: Vector2(24.8, 38.6), 7: Vector2(38.1, 46.9), 8: Vector2(53.0, 56.2),
	9: Vector2(25.6, 55.4), 10: Vector2(38.5, 64.3), 11: Vector2(53.0, 74.4), 12: Vector2(26.4, 71.1), 13: Vector2(39.0, 80.7),
	14: Vector2(53.0, 91.4), 15: Vector2(67.6, 64.3), 16: Vector2(80.5, 55.4), 17: Vector2(67.1, 80.7), 18: Vector2(79.7, 71.1)}

var fails := 0
var _game_hands: Array = []
# Inside this test's own mod folder, which the runner deletes even after a killed run.
var scratch := OS.get_executable_path().get_base_dir().path_join("mods/mp8_selftest/scan")
var out: FileAccess
var _loader

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/mp8_selftest/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	_loader = loader
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var log_text := FileAccess.get_file_as_string("user://modloader.log")
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	say("mods: %s" % ", ".join(PackedStringArray(_loader.mod_list())))
	ok("mp8_support is installed", _loader.has_mod("mp8_support"))
	ok("NetworkManager is up", nm != null)
	if nm == null or not _loader.has_mod("mp8_support"):
		finish()
		return
	# Chosen by the folders installed, not by the refusal it checks. Either copy's main.gd may be the one
	# dir_of() names, and an older one has no scan to test.
	var copies := _extended_folders()
	if copies.size() >= 2:
		_twice(log_text, copies)
		finish()
		return
	_scan_rule()
	if OS.get_environment("MP8_DEV_EXPECT") != "":
		_dev_switches(nm)
		finish()
		return
	if _loader.has_mod("overtime"):
		_refused(log_text, nm)
	else:
		await _mounted(log_text, nm)
		_hosting(log_text)
		await _chisel_pad()
		await _title_word()
		await _leave_menu_twice()
	finish()

# Machine Party: Extended's word beside the main menu's logo: one, right after the logo, at its scale, on
# screen and clear of the buttons; still one after the menu leaves and re-enters the tree (the hook fires again).
func _title_word() -> void:
	say("step: title word")
	var menu: Node = null
	for n in get_tree().current_scene.find_children("*", "Control", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("main_menu/scripts/main_menu.gd"):
			menu = n
	ok("main menu up", menu != null, get_tree().current_scene.name)
	if menu == null:
		return
	var corner = menu.get("version_label")
	ok("the corner shows the game version and the tag", corner is Label and corner.text == Globals.game_version + "+" + TAG, corner.text if corner is Label else corner)
	var logo: Control = menu.find_child("logo", true, false)
	var words := func() -> Array: return logo.get_parent().find_children("mp8_extended", "", false, false)
	ok("one word", words.call().size() == 1, words.call().size())
	if words.call().size() != 1:
		return
	var word: TextureRect = words.call()[0]
	ok("right after the logo", word.get_index() == logo.get_index() + 1, [word.get_index(), logo.get_index()])
	ok("art loaded", word.texture != null and word.texture.get_size().y > 0, word.texture)
	ok("at the logo's scale", word.scale == logo.scale, word.scale)
	ok("ignores the mouse", word.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var r := word.get_global_rect()
	ok("on screen", Rect2(0, 0, 960, 540).encloses(r), r)
	ok("right of the logo's left half", r.position.x > logo.get_global_rect().get_center().x, [r, logo.get_global_rect()])
	ok("clear of the buttons", not r.intersects(menu.start_button.get_global_rect()), menu.start_button.get_global_rect())
	var parent := menu.get_parent()
	var at := menu.get_index()
	parent.remove_child(menu)
	parent.add_child(menu)
	parent.move_child(menu, at)
	for i in 3:
		await get_tree().process_frame
	ok("still one after re-entering", words.call().size() == 1, words.call().size())

const LOCAL_LOBBY := "res://scenes/local_lobby/local_lobby.tscn"

# Host, Local and Customization each fade, then change scene. A second press during the fade releases both
# waits, and without the fix the second calls get_tree() on the menu the first took out, so the build dies here.
# Last, since it leaves the menu: Local, then Host twice and Customization, 0.1 s apart; only the first may act.
func _leave_menu_twice() -> void:
	say("step: the main menu's scene buttons pressed during the fade")
	var menu: Node = null
	for n in get_tree().current_scene.find_children("*", "Control", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("main_menu/scripts/main_menu.gd"):
			menu = n
	ok("main menu up for the presses", menu != null)
	if menu == null:
		return
	var waited := 0
	while waited < 50 and GlobalOverlay.get("overlay_tween") is Tween and GlobalOverlay.overlay_tween.is_running():
		await get_tree().create_timer(0.1).timeout
		waited += 1
	ok("the menu declares its leaving flag", "mp8_leaving" in menu)
	var host_before: bool = GameManager.host_game
	menu.local_original_button.pressed.emit()
	ok("the first press sets it", menu.get("mp8_leaving") == true, menu.get("mp8_leaving"))
	await get_tree().create_timer(0.1).timeout
	menu.host_original_button.pressed.emit()
	menu.host_custom_button.pressed.emit()
	ok("a later Host press leaves the first press's mode alone", GameManager.host_game == host_before and not GameManager.custom_game, [GameManager.host_game, GameManager.custom_game])
	await get_tree().create_timer(0.1).timeout
	menu.customization_button.pressed.emit()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
		var scene = get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == LOCAL_LOBBY:
			break
	for i in 30:
		await get_tree().process_frame
	var now = get_tree().current_scene
	ok("one scene change, the first press's: the local lobby", is_instance_valid(now) and now.scene_file_path == LOCAL_LOBBY, now.scene_file_path if is_instance_valid(now) else now)

# The folder scan on a made-up mods folder: a mod.json whose id, or folder name when it has none, is the one asked for.
func _scan_rule() -> void:
	say("step: scan rule")
	var main_script = _loader.compile(_loader.dir_of("mp8_support").path_join("main.gd"))
	ok("mp8_support's main.gd loads", main_script != null)
	if main_script == null:
		return
	var cases := [
		["empty", {}, ""],
		["overtime by id", {"renamed_ot": {"id": "overtime"}}, "renamed_ot"],
		["overtime by folder, no id", {"overtime": {"name": "x"}}, "overtime"],
		["folder named overtime, other id", {"overtime": {"id": "other"}}, ""],
		["dot folder", {".overtime": {"id": "overtime"}}, ""],
		["no mod.json", {"overtime": null}, ""],
		["others only", {"mp8_support": {"id": "mp8_support"}, "local_glasses": {"id": "local_glasses"}}, ""],
		["another id asked for", {"renamed": {"id": "some_mod"}, "overtime": {"id": "overtime"}}, "renamed", "some_mod"],
		["its own folder skipped", {"machine_party_extended": {"id": "mp8_support"}}, "", "mp8_support", "machine_party_extended"],
		["a second folder of its id", {"machine_party_extended": {"id": "mp8_support"}, "mp8_support": {"id": "mp8_support"}}, "mp8_support", "mp8_support", "machine_party_extended"],
	]
	for c in cases:
		_clear_scratch()
		DirAccess.make_dir_recursive_absolute(scratch)
		for sub in c[1]:
			DirAccess.make_dir_recursive_absolute(scratch.path_join(sub))
			if c[1][sub] != null:
				var f := FileAccess.open(scratch.path_join(sub).path_join("mod.json"), FileAccess.WRITE)
				f.store_string(JSON.stringify(c[1][sub]))
				f.close()
		var got: String = main_script._installed_folder(scratch, c[3] if c.size() > 3 else "overtime", c[4] if c.size() > 4 else "")
		ok("scan: %s" % c[0], got == c[2], got)
	_clear_scratch()

func _clear_scratch() -> void:
	var root := scratch
	if not DirAccess.dir_exists_absolute(root):
		return
	for sub in DirAccess.get_directories_at(root):
		var dir := root.path_join(sub)
		if FileAccess.file_exists(dir.path_join("mod.json")):
			DirAccess.remove_absolute(dir.path_join("mod.json"))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(root)

func _mounted(log_text: String, nm: Node) -> void:
	say("step: mp8_support alone")
	# The rows below read English words; the owner's save may name another language.
	var locale_before := TranslationServer.get_locale()
	TranslationServer.set_locale("EN")
	ok("overlay mounted, once", log_text.count("mp8_support: [MOUNTED]") == 1, log_text.count("mp8_support: [MOUNTED]"))
	ok("ready", log_text.contains("mp8_support: [READY]"))
	ok("no load-order error", not log_text.contains("LOAD_ORDER"))
	ok("no mp8_support failure note", not log_text.contains("mp8_support: [MP8:"))
	ok("tag", nm.get("MP8_VERSION_TAG") == TAG, nm.get("MP8_VERSION_TAG"))
	ok("game_version is vanilla's: no tag on the wire", not str(Globals.game_version).contains("+"), Globals.game_version)
	ok("the shown version ends in the tag", str(nm.call("mp8_full_version")).ends_with("+" + TAG), nm.call("mp8_full_version"))
	ok("8 players", nm.get("MAX_PLAYERS") == 8, nm.get("MAX_PLAYERS"))
	_relay(nm)
	_join_rules(nm)
	await _shared_rows(nm)
	_dev_switches(nm)
	var forms := [
		["v2.1.2+mp-extended-1.1", "mp-extended-1.1", "v2.1.2"],
		["v2.1.2+mp8-1.0", "mp8-1.0", "v2.1.2"],
		["v2.1.2+mp8-0.1", "mp8-0.1", "v2.1.2"],
		["v2.1.2+mp8-0.2", "mp8-0.2", "v2.1.2"],
		["v2.1.2+overtime-1.7", "overtime-1.7", "v2.1.2"],
		["v2.1.2", "", "v2.1.2"],
	]
	for f in forms:
		ok("tag of %s" % f[0], nm.call("_mp8_tag_of", f[0]) == f[1], nm.call("_mp8_tag_of", f[0]))
		ok("base of %s" % f[0], nm.call("_mp8_base_of", f[0]) == f[2], nm.call("_mp8_base_of", f[0]))
	# The refusal dialog's versions; whether the text fits the dialog is a render check, not this.
	var host_before = nm.get("_mp8_host_version")
	var dialogs := [
		["host on Overtime", "v2.1.2+overtime-1.7", [TAG, "overtime-1.7"]],
		["host on another game version", "v2.1.3+" + TAG, ["v2.1.2", "v2.1.3"]],
		["host on vanilla", "v2.1.2", [TAG, "v2.1.2"]],
		["host on 8 Player Support 0.1", "v2.1.2+mp8-0.1", [TAG, "mp8-0.1"]],
		["host on 8 Player Support 0.2", "v2.1.2+mp8-0.2", [TAG, "mp8-0.2"]],
		["host on 8 Player Support 0.3", "v2.1.2+mp8-0.3", [TAG, "mp8-0.3"]],
		["host on 8 Player Support 0.4", "v2.1.2+mp8-0.4", [TAG, "mp8-0.4"]],
		["host on 8 Player Support 0.5", "v2.1.2+mp8-0.5", [TAG, "mp8-0.5"]],
		["host on 8 Player Support 0.6", "v2.1.2+mp8-0.6", [TAG, "mp8-0.6"]],
		["host on 8 Player Support 0.7", "v2.1.2+mp8-0.7", [TAG, "mp8-0.7"]],
		["host on 8 Player Support 0.8", "v2.1.2+mp8-0.8", [TAG, "mp8-0.8"]],
		["host on 8 Player Support 0.9", "v2.1.2+mp8-0.9", [TAG, "mp8-0.9"]],
		["host on Extended 1.0", "v2.1.2+mp8-1.0", [TAG, "mp8-1.0"]],
		["host on a later Extended", "v2.1.2+mp-extended-1.2", [TAG, "mp-extended-1.2"]],
	]
	for d in dialogs:
		nm.set("_mp8_host_version", d[1])
		var text := str(nm.call("mp8_mismatch_text"))
		ok("refusal text, %s, names both builds" % d[0], d[2].all(func(s): return text.contains(s)), text.c_escape())
	nm.set("_mp8_host_version", host_before)
	var host_text := str(nm.call("_mp8_blocked_text_for_host", "v2.1.2+overtime-1.7"))
	ok("host's line names both builds", host_text.contains("overtime-1.7") and host_text.contains(TAG), host_text.c_escape())
	_hunter_hud(true)
	_hunter_hud(false)
	_text_checks()
	_chinese(nm)
	TranslationServer.set_locale(locale_before)
	await _intro_rack(4)
	await _intro_rack(8)
	await _intro_rack(4, true)
	await _intro_unstack(nm)
	await _wheat_field()
	await _hidden_renders()
	await _deck_blink(nm)
	await _countdown_out_of_tree(nm)
	await _thrown_unstick(nm)
	await _follow_unstick(nm)
	await _throw_grace(nm)

# The dev switches: every switch of ours is read from mp8_dev_args(), empty outside a test build.
# Every run checks the list against the build's verdict. With MP8_DEV_EXPECT=release|test and DEV_ARGS on
# the command line (MP_GAME_ARGS), only this step runs: the verdict must be the expected one, and a few real
# read sites must take the switch in a test build and their default in a shipped one.
const DEV_ARGS := ["mp8name=3", "mp8bold=0", "mp8audit", "mp8promoat=1,2,3", "mp8spread=20"]

func _dev_switches(nm: Node) -> void:
	say("step: dev switches")
	var expect := OS.get_environment("MP8_DEV_EXPECT")
	var allowed: bool = nm.call("mp8_development_tools_allowed")
	var raw := OS.get_cmdline_args()
	ok("mp8_dev_args() exists", nm.has_method("mp8_dev_args"))
	if nm.has_method("mp8_dev_args"):
		var dev: PackedStringArray = nm.call("mp8_dev_args")
		ok("mp8_dev_args() is the command line exactly when tools are allowed", dev == (raw if allowed else PackedStringArray()), [allowed, dev.size(), raw.size()])
	if expect == "":
		return
	ok("MP8_DEV_EXPECT is release or test", expect in ["release", "test"], expect)
	var test := expect == "test"
	ok("the switches are on the command line", DEV_ARGS.all(func(a): return raw.has(a)), " ".join(raw))
	ok("MP8_TEST_BUILD is %s" % str(test), nm.get("MP8_TEST_BUILD") == test, nm.get("MP8_TEST_BUILD"))
	ok("dev tools %s" % ("allowed" if test else "refused"), allowed == test)
	var uc: GDScript = load("res://minigames/intermission_new/components/intermission_user_container.gd")
	var name_max: int = uc.call("_mp8_arg_int", "mp8name=", -1)
	ok("name cut (a static helper): %s" % ("the switch's 3" if test else "the default"), name_max == (3 if test else -1), name_max)
	var uc2: GDScript = load("res://minigames/intermission_new/components/intermission_user_container_2d.gd")
	var bold: float = uc2.call("_mp8_arg_float", "mp8bold=", -1.0)
	ok("bold (the 2D container's helper): %s" % ("the switch's 0" if test else "the default"), bold == (0.0 if test else -1.0), bold)
	ok("audit log: %s" % ("on" if test else "off"), nm.get("_mp8_audit_on") == test, nm.get("_mp8_audit_on"))
	var gs := _game_script("game stand-in (dev switches)", false)
	if gs != null:
		var g: Node = gs.new()
		var at: String = g.call("_mp8_arg", "mp8promoat=")
		ok("promo times (game.gd's helper): %s" % ("the switch's" if test else "none"), at == ("1,2,3" if test else ""), at)
		g.free()
	var hunter: Node = load(HUNTER).instantiate()
	var spread: float = hunter.call("_mp8_hipfire_spread_deg")
	var stock: float = hunter.get("mp8_hipfire_spread_deg")
	ok("hip-fire spread: %s" % ("the switch's 20" if test else "the member's"), spread == (20.0 if test else stock), [spread, stock])
	hunter.free()

# The relay (mp8_net.gd): every listed method exists in its game script and is no @rpc of the game's, the
# join data carries the key, and the two predicates read it. A name missing from a script would make
# every call to it a silent no-op on the receiving peers.
func _relay(nm: Node) -> void:
	say("step: the relay and the key")
	var relays := get_tree().root.get_children().filter(func(n): return n.name == &"MP8Net")
	ok("one relay at /root/MP8Net", relays.size() == 1, relays.size())
	if relays.size() != 1:
		return
	var relay: Node = relays[0]
	var targets: Dictionary = relay.get("TARGETS")
	var count := 0
	for path in targets:
		var script := load(path) as GDScript
		ok("relay target script loads: %s" % path, script != null)
		if script == null:
			continue
		var names := script.get_script_method_list().map(func(m): return String(m["name"]))
		var rpcs: Dictionary = script.get_rpc_config()
		for method in targets[path]:
			count += 1
			ok("relay target %s.%s exists" % [path.get_file(), method], names.has(method))
			ok("relay target %s.%s is no @rpc" % [path.get_file(), method], not (rpcs.has(method) or rpcs.has(StringName(method))))
	ok("relay lists 34 targets", count == 34, count)
	var duck_rpcs: Dictionary = (load("res://minigames/duck_hunt/scripts/duck_hunt.gd") as GDScript).get_rpc_config()
	ok("the @rpc lookup sees a game RPC", duck_rpcs.has("set_ducks_ambient_light_rpc") or duck_rpcs.has(&"set_ducks_ambient_light_rpc"), duck_rpcs.keys())
	var probe := Node.new()
	add_child(probe)
	relay.send(0, probe, &"queue_free", [])
	ok("relay refuses an unlisted method", is_instance_valid(probe) and not probe.is_queued_for_deletion())
	probe.free()

	var backend := Node.new()
	backend.set_script(load("res://modules/multiplayer/backends/multiplayer_backend.gd"))
	backend.call("set_self_data", {"name": "selftest"})
	ok("join data carries the key", backend.get("self_data").get("mp8") == TAG, backend.get("self_data"))
	backend.free()

	var active = nm.get("active_backend")
	ok("a backend exists to read", active != null)
	if active == null:
		return
	var was_local: bool = GameManager.local_game
	var players: Dictionary = active.connected_players.duplicate()
	GameManager.local_game = false
	active.connected_players.clear()
	active.connected_players[1] = {"mp8": TAG}
	active.connected_players[7] = {"mp8": TAG}
	# Offline Bots' entry for a bot, which is no peer (bot_manager.gd's _connected_entry_for).
	active.connected_players[5] = {"id": 0, "peer_id": 5, "game_version": Globals.game_version, "is_bot": true}
	ok("an Extended peer", nm.mp8_peer_extended(7))
	ok("an Extended-only room", nm.mp8_peers_extended([7]))
	ok("no peers yet is Extended", nm.mp8_peers_extended([]))
	active.connected_players[9] = {"game_version": "v2.1.2"}
	ok("a vanilla peer", not nm.mp8_peer_extended(9))
	ok("an unknown peer", not nm.mp8_peer_extended(11))
	ok("a mixed room", not nm.mp8_peers_extended([7, 9]))
	ok("a peer with no player entry yet (mid-handshake) is skipped", nm.mp8_peers_extended([7, 11]))
	ok("but a vanilla player beside it still makes a mixed room", not nm.mp8_peers_extended([7, 11, 9]))
	active.connected_players[9] = {"mp8": "mp8-0.21"}
	ok("another Extended version is not this one", not nm.mp8_peers_extended([7, 9]))
	active.connected_players[9] = {"mp8": 22}
	ok("a key that is no String is not Extended", not nm.mp8_peer_extended(9))
	ok("online with no peers, this room is Extended: a bot's and a non-peer's entries are not counted", nm.mp8_room_extended(), multiplayer.get_peers())
	GameManager.local_game = true
	ok("the couch is always Extended", nm.mp8_room_extended())
	active.connected_players.clear()
	active.connected_players.merge(players)
	GameManager.local_game = was_local

# The join rules, the Steam member limit, the per-minigame latch and the refusal texts, on crafted rooms.
# With no real peers the live room reads Extended, so a mixed room is handed to mp8_join_refusal_in.
func _join_rules(nm: Node) -> void:
	say("step: the join rules")
	var rr: Dictionary = NetworkManager.RefuseReason
	ok("refusal reasons 0-3 are vanilla's", rr.get("None") == 0 and rr.get("VersionMismatch") == 1 and rr.get("SessionEnded") == 2 and rr.get("HostLeft") == 3, rr)
	ok("MP8RoomFull is 4, past vanilla's", rr.get("MP8RoomFull") == 4, rr)
	var full: int = rr.get("MP8RoomFull", -9)
	var mismatch: int = rr.get("VersionMismatch", -9)
	var active = nm.get("active_backend")
	ok("a backend exists for the join rules", active != null)
	if active == null:
		return
	var players: Dictionary = active.connected_players.duplicate()
	var was_local: bool = GameManager.local_game
	GameManager.local_game = false
	var ext := {"game_version": Globals.game_version, "mp8": TAG}
	var van := {"game_version": Globals.game_version}
	var cases := [
		# [what, players already in, joiner's data, room Extended, expected]
		["an Extended-only room of 7 takes an Extended 8th", 7, ext, true, -1],
		["at 8, an Extended 9th is left to the game's spectator rule", 8, ext, true, -1],
		["a vanilla 4th joins", 3, van, true, -1],
		["a vanilla 5th is refused", 4, van, true, full],
		["an Extended 5th is refused while a vanilla player is in", 4, ext, false, full],
		["an Extended 4th joins a mixed room", 3, ext, false, -1],
		["another Extended version is refused", 2, {"game_version": Globals.game_version, "mp8": "mp8-0.21"}, true, mismatch],
		["Extended 1.0 is refused", 2, {"game_version": Globals.game_version, "mp8": "mp8-1.0"}, true, mismatch],
		["a key that is no String counts as vanilla at 5", 4, {"game_version": Globals.game_version, "mp8": 22}, true, full],
		["a key that is no String counts as vanilla at 4", 3, {"game_version": Globals.game_version, "mp8": 22}, true, -1],
	]
	for c in cases:
		_fill_room(active, c[1])
		var got: int = nm.call("mp8_join_refusal_in", 50, c[2], c[3])
		ok("join rule: %s" % c[0], got == c[4], got)
	_fill_room(active, 3)
	active.connected_players[5] = {"id": 0, "peer_id": 5, "game_version": Globals.game_version, "is_bot": true}
	ok("join rule: Offline Bots' bots count toward the room's size", nm.call("mp8_join_refusal_in", 50, van, true) == full)
	_fill_room(active, 3)
	active.connected_players[50] = van
	ok("join rule: the joiner's own entry is not counted", nm.call("mp8_join_refusal_in", 50, van, true) == -1)
	_fill_room(active, 4)
	ok("join rule, live room: an Extended 5th joins with no vanilla peer", nm.call("mp8_join_refusal", 50, ext) == -1)
	ok("join rule, live room: a vanilla 5th is refused", nm.call("mp8_join_refusal", 50, van) == full)

	var cap: int = nm.get("max_player_count")
	ok("Steam limit: a mixed room holds 4", nm.call("mp8_lobby_limit", 3, false) == 4)
	ok("Steam limit: never below the members in it", nm.call("mp8_lobby_limit", 5, false) == 5)
	ok("Steam limit: an Extended room holds max_player_count", nm.call("mp8_lobby_limit", 2, true) == cap, cap)

	active.connected_players.clear()
	nm.set("_mp8_room_latch", 0)
	ok("latch: a minigame latched mixed stays mixed while the live room reads Extended", not nm.mp8_room_extended())
	nm.call("mp8_unlatch_room")
	ok("latch: unlatched, the live room again", nm.mp8_room_extended())
	nm.call("mp8_latch_room")
	ok("latch: latching stores the live room", nm.get("_mp8_room_latch") == 1, nm.get("_mp8_room_latch"))
	nm.set("_mp8_room_latch", 0)
	GameManager.local_game = true
	ok("latch: the couch is always Extended", nm.mp8_room_extended())
	GameManager.local_game = false
	nm.call("mp8_unlatch_room")

	var said: Array = []
	var hear := func(text): said.append(text)
	nm.mp8_join_blocked.connect(hear)
	nm.call("mp8_note_refusal", 50, full, van)
	nm.call("mp8_note_refusal", 51, full, ext)
	nm.call("mp8_note_refusal", 52, mismatch, {"game_version": "v2.1.2+mp8-0.21"})
	nm.call("mp8_note_refusal", 53, mismatch, {"game_version": Globals.game_version, "mp8": "mp8-0.23"})
	nm.mp8_join_blocked.disconnect(hear)
	ok("host's line, a vanilla 5th", said.size() > 0 and str(said[0]).contains("without Extended") and str(said[0]).contains("over 4"), said)
	ok("host's line, an Extended 5th in a mixed room", said.size() > 1 and str(said[1]).contains("holds 4"), said)
	ok("host's line, an older Extended names both builds", said.size() > 2 and str(said[2]).contains("mp8-0.21") and str(said[2]).contains(TAG), said)
	ok("host's line, another Extended's key names both builds", said.size() > 3 and str(said[3]).contains("mp8-0.23") and str(said[3]).contains(TAG), said)
	var refused: Dictionary = nm.get("_mp8_refused")
	ok("refused peers are noted, so their leave isn't told twice", [50, 51, 52, 53].all(func(id): return refused.has(id)), refused.keys())
	for id in [50, 51, 52, 53]:
		refused.erase(id)
	var room_full := str(nm.get("MP8_ROOM_FULL_TEXT"))
	ok("the joiner's room-full text fits the dialog's 3 lines", room_full.split("\n").size() <= 3 and room_full.contains("4"), room_full.c_escape())
	var host_before = nm.get("_mp8_host_version")
	nm.set("_mp8_host_version", "")
	var unknown := str(nm.call("mp8_mismatch_text"))
	ok("refusal text with no host version names ours", unknown.contains(TAG) and unknown.contains("unknown"), unknown.c_escape())
	nm.set("_mp8_host_version", host_before)

	active.connected_players.clear()
	active.connected_players.merge(players)
	GameManager.local_game = was_local

func _fill_room(active, n: int) -> void:
	active.connected_players.clear()
	for i in n:
		active.connected_players[100 + i] = {"mp8": TAG}

# The audit's "Every minigame" rows: each gate's Extended path and the game's own, in a room held by the
# latch, as a minigame sees it. With no real peers only the latch can make a room mixed.
func _stage(nm: Node, extended: bool) -> void:
	GameManager.local_game = false
	nm.set("_mp8_room_latch", 1 if extended else 0)

func _shared_rows(nm: Node) -> void:
	say("step: the shared rows' gates")
	if nm.get("active_backend") == null:
		ok("a backend exists for the shared rows", false)
		return
	var was_local: bool = GameManager.local_game
	var was_minigame = Globals.current_minigame_identifier
	await _preload_guards(nm)
	await _topup(nm)
	await _game_rows(nm)
	await _intermission_rows(nm)
	_minigame_rows(nm)
	_mixed_rows(nm)
	_mixed_slice_rows(nm)
	_mixed_debris_rows(nm)
	_mixed_spine_rows(nm)
	_mixed_filter_rows(nm)
	await _mixed_shared_rows(nm)
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local
	Globals.current_minigame_identifier = was_minigame

# A typed copy: set() leaves a typed property as it was when handed an untyped Dictionary.
func _ints(d: Dictionary) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for k in d:
		out[k] = d[k]
	return out

# A script compiled at runtime from source; null, and a FAIL, if it does not compile.
func _runtime_script(label: String, source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	var err := s.reload()
	ok("%s compiles" % label, err == OK, err)
	return s if err == OK else null

# The mixed-room copies' rows: a stand-in on a game script, its frame callbacks replaced and each named copy of the game's code
# (`_mp8_game_<name>`, full signature) counting its calls instead of running. That a copy equals src/ is checked
# outside the game, line for line.
func _copy_script(label: String, path: String, copies: Array, extra: Array = []) -> GDScript:
	var lines := ["extends \"%s\"" % path, "var mp8_test_copies := 0",
		"func _enter_tree() -> void:\n\tpass", "func _ready() -> void:\n\tpass",
		"func _process(_d: float) -> void:\n\tpass", "func _physics_process(_d: float) -> void:\n\tpass",
		"func _exit_tree() -> void:\n\tpass"]
	for c in copies:
		lines.append("func %s:\n\tmp8_test_copies += 1" % c)
	return _runtime_script(label, "\n".join(lines + extra + [""]))

# Whether a script declares a method itself: an older build has none, and its rows FAIL here
# rather than run a path that needs a scene.
func _declares(path: String, method: String) -> bool:
	var s := load(path) as GDScript
	return s != null and s.get_script_method_list().any(func(m): return m["name"] == method)

# One copy's row: the method is called on a stand-in, and the copy counts. Extended's own path must not reach it.
func _copy_row(label: String, path: String, sig: String, extended: bool, method: String, args: Array = [], sets: Dictionary = {}) -> void:
	var room := "Extended" if extended else "mixed"
	var copy_name := sig.substr(0, sig.find("("))
	if not _declares(path, copy_name):
		ok("%s, %s: the game's %s is declared" % [label, room, copy_name], false)
		return
	var s := _copy_script(label + " stand-in", path, [sig])
	if s == null:
		return
	var n: Node = s.new()
	add_child(n)
	for k in sets:
		n.set(k, sets[k])
	n.callv(method, args)
	var got: int = n.get("mp8_test_copies")
	ok("%s, %s: %s" % [label, room, "Extended's own" if extended else "the game's copy"], got == (0 if extended else 1), got)
	n.free()

const GAME := "res://scripts/scenes/game/game.gd"
const SMOKE := "res://minigames/smoke_break/scripts/smoke_break.gd"
const TROLLEY := "res://minigames/smoke_break/scripts/smoke_break_trolley.gd"
const DVD := "res://minigames/dvd_roomba/scripts/dvd_roomba.gd"
const TRAIN := "res://minigames/train_race/scripts/train_race.gd"
const WHEAT := "res://minigames/cutscene_test/scripts/cutscene_test.gd"
const COLLAR := "res://minigames/exploding_collar_race/scripts/exploding_collar_race.gd"
const DISCO := "res://minigames/disco_dodge/scrips/disco_dodge.gd"
const OVERLAY := "res://modules/minigame/components/overlay/scripts/minigame_overlay.gd"

# The mixed-room copies in the first minigames and the overlay: a mixed room runs the game's function, an Extended one its own.
# Where Extended's path needs a scene, only the mixed call is made.
func _mixed_rows(nm: Node) -> void:
	say("step: the mixed-room copies, the first minigames (%d presences)" % PlayerManager.player_presences.size())
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		# Extended returns at its end flag; the copy, counted, would not.
		_copy_row("DVD Roomba check_game_end", DVD, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"finished": true})
		_copy_row("Train Race check_game_end", TRAIN, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"game_end": true})
		# Extended: no seat for 99, so its .get() path returns; mixed: the game's tail after the super call.
		_copy_row("Smoke Break disconnect", SMOKE, "_mp8_game_player_disconnected_tail(_network_id: int)", extended, "player_disconnected", [99])
		# Extended: no revolver angle for seat 0 on a stand-in, so its bounds check returns.
		_copy_row("Smoke Break shot", TROLLEY, "_mp8_game_shoot_player(seat: int)", extended, "shoot_player", [0])
		if not extended:
			_copy_row("Smoke Break spawns", SMOKE, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Train Race spawns", TRAIN, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Wheat field spawns", WHEAT, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Minefield spawns", COLLAR, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Minefield mines", COLLAR, "_mp8_game_spawn_mines()", false, "spawn_mines")
			_copy_row("overlay countdown", OVERLAY, "_mp8_game_set_countdown(text: String, _with_fade: bool = true, _fade_time: float = 0.5)", false, "set_countdown", ["GO!"])
		# Each spawn setup sets mp8_player_count first when it runs; a mixed room returns before it.
		for c in [["Train Race", TRAIN, "_mp8_expand_spawns"], ["Stable Footing", DISCO, "_mp8_setup_spawns"],
				["Minefield", COLLAR, "_mp8_setup_spawns"], ["Smoke Break", SMOKE, "_mp8_setup_seats"]]:
			var s := _copy_script("%s spawn setup stand-in" % c[0], c[1], [])
			if s == null:
				continue
			var n: Node = s.new()
			add_child(n)
			n.set("mp8_player_count", -1)
			n.call(c[2])
			var count: int = n.get("mp8_player_count")
			ok("%s spawn setup, %s: %s" % [c[0], room, "runs" if extended else "skipped, the game's spawns kept"], (count >= 0) == extended, count)
			n.free()
		var cs := _copy_script("Minefield death order stand-in", COLLAR, [], [
			"@rpc(\"authority\", \"call_local\", \"reliable\")",
			"func remove_active_player_rpc(_network_id: int, remove_player_character: bool = false):\n\tpass"])
		if cs != null:
			var mg: Node = cs.new()
			add_child(mg)
			mg.call("_on_player_exploded", 5)
			var order: Array = mg.get("_mp8_dead_order")
			ok("Minefield death order, %s: %s" % [room, "kept" if extended else "not kept, as the game keeps none"], order.size() == (1 if extended else 0), order)
			mg.free()
	nm.call("mp8_unlatch_room")

const TM := "res://minigames/green_pea/scripts/green_pea.gd"
const TM_HANDLER := "res://minigames/green_pea/components/coach_handler/coach_handler.gd"
const TM_COACH := "res://minigames/green_pea/components/coach_handler/green_pea_coach.gd"
const CHISEL := "res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet.gd"
const CHISEL_PLAYER := "res://minigames/chisel_gauntlet_multiplayer/components/player/scripts/chisel_gauntlet_player.gd"
const CHISEL_LOCAL := "res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet_local_handler.gd"
const DUCK_HUNT := "res://minigames/duck_hunt/scripts/duck_hunt.gd"
const DUCK := "res://minigames/duck_hunt/components/duck_player/scripts/duck_player.gd"
const HUNTER_SCRIPT := "res://minigames/duck_hunt/components/hunter_player/scripts/hunter_player.gd"
const DUCK_LOCAL := "res://minigames/duck_hunt/scripts/duck_hunt_local_handler.gd"
const DUCK_REVEAL := "res://minigames/duck_hunt/states/role_reveal_state.gd"

# The mixed-room copies in Table Manners, Chisel and Duck Hunt: a mixed room runs the game's function, an Extended one
# its own. Extended's path is called only where a stand-in returns early (an end flag, no players, inactive).
func _mixed_slice_rows(nm: Node) -> void:
	say("step: the mixed-room copies, Table Manners, Chisel and Duck Hunt")
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		_copy_row("Table Manners end check", TM, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"finished": true})
		_copy_row("Table Manners halfway", TM, "_mp8_game_on_player_halfway(_network_id: int)", extended, "_on_player_halfway", [99])
		_copy_row("Table Manners press", TM_HANDLER, "_mp8_game_on_player_acted(_network_id: int, seat_index: int)", extended, "_on_player_acted", [99, 0], {"executing": true})
		_copy_row("Table Manners pause", TM_COACH, "_mp8_game_pause_eating_for_players(position_being_shot: int)", extended, "pause_eating_for_players", [0])
		_copy_row("Table Manners resume", TM_COACH, "_mp8_game_continue_eating_for_players()", extended, "continue_eating_for_players")
		_copy_row("Chisel pad input", CHISEL_HANDLER, "_mp8_game_process_controller_input(_delta: float)", extended, "process_controller_input", [0.016], {"active": false})
		_copy_row("Duck Hunt end check", DUCK_HUNT, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"resetting": true})
		_copy_row("duck shot", DUCK, "_mp8_game_shot_rpc(_damage: int)", extended, "shot_rpc", [1], {"active": false})
		# Offline Bots takes this script's path over with a subclass of it, so no stand-in can extend the path. By
		# effect instead: Extended's frame sets the fake cursor's alpha (0 here, off its pane), the game's never does.
		if _declares(CHISEL_LOCAL, "_mp8_game_process"):
			var lh: Node = load(CHISEL_LOCAL).new()
			add_child(lh)
			var ui := Control.new()
			add_child(ui)
			var cursor := Control.new()
			ui.add_child(cursor)
			var pane := TextureRect.new()
			ui.add_child(pane)
			pane.size = Vector2(100, 100)
			var kb: Node = load(CHISEL_PLAYER).new()
			var vp := SubViewport.new()
			kb.set("local_viewport", vp)
			lh.set("local_canvas_root", ui)
			lh.set("fake_cursor", cursor)
			lh.set("keyboard_player", kb)
			lh.set("keyboard_rect", pane)
			lh.set("keyboard_values", [Vector2.ZERO, Vector2(0.5, 0.5)])
			cursor.modulate.a = 0.5
			lh.call("_process", 0.016)
			var alpha: float = cursor.modulate.a
			ok("Chisel local frame, %s: %s" % [room, "Extended's own" if extended else "the game's copy"], is_equal_approx(alpha, 0.5) != extended, alpha)
			lh.free()
			ui.free()
			kb.free()
			vp.free()
		else:
			ok("Chisel local frame, %s: the game's _process is declared" % room, false)
		# The game's handlers have no _ready; Extended's connects the relayout to the window's size.
		for c in [["Chisel", CHISEL_LOCAL], ["Duck Hunt", DUCK_LOCAL]]:
			var h: Node = load(c[1]).new()
			add_child(h)
			var linked: bool = get_viewport().size_changed.is_connected(Callable(h, "_mp8_relayout"))
			ok("%s local handler's _ready, %s: %s" % [c[0], room, "connects" if extended else "connects nothing, as the game"], linked == extended, linked)
			h.free()
		if not extended:
			_copy_row("Table Manners coach's players", TM_HANDLER, "_mp8_game_set_players(_players)", false, "set_players", [{}])
			_copy_row("Table Manners shot over", TM_HANDLER, "_mp8_game_on_execution_finished()", false, "_on_execution_finished")
			_copy_row("Table Manners glance timer", TM_HANDLER, "_mp8_game_on_timer_timeout()", false, "_on_timer_timeout")
			_copy_row("Table Manners shot", TM_COACH, "_mp8_game_shoot_player(seat_position_to_shoot: int)", false, "shoot_player", [0])
			_copy_row("Table Manners shot visuals", TM_COACH, "_mp8_game_gun_shot_visuals(seat_position_to_shoot: int)", false, "gun_shot_visuals", [0])
			_copy_row("Table Manners finish", TM, "_mp8_game_on_player_finished(_network_id: int)", false, "_on_player_finished", [99])
			_copy_row("Table Manners death", TM, "_mp8_game_on_player_died(_network_id: int)", false, "_on_player_died", [99])
			_copy_row("Chisel spawns", CHISEL, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Chisel instructions", CHISEL, "_mp8_game_generate_random_cube_instructions()", false, "generate_random_cube_instructions")
			_copy_row("Chisel round timer", CHISEL, "_mp8_game_start_round_timer(_duration: float)", false, "start_round_timer", [1.0])
			_copy_row("Chisel spectator", CHISEL_PLAYER, "_mp8_game_set_spectator_rpc()", false, "set_spectator_rpc")
			_copy_row("Chisel look", CHISEL_PLAYER, "_mp8_game_look_at_rpc(target: ChiselGauntletPlayer.LookAtTarget)", false, "look_at_rpc", [0])
			_copy_row("Chisel teleport", CHISEL_PLAYER, "_mp8_game_teleport_rpc(_position: Vector3, _rotation: Vector3)", false, "teleport_rpc", [Vector3.ZERO, Vector3.ZERO])
			_copy_row("Duck Hunt spawns", DUCK_HUNT, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Duck Hunt role acknowledged", DUCK_HUNT, "_mp8_game_acknowledge_role_rpc(_network_id: int)", false, "acknowledge_role_rpc", [99])
			_copy_row("Duck Hunt player removed", DUCK_HUNT, "_mp8_game_remove_player_rpc(_network_id: int)", false, "remove_player_rpc", [99])
			_copy_row("Duck Hunt escape", DUCK_HUNT, "_mp8_game_on_player_finished(_network_id: int)", false, "_on_player_finished", [99])
			_copy_row("Duck Hunt duck died", DUCK_HUNT, "_mp8_game_on_player_died(_network_id: int)", false, "_on_player_died", [99])
			_copy_row("hunter shot", HUNTER_SCRIPT, "_mp8_game_shoot()", false, "shoot")
			_copy_row("hunter active", HUNTER_SCRIPT, "_mp8_game_set_active_rpc(_active: bool)", false, "set_active_rpc", [true])
			_copy_row("hunter setup", HUNTER_SCRIPT, "_mp8_game_setup_rpc(_position: Vector3, _duck_count: int)", false, "setup_rpc", [Vector3.ZERO, 3])
			_copy_row("duck teleport", DUCK, "_mp8_game_teleport_rpc(_position: Vector3)", false, "teleport_rpc", [Vector3.ZERO])
			_copy_row("Duck Hunt reveal", DUCK_REVEAL, "_mp8_game_reveal_online()", false, "reveal_online")
			# The game's call passes one hunter viewport; the dispatch is by that shape, so either room.
			var vp_a := SubViewport.new()
			var vp_b := SubViewport.new()
			_copy_row("Duck Hunt local views, the game's call", DUCK_LOCAL, "_mp8_game_setup(players_viewport: SubViewport, hunter_viewport: SubViewport)", false, "setup", [vp_a, vp_b])
			vp_a.free()
			vp_b.free()
			# A duck's frame: called directly, out of the tree.
			var ds: GDScript = null
			if _declares(DUCK, "_mp8_game_physics_process"):
				ds = _runtime_script("duck frame stand-in", "extends \"%s\"\nvar mp8_test_copies := 0\nfunc _mp8_game_physics_process(delta: float):\n\tmp8_test_copies += 1\n" % DUCK)
			if ds == null:
				ok("duck frame, mixed: the game's _physics_process is declared", false)
			else:
				var d: Node = ds.new()
				d.call("_physics_process", 0.016)
				ok("duck frame, mixed: the game's copy", d.get("mp8_test_copies") == 1, d.get("mp8_test_copies"))
				d.free()
			# Extended's seats would add markers and then reach for the scene's chairs, so only the mixed call.
			if _declares(TM, "_mp8_game_check_game_end"):
				var ts := _copy_script("Table Manners seats stand-in", TM, [])
				if ts != null:
					var tm: Node = ts.new()
					add_child(tm)
					var seats := Node3D.new()
					tm.add_child(seats)
					for i in 4:
						seats.add_child(Marker3D.new())
					tm.set("player_spawn_positions", seats)
					tm.call("_mp8_setup_seats")
					ok("Table Manners seats, mixed: the game's 4", seats.get_child_count() == 4 and tm.get("_mp8_seat_z").is_empty(), seats.get_child_count())
					tm.free()
			else:
				ok("Table Manners seats, mixed: the build has the mixed-room copies", false)
	# The game's two hunter tables, read by its shoot and set_active_rpc (the scene sets neither).
	var hunter: Node = load(HUNTER_SCRIPT).new()
	ok("hunter: the game's magazine table", str(hunter.get("magazine_capacity_by_duck_count")) == str({0: 7, 1: 7, 2: 8, 3: 10}), hunter.get("magazine_capacity_by_duck_count"))
	ok("hunter: the game's cycle table", str(hunter.get("reload_speed_by_duck_count")) == str({0: 0.95, 1: 0.95, 2: 0.9, 3: 0.8}), hunter.get("reload_speed_by_duck_count"))
	hunter.free()
	nm.call("mp8_unlatch_room")

const JP := "res://minigames/junk_platform/scripts/junk_platform.gd"
const JP_COMPACTOR := "res://minigames/junk_platform/scripts/junk_platform_compactor.gd"
const JP_CUBE := "res://minigames/junk_platform/components/junk_cube_rigidbody/junk_platform_cube_rigidbody.gd"
const JP_PLAYER := "res://minigames/junk_platform/components/player/scripts/junk_platform_player.gd"
const JP_HANDLER := "res://minigames/junk_platform/scripts/junk_handler.gd"

# The mixed-room copies in Debris Platforms: a mixed room runs the game's function, an Extended one its own. Extended's
# path is called only where a stand-in returns early (an end flag, a body that is no player, a path that resolves
# to nothing, a hit player, the pause).
func _mixed_debris_rows(nm: Node) -> void:
	say("step: the mixed-room copies, Debris Platforms")
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		_copy_row("Debris end check", JP, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"finished": true})
		var body := Node3D.new()
		add_child(body)
		_copy_row("Debris compactor kill", JP_COMPACTOR, "_mp8_game_on_body_entered(body)", extended, "on_body_entered", [body])
		body.free()
		_copy_row("Debris grab", JP_CUBE, "_mp8_game_set_held_rpc(held: bool, _held_by: NodePath)", extended, "set_held_rpc", [true, NodePath("mp8_no_such_node")])
		_copy_row("Debris throw", JP_PLAYER, "_mp8_game_update_interaction(_delta: float)", extended, "update_interaction", [0.016], {"is_hit": true})
		_copy_row("Debris junk phase", JP_HANDLER, "_mp8_game_set_active(_active: bool)", extended, "set_active", [false])
		_copy_row("Debris junk drop", JP_HANDLER, "_mp8_game_on_timer_timeout()", extended, "_on_timer_timeout", [], {"mp8_paused": true})
		# The handler's frame, by effect as well: Extended's clears the idle times while the junk is off, the game's
		# keeps none.
		if _declares(JP_HANDLER, "_mp8_game_physics_process"):
			var hs := _runtime_script("Debris junk frame stand-in", "extends \"%s\"\nvar mp8_test_copies := 0\nfunc _ready() -> void:\n\tpass\nfunc _mp8_game_physics_process(_delta: float) -> void:\n\tmp8_test_copies += 1\n" % JP_HANDLER)
			if hs != null:
				var h: Node = hs.new()
				add_child(h)
				h.set_physics_process(false)
				var idle: Dictionary[int, float] = {7: 1.0}
				h.set("mp8_idle_time", idle)
				h.call("_physics_process", 0.016)
				var left: int = (h.get("mp8_idle_time") as Dictionary).size()
				ok("Debris junk frame, %s: %s" % [room, "Extended's own" if extended else "the game's copy"], h.get("mp8_test_copies") == (0 if extended else 1) and (left == 0) == extended, [h.get("mp8_test_copies"), left])
				h.free()
		else:
			ok("Debris junk frame, %s: the game's _physics_process is declared" % room, false)
		if not extended:
			_copy_row("Debris spawns", JP, "_mp8_game_spawn_players()", false, "spawn_players")
			_copy_row("Debris camera turn", JP, "_mp8_game_rotate_camera_rpc(_rotation: float)", false, "rotate_camera_rpc", [180.0])
			_copy_row("Debris slam", JP_COMPACTOR, "_mp8_game_slam()", false, "slam")
			_copy_row("Debris cube reset", JP_CUBE, "_mp8_game_reset_rpc()", false, "reset_rpc")
			# The countdown's end: the game's super call sends "GO!" to the overlay, answered here.
			if _declares(JP, "_mp8_game_on_countdown_expired_tail"):
				var cs := _copy_script("Debris countdown stand-in", JP, ["_mp8_game_on_countdown_expired_tail()"], [
					"@rpc(\"any_peer\", \"call_local\", \"reliable\")",
					"func set_countdown_mesage_rpc(message: String, fade_time: float = 0.5, _size: int = 128):\n\tpass"])
				if cs != null:
					var mg: Node = cs.new()
					add_child(mg)
					mg.call("_on_countdown_expired")
					ok("Debris countdown end, mixed: the game's tail", mg.get("mp8_test_copies") == 1, mg.get("mp8_test_copies"))
					mg.free()
			else:
				ok("Debris countdown end, mixed: the game's tail is declared", false)
			# _ready itself: the stand-in keeps it, so add_child runs Minigame._ready, whose sends are answered here and
			# whose cursor flags are put back. Extended's own _ready needs the scene, so only the mixed room.
			if _declares(JP, "_mp8_game_ready_tail"):
				var rs := _runtime_script("Debris ready stand-in", "\n".join(["extends \"%s\"" % JP, "var mp8_test_copies := 0",
					"func _mp8_game_ready_tail():\n\tmp8_test_copies += 1",
					"func initialize_debug_specifics():\n\tpass",
					"@rpc(\"any_peer\", \"call_local\", \"reliable\")",
					"func set_effects_visibility_rpc(_visible: bool):\n\tpass",
					"@rpc(\"any_peer\", \"call_remote\", \"reliable\")",
					"func player_loaded(network_id: int):\n\tpass", ""]))
				if rs != null:
					var cursor: Array = [GameManager.can_set_cursor, PauseMenu.game_target_can_set_cursor,
						PauseMenu.game_target_cursor_active, PauseMenu.game_target_cursor_visible]
					var mg: Node = rs.new()
					add_child(mg)
					ok("Debris _ready, mixed: the game's tail", mg.get("mp8_test_copies") == 1, mg.get("mp8_test_copies"))
					mg.free()
					GameManager.can_set_cursor = cursor[0]
					PauseMenu.game_target_can_set_cursor = cursor[1]
					PauseMenu.game_target_cursor_active = cursor[2]
					PauseMenu.game_target_cursor_visible = cursor[3]
			else:
				ok("Debris _ready, mixed: the game's tail is declared", false)
	nm.call("mp8_unlatch_room")

const JP_DECK := "res://minigames/junk_platform/components/platform/junk_platform_platform.tscn"

# A deck still blinking when it leaves the tree. The game's loop then never yields, so a build without
# the fix hangs here to the runner's kill; with it the loop ends, in both rooms. The minigame's scene sets the
# circles and the alarm, so the lone deck gets an empty circle parent and no alarm.
func _deck_blink(nm: Node) -> void:
	say("step: a Debris deck leaving the tree mid-blink")
	var scene := load(JP_DECK) as PackedScene
	if scene == null:
		ok("Debris deck scene loads", false, JP_DECK)
		return
	var was_local: bool = GameManager.local_game
	for extended in [true, false]:
		_stage(nm, extended)
		var deck: Node = scene.instantiate()
		var circles := Node3D.new()
		deck.add_child(circles)
		deck.set("damage_circle_parent", circles)
		deck.set("alarm_playing", false)
		add_child(deck)
		deck.call("start_blinking")
		await get_tree().create_timer(0.05).timeout
		remove_child(deck)
		var frame := Engine.get_process_frames()
		await get_tree().create_timer(0.35).timeout
		ok("Debris deck out of the tree mid-blink, %s: the loop ends" % ("Extended" if extended else "mixed"),
			deck.get("blinking") == true and Engine.get_process_frames() > frame + 2, Engine.get_process_frames() - frame)
		deck.free()
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local

const COUNTDOWN := "res://minigames/shared/states/countdown_state.gd"

# A minigame's countdown whose tick comes after a scene change has taken the minigame out of the tree
# but not yet freed it. The game's loop then awaits get_tree() on null, so a build without the fix dies here; with
# it the countdown ends, in both rooms. The stand-in owner answers only what enter() reads.
func _countdown_out_of_tree(nm: Node) -> void:
	say("step: a countdown leaving the tree mid-tick")
	var overlay_s := _runtime_script("countdown overlay stand-in", "extends Node\nvar countdown_screen := Control.new()\nfunc set_countdown(_s):\n\tpass\n")
	var owner_s := _runtime_script("countdown owner stand-in", "extends Node\nvar minigame_overlay\n")
	var state_s := load(COUNTDOWN) as GDScript
	if overlay_s == null or owner_s == null or state_s == null:
		ok("the countdown state and its stand-ins load", false)
		return
	var was_local: bool = GameManager.local_game
	for extended in [true, false]:
		_stage(nm, extended)
		var mg: Node = owner_s.new()
		var overlay: Node = overlay_s.new()
		mg.set("minigame_overlay", overlay)
		var state: Node = state_s.new()
		mg.add_child(state)
		state.owner = mg
		var ticks: Array = []
		state.connect("tick", func(t): ticks.append(t))
		add_child(mg)
		state.call("enter")
		await get_tree().create_timer(0.5).timeout
		remove_child(mg)
		await get_tree().create_timer(1.5).timeout
		ok("a countdown out of the tree mid-tick, %s: it ends there, with no tick" % ("Extended" if extended else "mixed"), ticks.is_empty(), ticks)
		overlay.get("countdown_screen").free()
		overlay.free()
		mg.free()
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local

# A thrown device held where move_and_slide never reports a floor (in the room, a vertical edge of the
# hidden Placeholder's collision boxes) stays in Thrown for good on a build without the fix; with it, the device
# moves to the nearest navmesh point, in both rooms. Here the hold is a free fall high above a navmesh quad.
func _thrown_unstick(nm: Node) -> void:
	say("step: a thrown device that never lands")
	var owner_s := _runtime_script("thrown device stand-in", "extends CharacterBody3D\nvar gravity := 10.0\n" +
		"var throw_speed_decay := 50.0\nvar players_node: Node3D = null\nvar navigation_agent: NavigationAgent3D\nvar mp8_index := 1\n")
	var state_s := load(SB_STATES + "thrown_state.gd") as GDScript
	if owner_s == null or state_s == null:
		ok("the thrown state and its stand-in load", false)
		return
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	add_child(region)
	var was_local: bool = GameManager.local_game
	for extended in [true, false]:
		_stage(nm, extended)
		var dev: CharacterBody3D = owner_s.new()
		var agent := NavigationAgent3D.new()
		dev.add_child(agent)
		dev.set("navigation_agent", agent)
		var state: Node = state_s.new()
		dev.add_child(state)
		state.owner = dev
		add_child(dev)
		dev.global_position = Vector3(3, 50, 3)
		state.set("active", true)
		await get_tree().physics_frame
		for i in 150:
			await get_tree().physics_frame
			state.call("update_physics", 1.0 / 60.0)
		var p: Vector3 = dev.global_position
		ok("a thrown device that never lands, %s: moved to the navmesh within 2.5 s" % ("Extended" if extended else "mixed"),
			p.y < 5.0 and absf(p.x - 3.0) < 0.5 and absf(p.z - 3.0) < 0.5, p)
		dev.free()
	region.free()
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local

# A device chasing from inside one of the room's hidden collision boxes (a throw can start in there)
# never gets out on a build without the fix; with it, still for 3 s, it moves to the nearest navmesh point, in
# both rooms. Here the box is five static walls round the device, 20 m off a navmesh quad.
func _follow_unstick(nm: Node) -> void:
	say("step: a chasing device that cannot move")
	var owner_s := _runtime_script("chasing device stand-in", "extends CharacterBody3D\nvar gravity := 10.0\n" +
		"var speed := 5.0\nvar speed_increase_duration := 10.0\nvar speed_increase_over_time := 1.0\n" +
		"var players_in_proximity: Array = []\nvar game_instance = null\nvar navigation_agent: NavigationAgent3D\nvar mp8_index := 1\n")
	var state_s := load(SB_STATES + "follow_state.gd") as GDScript
	if owner_s == null or state_s == null:
		ok("the follow state and its stand-in load", false)
		return
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	add_child(region)
	var walls := StaticBody3D.new()
	for w in [[Vector3(30, -0.1, 30), Vector3(3, 0.2, 3)], [Vector3(28.9, 1.5, 30), Vector3(0.2, 3, 3)],
			[Vector3(31.1, 1.5, 30), Vector3(0.2, 3, 3)], [Vector3(30, 1.5, 28.9), Vector3(3, 3, 0.2)],
			[Vector3(30, 1.5, 31.1), Vector3(3, 3, 0.2)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		cs.position = w[0]
		walls.add_child(cs)
	add_child(walls)
	var was_local: bool = GameManager.local_game
	for extended in [true, false]:
		_stage(nm, extended)
		var dev: CharacterBody3D = owner_s.new()
		var body := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.5
		body.shape = ball
		dev.add_child(body)
		var agent := NavigationAgent3D.new()
		dev.add_child(agent)
		dev.set("navigation_agent", agent)
		var state: Node = state_s.new()
		dev.add_child(state)
		state.owner = dev
		add_child(dev)
		dev.global_position = Vector3(30, 0.6, 30)
		state.set("active", true)
		await get_tree().physics_frame
		for i in 210:
			await get_tree().physics_frame
			state.call("update_physics", 1.0 / 60.0)
		var p: Vector3 = dev.global_position
		ok("a chasing device that cannot move, %s: moved to the navmesh within 3.5 s" % ("Extended" if extended else "mixed"),
			p.x < 20.0 and p.z < 20.0, p)
		dev.free()
	walls.free()
	region.free()
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local

# Spine Breaker's second spider and a carrier: a player who throws a device off their back can't be chased or
# grabbed by another device for the throw grace, while a device thrown at them still attaches; a kick grants none;
# a dead end retargets in the same frame, not after the post-kill wait. A mixed room runs the game's code.
func _throw_grace(nm: Node) -> void:
	say("step: the throw grace and the dead end")
	var sm_s := _runtime_script("state machine stand-in", "\n".join(["extends \"res://modules/state_machine/StateMachine.gd\"",
		"var mp8_test_to: Array = []", "func _ready() -> void:\n\tpass", "func _process(_d: float) -> void:\n\tpass",
		"func _physics_process(_d: float) -> void:\n\tpass",
		"func transition_to(target_state_name: String, msg: Dictionary = {}, force: bool = false) -> void:\n\tmp8_test_to.append([String(target_state_name), msg])", ""]))
	var rpc_pass := "@rpc(\"any_peer\", \"call_local\", \"reliable\")"
	var mg_s := _copy_script("grace minigame stand-in", SB, [])
	var mg_rec_s := _copy_script("retarget-recording minigame stand-in", SB, [], ["var mp8_test_retargets: Array = []",
		"func mp8_retarget_now(dev) -> void:\n\tmp8_test_retargets.append(dev)"])
	var mg_cnt_s := _copy_script("target-counting minigame stand-in", SB, [], ["var mp8_test_chosen: Array = []",
		"func choose_new_target(which = null):\n\tmp8_test_chosen.append(which)"])
	var pl_s := _copy_script("grace player stand-in", SB_PLAYER, [], [rpc_pass,
		"func set_spine_breaker_rpc(_has_spine_breaker: bool, _thrown: bool = false, _from_direction: int = 0):\n\tpass"])
	var dev_s := _copy_script("grace device stand-in", SB_DEVICE, [], [rpc_pass, "func laugh_rpc():\n\tpass"])
	var follow_s := load(SB_STATES + "follow_state.gd") as GDScript
	var thrown_s := load(SB_STATES + "thrown_state.gd") as GDScript
	if sm_s == null or mg_s == null or mg_rec_s == null or mg_cnt_s == null or pl_s == null or dev_s == null or follow_s == null or thrown_s == null:
		ok("the throw grace's stand-ins load", false)
		return
	var was_local: bool = GameManager.local_game
	var trash: Array = []
	var room := Node3D.new()
	add_child(room)
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 0.2, 40)
	fcs.shape = fbox
	ground.add_child(fcs)
	room.add_child(ground)
	ground.position = Vector3(100, -0.1, 100)
	var players := Node3D.new()
	room.add_child(players)

	var mk_player := func(nid: int, at: Vector3) -> Node:
		var p: Node = pl_s.new()
		var pp := PlayerPresence.new()
		pp.network_id = nid
		trash.append(pp)
		p.set("player_presence", pp)
		p.set("active", true)
		players.add_child(p)
		p.global_position = at
		return p
	var mk_dev := func(mg: Node, index: int, at: Vector3) -> Node:
		var d: Node = dev_s.new()
		var sm: Node = sm_s.new()
		var cur := State.new()
		cur.name = "Follow"
		sm.set("current_state", cur)
		trash.append(cur)
		trash.append(sm)
		d.set("state_machine", sm)
		d.set("game_instance", mg)
		d.set("mp8_index", index)
		d.set("players_node", players)
		var body := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.5
		body.shape = ball
		d.add_child(body)
		room.add_child(d)
		d.global_position = at
		return d
	var mk_state := func(s: GDScript, d: Node) -> Node:
		var st: Node = s.new()
		d.add_child(st)
		st.owner = d
		st.set("state_machine", d.get("state_machine"))
		st.set("active", true)
		return st
	var to_of := func(d: Node) -> Array:
		return d.get("state_machine").get("mp8_test_to")

	# A dead end asks for its new target in the same frame (before the gate: a build without the change emits
	# request_new_target, which waits out MP8_DEVICE_WAIT).
	_stage(nm, true)
	var mg_rec: Node = mg_rec_s.new()
	add_child(mg_rec)
	var c: Node = mk_dev.call(mg_rec, 2, Vector3(105, 0.6, 105))
	var carrier: Node = mk_player.call(43, Vector3(106, 0.5, 106))
	var emitted := [0]
	c.connect("request_new_target", func(): emitted[0] += 1)
	var fc: Node = mk_state.call(follow_s, c)
	carrier.set("has_spine_breaker", true)
	fc.set("target", carrier)
	fc.call("_mp8_check_dead_end", 1.0 / 60.0)
	var recs: Array = mg_rec.get("mp8_test_retargets")
	ok("Extended: a dead end (the target took another device) retargets in the same frame",
		recs.size() == 1 and recs[0] == c and emitted[0] == 0, [recs.size(), emitted[0]])
	fc.free()

	var mg: Node = mg_s.new()
	add_child(mg)
	if not (mg.has_method("mp8_note_throw") and mg.has_method("mp8_in_throw_grace") and mg.has_method("mp8_retarget_now")):
		ok("the minigame declares mp8_note_throw, mp8_in_throw_grace and mp8_retarget_now", false)
	else:
		_stage(nm, true)
		var grace: float = mg.call("_mp8_throw_grace")
		var frames := int(grace * Engine.physics_ticks_per_second)
		ok("the throw grace is set (%.1f s)" % grace, grace > 0.0, grace)
		var throws: Dictionary = mg.get("_mp8_throws")
		var a: Node = mk_dev.call(mg, 1, Vector3(100, 0.6, 100))
		var b: Node = mk_dev.call(mg, 2, Vector3(103, 0.6, 100))
		var p: Node = mk_player.call(41, Vector3(100, 0.5, 101))
		var q: Node = mk_player.call(42, Vector3(110, 0.5, 110))

		# A throw off the back starts the grace; a kick does not.
		a.call("try_throw_rpc", Vector3(100, 2, 100), Vector3.FORWARD, 1.0, p.get_path(), true)
		ok("Extended: a kick grants no throw grace", throws.is_empty(), throws)
		a.call("try_throw_rpc", Vector3(100, 2, 100), Vector3.FORWARD, 1.0, p.get_path(), false)
		ok("Extended: a throw off the back is noted", throws.has(41), throws)
		ok("Extended: the thrower is in grace from the other device", mg.call("mp8_in_throw_grace", p, b))
		ok("Extended: but not from the device they threw", not mg.call("mp8_in_throw_grace", p, a))
		throws[41][1] -= frames - 2
		ok("Extended: still in grace just before it ends", mg.call("mp8_in_throw_grace", p, b))
		throws[41][1] -= 2
		ok("Extended: out of grace once it ends", not mg.call("mp8_in_throw_grace", p, b))
		throws[41][1] = Engine.get_physics_frames()

		# Target choice prefers anyone else; the thrower only when nobody else is left.
		var actives: Dictionary = mg.get("active_players")
		actives[41] = p
		actives[42] = q
		var picks := {}
		for i in 30:
			picks[mg.call("_mp8_pick_prey", b)] = true
		ok("Extended: the other device's target choice skips the thrower", picks.size() == 1 and picks.has(q), picks.keys())
		actives.erase(42)
		ok("Extended: and takes them when nobody else is left", mg.call("_mp8_pick_prey", b) == p)
		actives.clear()

		# The chasing device: no contact and no target during the grace, contact after it; the thrown one's own chase
		# ignores it.
		var fb: Node = mk_state.call(follow_s, b)
		var bp: Array = b.get("players_in_proximity")
		bp.append(p)
		b.global_position = p.global_position + Vector3(0.8, 0, 0)
		fb.call("update_proximity_check")
		fb.call("_on_player_attach_entered", p)
		ok("Extended: the other device's chase neither grabs nor targets a thrower in grace",
			to_of.call(b).is_empty() and fb.get("target") != p, [to_of.call(b), fb.get("target")])
		throws[41][1] -= frames
		fb.call("update_proximity_check")
		ok("Extended: after the grace its chase grabs them", to_of.call(b).size() == 1 and to_of.call(b)[0][0] == "Attached", to_of.call(b))
		throws[41][1] = Engine.get_physics_frames()
		to_of.call(a).clear()
		var fa: Node = mk_state.call(follow_s, a)
		fa.call("_on_player_attach_entered", p)
		ok("Extended: the thrown device's own chase grabs its thrower", to_of.call(a).size() == 1 and to_of.call(a)[0][0] == "Attached", to_of.call(a))
		fb.free()
		fa.free()
		to_of.call(a).clear()
		to_of.call(b).clear()

		# A thrower whose contact was refused during the grace and who is still inside the attach area is taken when it
		# ends, though the device is past the 1.45 m contact distance (the area reaches them up to about 1.7 m away).
		var h: Node = mk_dev.call(mg, 2, Vector3(120, 0.5, 120))
		var area := Area3D.new()
		var acs := CollisionShape3D.new()
		var asph := SphereShape3D.new()
		asph.radius = 1.0
		acs.shape = asph
		area.add_child(acs)
		h.add_child(area)
		h.set("player_attach_area", area)
		var pcs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.7
		pcs.shape = cap
		p.add_child(pcs)
		p.global_position = Vector3(121.6, 0.5, 120)
		throws[41][1] = Engine.get_physics_frames()
		for i in 3:
			await get_tree().physics_frame
		var fh: Node = mk_state.call(follow_s, h)
		fh.call("_on_player_attach_entered", p)
		fh.call("update_proximity_check")
		var held_ok: bool = area.overlaps_body(p) and to_of.call(h).is_empty()
		throws[41][1] -= frames
		fh.call("update_proximity_check")
		ok("Extended: a thrower still touching when the grace ends is taken, 1.6 m away",
			held_ok and to_of.call(h).size() == 1 and to_of.call(h)[0][0] == "Attached", [held_ok, to_of.call(h)])
		fh.free()
		h.free()
		pcs.free()
		p.global_position = Vector3(100, 0.5, 101)
		throws[41][1] = Engine.get_physics_frames()

		# A device thrown at a player in grace still attaches.
		var tb: Node = mk_state.call(thrown_s, b)
		tb.call("_on_player_attach_entered", p)
		ok("Extended: a device thrown at a thrower in grace attaches", to_of.call(b).size() == 1 and to_of.call(b)[0][0] == "Attached", to_of.call(b))
		to_of.call(b).clear()

		# A device landing beside a thrower in grace follows someone else.
		b.global_position = Vector3(100.5, 0.6, 101)
		b.set("velocity", Vector3.ZERO)
		for i in 60:
			await get_tree().physics_frame
			tb.call("update_physics", 1.0 / 60.0)
			if not to_of.call(b).is_empty():
				break
		var landed: Array = to_of.call(b)
		ok("Extended: a device landing beside a thrower in grace follows someone else",
			landed.size() == 1 and landed[0][0] == "Follow" and landed[0][1].get("target") == q, landed)
		tb.free()

		var mg_cnt: Node = mg_cnt_s.new()
		add_child(mg_cnt)
		mg_cnt.call("mp8_retarget_now", c)
		var chosen: Array = mg_cnt.get("mp8_test_chosen")
		ok("Extended: mp8_retarget_now chooses at once, with no wait", chosen.size() == 1 and chosen[0] == c, chosen)

		# A mixed room: the game's throw notes nothing, and the game's chase grabs a player whatever the grace.
		_stage(nm, false)
		throws.clear()
		a.call("try_throw_rpc", Vector3(100, 2, 100), Vector3.FORWARD, 1.0, p.get_path(), false)
		ok("mixed: a throw notes no grace", throws.is_empty(), throws)
		throws[41] = [a, Engine.get_physics_frames()]
		to_of.call(b).clear()
		var fm: Node = mk_state.call(follow_s, b)
		fm.call("_on_player_attach_entered", p)
		ok("mixed: the chase grabs a player in grace", to_of.call(b).size() == 1 and to_of.call(b)[0][0] == "Attached", to_of.call(b))
		fm.free()
		mg_cnt.free()
	mg.free()
	mg_rec.free()
	room.free()
	for t in trash:
		if is_instance_valid(t):
			t.free()
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local

const SB := "res://minigames/spine_breaker/scripts/spine_breaker.gd"
const SB_DEVICE := "res://minigames/spine_breaker/components/device/spine_breaker_device.gd"
const SB_STATES := "res://minigames/spine_breaker/components/device/states/"
const SB_PLAYER := "res://minigames/spine_breaker/components/player/scripts/spine_breaker_player.gd"

# A frame callback's row, mixed room only: _copy_script stubs every frame callback, so this stand-in keeps the one
# under test.
func _frame_row(label: String, path: String, sig: String, method: String, args: Array) -> void:
	var copy_name := sig.substr(0, sig.find("("))
	if not _declares(path, copy_name):
		ok("%s, mixed: the game's %s is declared" % [label, copy_name], false)
		return
	var lines := ["extends \"%s\"" % path, "var mp8_test_copies := 0", "func _enter_tree() -> void:\n\tpass",
		"func _ready() -> void:\n\tpass", "func _exit_tree() -> void:\n\tpass"]
	for cb in ["_process", "_physics_process"]:
		if cb != method:
			lines.append("func %s(_d: float) -> void:\n\tpass" % cb)
	lines.append("func %s:\n\tmp8_test_copies += 1" % sig)
	var s := _runtime_script(label + " stand-in", "\n".join(lines + [""]))
	if s == null:
		return
	var n: Node = s.new()
	add_child(n)
	n.set_process(false)
	n.set_physics_process(false)
	n.callv(method, args)
	var got: int = n.get("mp8_test_copies")
	ok("%s, mixed: the game's copy" % label, got == 1, got)
	n.free()

# The mixed-room copies in Spine Breaker. Extended's path is called only where a stand-in returns early (an end flag,
# no such player, one player left, a retired device, an inactive state or player); the rest of Extended's code
# reads the scene's nodes or the device, so those rows run in the mixed room only.
func _mixed_spine_rows(nm: Node) -> void:
	say("step: the mixed-room copies, Spine Breaker")
	var follow := SB_STATES + "follow_state.gd"
	var thrown := SB_STATES + "thrown_state.gd"
	for extended in [true, false]:
		_stage(nm, extended)
		_copy_row("Spine end check", SB, "_mp8_game_check_game_end()", extended, "check_game_end", [], {"finished": true})
		_copy_row("Spine leave", SB, "_mp8_game_remove_player_rpc(_network_id: int)", extended, "remove_player_rpc", [987654])
		_copy_row("Spine target choice", SB, "_mp8_game_choose_new_target()", extended, "choose_new_target")
		_copy_row("Spine device throw", SB_DEVICE, "_mp8_game_try_throw_rpc(_start_position: Vector3, _direction: Vector3, _strength: float, thrower: NodePath, kick: bool = false)",
			extended, "try_throw_rpc", [Vector3.ZERO, Vector3.FORWARD, 1.0, NodePath("mp8_no_such_node")], {"mp8_retired": true})
		var body := Node3D.new()
		add_child(body)
		_copy_row("Spine chase contact", follow, "_mp8_game_on_player_attach_entered(body)", extended, "_on_player_attach_entered", [body])
		_copy_row("Spine landing contact", thrown, "_mp8_game_on_player_attach_entered(body)", extended, "_on_player_attach_entered", [body])
		body.free()
		_copy_row("Spine throw press", SB_PLAYER, "_mp8_game_update_throwing(_delta: float)", extended, "update_throwing", [0.016])
		_copy_row("Spine throw", SB_PLAYER, "_mp8_game_throw_spine_breaker_rpc()", extended, "throw_spine_breaker_rpc")
		if extended:
			continue
		_copy_row("Spine spawns", SB, "_mp8_game_spawn_players()", false, "spawn_players")
		_copy_row("Spine new target", SB, "_mp8_game_on_device_requested_target()", false, "_on_device_requested_target")
		_frame_row("Spine device frame", SB_DEVICE, "_mp8_game_physics_process(delta: float) -> void", "_physics_process", [0.016])
		_copy_row("Spine attach", SB_STATES + "attached_state.gd", "_mp8_game_enter(_msg: Dictionary = {}) -> void", false, "enter", [{}])
		_copy_row("Spine strike", SB_STATES + "break_spine_state.gd", "_mp8_game_enter(_msg: Dictionary = {}) -> void", false, "enter", [{}])
		_copy_row("Spine reset after the kill", SB_STATES + "break_spine_state.gd", "_mp8_game_on_spine_broken()", false, "_on_spine_broken")
		_copy_row("Spine chase", follow, "_mp8_game_enter(_msg: Dictionary = {}) -> void", false, "enter", [{}])
		_copy_row("Spine chase frame", follow, "_mp8_game_update_physics(_delta: float) -> void", false, "update_physics", [0.016])
		_copy_row("Spine proximity", follow, "_mp8_game_update_proximity_check()", false, "update_proximity_check")
		_copy_row("Spine flight", thrown, "_mp8_game_update_physics(_delta: float) -> void", false, "update_physics", [0.016])
		_frame_row("Spine player frame", SB_PLAYER, "_mp8_game_process(_delta: float) -> void", "_process", [0.016])
		_copy_row("Spine carry", SB_PLAYER, "_mp8_game_set_spine_breaker_rpc(_has_spine_breaker: bool, _thrown: bool = false, _from_direction: int = 0)",
			false, "set_spine_breaker_rpc", [false])
		_copy_row("Spine death", SB_PLAYER, "_mp8_game_break_spine_rpc()", false, "break_spine_rpc")
		# _ready itself, as Debris' row: Minigame._ready's sends answered, its cursor flags put back.
		if _declares(SB, "_mp8_game_ready_tail"):
			var rs := _runtime_script("Spine ready stand-in", "\n".join(["extends \"%s\"" % SB, "var mp8_test_copies := 0",
				"func _mp8_game_ready_tail():\n\tmp8_test_copies += 1",
				"func initialize_debug_specifics():\n\tpass",
				"@rpc(\"any_peer\", \"call_local\", \"reliable\")",
				"func set_effects_visibility_rpc(_visible: bool):\n\tpass",
				"@rpc(\"any_peer\", \"call_remote\", \"reliable\")",
				"func player_loaded(network_id: int):\n\tpass", ""]))
			if rs != null:
				var cursor: Array = [GameManager.can_set_cursor, PauseMenu.game_target_can_set_cursor,
					PauseMenu.game_target_cursor_active, PauseMenu.game_target_cursor_visible]
				var mg: Node = rs.new()
				add_child(mg)
				ok("Spine _ready, mixed: the game's tail", mg.get("mp8_test_copies") == 1, mg.get("mp8_test_copies"))
				mg.free()
				GameManager.can_set_cursor = cursor[0]
				PauseMenu.game_target_can_set_cursor = cursor[1]
				PauseMenu.game_target_cursor_active = cursor[2]
				PauseMenu.game_target_cursor_visible = cursor[3]
		else:
			ok("Spine _ready, mixed: the game's tail is declared", false)
	nm.call("mp8_unlatch_room")

const BR := "res://minigames/burn_recycle/scripts/burn_recycle.gd"
const BR_LOCAL := "res://minigames/burn_recycle/scripts/burn_recycle_local_handler.gd"
const BR_PLAYER := "res://minigames/burn_recycle/components/player/burn_recycle_player.gd"

# The mixed-room copies in The Filter. Extended's path is called only where a stand-in has nothing to act on (no items
# on the belt) or by effect (the local handler's _ready); the rest reads the scene's stations or sends and awaits,
# so those rows run in the mixed room only.
func _mixed_filter_rows(nm: Node) -> void:
	say("step: the mixed-room copies, The Filter")
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		_copy_row("Filter belt move", BR_PLAYER, "_mp8_game_move_items_visual()", extended, "move_items_visual")
		# Offline Bots takes this path over with a subclass, which inherits the _ready under test.
		var h: Node = load(BR_LOCAL).new()
		add_child(h)
		var linked: bool = get_viewport().size_changed.is_connected(Callable(h, "_mp8_relayout"))
		ok("Filter local handler's _ready, %s: %s" % [room, "connects" if extended else "connects nothing, as the game"], linked == extended, linked)
		h.free()
		if extended:
			continue
		_copy_row("Filter spawns", BR, "_mp8_game_spawn_players()", false, "spawn_players")
		_copy_row("Filter round end", BR, "_mp8_game_round_finished()", false, "round_finished")
		_copy_row("Filter elimination", BR, "_mp8_game_eliminate_players()", false, "eliminate_players")
		_copy_row("Filter new round", BR, "_mp8_game_start_new_round()", false, "start_new_round")
		_copy_row("Filter console turn", BR_PLAYER, "_mp8_game_setup_clientside_visuals(_seat_counter: int)", false, "setup_clientside_visuals", [0])
		_copy_row("Filter belt", BR_PLAYER, "_mp8_game_set_active_belt(_seat_counter: int)", false, "set_active_belt", [0])
		_copy_row("Filter press", BR_PLAYER, "_mp8_game_set_active_press(_seat_counter: int)", false, "set_active_press", [0])
		_copy_row("Filter look", BR_PLAYER, "_mp8_game_look_at_seat(_seat_index: int)", false, "look_at_seat", [1])
		_copy_row("Filter crush", BR_PLAYER, "_mp8_game_set_eliminated_rpc()", false, "set_eliminated_rpc")
		# setup_rpc reads no room: the game's body (the seat's turn and item types), never Extended's setup.
		var ss := _copy_script("Filter setup stand-in", BR_PLAYER, [
			"mp8_setup_rpc(_rotation_degrees: Vector3, _random_types_byte_array: PackedByteArray, _slots: int = 0, _push: float = 0.0)"])
		if ss != null:
			var p: Node3D = ss.new()
			add_child(p)
			p.call("setup_rpc", Vector3(0.0, 90.0, 0.0), PackedByteArray([0]))
			var got := [p.get("mp8_test_copies"), (p.get("random_item_types") as Array).size(), p.rotation_degrees.y]
			ok("Filter setup_rpc: the game's body", got[0] == 0 and got[1] == 1 and is_equal_approx(got[2], 90.0), got)
			p.free()
		# _ready itself, as Debris' row: Minigame._ready's sends answered, its cursor flags put back.
		if _declares(BR, "_mp8_game_ready_tail"):
			var rs := _runtime_script("Filter ready stand-in", "\n".join(["extends \"%s\"" % BR, "var mp8_test_copies := 0",
				"func _mp8_game_ready_tail():\n\tmp8_test_copies += 1",
				"func initialize_debug_specifics():\n\tpass",
				"@rpc(\"any_peer\", \"call_local\", \"reliable\")",
				"func set_effects_visibility_rpc(_visible: bool):\n\tpass",
				"@rpc(\"any_peer\", \"call_remote\", \"reliable\")",
				"func player_loaded(network_id: int):\n\tpass", ""]))
			if rs != null:
				var cursor: Array = [GameManager.can_set_cursor, PauseMenu.game_target_can_set_cursor,
					PauseMenu.game_target_cursor_active, PauseMenu.game_target_cursor_visible]
				var mg: Node = rs.new()
				add_child(mg)
				ok("Filter _ready, mixed: the game's tail", mg.get("mp8_test_copies") == 1, mg.get("mp8_test_copies"))
				mg.free()
				GameManager.can_set_cursor = cursor[0]
				PauseMenu.game_target_can_set_cursor = cursor[1]
				PauseMenu.game_target_cursor_active = cursor[2]
				PauseMenu.game_target_cursor_visible = cursor[3]
		else:
			ok("Filter _ready, mixed: the game's tail is declared", false)
	nm.call("mp8_unlatch_room")

const INTRO := "res://minigames/intermission_new/components/intermission_cutscene_intro.gd"
const SCORE_SCREEN := "res://minigames/intermission_new/components/intermission_score_screen.gd"
const USER_ROW := "res://minigames/intermission_new/components/intermission_user_container.gd"
const USER_ROW_2D := "res://minigames/intermission_new/components/intermission_user_container_2d.gd"
const INPUT := "res://addons/multiplayer_input/multiplayer_input.gd"

# The mixed-room copies in the shared flow: the intermission's game layout and intro, the input addon's erase, and the lobby.
# The score board and the name rows follow the show's layout flag, the intro and the erase the live room.
func _mixed_shared_rows(nm: Node) -> void:
	say("step: the mixed-room copies, the shared flow and the lobby")
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		# The score board's own rows list is empty on a stand-in, so Extended's loop places nothing.
		_copy_row("score board rows", SCORE_SCREEN, "_mp8_game_reset_user_containers(_total_score_by_network_id: Dictionary, _game_score_by_network_id: Dictionary)",
			extended, "reset_user_containers", [{}, {}], {"mp8_extended_layout": extended})
		# Extended's input path erases this stand-in's own (empty) device list; the copy would walk InputMap.
		_copy_row("pad actions erased", INPUT, "_mp8_game_delete_actions_for_device(device: int)", extended, "_delete_actions_for_device", [3])
		if not extended:
			_copy_row("name row", USER_ROW, "_mp8_game_set_user_container_data(_score: int, _name: String)", false,
				"set_user_container_data", [0, "ABCDEFGHIJK"], {"mp8_extended": false})
			_copy_row("briefing name row", USER_ROW_2D, "_mp8_game_set_user_data(_score: int, _name: String)", false,
				"set_user_data", [0, "ABCDEFGHIJK"], {"mp8_extended": false})
			_copy_row("intro", INTRO, "_mp8_game_start_intro_cutscene()", false, "start_intro_cutscene")
			_copy_row("intro skipped", INTRO, "_mp8_game_skip_intro_cutscene()", false, "skip_intro_cutscene")
			_copy_row("intro name tag", INTRO, "_mp8_game_bootup_nametag()", false, "bootup_nametag")
			_copy_row("intro name tags reset", INTRO, "_mp8_game_reset_nametags_rpc(id_array: Array)", false, "reset_nametags_rpc", [[1]])
	nm.call("mp8_unlatch_room")
	_seat_rows(nm)
	await _lobby_layout_rows(nm)

# The seat map, fitted before the game's loop takes the first free seat.
func _seat_rows(nm: Node) -> void:
	if not _declares("res://modules/multiplayer/network_manager.gd", "mp8_fit_seats"):
		ok("seat map: mp8_fit_seats exists", false)
		return
	var cases := [
		["mixed, seats 6 and 7 taken: moved to 1 and 2, the game's 4 seats", {0: -1, 1: -1, 2: -1, 3: -1, 4: -1, 5: 12, 6: 13, 7: -1}, false, {0: 12, 1: 13, 2: -1, 3: -1}],
		["mixed, the host at 1 and seat 8 taken: moved to 2", {0: 1, 1: -1, 2: -1, 3: -1, 4: -1, 5: -1, 6: -1, 7: 14}, false, {0: 1, 1: 14, 2: -1, 3: -1}],
		["mixed, already in 1-4: kept, the game's 4 seats", {0: 1, 1: -1, 2: 12, 3: -1, 4: -1, 5: -1, 6: -1, 7: -1}, false, {0: 1, 1: -1, 2: 12, 3: -1}],
		["mixed, a map of 4 stays as it is", {0: 1, 1: 12, 2: -1, 3: -1}, false, {0: 1, 1: 12, 2: -1, 3: -1}],
		["Extended, a map of 4 grows back to 8", {0: 1, 1: 12, 2: -1, 3: -1}, true, {0: 1, 1: 12, 2: -1, 3: -1, 4: -1, 5: -1, 6: -1, 7: -1}],
		["Extended, a map of 8 is kept", {0: 1, 1: -1, 2: -1, 3: -1, 4: -1, 5: 12, 6: -1, 7: -1}, true, {0: 1, 1: -1, 2: -1, 3: -1, 4: -1, 5: 12, 6: -1, 7: -1}],
	]
	for c in cases:
		var got = nm.call("mp8_fit_seats", c[1], c[2])
		ok("seat map, %s" % c[0], got == _ints(c[3]), got)

# A lobby handler built as the lobby scene has it (4 slots, each with its assigner and tag; the camera
# and the chairs beside the slots' parent), extended by the real _mp8_extend_lobby, then switched both ways.
func _lobby_layout_rows(nm: Node) -> void:
	if not nm.has_method("mp8_lobby_layout"):
		ok("lobby layout: mp8_lobby_layout exists", false)
		return
	var hs := _runtime_script("lobby handler stand-in", "\n".join(["extends Node",
		"var players: Array = []", "var customization_assigners: Array = []", "var nametags: Array = []", ""]))
	if hs == null:
		return
	var root := Node3D.new()
	add_child(root)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	root.add_child(cam)
	cam.position = Vector3(0, 2, 6)
	var env := Node3D.new()
	env.name = "lobby environment1"
	root.add_child(env)
	var chair := Node3D.new()
	chair.name = "chair1"
	env.add_child(chair)
	# Seat 2's chair in the lobby scene: its copy, seat 6's, takes a further nudge.
	var chair2 := Node3D.new()
	chair2.name = "chair_001"
	env.add_child(chair2)
	chair2.position = Vector3(-1.0, 0.8, 0.4)
	var slots := Node3D.new()
	root.add_child(slots)
	var h: Node = hs.new()
	root.add_child(h)
	for i in 4:
		var slot := Node3D.new()
		slots.add_child(slot)
		var a := Node3D.new()
		slot.add_child(a)
		var t := Label3D.new()
		slot.add_child(t)
		h.get("players").append(slot)
		h.get("customization_assigners").append(a)
		h.get("nametags").append(t)
	var game_slots: Array = h.get("players").duplicate()
	nm.call("_mp8_extend_lobby", h)
	var chairs: Node3D = env.get_node_or_null("MP8ChairRow")
	var ext_cam := cam.position
	ok("lobby layout: extended to 8 slots, a chair row and the camera moved", h.get("players").size() == 8 and chairs != null and ext_cam != Vector3(0, 2, 6),
		[h.get("players").size(), chairs != null, ext_cam])
	var consts: Dictionary = nm.get_script().get_script_constant_map()
	var row2: Vector3 = consts.get("MP8_ROW2_OFFSET", Vector3.INF)
	var nudge: Vector3 = consts.get("MP8_ROW2_SEAT6_NUDGE", Vector3.INF)
	var copy6: Node3D = chairs.get_node_or_null("MP8chair_001") if chairs else null
	var copy1: Node3D = chairs.get_node_or_null("MP8chair1") if chairs else null
	ok("lobby layout: seat 6 and its chair's copy at the row offset plus the nudge, the other chair at the offset",
		h.get("players")[5].position.is_equal_approx(row2 + nudge) and copy6 != null and copy6.position.is_equal_approx(chair2.position + row2 + nudge)
		and copy1 != null and copy1.position.is_equal_approx(row2) and h.get("players")[4].position.is_equal_approx(row2),
		[h.get("players")[5].position, copy6.position if copy6 else null, copy1.position if copy1 else null, row2, nudge])
	# The nudge finds seat 2's chair by name, and a missing name leaves it where it was without an error.
	var scene: PackedScene = load("res://scenes/lobby/lobby_scene.tscn")
	var authored: Node = scene.instantiate() if scene else null
	var named: Node = authored.find_child("chair_001", true, false) if authored else null
	ok("lobby layout: the online lobby scene has a shown chair_001 in lobby environment1",
		named is Node3D and named.visible and named.get_parent().name == "lobby environment1", authored.get_path_to(named) if named else null)
	if authored:
		authored.free()
	h.get("players")[5].visible = true
	nm.call("mp8_lobby_layout", h, false)
	ok("lobby layout, a mixed room: the game's 4 slots", h.get("players") == game_slots and h.get("customization_assigners").size() == 4 and h.get("nametags").size() == 4,
		h.get("players").size())
	var clone: Node3D = slots.get_child(5) if slots.get_child_count() > 5 else null
	ok("lobby layout, a mixed room: the copied slots hidden, the chair row hidden, the camera back",
		clone != null and not clone.visible and chairs != null and not chairs.visible and cam.position == Vector3(0, 2, 6), [clone != null and clone.visible, chairs != null and chairs.visible, cam.position])
	nm.call("mp8_lobby_layout", h, true)
	ok("lobby layout, Extended again: 8 slots, the chair row shown, the camera moved", h.get("players").size() == 8 and chairs.visible and cam.position == ext_cam,
		[h.get("players").size(), chairs.visible, cam.position])
	root.free()

const GUARDED := ["spine_breaker", "train_race", "burn_recycle", "duck_hunt", "dvd_roomba", "forklift_certified",
	"green_pea", "junk_platform", "knife_at_the_office", "escalator_pit", "exploding_collar_race", "manufacture_gun"]

# Each minigame's own handler on a stand-in: the game's scripts with their frame callbacks, RPCs and end check
# replaced. check_game_end() counts. Exploding Collar's guard sits in remove_active_player_rpc, called directly.
func _guard_script(name: String, stub_rpcs: bool = true) -> GDScript:
	var path := "res://minigames/%s/scripts/%s.gd" % [name, name]
	var base := load(path) as GDScript
	var methods := base.get_script_method_list().map(func(m): return String(m["name"]))
	var src := "extends \"%s\"\nvar mp8_test_ends := 0\n" % path
	src += "func _enter_tree() -> void:\n\tpass\nfunc _ready() -> void:\n\tpass\n"
	src += "func _process(_d: float) -> void:\n\tpass\nfunc _physics_process(_d: float) -> void:\n\tpass\n"
	src += "func _exit_tree() -> void:\n\tpass\n"
	var from_disconnect: bool = name in ["burn_recycle", "forklift_certified"]
	src += "func check_game_end(%s):\n\tmp8_test_ends += 1\n" % ("_from_disconnect: bool = false" if from_disconnect else "")
	for rpc_name in ["remove_player_rpc", "disconnect_player_rpc"]:
		if stub_rpcs and methods.has(rpc_name):
			src += "func %s(_network_id: int):\n\tpass\n" % rpc_name
	return _runtime_script("guard stand-in %s%s" % [name, "" if stub_rpcs else " (its RPCs kept)"], src)

# Every handler, all at once: the 9 with a 1 s await share one wait.
func _guard_pass(nm: Node, scripts: Dictionary, extended_at_call: bool, extended_after: bool, loaded: bool, id_known: bool) -> Dictionary:
	var nodes := {}
	_stage(nm, extended_at_call)
	for name in scripts:
		var n: Node = scripts[name].new()
		add_child(n)
		n.set("is_all_player_loaded", loaded)
		nodes[name] = n
	for name in nodes:
		var n: Node = nodes[name]
		if name == "manufacture_gun" and id_known:
			n.get("active_players")[99] = null
		if name == "exploding_collar_race":
			n.call("remove_active_player_rpc", 99)
		else:
			n.call("player_disconnected", 99)
	_stage(nm, extended_after)
	await get_tree().create_timer(1.3).timeout
	var ends := {}
	for name in nodes:
		ends[name] = nodes[name].get("mp8_test_ends")
		nodes[name].free()
	nm.call("mp8_unlatch_room")
	return ends

func _preload_guards(nm: Node) -> void:
	var scripts := {}
	for name in GUARDED:
		var s := _guard_script(name)
		if s != null:
			scripts[name] = s
	if scripts.is_empty():
		return
	# Extended at the disconnect, mixed by the time the await ends: the room read at entry still skips.
	var ext := await _guard_pass(nm, scripts, true, false, false, true)
	var mixed := await _guard_pass(nm, scripts, false, false, false, true)
	var loaded := await _guard_pass(nm, scripts, true, true, true, true)
	for name in scripts:
		ok("guard %s: Extended skips the end check before loading, though the room turns mixed mid-wait" % name, ext[name] == 0, ext[name])
		ok("guard %s: a mixed room runs the game's end check" % name, mixed[name] == 1, mixed[name])
		ok("guard %s: after loading, the end check runs (the stand-in is reached)" % name, loaded[name] == 1, loaded[name])
	if scripts.has("manufacture_gun"):
		var one := {"manufacture_gun": scripts["manufacture_gun"]}
		var gone_ext := await _guard_pass(nm, one, true, true, true, false)
		var gone_mixed := await _guard_pass(nm, one, false, false, true, false)
		ok("Firearm Factory: a player with no entry, Extended, still ends the check", gone_ext["manufacture_gun"] == 1, gone_ext)
		# A release build's raw read of a missing key gives null and goes on, so the game's handler reaches its end check.
		ok("Firearm Factory: a player with no entry, mixed, the game's raw read goes on to the end check", gone_mixed["manufacture_gun"] == 1, gone_mixed)

# The spawn top-up adds markers to a minigame's 4 only in an Extended room.
func _topup(nm: Node) -> void:
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		var holder := Node3D.new()
		add_child(holder)
		var container := Node3D.new()
		container.name = "SpectatePositions"
		holder.add_child(container)
		var markers: Array = []
		for i in 4:
			var m := Marker3D.new()
			container.add_child(m)
			m.position = Vector3(i * 3.0, 0, (i % 2) * 3.0)
			markers.append(m)
		_stage(nm, extended)
		nm.call("_mp8_topup", container)
		ok("top-up, container, %s: %d markers" % [room, 8 if extended else 4], container.get_child_count() == (8 if extended else 4), container.get_child_count())
		var mg_script := _runtime_script("top-up array stand-in", "extends Node\nvar player_spawn_positions: Array = []\n")
		if mg_script != null:
			var mg: Node = mg_script.new()
			holder.add_child(mg)
			mg.set("player_spawn_positions", markers.duplicate())
			nm.call("_mp8_topup_spawn_arrays", mg)
			var got: int = mg.get("player_spawn_positions").size()
			ok("top-up, array, %s: %d spawns" % [room, 8 if extended else 4], got == (8 if extended else 4), got)
		holder.free()
	nm.call("mp8_unlatch_room")

# The audit's "By minigame" rows, each on its own function: the real check_game_end and the round end's
# enter() go on to RPCs and a null state machine, which end a release build. A method b69 lacks is a FAIL.
func _minigame_rows(nm: Node) -> void:
	say("step: the per-minigame rows' gates")
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		var server: bool = nm.call("mp8_sends_broadcast", true) if nm.has_method("mp8_sends_broadcast") else false
		var client: bool = nm.call("mp8_sends_broadcast", false) if nm.has_method("mp8_sends_broadcast") else extended
		ok("server-only broadcasts, %s: the server sends" % room, server, server)
		ok("server-only broadcasts, %s: a client %s" % [room, "doesn't" if extended else "sends too, as the game does"], client != extended, client)
		_dvd_spawns(extended, room)
		# A mixed room runs the game's check_game_end, which scores player_count (the mixed-room rows).
		for name in (["dvd_roomba", "train_race"] if extended else []):
			var s := _guard_script(name)
			if s == null:
				continue
			var mg: Node = s.new()
			add_child(mg)
			var dead: Array[int] = [11, 12]
			mg.set("dead_players", dead)
			mg.set("player_count", 4)
			var got = mg.call("_mp8_survivor_score") if mg.has_method("_mp8_survivor_score") else -1
			ok("survivor score %s, %s, 2 dead of 4 (one left): 3" % [name, room], got == 3, got)
			mg.free()
		_collar_ranks(extended, room)
		_smoke_round_end(extended, room)
		_knife_rows(extended, room)
		_firearm_rows(extended, room)
		_forklift_disconnect(extended, room)
		_forklift_lights(extended, room)
	nm.call("mp8_unlatch_room")

func _dvd_spawns(extended: bool, room: String) -> void:
	var s := _guard_script("dvd_roomba")
	if s == null:
		return
	var mg: Node = s.new()
	add_child(mg)
	var container := Node3D.new()
	mg.add_child(container)
	for i in 4:
		var m := Marker3D.new()
		container.add_child(m)
		m.position = Vector3(6.0 if i % 2 == 0 else -6.0, 0, 6.0 if i < 2 else -6.0)
	mg.set("player_spawn_parent_node", container)
	mg.call("_mp8_topup_spawns")
	ok("DVD Roomba spawns, %s: %d" % [room, 8 if extended else 4], container.get_child_count() == (8 if extended else 4), container.get_child_count())
	mg.free()

func _collar_ranks(extended: bool, room: String) -> void:
	var s := _guard_script("exploding_collar_race")
	if s == null:
		return
	var mg: Node = s.new()
	add_child(mg)
	mg.set("player_scores", _ints({7: 2, 8: 1}))
	var order: Array[int] = [8]
	mg.set("_mp8_dead_order", order)
	mg.call("_mp8_rank_scores")
	var want := {7: 0, 8: 0} if extended else {7: 2, 8: 1}
	ok("Exploding Collar scores, %s: %s" % [room, "ranked" if extended else "the game's kept"], mg.get("player_scores") == _ints(want), mg.get("player_scores"))
	mg.free()

# Four finish in order; the first already has smoke_break.gd's running +1. A mixed room's enter() calls the
# game's copy (counted); Extended's own scoring is its helper, since enter() goes on to an RPC and the state machine.
func _smoke_round_end(extended: bool, room: String) -> void:
	var end_path := "res://minigames/smoke_break/states/round_end_state.gd"
	if not extended:
		if not _declares(end_path, "_mp8_game_enter"):
			ok("Smoke Break round end, mixed: the game's _mp8_game_enter is declared", false)
			return
		var cs := _copy_script("Smoke Break round end stand-in", end_path, ["_mp8_game_enter(_msg: Dictionary = {}) -> void"])
		if cs == null:
			return
		var st: Node = cs.new()
		add_child(st)
		st.call("enter", {})
		var got: int = st.get("mp8_test_copies")
		ok("Smoke Break round end, mixed: the game's enter()", got == 1, got)
		st.free()
		return
	var owner_s := _runtime_script("Smoke Break owner stand-in", "\n".join([
		"extends Node", "signal player_scores_finalized(scores)", "var player_scores: Dictionary = {}",
		"var finished_players: Array = []", "var active_players: Array = []", ""]))
	var presence_s := _runtime_script("Smoke Break presence stand-in", "extends RefCounted\nvar network_id := 0\nvar network_name := \"\"\n")
	var player_s := _runtime_script("Smoke Break player stand-in", "extends Node\nvar player_presence\nvar active_player_seat_index := 0\n")
	if owner_s == null or presence_s == null or player_s == null:
		return
	var stub: Node = owner_s.new()
	add_child(stub)
	var state: Node = load("res://minigames/smoke_break/states/round_end_state.gd").new()
	stub.add_child(state)
	state.owner = stub
	var finished: Array = stub.get("finished_players")
	var scores: Dictionary = stub.get("player_scores")
	for id in [1, 2, 3, 4]:
		var pr = presence_s.new()
		pr.set("network_id", id)
		pr.set("network_name", "P%d" % id)
		var p: Node = player_s.new()
		p.set("player_presence", pr)
		stub.add_child(p)
		finished.append(p)
		scores[id] = 1 if id == 1 else 0
	if state.has_method("_mp8_score_finishers"):
		state.call("_mp8_score_finishers", [])
	var want := {1: 5, 2: 3, 3: 2, 4: 1}
	ok("Smoke Break round end, %s: 5/3/2/1" % room, scores == want, scores)
	stub.free()

const KNIFE_SEALED := "Geometry/kato office art1/searchables parent/desk with drawers3/Searchable right side"

func _knife_rows(extended: bool, room: String) -> void:
	var s := _guard_script("knife_at_the_office")
	if s == null:
		return
	var mg: Node = s.new()
	add_child(mg)
	var container := Node3D.new()
	mg.add_child(container)
	for i in 4:
		container.add_child(Marker3D.new())
	mg.set("player_spawn_positions_node", container)
	mg.call("_mp8v_add_spawns")
	ok("Inside Job spawns, %s: %d" % [room, 8 if extended else 4], container.get_child_count() == (8 if extended else 4), container.get_child_count())

	var parent: Node = mg
	var parts := KNIFE_SEALED.split("/")
	for i in parts.size() - 1:
		var n := Node3D.new()
		n.name = parts[i]
		parent.add_child(n)
		parent = n
	var sealed: Area3D = load("res://minigames/knife_at_the_office/components/searchable/searchable.gd").new()
	sealed.name = parts[parts.size() - 1]
	parent.add_child(sealed)
	var reachable: Area3D = load("res://minigames/knife_at_the_office/components/searchable/searchable.gd").new()
	parent.add_child(reachable)
	mg.call("_mp8_collect_searchables")
	var listed: int = mg.get("searchables").size()
	ok("Inside Job containers, %s: %s" % [room, "the sealed one off, 1 listed" if extended else "all on, none listed, as the game does"],
		sealed.monitoring != extended and listed == (1 if extended else 0), [sealed.monitoring, listed])

	# The host's own search: Extended calls its player directly; the game's call_remote broadcast never runs on the host.
	var searcher_s := _runtime_script("Inside Job searcher stand-in", "\n".join([
		"extends \"res://minigames/knife_at_the_office/components/player/scripts/knife_at_the_office_player.gd\"",
		"var mp8_test_results := 0",
		"func _ready() -> void:\n\tpass", "func _process(_d: float) -> void:\n\tpass",
		"func _physics_process(_d: float) -> void:\n\tpass", "func _exit_tree() -> void:\n\tpass",
		"@rpc(\"any_peer\", \"call_remote\", \"reliable\")", "func search_result_rpc(_found_item: bool):\n\tmp8_test_results += 1", ""]))
	if searcher_s != null:
		var searcher: Node = searcher_s.new()
		mg.add_child(searcher)
		var me: int = multiplayer.get_unique_id()
		mg.get("players")[me] = searcher
		mg.call("request_item_find_rpc", me)
		var got: int = searcher.get("mp8_test_results")
		ok("Inside Job host's own search, %s: %s" % [room, "its result arrives" if extended else "no result, as the game's broadcast"], got == (1 if extended else 0), got)
		mg.get("players").erase(me)

	# The finder's point before the 1.5 s wait: Extended's at the find, the game's only after it. The projector and
	# the hunt are marked started, so nothing past the await runs.
	mg.set("player_scores", _ints({5: 0}))
	mg.set("projector_started", true)
	mg.set("hunting_phase", true)
	mg.call("_on_item_found", 5)
	var at_find: int = mg.get("player_scores")[5]
	ok("Inside Job finder's point at the find, %s: %d" % [room, 1 if extended else 0], at_find == (1 if extended else 0), at_find)

	var handler: Node = load("res://minigames/knife_at_the_office/components/countdown_handler/countdown_handler.gd").new()
	var box := HBoxContainer.new()
	handler.add_child(box)
	var icons: Array = handler.get("alive_indicator_icons")
	for i in 4:
		var icon := TextureRect.new()
		box.add_child(icon)
		icons.append(icon)
	handler.call("_mp8_extend_alive_indicators")
	var n_icons: int = handler.get("alive_indicator_icons").size()
	ok("Inside Job alive indicators, %s: %d" % [room, 8 if extended else 4], n_icons == (8 if extended else 4), n_icons)
	handler.free()

	var player: Node = load("res://minigames/knife_at_the_office/components/player/scripts/knife_at_the_office_player.gd").new()
	player.set("game_reference", mg)
	mg.set("searching_disabled", false)
	var waits = player.call("_mp8_stab_waits") if player.has_method("_mp8_stab_waits") else not extended
	ok("Inside Job stab before the hunt, %s: %s" % [room, "waits" if extended else "lands, as the game does"], waits == extended, waits)
	player.free()
	mg.free()

func _firearm_rows(extended: bool, room: String) -> void:
	var P: GDScript = load("res://minigames/manufacture_gun/components/player/scripts/manufacture_gun_player.gd")
	var bench: Node3D = load("res://minigames/manufacture_gun/components/workstation/scripts/manufacture_gun_workstation.gd").new()
	var presence := PlayerPresence.new()
	presence.network_id = 2
	bench.set("player_presence", presence)
	var body := StaticBody3D.new()
	bench.add_child(body)
	var refused = P.call("mp8_drop_refused", body, 1) if P.get_script_method_list().any(func(m): return m["name"] == "mp8_drop_refused") else not extended
	ok("Firearm Factory drop on another's bench, %s: %s" % [room, "refused" if extended else "lands, as the game does"], refused == extended, refused)
	bench.free()
	presence.free()

	var s := _guard_script("manufacture_gun")
	if s == null:
		return
	var mg: Node = s.new()
	add_child(mg)
	mg.call("request_item_sequence_rpc", 1)
	var seq: Array = mg.get("item_sequence")
	ok("Firearm Factory sequence for a player without a bench, %s: %s" % [room, "refused" if extended else "sent, as the game does"],
		seq.is_empty() == extended, seq)
	mg.set("item_sequence", [])
	mg.call("mp8_receive_item_sequence_rpc", [99])
	seq = mg.get("item_sequence")
	ok("Firearm Factory malformed sequence, %s: %s" % [room, "refused" if extended else "taken, as the game does"],
		seq.is_empty() == extended, seq)
	mg.free()

# Real bays in a stand-in's tree, one player each; a bay's _ready duplicates its border mesh's material.
func _forklift_stage(owners: Array) -> Node:
	var s := _guard_script("forklift_certified", false)
	if s == null:
		return null
	var mg: Node = s.new()
	add_child(mg)
	var parent := Node3D.new()
	mg.add_child(parent)
	mg.set("delivery_area_parent", parent)
	var areas: Array = mg.get("delivery_areas")
	var members: Array = []
	var area_s: GDScript = load("res://minigames/forklift_certified/components/delivery_area/forklift_certified_delivery_area.gd")
	for id in owners:
		var a: Area3D = area_s.new()
		var border := MeshInstance3D.new()
		border.material_override = StandardMaterial3D.new()
		a.set("border_mesh_instance", border)
		a.set("counter_label", Label3D.new())
		a.set("area_light", SpotLight3D.new())
		a.set("speaker_mechanism", AudioStreamPlayer3D.new())
		for c in ["border_mesh_instance", "counter_label", "area_light", "speaker_mechanism"]:
			a.add_child(a.get(c))
		parent.add_child(a)
		a.set("belongs_to_id", id)
		areas.append(a)
		members.append([id])
	mg.set("_mp8_area_members", members)
	return mg

func _forklift_disconnect(extended: bool, room: String) -> void:
	var mg := _forklift_stage([11, 12, 13, 14])
	if mg == null:
		return
	var bay: Node = mg.get("delivery_areas")[1]
	mg.call("disconnect_player_rpc", 12)
	var n: int = mg.get("delivery_areas").size()
	var rows: Array = mg.get("_mp8_area_members")
	var want_rows: Array = [[11], [], [13], [14]] if extended else [[11], [12], [13], [14]]
	ok("Forklift disconnect, %s: %s" % [room, "the bay kept, closed" if extended else "the bay dropped, as the game does"],
		n == (4 if extended else 3) and rows == want_rows and bay.get("belongs_to_id") == -2, [n, rows, bay.get("belongs_to_id")])
	mg.free()

func _forklift_lights(extended: bool, room: String) -> void:
	var player_s := _runtime_script("Forklift player stand-in", "\n".join([
		"extends Node3D", "var mp8_test_lights := 0",
		"@rpc(\"any_peer\", \"call_local\", \"reliable\")", "func set_indicator_light_rpc(_on: bool):\n\tmp8_test_lights += 1",
		"@rpc(\"any_peer\", \"call_local\", \"reliable\")", "func trigger_achievement_rpc():\n\tpass", ""]))
	if player_s == null:
		return
	var mg := _forklift_stage([11, 12])
	if mg == null:
		return
	var active: Dictionary = mg.get("active_players")
	var players: Array = []
	for id in [11, 12]:
		var p: Node3D = player_s.new()
		mg.add_child(p)
		active[id] = p
		players.append(p)
	mg.call("_on_crate_numbers_changed")
	mg.call("_on_crate_numbers_changed")
	var lights: int = players.reduce(func(acc, p): return acc + int(p.get("mp8_test_lights")), 0)
	ok("Forklift lights, two crate changes, %s: %d sends" % [room, 2 if extended else 4], lights == (2 if extended else 4), lights)
	var bay: Node = mg.get("delivery_areas")[0]
	bay.set("mp8_indicator_state", 1)
	bay.call("set_owner_rpc", 12)
	var cache: int = bay.get("mp8_indicator_state")
	ok("Forklift bay's light cache on a new owner, %s: %s" % [room, "reset" if extended else "untouched, the game keeps none"], cache == (-1 if extended else 1), cache)
	mg.free()

# game.gd on a stand-in in the tree, its frame callbacks and exit replaced (the game's _exit_tree would cancel
# the backend); receive_scores_rpc counts and _mp8_trace records how far load_minigame got. With stub_load,
# load_minigame only records what it was asked for.
func _game_script(label: String, stub_load: bool, extra: Array = []) -> GDScript:
	var lines := [
		"extends \"res://scripts/scenes/game/game.gd\"",
		"var mp8_test_scores_sent := 0",
		"var mp8_test_traces: Array = []",
		"var mp8_test_loads: Array = []",
		"func _ready() -> void:\n\tpass",
		"func _process(_d: float) -> void:\n\tpass",
		"func _exit_tree() -> void:\n\tpass",
		"func receive_scores_rpc(_t: Dictionary, _g: Dictionary):\n\tmp8_test_scores_sent += 1",
		"func _mp8_trace(msg: String) -> void:\n\tmp8_test_traces.append(msg)"]
	if stub_load:
		lines.append("func load_minigame(id: Globals.MinigameIdentifier, _r: bool, _t: int = -1, ):\n\tmp8_test_loads.append(id)")
	return _runtime_script(label, "\n".join(lines + extra + [""]))

func _game_rows(nm: Node) -> void:
	var game_script := _game_script("game stand-in", true)
	var mg_script := _runtime_script("minigame stand-in", "\n".join([
		"extends \"res://modules/minigame/minigame.gd\"",
		"func _ready() -> void:\n\tpass", ""]))
	if game_script == null or mg_script == null:
		return
	var g: Node = game_script.new()
	add_child(g)
	g.set("score_multiplier", 85)
	var cases := [
		["Duck Hunt", Globals.MinigameIdentifier.DuckHunt, 127],
		["Exploding Collar", Globals.MinigameIdentifier.ExplodingCollarRace, 191],
		["Table Manners", Globals.MinigameIdentifier.GreenPea, 255],
	]
	for c in cases:
		Globals.current_minigame_identifier = c[1]
		for extended in [true, false]:
			var room := "Extended" if extended else "mixed"
			var want: int = c[2] if extended else 255
			_stage(nm, extended)
			g.set("round_score_by_network_id", _ints({7: 0}))
			g.call("_on_minigame_player_scored", 7, 3)
			ok("score, %s, %s: %d" % [c[0], room, want], g.get("round_score_by_network_id")[7] == want, g.get("round_score_by_network_id"))
			g.set("round_score_by_network_id", _ints({7: 0}))
			g.call("_on_minigame_player_score_finalized", {7: 3})
			ok("finalized score, %s, %s: %d" % [c[0], room, want], g.get("round_score_by_network_id")[7] == want, g.get("round_score_by_network_id"))
	Globals.current_minigame_identifier = Globals.MinigameIdentifier.GreenPea
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		_stage(nm, extended)
		g.set("mp8_test_scores_sent", 0)
		g.set("game_score_by_network_id", _ints({7: 0, 8: 0}))
		g.set("round_score_by_network_id", _ints({7: 5}))
		g.set("total_score_by_network_id", _ints({7: 0, 8: 0}))
		g.call("update_scores", false)
		var sent: int = g.get("mp8_test_scores_sent")
		# A mixed room runs the game's copy, raw read and all. In this release build the missing read doesn't stop
		# the function: 8 gets the value read before it (7's 5), and the scores are sent.
		ok("update_scores, a player with no round entry, %s: sent" % room, sent == 1, sent)
		var game_scores: Dictionary = g.get("game_score_by_network_id")
		ok("update_scores, a player with no round entry, %s: %s" % [room, "8 scores 0" if extended else "8 gets 7's 5, as the game's raw read does"],
			game_scores == _ints({7: 5, 8: 0 if extended else 5}), game_scores)
		if not _declares(GAME, "_mp8_game_update_scores"):
			ok("update_scores, %s: the game's _mp8_game_update_scores is declared" % room, false)
		else:
			var cs := _game_script("game stand-in, update_scores' copy counted", true, ["var mp8_test_copies := 0",
				"func _mp8_game_update_scores(_more_rounds: bool):\n\tmp8_test_copies += 1"])
			if cs != null:
				var cg: Node = cs.new()
				add_child(cg)
				cg.set("game_score_by_network_id", _ints({7: 0}))
				cg.set("round_score_by_network_id", _ints({7: 5}))
				cg.set("total_score_by_network_id", _ints({7: 0}))
				cg.call("update_scores", false)
				var copies: int = cg.get("mp8_test_copies")
				ok("update_scores, %s: %s" % [room, "Extended's own" if extended else "the game's copy"], copies == (0 if extended else 1), copies)
				cg.free()
		var mg: Node = mg_script.new()
		g.add_child(mg)
		g.set("minigame", mg)
		mg.set("players_loaded", [1, 99] as Array[int])
		g.call("_mp8_recheck_load_gate", 99)
		var left: Array = mg.get("players_loaded")
		ok("load gate recheck, %s: %s" % [room, "erases the leaver" if extended else "leaves the gate alone"], left.has(99) != extended, left)
		g.set("minigame", null)
		mg.free()
	await _finish_claim(nm, g, mg_script)
	g.free()
	await _load_serial(nm, mg_script)
	nm.call("mp8_unlatch_room")

# The real load_minigame: a later load during the cleanup's 1 s wait stops this one in an Extended room only. A
# load that goes on instantiates its minigame and adds it to a parent outside the tree, so it never runs; a null
# parent ends a release build there. Each parent is freed with its minigame.
func _load_serial(nm: Node, mg_script: GDScript) -> void:
	var game_script := _game_script("game stand-in, the real load", false)
	if game_script == null:
		return
	var was_game_minigame = GameManager.current_minigame_identifier
	# [what, room at the call, a later load during the wait, went on]. The room turns mixed during every wait.
	var cases := [
		["Extended, a later load stops this one, though the room turns mixed mid-wait", true, true, false],
		["mixed, a later load doesn't stop it, as in the game", false, true, true],
		["Extended, no later load: it goes on", true, false, true],
	]
	var games := []
	for c in cases:
		var g: Node = game_script.new()
		add_child(g)
		var previous: Node = mg_script.new()
		add_child(previous)
		previous.minigame_loaded.connect(Callable(g, "_on_minigame_loaded"))
		previous.minigame_ready.connect(Callable(g, "_on_minigame_ready"))
		g.set("minigame", previous)
		g.set("minigame_parent", Node.new())
		_stage(nm, c[1])
		g.call("load_minigame", Globals.MinigameIdentifier.GreenPea, false)
		games.append(g)
	for i in cases.size():
		if cases[i][2]:
			games[i].set("_mp8_load_serial", int(games[i].get("_mp8_load_serial")) + 1)
	_stage(nm, false)
	await get_tree().create_timer(1.3).timeout
	for i in cases.size():
		var g: Node = games[i]
		var went: bool = g.get("mp8_test_traces").any(func(t): return String(t).begins_with("load_minigame start"))
		ok("load serial: %s" % cases[i][0], went == cases[i][3], g.get("mp8_test_traces"))
		g.get("minigame_parent").free()
		g.free()
	GameManager.current_minigame_identifier = was_game_minigame
	nm.call("mp8_unlatch_room")

# minigame_playing_state.gd with the game stand-in as its owner: Extended claims the finish by epoch, a mixed
# room connects the game's own handler. The handler's last line (no state machine here) stops after the counts.
func _finish_claim(nm: Node, g: Node, mg_script: GDScript) -> void:
	var state_script := load("res://scripts/scenes/game/states/minigame_playing_state.gd") as GDScript
	if state_script == null:
		return
	var playlist: Array[Globals.MinigameIdentifier] = [Globals.MinigameIdentifier.GreenPea]
	# [what, room at enter, room at the finish, exit() before the finish, the round closed before it, scores sent]
	# A finish for a closed round is the late or repeated one the claim drops; the game's flow takes it.
	var cases := [
		["Extended, a live round's finish advances", true, true, false, false, 1],
		["Extended, a closed round's finish is dropped", true, true, false, true, 0],
		["mixed, a closed round's finish advances, as in the game", false, false, false, true, 1],
		["mixed, exit() leaves the game's handler connected", false, false, true, true, 1],
		["the room read at enter() holds when the latch turns mixed", true, false, false, true, 0],
	]
	for c in cases:
		var mg: Node = mg_script.new()
		g.add_child(mg)
		g.set("minigame", mg)
		g.set("session_minigame_list", playlist)
		g.set("session_minigame_index", 0)
		g.set("session_current_minigame_round", 1)
		g.set("session_current_minigame_max_rounds", 1)
		g.set("game_score_by_network_id", _ints({}))
		g.set("round_score_by_network_id", _ints({}))
		g.set("mp8_test_scores_sent", 0)
		g.call("_mp8_round_open", Globals.MinigameIdentifier.GreenPea)
		var state: Node = state_script.new()
		g.add_child(state)
		state.owner = g
		_stage(nm, c[1])
		state.call("enter")
		if c[3]:
			state.call("exit")
		if c[4]:
			g.call("_mp8_round_close", "test")
		_stage(nm, c[2])
		mg.emit_signal("minigame_finished", 1)
		var sent: int = g.get("mp8_test_scores_sent")
		ok("finish: %s" % c[0], sent == c[5], sent)
		state.free()
		g.set("minigame", null)
		mg.free()
		g.call("_mp8_round_close", "test")

# The intermission's boards, chosen per show (row 5): a mixed room gets the scene's own 4 rows back, as authored.
func _intermission_rows(nm: Node) -> void:
	var ref: Node = load(INTERMISSION).instantiate()
	var scene: Node = load(INTERMISSION).instantiate()
	add_child(scene)
	for i in 3:
		await get_tree().process_frame
	var manager = scene.get("cutscene_intro").intermission_manager
	var ref_manager = ref.get("cutscene_intro").intermission_manager
	_score_board(nm, manager.screen_score, ref_manager.screen_score)
	_briefing_board(nm, manager.screen_briefing, ref_manager.screen_briefing)
	var screen: SubViewport = scene.get_node_or_null("viewport_intermission screen/SubViewport")
	if screen != null:
		_stage(nm, false)
		manager.intermission_main_parent.visible = false
		ok("intermission screen, mixed: drawn while hidden, as the game does", screen.render_target_update_mode == SubViewport.UPDATE_ALWAYS, screen.render_target_update_mode)
		manager.intermission_main_parent.visible = true
		_stage(nm, true)
		manager.intermission_main_parent.visible = false
		ok("intermission screen, Extended: stops while hidden", screen.render_target_update_mode == SubViewport.UPDATE_DISABLED, screen.render_target_update_mode)
		manager.intermission_main_parent.visible = true
	# The cutscene's 8 s first: the board's two setup() calls are still running, and they sort the rows at about 2.7 s.
	await _cutscene_rows(nm, manager)
	await _swap_rows(manager.screen_score, scene)
	nm.call("mp8_unlatch_room")
	scene.free()
	ref.free()

# The swap: in the game's layout a row's target x is the other row's live x; in Extended's it comes from the x
# table. The two rows' live x are set apart, as mid-tween, so the two bodies differ in a single column too.
func _swap_rows(ss: Node, scene: Node) -> void:
	var om: Node = null
	for n in scene.find_children("*", "", true, false):
		if n.has_method("switch_places") and n.get("intermission_score") != null:
			om = n
	ok("swap: the score board's order manager found", om != null and om.get("intermission_score") == ss)
	if om == null:
		return
	for extended in [false, true]:
		var room := "Extended" if extended else "mixed"
		ss.call("mp8_apply_layout", extended)
		var rows: Array = ss.get("user_container_array")
		var a: Node3D = rows[0]
		var b: Node3D = rows[1]
		a.position.x = b.position.x + 0.3
		a.call("set_user_rank_label", 1)
		b.call("set_user_rank_label", 2)
		var want_a := b.position.x
		var want_b := a.position.x
		if extended:
			var xs: Array = ss.get("mp8_rank_x_positions")
			want_a = xs[1]
			want_b = xs[0]
		else:
			var ext_x: float = om.call("_mp8_slot_position", a, 2).x
			ok("swap, mixed: Extended's body would land elsewhere, so the row tells them apart", not is_equal_approx(ext_x, want_a), ext_x)
		om.call("switch_places", a, b)
		await get_tree().create_timer(0.7).timeout
		var y_ok: bool = is_equal_approx(a.position.y, ss.get("rank_y_positions")[1]) and is_equal_approx(b.position.y, ss.get("rank_y_positions")[0])
		ok("swap, %s: %s" % [room, "the x table" if extended else "the other row's live x, the game's body"],
			is_equal_approx(a.position.x, want_a) and is_equal_approx(b.position.x, want_b) and y_ok, [a.position, b.position, want_a, want_b])
	ss.call("mp8_apply_layout", true)

# The cutscene transition's enter() (4 s of awaits) on the real intermission: Extended starts the list at slot 0,
# a mixed room keeps the slot it had, as the game does. The stand-in records the load it is asked for.
func _cutscene_rows(nm: Node, manager: Node) -> void:
	var state_script := load("res://scripts/scenes/game/states/minigame_cutscene_transition_state.gd") as GDScript
	var game_script := _game_script("game stand-in, loads recorded", true)
	if state_script == null or game_script == null:
		return
	var playlist: Array[Globals.MinigameIdentifier] = [Globals.MinigameIdentifier.GreenPea, Globals.MinigameIdentifier.DuckHunt, Globals.MinigameIdentifier.TrainRace]
	for extended in [true, false]:
		var room := "Extended" if extended else "mixed"
		var g: Node = game_script.new()
		add_child(g)
		g.set("session_minigame_list", playlist)
		g.set("session_minigame_index", 2)
		g.set("session_next_minigame_index", 1)
		var state: Node = state_script.new()
		state.set("intermission_manager", manager)
		g.add_child(state)
		state.owner = g
		_stage(nm, extended)
		state.call("enter")
		await get_tree().create_timer(4.3).timeout
		var slot: int = g.get("session_minigame_index")
		ok("cutscene transition, %s: slot %d" % [room, 0 if extended else 2], slot == (0 if extended else 2), slot)
		ok("cutscene transition, %s: loads the list's first" % room, g.get("mp8_test_loads") == [Globals.MinigameIdentifier.GreenPea], g.get("mp8_test_loads"))
		g.free()

func _score_board(nm: Node, ss: Node, ref: Node) -> void:
	var ref_rows: Array = ref.get("user_container_array")
	var all: Array = ss.get("user_container_array").duplicate()
	ok("score board: 8 rows built", all.size() == 8, all.size())
	if all.size() != 8 or ref_rows.size() != 4:
		return
	var check_vanilla := func(when: String) -> void:
		var rows: Array = ss.get("user_container_array")
		ok("score board, mixed%s: 4 rows" % when, rows.size() == 4 and ss.get("score_container_nodes").size() == 4, rows.size())
		ok("score board, mixed%s: the game's y table" % when, ss.get("rank_y_positions") == [0.84, 0.325, -0.19, -0.705], ss.get("rank_y_positions"))
		ok("score board, mixed%s: no x table" % when, ss.get("mp8_rank_x_positions").is_empty())
		var same := true
		for i in 4:
			var a: Node3D = rows[i]
			var b: Node3D = ref_rows[i]
			# The game's sibling list: the scene's own entries, then the 4 rows its _ready() appends.
			var siblings: int = b.get("user_container_array").size() + 4
			if a.scale != b.scale or not is_equal_approx(a.position.x, b.position.x) or a.get("lerp_duration_score") != b.get("lerp_duration_score") or a.get("user_container_array").size() != siblings:
				same = false
		ok("score board, mixed%s: rows as authored (scale, x, score roll, the game's sibling list)" % when, same)
		ok("score board, mixed%s: rows 5-8 hidden" % when, range(4, 8).all(func(i): return not all[i].visible))
		ok("score board, mixed%s: the layout flag is the game's" % when, ss.get("mp8_extended_layout") == false)
		rows[0].call("set_user_container_data", 10, "ABCDEFGHIJK")
		ok("score board, mixed%s: the game's name cut" % when, rows[0].label_name.text == "ABCDEFGH-", rows[0].label_name.text)
		ok("score board, mixed%s: the game's font" % when, not (rows[0].label_name.font is FontVariation))
	var check_extended := func(when: String) -> void:
		var rows: Array = ss.get("user_container_array")
		ok("score board, Extended%s: 8 rows at 0.48" % when, rows.size() == 8 and rows.all(func(r): return is_equal_approx(r.scale.x, 0.48)), rows.size())
		ok("score board, Extended%s: 8 y and x slots" % when, ss.get("rank_y_positions").size() == 8 and ss.get("mp8_rank_x_positions").size() == 8)
		rows[0].call("set_user_container_data", 10, "ABCDEFGHIJK")
		ok("score board, Extended%s: the 7-character cut" % when, rows[0].label_name.text == "ABCDEF-", rows[0].label_name.text)
		ok("score board, Extended%s: bold" % when, rows[0].label_name.font is FontVariation)
	var ext_y: Array = ss.get("rank_y_positions").duplicate()
	ss.call("mp8_apply_layout", false)
	check_vanilla.call("")
	ss.call("mp8_apply_layout", true)
	check_extended.call(" after mixed")
	ok("score board, Extended after mixed: the same y table", ss.get("rank_y_positions") == ext_y)
	ss.call("mp8_apply_layout", false)
	check_vanilla.call(", again")
	_stage(nm, true)
	ss.call("setup", _ints({}), _ints({}))
	ok("score board: setup() in an Extended room shows 8 rows", ss.get("user_container_array").size() == 8)
	_stage(nm, false)
	ss.call("setup", _ints({}), _ints({}))
	ok("score board: setup() in a mixed room shows the game's 4", ss.get("user_container_array").size() == 4)
	ss.call("mp8_apply_layout", true)

func _rect(c: Control) -> Array:
	return [c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom, c.offset_left, c.offset_top, c.offset_right, c.offset_bottom, c.scale]

func _briefing_board(nm: Node, bs: Node, ref: Node) -> void:
	var ref_rows: Array = ref.get("user_container_array")
	var all: Array = bs.get("user_container_array").duplicate()
	ok("briefing: 8 rows built", all.size() == 8, all.size())
	if all.size() != 8 or ref_rows.size() != 4:
		return
	var ref_buttons: Array = ref.get("invite_buttons_visuals") + ref.get("invite_buttons_interacts")
	var check_vanilla := func(when: String) -> void:
		var rows: Array = bs.get("user_container_array")
		ok("briefing, mixed%s: 4 rows, scores, speakers and invites" % when, rows.size() == 4 and bs.get("score_container_nodes").size() == ref.get("score_container_nodes").size()
			and bs.get("speakers_show_player_card").size() == ref.get("speakers_show_player_card").size()
			and bs.get("invite_buttons_visuals").size() == 4 and bs.get("invite_buttons_interacts").size() == 4,
			[rows.size(), bs.get("score_container_nodes").size(), bs.get("speakers_show_player_card").size()])
		ok("briefing, mixed%s: the game's y table" % when, bs.get("rank_y_positions") == [0.0, 19.0, 38.0, 57.0], bs.get("rank_y_positions"))
		ok("briefing, mixed%s: rows at the scene's scale" % when, range(4).all(func(i): return rows[i].scale == ref_rows[i].scale))
		var buttons: Array = bs.get("invite_buttons_visuals") + bs.get("invite_buttons_interacts")
		var rects_same: bool = buttons.size() == ref_buttons.size()
		for i in mini(buttons.size(), ref_buttons.size()):
			if _rect(buttons[i]) != _rect(ref_buttons[i]):
				rects_same = false
				say("  invite %d: %s against the scene's %s" % [i, str(_rect(buttons[i])), str(_rect(ref_buttons[i]))])
		ok("briefing, mixed%s: invite buttons as authored" % when, rects_same)
		ok("briefing, mixed%s: rows 5-8 hidden" % when, range(4, 8).all(func(i): return not all[i].visible))
		rows[0].call("set_user_data", 0, "ABCDEFGHIJK")
		ok("briefing, mixed%s: the game's name cut" % when, rows[0].label_name.text == "ABCDEFGH-", rows[0].label_name.text)
		ok("briefing, mixed%s: the game's font" % when, not (rows[0].label_name.get_theme_font("font") is FontVariation))
	var check_extended := func(when: String) -> void:
		var rows: Array = bs.get("user_container_array")
		ok("briefing, Extended%s: 8 rows at 0.5" % when, rows.size() == 8 and rows.all(func(r): return is_equal_approx(r.scale.x, 0.5)), rows.size())
		rows[0].call("set_user_data", 0, "ABCDEFGHIJK")
		ok("briefing, Extended%s: the 7-character cut" % when, rows[0].label_name.text == "ABCDEF-", rows[0].label_name.text)
		ok("briefing, Extended%s: bold" % when, rows[0].label_name.get_theme_font("font") is FontVariation)
	bs.call("mp8_apply_layout", false)
	check_vanilla.call("")
	bs.call("mp8_apply_layout", true)
	check_extended.call(" after mixed")
	bs.call("mp8_apply_layout", false)
	check_vanilla.call(", again")
	_stage(nm, true)
	bs.call("reset_briefing_rpc", _ints({}), 0, 1)
	ok("briefing: a reset in an Extended room shows 8 rows", bs.get("user_container_array").size() == 8)
	_stage(nm, false)
	bs.call("update_player_data_rpc", {})
	ok("briefing: an update mid-briefing never shrinks to 4", bs.get("user_container_array").size() == 8)
	bs.call("reset_briefing_rpc", _ints({}), 0, 1)
	ok("briefing: a reset in a mixed room shows the game's 4", bs.get("user_container_array").size() == 4)
	_stage(nm, true)
	bs.call("update_player_data_rpc", {})
	ok("briefing: an update mid-briefing grows to 8 when the room is Extended again", bs.get("user_container_array").size() == 8)

# Duck Hunt's MAG/RATE line: in a local game inside the hunter's own tile HUD, one line at 14 px
# (owner's pick); online on the window-wide overlay, two lines at 26 px, as Overtime draws it.
func _hunter_hud(local: bool) -> void:
	var where := "local" if local else "online"
	var was_local: bool = GameManager.local_game
	GameManager.local_game = local
	var hunter: Node = load(HUNTER).instantiate()
	add_child(hunter)
	var presence := PlayerPresence.new()
	presence.network_id = multiplayer.get_unique_id()
	hunter.player_presence = presence
	hunter.call("_mp8_show_id_hud")
	var lbl = hunter.get("_mp8_id_label")
	ok("MAG/RATE label made (%s)" % where, lbl is RichTextLabel)
	if lbl is RichTextLabel:
		ok("MAG/RATE in the tile HUD (%s)" % where, (lbl.get_parent() == hunter.hud) == local, lbl.get_parent().name)
		var size: int = lbl.get_theme_font_size("normal_font_size")
		ok("MAG/RATE size (%s)" % where, size == (14 if local else 26), size)
		ok("MAG/RATE lines (%s)" % where, lbl.text.contains("\n") != local, lbl.text.c_escape())
	# Freed now, not queued: the test quits right after, and a hunter still holding its presence crashes the exit.
	hunter.free()
	presence.free()
	GameManager.local_game = was_local

# 1.1.0's Chinese: the language read as the game sets it, and a sample of each script's strings in
# ZHS and ZHT. extended/tools/check_text_triples.ps1 checks every triple's shape at build time.
func _chinese(nm: Node) -> void:
	say("step: Chinese text")
	var langs := {"EN": "EN", "ZHS": "ZHS", "ZHT": "ZHT", "zh_CN": "ZHS", "zh-Hans": "ZHS", "zh_TW": "ZHT", "zh_HK": "ZHT", "DE": "EN", "JA": "EN"}
	var wrong := langs.keys().filter(func(k): return nm.call("mp8_locale", k) != langs[k])
	ok("the game's language read as EN, ZHS or ZHT", wrong.is_empty(), wrong)
	var host_before = nm.get("_mp8_host_version")
	for lang in ["ZHS", "ZHT"]:
		TranslationServer.set_locale(lang)
		ok("mp8_locale() follows the game (%s)" % lang, nm.call("mp8_locale") == lang, nm.call("mp8_locale"))
		var duck: Node = load("res://minigames/duck_hunt/scripts/duck_hunt.gd").new()
		duck.set("mp8_hunter_names", ["theo", "marc"])
		var two := str(duck.call("mp8_hunters_line"))
		ok("reveal line, two hunters, %s" % lang, two.begins_with("THEO") and two.contains("MARC") and _has_cjk(two), two)
		duck.free()
		var burn: Node = load("res://minigames/burn_recycle/scripts/burn_recycle.gd").new()
		burn.call("_mp8_score_board_rpc", PackedInt32Array([901, 902]), PackedInt32Array([-1, 12]))
		var panel = burn.get("_mp8_score_panel")
		var board: String = panel.text if panel is Label else ""
		ok("board text, %s" % lang, board.begins_with("得分") and board.contains("12") and board.contains("已淘汰"), board)
		burn.free()
		nm.set("_mp8_host_version", "v2.1.2+mp8-1.0")
		var refusal := str(nm.call("mp8_mismatch_text"))
		ok("refusal text, a 1.0 host, %s: both builds, 2 lines" % lang, refusal.contains(TAG) and refusal.contains("mp8-1.0") and refusal.split("\n").size() == 2 and _has_cjk(refusal), refusal.c_escape())
		var host := str(nm.call("_mp8_blocked_text_for_host", "v2.1.2+mp8-1.0"))
		ok("host's line, %s" % lang, host.contains(TAG) and host.contains("mp8-1.0") and _has_cjk(host), host)
		var full := str(nm.call("mp8_room_full_text"))
		ok("room-full text, %s, 2 lines" % lang, full.split("\n").size() == 2 and _has_cjk(full), full.c_escape())
	nm.set("_mp8_host_version", host_before)
	_board_lines()
	TranslationServer.set_locale("EN")
	ok("room-full text in English is the const", nm.call("mp8_room_full_text") == nm.get("MP8_ROOM_FULL_TEXT"))

# The Filter's board in the tree, 8 long names in ZHS: lines break only at a separator, so each name stays
# with its count or 已淘汰 (Godot's own wrap split them).
func _board_lines() -> void:
	var burn: Node = load("res://minigames/burn_recycle/scripts/burn_recycle.gd").new()
	var panel := Label.new()
	add_child(panel)
	panel.add_theme_font_override("font", load("res://fonts/Terminal F4.ttf"))
	panel.add_theme_font_size_override("font_size", 16)
	burn.set("_mp8_score_panel", panel)
	var sep := "  ·  "
	var parts := PackedStringArray()
	for i in 8:
		parts.append("PLAYERNAME%d %s" % [i, "已淘汰" if i > 3 else str(40 - i)])
	var text: String = burn.call("_mp8_score_lines", "得分   ", parts)
	var lines := text.split("\n")
	var width: float = panel.get_viewport_rect().size.x - 20.0
	var whole := Array(parts).all(func(p): return Array(lines).any(func(l): return l.contains(p)))
	ok("board lines join back to one line at the separators", sep.join(lines) == "得分   " + sep.join(parts), text.c_escape())
	ok("board lines keep every name with its status", whole and lines.size() > 1, [lines.size(), width])
	burn.set("_mp8_score_panel", null)
	panel.free()
	burn.free()

func _has_cjk(text: String) -> bool:
	for c in text:
		if c.unicode_at(0) >= 0x3000:
			return true
	return false

# The 0.7.0 strings, on bare script instances: Duck Hunt's online reveal line, The Filter's board.
func _text_checks() -> void:
	var duck: Node = load("res://minigames/duck_hunt/scripts/duck_hunt.gd").new()
	duck.set("mp8_hunter_names", ["THEO"])
	var one := str(duck.call("mp8_hunters_line"))
	ok("reveal line, one hunter: the game's own", one.contains("THEO") and one.contains("HUNTER") and not one.contains(" AND "), one)
	duck.set("mp8_hunter_names", ["theo", "marc"])
	var two := str(duck.call("mp8_hunters_line"))
	ok("reveal line, two hunters", two == "THEO AND MARC ARE THE HUNTERS.", two)
	duck.free()
	var burn: Node = load("res://minigames/burn_recycle/scripts/burn_recycle.gd").new()
	burn.call("_mp8_score_board_rpc", PackedInt32Array([901, 902, 903]), PackedInt32Array([-1, 12, 30]))
	var panel = burn.get("_mp8_score_panel")
	var want := "SCORE   903 30  ·  902 12  ·  901 OUT"
	ok("board text: best first, OUT last", panel is Label and panel.text == want, (panel.text if panel is Label else "no label").c_escape())
	burn.call("_mp8_score_board_rpc", PackedInt32Array(), PackedInt32Array())
	ok("board clears", panel is Label and panel.text == "", "")
	burn.free()
	_filter_rounds()
	_table_catch_limit()

# Table Manners (0.21.0): a round that starts with 6 or more players catches two a glance, below it one.
func _table_catch_limit() -> void:
	var C: GDScript = load("res://minigames/green_pea/components/coach_handler/coach_handler.gd")
	var got: Array = range(1, 9).map(func(k): return C.call("mp8_catch_limit", k))
	ok("Table Manners catch limit at 1-8 seated", got == [1, 1, 1, 1, 1, 2, 2, 2], got)

# The Filter at 5-8 players (0.16.0): 4 rounds without ties, at most 2 out a round, the game's zero and
# tie rules per slot.
func _filter_rounds() -> void:
	var B: GDScript = load("res://minigames/burn_recycle/scripts/burn_recycle.gd")
	var want := {5: [1, 1, 1, 1], 6: [2, 1, 1, 1], 7: [2, 2, 1, 1], 8: [2, 2, 2, 1]}
	for n in want:
		var got: Array = []
		var active: int = n
		while active > 1 and got.size() < 8:
			var k: int = B.call("mp8_elim_slots", active, got.size())
			got.append(k)
			active -= k
		ok("Filter schedule at %d" % n, got == want[n], got)
	ok("Filter after a tie round at 8, still 2 out", B.call("mp8_elim_slots", 8, 1) == 2, B.call("mp8_elim_slots", 8, 1))
	ok("Filter 5 left for round 4 after ties: 2 out, a round more", B.call("mp8_elim_slots", 5, 3) == 2, B.call("mp8_elim_slots", 5, 3))
	ok("Filter past round 4, 2 left: 1 out", B.call("mp8_elim_slots", 2, 5) == 1, B.call("mp8_elim_slots", 2, 5))
	var pick := func(scores: Dictionary, slots: int) -> Array: return B.call("mp8_pick_victims", scores, slots)
	var r: Array = pick.call({1: 5, 2: 3, 3: 9, 4: 7}, 2)
	ok("Filter picks the two lowest, lowest first", r == [2, 1], r)
	r = pick.call({1: 3, 2: 5, 3: 5, 4: 9}, 2)
	ok("Filter tie straddling the cut: nobody from it", r == [1], r)
	r = pick.call({1: 4, 2: 4, 3: 9}, 1)
	ok("Filter tie at one slot: nobody, as the game", r == [], r)
	r = pick.call({1: 2, 2: 6}, 1)
	ok("Filter one slot: the lone lowest", r == [1], r)
	r = pick.call({1: 4, 2: 4, 3: 9}, 2)
	ok("Filter tied pair inside the slots: both", r.size() == 2 and r.has(1) and r.has(2), r)
	r = pick.call({1: 0, 2: 0, 3: 0, 4: 5}, 2)
	ok("Filter zeros fill the slots at random", r.size() == 2 and r.all(func(id): return id in [1, 2, 3]), r)
	r = pick.call({1: 0, 2: 3, 3: 5}, 2)
	ok("Filter a zero, then the next lowest", r == [1, 2], r)

func _refused(log_text: String, nm: Node) -> void:
	say("step: mp8_support beside overtime")
	ok("mp8_support refused", log_text.contains("mp8_support: [MP8:OVERTIME_PRESENT]"))
	ok("mp8_support did not mount", not log_text.contains("mp8_support: [MOUNTED]"))
	ok("overtime mounted", log_text.contains("overtime: [MOUNTED]"))
	ok("Overtime's tag is live", str(nm.get("MP8_VERSION_TAG")).begins_with("overtime-"), nm.get("MP8_VERSION_TAG"))
	# All or nothing: a refused Extended starts none of the mods in its bundle.
	ok("no bundled mod started", _hosted_nodes().is_empty() and not log_text.contains("mp8_support: hosting"), _hosted_nodes())

# Extended in two folders (the bundle's machine_party_extended beside a build's mp8_support): every copy
# with the check refuses before mounting, so both do when both have it; an older one mounts alone.
# Either way no bundle's mods start and at most one overlay mounts.
func _twice(log_text: String, copies: Array) -> void:
	say("step: installed in two folders %s" % str(copies))
	var refusals := log_text.count("mp8_support: [MP8:INSTALLED_TWICE]")
	var mounts := log_text.count("mp8_support: [MOUNTED]")
	say("refusals %d, mounts %d" % [refusals, mounts])
	ok("a copy refused", refusals >= 1, refusals)
	ok("one overlay at most, and none when both copies refused", mounts == 2 - refusals, [refusals, mounts])
	ok("no bundled mod started", _hosted_nodes().is_empty() and not log_text.contains("mp8_support: hosting"), _hosted_nodes())

# A bundle's mods sit in its folder's subfolders. Each starts once, under the loader and named by its id,
# with its folder in "mpml_dir", unless a separate copy of it is installed, which runs alone.
func _hosting(log_text: String) -> void:
	say("step: bundled mods")
	var dir: String = _loader.dir_of("mp8_support")
	var mods_dir := dir.get_base_dir()
	var main_script = _loader.compile(dir.path_join("main.gd"))
	var bundled := []
	for sub in DirAccess.get_directories_at(dir):
		if FileAccess.file_exists(dir.path_join(sub).path_join("mod.json")):
			bundled.append(sub)
	say("bundled: %s" % str(bundled))
	if bundled.is_empty():
		ok("no bundle: nothing hosted", _hosted_nodes().is_empty() and not log_text.contains("mp8_support: hosting"), _hosted_nodes())
		return
	for sub in bundled:
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(sub).path_join("mod.json")))
		var id := str(data.get("id", sub))
		var copies := _mod_nodes(id)
		ok("%s: one copy running" % id, copies.size() == 1, copies)
		var separate: String = main_script._installed_folder(mods_dir, id)
		if separate.is_empty():
			var node: Node = _loader.get_node_or_null(id)
			ok("%s: hosted under the loader" % id, node != null and node.get_meta("mpml_dir", "") == dir.path_join(sub), node)
			ok("%s: its hosting note" % id, log_text.contains("mp8_support: hosting %s v%s" % [id, data.get("version", "0.0.0")]))
		else:
			ok("%s: the separate mods/%s runs, the bundle's stands down" % [id, separate], copies.size() == 1 and not copies[0].has_meta("mpml_dir"), copies)
			ok("%s: its stand-down note" % id, log_text.contains("mp8_support: mods/%s runs instead of this bundle's %s" % [separate, id]))

# Every top-level folder whose mod.json id (or, with none, its name) is mp8_support.
func _extended_folders() -> Array:
	var mods_dir := OS.get_executable_path().get_base_dir().path_join("mods")
	var found := []
	for sub in DirAccess.get_directories_at(mods_dir):
		var path := mods_dir.path_join(sub).path_join("mod.json")
		if sub.begins_with(".") or not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("id", sub)) == "mp8_support":
			found.append(sub)
	return found

func _hosted_nodes() -> Array:
	return _loader.get_children().filter(func(n): return n.has_meta("mpml_dir"))

# By its MOD_ID line rather than its name: two copies under one parent can't share a name.
func _mod_nodes(id: String) -> Array:
	var line := 'const MOD_ID := "%s"' % id
	return _loader.get_children().filter(func(n): return n.get_script() is GDScript and n.get_script().source_code.contains(line))

# The intro's rack (roadmap step 10): the game's 4 slots up to 4 players; from 5, 8 slots in two stacks, built once
# however many of the intro, the skip and a reconnect ask, each tag and tube in its own place. "again": a new
# instance after an 8-player build still has the game's hand positions (a build must not rewrite the scene's copy).
func _intro_rack(players: int, again := false) -> void:
	var scene: Node = load(INTERMISSION).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var intro = scene.get("cutscene_intro")
	var label := "%d players%s" % [players, ", a new instance after 8" if again else ""]
	ok("intro found (%s)" % label, intro != null)
	if intro != null:
		var hands_before: Array = intro.hand_armature_parent_position_by_rack_index.duplicate()
		if _game_hands.is_empty():
			_game_hands = hands_before
		ok("the game's hand positions (%s)" % label, hands_before == _game_hands, hands_before)
		var mount: Node3D = intro.intermission_manager.intermission_cam.get_parent()
		ok("camera mount authored at zero (%s)" % label, mount.position == Vector3.ZERO, mount.position)
		var copies := func() -> int: return scene.find_children("* mp8 *", "", true, false).size()
		await intro.call("_mp8_build_rack", players)
		var after_first: int = copies.call()
		await intro.call("_mp8_build_rack", players)
		ok("built once (%s)" % label, copies.call() == after_first and after_first == (25 if players > 4 else 0), [after_first, copies.call()])
		var want := 8 if players > 4 else 4
		var tags: Array = intro.rack_nametags
		var tubes: Array = intro.vessels_in_main_rack
		ok("tags (%s)" % label, tags.size() == want, tags.size())
		ok("tubes (%s)" % label, tubes.size() == want, tubes.size())
		ok("hand positions (%s)" % label, intro.hand_armature_parent_position_by_rack_index.size() == want)
		ok("arm scale (%s)" % label, is_equal_approx(intro.hand_armature_parent.scale.x, 0.7 if players > 4 else 1.0), intro.hand_armature_parent.scale)
		var apart := func(nodes: Array) -> bool:
			for i in nodes.size():
				for j in i:
					if nodes[i].global_position.distance_to(nodes[j].global_position) < 0.1:
						return false
			return true
		ok("each tag in its own place (%s)" % label, apart.call(tags))
		ok("each tube in its own place (%s)" % label, apart.call(tubes))
		if players > 4:
			ok("tags 5-8 below tags 1-4", range(4).all(func(i): return tags[i + 4].global_position.y < tags[3].global_position.y))
			ok("tags 5-8 are their own nodes", range(4).all(func(i): return tags[i + 4] != tags[i] and tags[i + 4].is_inside_tree()))
	scene.free()

# A rack stacked at a start of 5 or more, in a room that has since turned mixed: the
# mixed intro unstacks it first, so the game's copy runs on the game's 4 slots, each where the scene has it.
# An Extended room keeps the stack, and the rack stacks again after.
func _intro_unstack(nm: Node) -> void:
	var scene: Node = load(INTERMISSION).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var intro = scene.get("cutscene_intro")
	if intro == null or not intro.has_method("_mp8_unstack_rack"):
		ok("intro: _mp8_unstack_rack exists", false)
		scene.free()
		return
	var was_local: bool = GameManager.local_game
	var copies := func() -> int: return scene.find_children("* mp8 *", "", true, false).size()
	var tags_before: Array = intro.rack_nametags.duplicate()
	var tag_xf: Array = tags_before.map(func(t): return t.global_transform)
	var tube_xf: Array = intro.vessels_in_main_rack.map(func(t): return t.global_transform)
	var hidden_before: int = intro.visuals_to_hide.size()
	await intro.call("_mp8_build_rack", 8)
	_stage(nm, true)
	await intro.call("reset_nametags_rpc", [])
	ok("intro rack, Extended: still stacked", intro.rack_nametags.size() == 8 and copies.call() == 25, [intro.rack_nametags.size(), copies.call()])
	_stage(nm, false)
	# Mid-way through Extended's intro its loop still indexes the stack: a room turned mixed waits for the next show.
	intro.set("_mp8_intro_playing", true)
	await intro.call("reset_nametags_rpc", [])
	ok("intro rack, mixed while Extended's intro plays: still stacked", intro.rack_nametags.size() == 8 and copies.call() == 25, [intro.rack_nametags.size(), copies.call()])
	intro.set("_mp8_intro_playing", false)
	await intro.call("reset_nametags_rpc", [])
	var tags: Array = intro.rack_nametags
	ok("intro rack, mixed: the game's 4 tags and tubes", tags.size() == 4 and intro.vessels_in_main_rack.size() == 4, [tags.size(), intro.vessels_in_main_rack.size()])
	ok("intro rack, mixed: the scene's own tags", tags == tags_before)
	ok("intro rack, mixed: the added nodes gone", copies.call() == 0, copies.call())
	var arm_back: bool = intro.hand_armature_parent_position_by_rack_index == _game_hands and is_equal_approx(intro.hand_armature_parent.scale.x, 1.0)
	ok("intro rack, mixed: the game's hand positions and arm", arm_back, intro.hand_armature_parent.scale)
	ok("intro rack, mixed: the hidden list as authored", intro.visuals_to_hide.size() == hidden_before, intro.visuals_to_hide.size())
	var in_place := true
	for i in 4:
		if not tags[i].global_transform.is_equal_approx(tag_xf[i]) or not intro.vessels_in_main_rack[i].global_transform.is_equal_approx(tube_xf[i]):
			in_place = false
	ok("intro rack, mixed: each tag and tube back in place", in_place)
	nm.call("mp8_unlatch_room")
	GameManager.local_game = was_local
	await intro.call("_mp8_build_rack", 8)
	ok("intro rack: stacks again after", intro.rack_nametags.size() == 8 and copies.call() == 25, [intro.rack_nametags.size(), copies.call()])
	scene.free()

# 0.8.0's renders nobody sees: the intermission's terminal screen draws only while the scene shows, and the
# window's 3D is skipped only behind an opaque, visible, full-window ColorRect as a tile layer's first child.
func _hidden_renders() -> void:
	var scene: Node = load(INTERMISSION).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var manager = scene.get("cutscene_intro").intermission_manager
	var screen: SubViewport = scene.get_node_or_null("viewport_intermission screen/SubViewport")
	ok("intermission screen found", screen != null)
	if screen != null:
		ok("intermission screen draws while the scene shows", screen.render_target_update_mode == SubViewport.UPDATE_ALWAYS, screen.render_target_update_mode)
		manager.intermission_main_parent.visible = false
		ok("intermission screen stops while the scene is hidden", screen.render_target_update_mode == SubViewport.UPDATE_DISABLED, screen.render_target_update_mode)
		manager.intermission_main_parent.visible = true
		ok("intermission screen draws again when the scene shows", screen.render_target_update_mode == SubViewport.UPDATE_ALWAYS, screen.render_target_update_mode)
	scene.free()
	var local_game: GDScript = load("res://scenes/local_game/script/local_game.gd")
	var window := Rect2(0, 0, 960, 540)
	var layer := CanvasLayer.new()
	var cover := ColorRect.new()
	cover.color = Color.BLACK
	cover.size = window.size
	layer.add_child(cover)
	add_child(layer)
	ok("window 3D skipped behind an opaque full cover", local_game.mp8_covers_window(layer, window))
	var cases := {
		"a half-transparent cover": func(): cover.color.a = 0.5,
		"a faded cover": func(): cover.modulate.a = 0.99,
		"a hidden layer": func(): layer.visible = false,
		"a hidden cover": func(): cover.visible = false,
		"a cover a pixel short": func(): cover.size = window.size - Vector2(0, 1),
		"a moved layer": func(): layer.offset = Vector2(1, 0),
		"a cover with a shader": func(): cover.material = ShaderMaterial.new(),
	}
	for label in cases:
		cases[label].call()
		ok("window 3D drawn with %s" % label, not local_game.mp8_covers_window(layer, window))
		cover.color = Color.BLACK
		cover.modulate = Color.WHITE
		cover.visible = true
		cover.size = window.size
		cover.material = null
		layer.visible = true
		layer.offset = Vector2.ZERO
	var under := Control.new()
	layer.add_child(under)
	layer.move_child(under, 0)
	ok("window 3D drawn when the cover is not the layer's first child", not local_game.mp8_covers_window(layer, window))
	ok("window 3D drawn with no layer", not local_game.mp8_covers_window(null, window))
	layer.free()

# The wheat field's spawn spots: the scene's 4 markers up to 4 players; from 5, its 4 more, each far enough from
# the others and from the house's trigger, standing in the fixed camera's view and not behind a first-row player.
func _wheat_field() -> void:
	var was_local: bool = GameManager.local_game
	# Minigame._ready stops before the network calls in a local game.
	GameManager.local_game = true
	var scene: Node = load(WHEAT_FIELD).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var markers: Array = scene.players_spawn_node.get_children()
	var at_markers: Array = markers.map(func(m): return m.global_position)
	ok("the wheat field keeps the game's 4 markers, no top-up", markers.size() == 4, markers.size())
	var four: Array = scene.call("_mp8_spawn_spots", markers, 4)
	ok("4 players stand on the markers", four == at_markers, four)
	var spots: Array = scene.call("_mp8_spawn_spots", markers, 8)
	ok("8 players get 8 spots, the markers first", spots.size() == 8 and spots.slice(0, 4) == at_markers, spots)
	var apart := true
	for i in spots.size():
		for j in i:
			apart = apart and spots[i].distance_to(spots[j]) >= 2.0
	ok("the spots are at least 2 m apart", apart, spots)
	var proximity := FieldHouseProximity.new()
	var house: Vector3 = proximity.house_location
	proximity.free()
	ok("every spot is outside the house's trigger", spots.all(func(p): return p.distance_to(house) > 30.0 and p.y == 0.0), spots.map(func(p): return p.distance_to(house)))
	var cam: Camera3D = scene.cam
	var reach := tan(deg_to_rad(cam.fov) / 2.0) * 0.95
	var across := func(p: Vector3) -> float:
		var local: Vector3 = cam.global_transform.affine_inverse() * p
		return local.x / (-local.z * reach * 16.0 / 9.0)
	var in_view := func(p: Vector3) -> bool:
		for lift in [0.0, 1.8]:
			var local: Vector3 = cam.global_transform.affine_inverse() * (p + Vector3.UP * lift)
			if local.z >= 0.0 or absf(local.x) > -local.z * reach * 16.0 / 9.0 or absf(local.y) > -local.z * reach:
				return false
		return true
	ok("every spot is in the camera's 16:9 view, feet to head", spots.all(func(p): return in_view.call(p)), spots.map(func(p): return across.call(p)))
	var clear := true
	for b in spots.slice(4):
		for f in spots.slice(0, 4):
			clear = clear and absf(across.call(b) - across.call(f)) >= 0.1
	ok("no second-row spot is behind a first-row player on screen", clear, spots.map(func(p): return snappedf(across.call(p), 0.01)))
	# The scene's own _ready waits 1 s in a local game before it signals; free it after that.
	await get_tree().create_timer(1.2).timeout
	scene.free()
	GameManager.local_game = was_local

func _chisel_steps(H: GDScript, from: int, direction: Vector2, gone: Array = []) -> int:
	var others := {}
	for id in CHISEL_CUBES:
		if id != from and not id in gone:
			others[id] = CHISEL_CUBES[id]
	return H.mp8_pick_screen_target(CHISEL_CUBES[from], others, direction)

func _chisel_pad() -> void:
	say("step: chisel pad steps")
	var H: GDScript = load(CHISEL_HANDLER)
	ok("the handler picks by screen direction", H.get_script_method_list().any(func(m): return m.name == "_mp8_screen_target"))
	var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var none: int = H.get_script_constant_map().get("MP8_NO_TARGET", -1)
	var seen := {8: 0}
	var queue := [8]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for d in dirs:
			var to: int = _chisel_steps(H, at, d)
			if to != none and not seen.has(to):
				seen[to] = seen[at] + 1
				queue.append(to)
	ok("every cube, SUBMIT and RESET reachable from the start cube", seen.size() == 21, seen.keys())
	ok("the top-back cube 2 presses from the start", seen.get(0) == 2, seen.get(0))
	var ups := [1, 3, 4].map(func(i): return _chisel_steps(H, i, Vector2.UP))
	ok("up from the top face's cubes 1, 3 and 4 reaches the top-back cube", ups == [0, 0, 0], ups)
	var off := []
	for i in CHISEL_CUBES:
		for d in dirs:
			var to: int = _chisel_steps(H, i, d)
			if to != none and rad_to_deg(absf((CHISEL_CUBES[to] - CHISEL_CUBES[i]).angle_to(d))) > H.MP8_SCREEN_CONE_DEG:
				off.append([i, d, to])
	ok("no step lands outside the cone", off.is_empty(), off)
	ok("a chiselled cube is skipped", _chisel_steps(H, 8, Vector2.UP, [4]) == 0, _chisel_steps(H, 8, Vector2.UP, [4]))
	var to_submit := [6, 9, 12].map(func(i): return _chisel_steps(H, i, Vector2.LEFT))
	ok("left from the left face's edge reaches SUBMIT (-1, not the fallback)", to_submit == [-1, -1, -1], to_submit)
	var to_reset := [2, 16, 18].map(func(i): return _chisel_steps(H, i, Vector2.RIGHT))
	ok("right from the right face's edge reaches RESET", to_reset == [-2, -2, -2], to_reset)
	ok("nothing that way gives the table fallback, an id no segment has", none < -2 and _chisel_steps(H, 0, Vector2.UP) == none and _chisel_steps(H, 14, Vector2.DOWN) == none, none)
	await _chisel_diagonals(H, none)

# 0.11: the honeycomb's diagonal neighbours are one stick press away.
func _chisel_diagonals(H: GDScript, none: int) -> void:
	say("step: chisel diagonal steps")
	ok("the handler reads 8 directions", H.get_script_method_list().any(func(m): return m.name == "_mp8_stick_press"))
	var r := Vector2(1, 0)
	var ur := Vector2(1, -1).normalized()
	var snaps := [H.mp8_snap_8(Vector2(1, 0)), H.mp8_snap_8(Vector2(0.7, -0.65)), H.mp8_snap_8(Vector2(0.9, -0.3)), H.mp8_snap_8(Vector2(0.3, 0.95)), H.mp8_snap_8(Vector2.ZERO)]
	ok("a stick snaps to the nearest of 8 directions", snaps[0] == r and snaps[1].is_equal_approx(ur) and snaps[2] == r and snaps[3] == Vector2.DOWN and snaps[4] == Vector2.ZERO, snaps)
	var leans := [H.mp8_snap_8(Vector2(0.8, -0.6)), H.mp8_cardinal(Vector2(0.8, -0.6)), H.mp8_cardinal(Vector2(0.6, -0.8))]
	ok("a diagonal falls back to the stick it leans toward", leans[0].is_equal_approx(ur) and leans[1] == Vector2.RIGHT and leans[2] == Vector2.UP, leans)
	var d8 := {"U": Vector2.UP, "D": Vector2.DOWN, "L": Vector2.LEFT, "R": Vector2.RIGHT, "UR": ur, "UL": Vector2(-1, -1).normalized(), "DR": Vector2(1, 1).normalized(), "DL": Vector2(-1, 1).normalized()}
	var around := {}
	for k in ["U", "D", "UR", "DR", "UL", "DL"]:
		around[k] = _chisel_steps(H, 8, d8[k])
	ok("from cube 8 each of its six neighbours is one press", around == {"U": 4, "D": 11, "UR": 5, "DR": 15, "UL": 7, "DL": 10}, around)
	var missed := []
	for pair in [[8, 5], [8, 15], [2, 5], [16, 5], [16, 15], [7, 10], [9, 10], [12, 10], [11, 10], [11, 13], [3, 4], [1, 4], [7, 4], [5, 4]]:
		if not d8.values().any(func(d): return _chisel_steps(H, pair[0], d) == pair[1]):
			missed.append(pair)
	ok("every pair the owner found hard is one press", missed.is_empty(), missed)
	var seen := {8: 0}
	var queue := [8]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for d in d8.values():
			var to: int = _chisel_steps(H, at, d)
			if to != none and not seen.has(to):
				seen[to] = seen[at] + 1
				queue.append(to)
	ok("with diagonals every cube, SUBMIT and RESET still reachable, cube 0 in 2", seen.size() == 21 and seen.get(0) == 2, seen)
	# The press itself, through the game's actions: Input outside a local game, as online.
	var was_local: bool = GameManager.local_game
	GameManager.local_game = false
	var h: Node = H.new()
	var got := []
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	Input.action_press(&"up", 0.3)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	Input.action_press(&"right", 0.7)
	Input.action_press(&"up", 0.7)
	got.append(h._mp8_stick_press(0.016))
	ok("a flick waits for its second axis, then steps diagonally", got[0] == Vector2.ZERO and got[1] == Vector2.ZERO and H.mp8_snap_8(got[2]).is_equal_approx(ur), got)
	_release_dirs()
	await get_tree().process_frame
	got.clear()
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	got.append(h._mp8_stick_press(0.1))
	ok("a gentle push steps once the settle time has passed", got[0] == Vector2.ZERO and H.mp8_snap_8(got[1]) == r, got)
	_release_dirs()
	await get_tree().process_frame
	got.clear()
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	_release_dirs()
	await get_tree().process_frame
	got.append(h._mp8_stick_press(0.016))
	ok("a tap released before it settles still steps", got[0] == Vector2.ZERO and H.mp8_snap_8(got[1]) == r, got)
	await get_tree().process_frame
	# Raw strengths follow the stick below the deadzone: its rest after a tap must not steer.
	got.clear()
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	_release_dirs()
	Input.action_press(&"up", 0.03)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	got.append(h._mp8_stick_press(0.1))
	ok("a tap steps the way it was pushed, not the way the stick rests", got[0] == Vector2.ZERO and got[1] == Vector2.ZERO and H.mp8_snap_8(got[2]) == r, got)
	_release_dirs()
	await get_tree().process_frame
	got.clear()
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	got.append(h._mp8_stick_press(0.0, true))
	ok("A during a settling press settles it at once (the handler steps before cutting)", got[0] == Vector2.ZERO and H.mp8_snap_8(got[1]) == r, got)
	_release_dirs()
	await get_tree().process_frame
	got.clear()
	Input.action_press(&"right", 0.3)
	got.append(h._mp8_stick_press(0.016))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	got.append(h._mp8_stick_press(0.1))
	ok("a press left settling while the handler was not called is dropped", got == [Vector2.ZERO, Vector2.ZERO], got)
	_release_dirs()
	await get_tree().process_frame
	Input.action_press(&"left")
	var dpad: Vector2 = h._mp8_stick_press(0.016)
	ok("a d-pad press steps at once", dpad == Vector2.LEFT, dpad)
	_release_dirs()
	await get_tree().process_frame
	ok("no press, no step", h._mp8_stick_press(0.016) == Vector2.ZERO)
	h.free()
	GameManager.local_game = was_local

func _release_dirs() -> void:
	for a in [&"up", &"down", &"left", &"right"]:
		Input.action_release(a)

