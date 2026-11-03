extends Node

# Dev-only headless regression test for gamecube_support. See README.
# Works with Overtime / Better Couch Lobby / Bots / FPV / MP+ installed.
# Style changes use persist=false; the console check restores the config file.

const BASE := "res://textures/ui/control/"
const INTERMISSION := "res://minigames/intermission_new/intermission_new.tscn"
const LABEL := "res://modules/user_interface/intermission_control_input_label/intermission_control_input_label.tscn"
const HUNTER := "res://minigames/duck_hunt/components/hunter_player/hunter_player.tscn"
const BURN := "res://minigames/burn_recycle/components/player/burn_recycle_player.tscn"
const CONTROLS := "GcMinigameControls"
const PLAYER_ACTIONS := ["up", "down", "left", "right", "left_shoulder", "right_shoulder", "action_1", "action_2"]
const BUTTON_WORDS := "\\b(LB|RB|LT|RT|START|SELECT|BACK)\\b|PRESS [ABXY]\\b"

var fails := 0
var out: FileAccess
var _loader
var api
var sw

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/gcs_selftest/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _raw(device: int, axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	_loader = loader
	say("mod_ready, mods: %s" % str(loader.mod_list()))
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	api = _loader.registry("gamecube_support").get("api")
	ok("mod loaded and registered", api != null)
	if api == null:
		finish(); return
	sw = api.swapper
	var style0: String = api.config["style"]
	var art0: String = api.config["art"]
	var layout0: String = api.config["button_layout"]
	api.set_layout("nintendo", false)

	say("step: takeover")
	ok("every slot taken over", sw.proxies.size() == api.SLOTS.size(), [sw.proxies.size(), api.SLOTS.size()])
	ok("nothing loaded before takeover", sw.precached.is_empty(), sw.precached)
	ok("no install problems", sw.problems.is_empty(), sw.problems)
	ok("glyph sizes match vanilla", sw.size_mismatches(api.slot_keys()).is_empty(), sw.size_mismatches(api.slot_keys()))
	var counts: Array = api.ARTS.map(func(a): return sw.glyphs.get(a, {}).size())
	ok("every art set loaded", counts == [13, 13, 13, 12], counts)  # classic, outline, authentic, letters
	for rel in sw.proxies:
		var path: String = BASE + rel
		var by_path = load(path)
		var uid := ResourceLoader.get_resource_uid(path)
		var by_uid = load(ResourceUID.id_to_text(uid)) if uid != ResourceUID.INVALID_ID else null
		ok("load() returns proxy: " + rel, by_path == sw.proxies[rel] and (uid == ResourceUID.INVALID_ID or by_uid == sw.proxies[rel]), "uid " + ("none" if uid == ResourceUID.INVALID_ID else ResourceUID.id_to_text(uid)))
	ok("cache still ours", sw.lost_paths().is_empty(), sw.lost_paths())

	say("step: style switching")
	var keys: Dictionary = api.slot_keys()
	var south = sw.proxies["controller_button_south.png"]
	var changes := [0]
	south.changed.connect(func(): changes[0] += 1)
	api.set_art("classic", false)
	api.set_style("gamecube", false)
	ok("gamecube: every slot shows its glyph", sw.proxies.keys().all(func(r): return sw.proxies[r].atlas == sw.glyphs["classic"].get(keys[r])))
	ok("proxy emitted changed", changes[0] > 0, changes[0])
	ok("proxy keeps vanilla size", Vector2i(south.get_size()) == Vector2i(32, 32), south.get_size())
	api.set_art("letters", false)
	ok("letters art swaps images", south.atlas == sw.glyphs["letters"]["A"])
	ok("letters keeps vanilla stick", sw.proxies["controller_analog_alt.png"].atlas == sw.vanilla["controller_analog_alt.png"])
	api.set_art("authentic", false)
	ok("authentic art swaps images", south.atlas == sw.glyphs["authentic"]["A"])
	api.set_art("outline", false)
	ok("outline art swaps images", south.atlas == sw.glyphs["outline"]["A"])
	api.set_style("xbox", false)
	ok("xbox: every slot back to vanilla", sw.proxies.keys().all(func(r): return sw.proxies[r].atlas == sw.vanilla[r]))
	api.set_art("classic", false)

	say("step: button layout")
	var east = sw.proxies["controller_button_east.png"]
	var west = sw.proxies["controller_button_west.png"]
	api.set_style("gamecube", false)
	ok("nintendo: east shows B, west shows X", east.atlas == sw.glyphs["classic"]["B"] and west.atlas == sw.glyphs["classic"]["X"])
	api.set_layout("positional", false)
	ok("positional: east shows X, west shows B", east.atlas == sw.glyphs["classic"]["X"] and west.atlas == sw.glyphs["classic"]["B"])
	api.set_layout("nintendo", false)
	ok("bad layout rejected", not api.set_layout("sideways", false) and api.config["button_layout"] == "nintendo")
	api.set_style("xbox", false)

	say("step: intermission controls page")
	var inter = load(INTERMISSION).instantiate()
	var mapping_node: Node = null
	for n in inter.find_children("*", "Node", true, false):
		var s = n.get_script()
		if s != null and str(s.resource_path).ends_with("input_icon_mapping.gd"):
			mapping_node = n
			break
	ok("InputIconMapping found", mapping_node != null)
	if mapping_node != null:
		var proxies: Array = sw.proxies.values()
		var mapped: Array = mapping_node.mapping.values()
		var ours := mapped.filter(func(t): return t in proxies).size()
		ok("controller icons in mapping are proxies", ours >= 8, "%d of %d mapping entries" % [ours, mapped.size()])
		var vanilla_controller := mapped.filter(func(t): return t != null and not (t in proxies) and str(t.resource_path).begins_with(BASE + "controller_button"))
		ok("no face button escaped the takeover", vanilla_controller.is_empty(), vanilla_controller.map(func(t): return t.resource_path))
	var manager: Node = null
	for n in [inter] + inter.find_children("*", "Node", true, false):
		var s = n.get_script()
		if s != null and str(s.resource_path).ends_with("intermission_manager.gd"):
			manager = n
			break
	ok("IntermissionManager found", manager != null)
	if manager != null:
		var rows := {}
		var names: Array = InputIconMapping.InputAction.keys()
		for m in manager.minigame_icon_resource_array:
			for c in m.controls_data:
				if m.identifier == Globals.MinigameIdentifier.BurnRecycle:
					rows[c.control_text] = Array(c.controller_icons)
				elif m.identifier == Globals.MinigameIdentifier.DuckHunt:
					say("INFO Duck Hunt briefing row %s: controller %s" % [c.control_text, Array(c.controller_icons).map(func(a): return names[a])])
		var face := InputIconMapping.InputAction
		ok("The Filter's briefing lists A alone for Burn and B alone for Recycle", rows.get("LOC_CONTROL_BURN") == [face.ControllerFaceSouth] and rows.get("LOC_CONTROL_RECYCLE") == [face.ControllerFaceEast], rows)
	_audit_text(inter)
	inter.free()

	say("step: live control label")
	var dev0 = GameManager.current_input_device
	GameManager.current_input_device = GameManager.InputDevice.Controller
	var lbl = load(LABEL).instantiate()
	get_tree().root.add_child(lbl)
	await frames(1)
	await lbl.set_data([], [load(BASE + "controller_button_south.png"), load(BASE + "controller_right_shoulder.png")], "Test", "")
	var rects: Array = lbl.controller_texture_rects
	ok("label built 2 controller icons", rects.size() == 2, rects.size())
	if rects.size() == 2:
		ok("label uses proxies", rects[0].texture == south and rects[1].texture == sw.proxies["controller_right_shoulder.png"])
		ok("label icons visible at 16x16", rects[0].visible and rects[0].custom_minimum_size == Vector2(16, 16), rects[0].custom_minimum_size)
		api.set_style("gamecube", false)
		await frames(1)
		ok("live label flips to GameCube A and Z", rects[0].texture.atlas == sw.glyphs["classic"]["A"] and rects[1].texture.atlas == sw.glyphs["classic"]["Z"])
		api.set_style("xbox", false)
		await frames(1)
		ok("live label flips back to vanilla", rects[0].texture.atlas == sw.vanilla["controller_button_south.png"])
	lbl.queue_free()

	say("step: briefing glyphs")
	var burn: Node = await _briefing_row("LOC_CONTROL_BURN", "controller_button_south.png")
	var recycle: Node = await _briefing_row("LOC_CONTROL_RECYCLE", "controller_button_east.png")
	var shoot: Node = await _briefing_row("LOC_CONTROL_SHOOT", "controller_right_trigger.png")
	var p: Dictionary = sw.proxies
	ok("every briefing row gets the helper", [burn, recycle, shoot].all(func(r): return r.get_node_or_null("GcBriefingGlyphs") != null))
	api.set_style("gamecube", false)
	await frames(2)
	ok("GameCube: Burn shows A then X", _shown(burn) == [p["controller_button_south.png"], p["controller_button_west.png"]], _shown(burn))
	ok("GameCube: Recycle shows B then Y", _shown(recycle) == [p["controller_button_east.png"], p["controller_button_north.png"]], _shown(recycle))
	ok("GameCube: another row gets nothing", _shown(shoot) == [p["controller_right_trigger.png"]], _shown(shoot))
	var x_rect: Array = burn.get_children().filter(func(c): return c is TextureRect and c.texture == p["controller_button_west.png"])
	ok("X is sized as the row's A", x_rect.size() == 1 and x_rect[0].custom_minimum_size == burn.controller_texture_rects[0].custom_minimum_size, x_rect.map(func(c): return c.custom_minimum_size))
	ok("X sits before the row's text", x_rect.size() == 1 and x_rect[0].get_index() < burn.icon_label.get_index())
	var slash: Array = burn.get_children().filter(func(c): return c is Label and c != burn.icon_label)
	ok("a visible / sits between A and X", slash.size() == 1 and slash[0].text == "/" and slash[0].visible and x_rect.size() == 1 and slash[0].get_index() == x_rect[0].get_index() - 1 and slash[0].get_index() > burn.controller_texture_rects[0].get_index(), slash.map(func(c): return [c.text, c.visible, c.get_index()]))
	api.set_layout("positional", false)
	await frames(2)
	ok("positional: Burn shows A alone", _shown(burn) == [p["controller_button_south.png"]], _shown(burn))
	api.set_layout("nintendo", false)
	burn.fake_input_device_change(GameManager.InputDevice.Keyboard)
	await frames(2)
	ok("keyboard: X hides with the row's pad glyphs", _shown(burn).is_empty(), _shown(burn))
	burn.fake_input_device_change(GameManager.InputDevice.Controller)
	api.set_style("xbox", false)
	await frames(2)
	ok("xbox: Burn shows A alone", _shown(burn) == [p["controller_button_south.png"]], _shown(burn))
	ok("xbox: the / hides too", slash.size() == 1 and not slash[0].visible)
	for r in [burn, recycle, shoot]:
		r.queue_free()
	GameManager.current_input_device = dev0

	say("step: duck hunt look-speed prompt")
	var hunter = load(HUNTER).instantiate()
	var wide := [sw.proxies["hires/controller_left_shoulder_button_wide_2x.png"], sw.proxies["hires/controller_right_shoulder_button_wide_2x.png"]]
	var users: Array = hunter.find_children("*", "TextureRect", true, false).filter(func(r): return r.texture in sw.proxies.values())
	ok("hunter prompt uses both wide proxies", wide.all(func(w): return users.any(func(r): return r.texture == w)), users.map(func(r): return r.name))
	ok("no proxy drawn with tile stretch", users.all(func(r): return r.stretch_mode != TextureRect.STRETCH_TILE))
	hunter.free()

	say("step: auto detector")
	var d = api.detector
	ok("detector running", d != null and d.is_inside_tree())
	if d != null:
		var clock0: Callable = d.clock
		d.gamecube = false
		d._pending = null
		d._last_switch = -1 << 40
		d.cooldown_ms = 1000
		api.set_style("auto", false)
		d.feed(true, 10000)
		ok("GameCube press switches at once", d.gamecube and api.is_showing_gamecube())
		ok("auto shows GameCube glyphs", south.atlas == sw.glyphs["classic"]["A"])
		d.feed(false, 10400)
		ok("other pad inside cooldown waits", d.gamecube)
		d.flush(10999)
		ok("still waiting at 999 ms", d.gamecube)
		d.flush(11000)
		ok("switches when cooldown ends", not d.gamecube and south.atlas == sw.vanilla["controller_button_south.png"])
		d.feed(true, 11300)
		d.feed(false, 11600)
		d.flush(12100)
		ok("newest pending press wins", not d.gamecube)
		api.set_style("xbox", false)
		d.feed(true, 20000)
		ok("manual style ignores presses", d.gamecube and not api.is_showing_gamecube())
		var before: bool = d.gamecube
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = true
		Input.parse_input_event(key)
		await frames(2)
		key.pressed = false
		Input.parse_input_event(key)
		await frames(2)
		ok("keyboard input leaves the pad type alone", d.gamecube == before)
		d.clock = clock0
		say("INFO connected pads: %s" % str(Input.get_connected_joypads().map(func(x): return d.describe(x))))

	say("step: gc input")
	var gi = api.gc_input
	ok("gc input running", gi != null and gi.is_inside_tree())
	if gi != null:
		var G = gi.get_script()
		var guid := "030096ea790000004618000000000000"
		var swapped: String = G.remap_line(guid, true)
		var plain: String = G.remap_line(guid, false)
		ok("remap line swaps B and X only", swapped.begins_with(guid + ",") and swapped.contains(",a:b0,b:b2,x:b1,y:b3,") and swapped.ends_with(",platform:Windows"), swapped)
		ok("identity line undoes it", plain.contains(",a:b0,b:b1,x:b2,y:b3,"), plain)
		ok("remap keeps LB, RB and half-axis triggers", swapped.contains("leftshoulder:b9") and swapped.contains("rightshoulder:b10") and swapped.contains("+lefttrigger:+a4") and swapped.contains("+righttrigger:+a5"))
		var clone := {"vendor_id": "121", "product_id": "6214"}
		ok("DInput clone handled", G.is_dinput_adapter(clone, guid))
		ok("Mayflash 1843 handled", G.is_dinput_adapter({"vendor_id": "121", "product_id": "6211"}, "03000000790000004318000000000000"))
		ok("HIDAPI pad not handled", not G.is_dinput_adapter(clone, "0500ea7b790000004618000000016800"))
		ok("8BitDo not handled", not G.is_dinput_adapter({"vendor_id": "11720", "product_id": "12555"}, "0300fa67c82d00000b31000014017801"))
		ok("vid:pid from info", G.vid_pid(clone) == "0079:1846", G.vid_pid(clone))
		var prof: Dictionary = G.adapter_profile("0079:1846", {})
		ok("clone adapter is positional without LB", prof["face"] == "positional" and not prof["has_lb"], prof)
		ok("positional adapter swaps for nintendo", G.needs_swap(prof, "nintendo"))
		ok("positional adapter left alone for positional", not G.needs_swap(prof, "positional"))
		# Godot 4.5.2's DB maps the Mayflash ids by label (b:b2,x:b0).
		var mf: Dictionary = G.adapter_profile("0079:1844", {})
		ok("Mayflash 1844 arrives nintendo-style without LB", mf["face"] == "nintendo" and not mf["has_lb"], mf)
		var mf3: Dictionary = G.adapter_profile("0079:1843", {})
		ok("Mayflash 1843 arrives nintendo-style, LB still synthesized", mf3["face"] == "nintendo" and not mf3["has_lb"], mf3)
		ok("nintendo adapter not swapped for nintendo", not G.needs_swap(mf, "nintendo"))
		ok("nintendo adapter swapped for positional", G.needs_swap(mf, "positional"))
		var over: Dictionary = G.adapter_profile("0079:1846", {"0079:1846": {"face": "nintendo", "has_lb": true, "junk": 1}})
		ok("override applies and ignores unknown keys", over["face"] == "nintendo" and over["has_lb"] and not over.has("junk"), over)
		ok("bad override type ignored", G.adapter_profile("0079:1846", {"0079:1846": {"has_lb": "yes"}})["has_lb"] == false)
		var full: Vector2 = G.scale_stick(Vector2(0.75, 0.0), Vector2(0.75, 0.75))
		ok("0.75 stick reaches full", is_equal_approx(full.x, 1.0), full)
		var diag: Vector2 = G.scale_stick(Vector2(0.6, 0.6), Vector2(0.75, 0.75))
		ok("diagonal stays inside the unit circle", diag.length() <= 1.0001 and diag.x > 0.7, diag)
		var rest: Vector2 = G.scale_stick(Vector2(-0.047, 0.03), Vector2(0.75, 0.75))
		ok("resting noise stays under the 0.2 deadzone", absf(rest.x) < 0.2 and absf(rest.y) < 0.2, rest)
		ok("trigger rest reads 0", G.scale_trigger(0.062, 0.07, 0.9) == 0.0)
		ok("trigger top reads 1", is_equal_approx(G.scale_trigger(0.9, 0.07, 0.9), 1.0))
		ok("auto range widens", is_equal_approx(G.widen(0.75, -0.8), 0.8))
		ok("auto range never narrows", is_equal_approx(G.widen(0.8, 0.5), 0.8))
		ok("auto range caps at 1", G.widen(0.9, 1.3) == 1.0)
		var dzs := [0.5, 0.2]
		ok("curve keeps deadzones as fixed points", G.curve(0.5, 0.0, 0.75, dzs) == 0.5 and G.curve(0.2, 0.0, 0.75, dzs) == 0.2 and G.curve(-0.5, 0.0, 0.75, dzs) == -0.5)
		ok("curve reaches full at the range", G.curve(0.75, 0.0, 0.75, dzs) == 1.0 and G.curve(-0.9, 0.0, 0.75, dzs) == -1.0)
		# Including ends a hand-edited config allows: stick_range down to 0.3,
		# trigger_rest up to 0.5.
		var disagree := []
		for i in 101:
			var rv := i / 100.0
			for lo in [0.0, 0.07, 0.25, 0.5]:
				for hi in [0.3, 0.4, 0.75, 0.9]:
					if hi <= lo:
						continue
					for dz in dzs:
						var cv: float = G.curve(rv, lo, hi, dzs)
						if (absf(cv) >= dz) != (rv >= dz) or (absf(float(PackedFloat32Array([cv])[0])) >= dz) != (rv >= dz):
							disagree.append([rv, lo, hi, dz])
		ok("curve is past a deadzone exactly when the raw value is", disagree.is_empty(), disagree.slice(0, 4))
		ok("trigger curve: rest reads 0, deadzone kept", G.scale_trigger(0.07, 0.07, 0.9, dzs) == 0.0 and G.scale_trigger(0.2, 0.07, 0.9, dzs) == 0.2)
		var edge: Vector2 = G.scale_stick(Vector2(0.52, 0.74), Vector2(0.75, 0.75), [0.5], [0.5])
		ok("circle limit doesn't pull an axis under its deadzone", edge.x >= 0.5 and edge.y > 0.8, edge)
		say("INFO live deadzones: down %s, right %s, L trigger %s" % [gi.deadzones(1, 1.0), gi.deadzones(0, 1.0), gi.deadzones(4, 1.0)])
		ok("live deadzones read", 0.5 in gi.deadzones(1, 1.0), gi.deadzones(1, 1.0))
		ok("L click presses at threshold", G.l_click_step(false, 0.86, 0.85) and not G.l_click_step(false, 0.8, 0.85))
		ok("L click holds until well released", G.l_click_step(true, 0.8, 0.85) and not G.l_click_step(true, 0.74, 0.85))
		var dup16 := []
		for i in 16:
			dup16.append({"name": "Nintendo GameCube Controller", "guid": "x"})
		ok("16 HIDAPI pads flagged", not G.duplicate_problem(dup16, false).is_empty())
		ok("16 pads flagged even with the fix set", not G.duplicate_problem(dup16, true).is_empty())
		var official := dup16.slice(0, 4)
		ok("4 HIDAPI pads (official adapter) fine", G.duplicate_problem(official, false).is_empty())
		var clean := [{"name": "GameCube Controller Adapter"}, {"name": "GameCube Controller Adapter"}, {"name": "GameCube Controller Adapter"}, {"name": "GameCube Controller Adapter"}, {"name": "XInput Controller"}]
		ok("4 adapter ports + 8BitDo fine", G.duplicate_problem(clean, true).is_empty())
		say("INFO duplicate check here: '%s'" % gi.current_problem())

		# The live loop, on a fake device: _raw() stands in for SDL's events.
		var fd := 15
		gi.track_pad(fd, guid, "0079:1846")
		_raw(fd, 0, 0.72)
		_raw(fd, 1, 0.03)
		_raw(fd, 4, 0.062)
		_raw(fd, 5, 0.0)
		await frames(10)
		var x := Input.get_joy_axis(fd, 0)
		var want: float = G.scale_stick(Vector2(0.72, 0.03), Vector2(0.75, 0.75), gi.deadzones(0, 0.72), gi.deadzones(1, 0.03)).x
		ok("held stick scaled once, not again every frame", absf(x - want) < 0.01 and want > 0.9, [x, want])
		ok("auto range not widened by our own output", is_equal_approx(gi.pad_state(fd)["range"][0], 0.75), gi.pad_state(fd)["range"])
		ok("released trigger reads 0", Input.get_joy_axis(fd, 4) == 0.0, Input.get_joy_axis(fd, 4))
		_raw(fd, 0, 0.047)
		await frames(10)
		x = Input.get_joy_axis(fd, 0)
		ok("resting stick doesn't creep", absf(x - 0.047) < 0.005, x)
		_raw(fd, 4, 0.92)
		await frames(3)
		ok("full L squeeze reads 1", Input.get_joy_axis(fd, 4) > 0.99, Input.get_joy_axis(fd, 4))
		ok("full L squeeze presses LB", Input.is_joy_button_pressed(fd, JOY_BUTTON_LEFT_SHOULDER))
		_raw(fd, 4, 0.95)  # scales to 1.0 again: must still overwrite the raw value
		await frames(3)
		ok("trigger pinned at full stays 1", Input.get_joy_axis(fd, 4) == 1.0, Input.get_joy_axis(fd, 4))
		_raw(fd, 4, 0.062)
		await frames(3)
		ok("L release lets go of LB", not Input.is_joy_button_pressed(fd, JOY_BUTTON_LEFT_SHOULDER) and Input.get_joy_axis(fd, 4) == 0.0)
		_raw(fd, 4, 0.035)  # below rest: scales to 0 again
		await frames(3)
		ok("released trigger noise stays 0", Input.get_joy_axis(fd, 4) == 0.0, Input.get_joy_axis(fd, 4))
		gi.untrack_pad(fd)
		for a in 6:
			_raw(fd, a, 0.0)

	say("step: menu directions")
	var M = api.get_script()
	var b0 := InputEventJoypadButton.new()
	b0.button_index = JOY_BUTTON_DPAD_UP
	var b3 := InputEventJoypadButton.new()
	b3.device = 3
	var widened: int = M.widen_to_any_pad([b0, b3, InputEventKey.new()])
	ok("only device-0 pad bindings widen", widened == 1 and b0.device == -1 and b3.device == 3, widened)
	var k := InputEventKey.new()
	var narrowed: int = M.narrow_to([b0, b3, k], 3)
	ok("narrowing moves pad bindings only", narrowed == 1 and b0.device == 3 and b3.device == 3 and k.device == 0, narrowed)
	ok("old menus_any_pad: false is off", M.menu_pad_from(false) == "off")
	ok("old menus_any_pad: true is the new default", M.menu_pad_from(true) == "first" and M.menu_pad_from("junk") == "first")
	var DT = api.detector.get_script() if api.detector != null else null
	if DT != null:
		ok("no claim in the first 1.5 s", not DT.claim_allowed(1499, 0, -1 << 40) and DT.claim_allowed(1500, 0, -1 << 40))
		ok("no claim within 1.5 s of any pad connecting", not DT.claim_allowed(10000, 0, 9000) and DT.claim_allowed(10500, 0, 9000))
	if api.config["menu_pad"] == "off":
		say("INFO menu_pad is off in the config, live checks skipped")
	else:
		for action in api.MENU_DIRECTIONS:
			var live := InputMap.action_get_events(action).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)
			var stored: Array = ProjectSettings.get_setting("input/" + action)["events"].filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)
			ok("%s pad bindings take any pad" % action, not live.is_empty() and live.all(func(d): return d == -1), live)
			ok("%s stays so through the game's InputMap reloads" % action, not stored.is_empty() and stored.all(func(d): return d == -1), stored)
		_raw(14, 1, 1.0)
		await frames(1)
		ok("a stick on device 14 presses ui_down", Input.is_action_pressed("ui_down"))
		_raw(14, 1, 0.0)
		await frames(1)
		say("INFO ui_down deadzone %.2f" % InputMap.action_get_deadzone("ui_down"))
		# A slow push across ui_down's deadzone. If SDL's raw value and the
		# calibrated one disagree about it, they take turns pressing ui_down.
		var gi2 = api.gc_input
		if gi2 != null:
			var md := 13
			gi2.track_pad(md, "030096ea790000004618000000000000", "0079:1846")
			_raw(md, 1, 0.0)
			await frames(3)
			# Sampled after the raw event and again after gc_input's injection.
			var presses := 0
			var was_down := false
			for v in [0.40, 0.44, 0.48, 0.51, 0.55, 0.6, 0.7]:
				_raw(md, 1, v)
				for sample in 2:
					var down := Input.is_action_pressed("ui_down")
					if down and not was_down:
						presses += 1
					was_down = down
					if sample == 0:
						await frames(1)
			ok("a slow stick push presses ui_down once", presses == 1, presses)
			_raw(md, 1, 0.0)
			await frames(3)
			gi2.untrack_pad(md)
			_raw(md, 1, 0.0)
		if api.config["menu_pad"] == "first" and api.detector != null:
			await _menu_pad()

	await _minigame_controls()
	await _lobby_drop_out()

	say("step: the adapter hint's folder")
	# Shown only when SDL claims the adapter twice, which headless never sees; the bundle's folder is D157's.
	var hint: String = api._duplicate_hint()
	var where := "mods/machine_party_extended/gamecube_support" if api.has_meta("mpml_dir") else "mods/gamecube_support"
	ok("the hint names this mod's folder (%s)" % where, hint.contains("in the %s folder" % where), hint)

	say("step: console")
	var con = _loader.get_node_or_null("console")
	if con == null:
		say("INFO console not installed, skipped")
	else:
		ok("console bridge attached", api.bridge != null)
		var cfg_path: String = api.CONFIG_PATH
		var cfg_before := FileAccess.get_file_as_string(cfg_path) if FileAccess.file_exists(cfg_path) else ""
		var input: LineEdit = con.get("_input")
		input.text_submitted.emit("gc style gamecube")
		ok("gc style command works", api.config["style"] == "gamecube")
		input.text_submitted.emit("gc layout positional")
		ok("gc layout command works", api.config["button_layout"] == "positional")
		input.text_submitted.emit("mods")
		var log_text: String = con.get("_log").get_parsed_text()
		# The console itself, since a mod hosted in Extended's bundle is not in the loader's list (D157).
		ok("other console commands still work", log_text.contains("console v"), log_text.right(200))
		input.text_submitted.emit("gc pads")
		if not cfg_before.is_empty():
			var f := FileAccess.open(cfg_path, FileAccess.WRITE)
			f.store_string(cfg_before)
			f.close()

	say("step: overtime")
	var ot_id := "overtime" if _loader.has_mod("overtime") else "mp8_support" if _loader.has_mod("mp8_support") else ""
	if not ot_id.is_empty():
		var loader_log := FileAccess.get_file_as_string("user://modloader.log")
		ok("%s overlay mounted" % ot_id, loader_log.contains(ot_id + ": [MOUNTED]"))
		ok("no %s load-order error" % ot_id, not loader_log.contains("LOAD_ORDER"))
	else:
		say("INFO neither overtime nor mp8_support installed, skipped")

	api.set_art(art0, false)
	api.set_style(style0, false)
	api.set_layout(layout0, false)
	finish()

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

func _pads_of(action: String) -> Array:
	return InputMap.action_get_events(action).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)

func _stored_pads_of(action: String) -> Array:
	return ProjectSettings.get_setting("input/" + action)["events"].filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)

func _stick_down(device: int) -> bool:
	_raw(device, 1, 1.0)
	var down := Input.is_action_pressed("ui_down")
	_raw(device, 1, 0.0)
	return down

# MultiplayerInput.set_ui_action_device's loop (multiplayer_input.gd:192-209)
# without its initialize(), which would reset the core actions later steps use.
func _lobby_host(device: int) -> void:
	for action in InputMap.get_actions():
		if not (String(action).begins_with("ui_") or String(action).begins_with("playlist_")):
			break
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				if device == -1:
					InputMap.action_erase_event(action, e)
				else:
					e.device = device

func _menu_pad() -> void:
	say("step: menu pad")
	var reg: Dictionary = _loader.registry("gamecube_support")
	ok("no pad has the menus at start (headless)", api.menu_pad == -1 and reg.get("menu_pad") == -1, [api.menu_pad, reg.get("menu_pad")])
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	await frames(10)
	ok("the main menu hook ran", api._at_main_menu())
	var t0: int = api.detector._started
	api._on_pad_pressed(14, t0 + 1000)
	ok("a press in the start guard doesn't claim", api.menu_pad == -1, api.menu_pad)
	api._on_pad_pressed(14, t0 + 5000)
	ok("the first press after it claims the menus", api.menu_pad == 14 and reg.get("menu_pad") == 14, [api.menu_pad, reg.get("menu_pad")])
	api._on_pad_pressed(13, t0 + 6000)
	ok("a later press from another pad doesn't", api.menu_pad == 14, api.menu_pad)
	for action in ["ui_accept", "ui_down", "playlist_add"]:
		ok("%s follows the menu pad, stored and live" % action, _pads_of(action).all(func(d): return d == 14) and _stored_pads_of(action).all(func(d): return d == 14) and not _pads_of(action).is_empty(), [_pads_of(action), _stored_pads_of(action)])
	ok("the menu pad's stick moves menus, another's doesn't", _stick_down(14) and not _stick_down(13))
	_lobby_host(13)
	ok("precondition: a lobby host pad takes the menus", _pads_of("ui_down").all(func(d): return d == 13), _pads_of("ui_down"))
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	await frames(10)
	ok("back at the main menu the menu pad has them again", _pads_of("ui_down").all(func(d): return d == 14) and _stick_down(14) and not _stick_down(13), _pads_of("ui_down"))
	_lobby_host(-1)
	ok("precondition: a host pad leaving the lobby erases pad bindings", _pads_of("ui_down").is_empty(), _pads_of("ui_down"))
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	await frames(10)
	ok("the main menu puts erased bindings back", _stick_down(14) and _pads_of("ui_down").size() == _stored_pads_of("ui_down").size(), _pads_of("ui_down"))
	api._on_menu_pad_connection(14, false)
	ok("the menu pad disconnecting frees the menus", api.menu_pad == -1 and reg.get("menu_pad") == -1 and _stick_down(13) and _stick_down(14))
	api._on_pad_pressed(13, t0 + 9000)
	ok("the next pad to press takes them", api.menu_pad == 13 and _stick_down(13) and not _stick_down(14), api.menu_pad)
	api._on_menu_pad_connection(13, false)

func _briefing_row(key: String, rel: String) -> Node:
	var row = load(LABEL).instantiate()
	get_tree().root.add_child(row)
	await frames(1)
	await row.set_data([], [sw.proxies[rel]], key, "")
	await frames(2)
	return row

func _shown(row: Node) -> Array:
	return row.get_children().filter(func(c): return c is TextureRect and c.visible).map(func(c): return c.texture)

# Flags translated strings that name pad buttons (INFO only, not failures).
func _audit_text(_inter: Node) -> void:
	var re := RegEx.create_from_string(BUTTON_WORDS)
	var hits := PackedStringArray()
	var checked := 0
	for loc in TranslationServer.get_loaded_locales():
		var t = TranslationServer.get_translation_object(loc)
		if t == null or not t.has_method("get_translated_message_list"):
			continue
		for msg in t.get_translated_message_list():
			checked += 1
			if re.search(str(msg).to_upper()) != null:
				hits.append("%s: %s" % [loc, str(msg).substr(0, 60)])
	say("INFO text audit: %d strings checked, %d name buttons" % [checked, hits.size()])
	for h in hits.slice(0, 30):
		say("INFO   " + h)

# --- lobby drop-out -------------------------------------------------------------

func _press(device: int, button: int) -> void:
	_button(device, button, true)
	await frames(2)
	_button(device, button, false)
	await frames(2)

# PC8: a GameCube pad's B on its name screen drops its player out of the local lobby.
func _lobby_drop_out() -> void:
	say("step: lobby drop-out")
	var D: GDScript = api.lobby_drop_out
	ok("drop-out script loaded", D != null)
	if D == null:
		return
	ok("rule: GameCube B on the name screen drops out", D.drops_out(true, true, true, true))
	ok("rule: not the B that opened the name screen", not D.drops_out(false, true, true, true))
	ok("rule: not another pad's B", not D.drops_out(true, true, false, true))
	ok("rule: B is action_2, under positional action_3", D.b_action("nintendo") == &"action_2" and D.b_action("positional") == &"action_3")
	var det = api.detector
	if det == null:
		return
	var layout0: String = api.config["button_layout"]
	api.set_layout("nintendo", false)
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")
	await frames(30)
	await get_tree().create_timer(1.0).timeout
	var lobby = get_tree().current_scene
	var panels: Array = lobby.local_lobby_player_controls
	ok("one drop-out helper on every panel (%d)" % panels.size(), panels.all(func(p): return p.get_children().filter(func(c): return String(c.name).begins_with(api.DROP_OUT_NAME)).size() == 1))
	var fg := 12
	var fo := 11
	det.type_overrides[fg] = true
	det.type_overrides[fo] = false
	# A pad host in seat 0 runs set_ui_action_device, whose initialize() drops every
	# clone, so the fake pads get theirs after it.
	lobby.join(fo, true)
	await frames(2)
	_make_clones(fo)
	_make_clones(fg)
	lobby.join(fg, true)
	await frames(2)
	panels[0]._on_name_confirmed("PAD")
	panels[1]._on_name_confirmed("GC")
	await frames(3)
	await _press(fg, JOY_BUTTON_B)
	ok("GameCube B in the outfit panel: the name screen, still seated", lobby.player_data.has(1) and panels[1].name_entry_selector.active, lobby.player_data.keys())
	await _press(fg, JOY_BUTTON_B)
	ok("GameCube B on the name screen: dropped out", not lobby.player_data.has(1) and panels[1].assigned_player_id == -1, lobby.player_data.keys())
	await _press(fo, JOY_BUTTON_B)
	await _press(fo, JOY_BUTTON_B)
	ok("another pad's B on the name screen: still seated", lobby.player_data.has(0) and panels[0].name_entry_selector.active, lobby.player_data.keys())
	api.set_layout("positional", false)
	lobby.join(fg, true)
	await frames(3)
	await _press(fg, JOY_BUTTON_B)
	ok("positional: the east button (labelled X) doesn't drop out", lobby.player_data.has(1), lobby.player_data.keys())
	await _press(fg, JOY_BUTTON_X)
	ok("positional: GameCube B (west) drops out", not lobby.player_data.has(1), lobby.player_data.keys())
	api.set_layout("nintendo", false)
	await _press(fo, JOY_BUTTON_START)
	ok("Start still drops any pad out", not lobby.player_data.has(0), lobby.player_data.keys())
	det.type_overrides.erase(fg)
	det.type_overrides.erase(fo)
	_drop_clones(fg)
	_drop_clones(fo)
	api.set_layout(layout0, false)
	PlayerManager.reset()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	await frames(10)

# --- minigame controls ----------------------------------------------------------

func _button(device: int, button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()

# Presses a button, reads each action's strength while it is down, lets go.
func _tap(device: int, button: int, actions: Array) -> Array:
	_button(device, button, true)
	var got := []
	for a in actions:
		got.append(Input.get_action_strength(a))
	_button(device, button, false)
	return got

func _quiet(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)

func _named(device: int) -> Array:
	return PLAYER_ACTIONS.map(func(a): return "%d%s" % [device, a])

# Every event of each action, in order; with_ids also tells the objects apart.
func _snapshot(actions: Array, with_ids: bool) -> Dictionary:
	var s := {}
	for a in actions:
		if not InputMap.has_action(a):
			s[a] = "missing"
			continue
		var evs := PackedStringArray()
		for e in InputMap.action_get_events(a):
			var what: String = e.as_text()
			if e is InputEventJoypadButton:
				what = "button %d" % e.button_index
			elif e is InputEventJoypadMotion:
				what = "axis %d %.2f" % [e.axis, e.axis_value]
			var id: String = ("#%d" % e.get_instance_id()) if with_ids else ""
			evs.append("%s%s device %d %s" % [e.get_class(), id, e.device, what])
		s[a] = evs
	return s

# A with_ids snapshot without the object ids.
func _snapshot_values(snap: Dictionary) -> Dictionary:
	# Ids of RefCounted objects print negative.
	var re := RegEx.create_from_string("#-?\\d+")
	var s := {}
	for a in snap:
		if snap[a] is PackedStringArray:
			var evs := PackedStringArray()
			for line in snap[a]:
				evs.append(re.sub(line, ""))
			s[a] = evs
		else:
			s[a] = snap[a]
	return s

func _snapshot_only(snap: Dictionary, actions: Array) -> Dictionary:
	var s := {}
	for a in actions:
		s[a] = snap.get(a)
	return s

func _same(a: Dictionary, b: Dictionary) -> bool:
	return str(a) == str(b)

# As MultiplayerInput does on connect (multiplayer_input.gd:77-105): the game's
# own function when it has core actions, else the same steps for our actions.
func _make_clones(device: int) -> void:
	if MultiplayerInput.core_actions.has(&"left"):
		MultiplayerInput._create_actions_for_device(device)
		return
	for core in PLAYER_ACTIONS:
		var events: Array = InputMap.action_get_events(core).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		if events.is_empty():
			continue
		var clone := "%d%s" % [device, core]
		InputMap.add_action(clone, InputMap.action_get_deadzone(core))
		for e in events:
			var c = e.duplicate()
			c.device = device
			InputMap.action_add_event(clone, c)

# As MultiplayerInput does on disconnect, limited to this device's clones.
func _drop_clones(device: int) -> void:
	MultiplayerInput.device_actions.erase(device)
	var cores: Array = MultiplayerInput.core_actions.map(func(c): return String(c))
	cores.append_array(PLAYER_ACTIONS)
	var prefix := str(device)
	for a in InputMap.get_actions():
		var s := String(a)
		if s.begins_with(prefix) and s.substr(prefix.length()) in cores:
			InputMap.erase_action(a)

func _spawn(scene: String, label: String, kind: String, pads: Array) -> Node:
	var player: Node = load(scene).instantiate()
	get_tree().root.add_child(player)
	_quiet(player)
	var helper := player.get_node_or_null(CONTROLS)
	var count := player.get_children().filter(func(c): return String(c.name).begins_with(CONTROLS)).size()
	ok("%s: the hook attached one controls helper" % label, helper != null and count == 1, count)
	if helper != null:
		ok("%s: helper kind" % label, helper.kind == kind, helper.kind)
		helper.pads = func(): return pads
	return player

func _prompt_slots(hunter: Node) -> Array:
	var wide := [sw.proxies["hires/controller_left_shoulder_button_wide_2x.png"], sw.proxies["hires/controller_right_shoulder_button_wide_2x.png"]]
	var found := []
	for w in wide:
		for r in hunter.controller_sensitivity_prompt.find_children("*", "TextureRect", true, false):
			if r.texture == w:
				found.append(r)
				break
	return found

# "proxy": both slots draw the shared shoulder proxies; an art name: the D-pad glyphs of that set.
func _prompt_shows(slots: Array, what: String) -> bool:
	if slots.size() != 2:
		return false
	if what == "proxy":
		return slots[0].texture == sw.proxies["hires/controller_left_shoulder_button_wide_2x.png"] and slots[1].texture == sw.proxies["hires/controller_right_shoulder_button_wide_2x.png"]
	var g: Dictionary = sw.glyphs.get(what, {})
	return g.has("Dpad_left_wide") and slots[0].texture == g["Dpad_left_wide"] and slots[1].texture == g["Dpad_right_wide"]

func _prompt_now(slots: Array) -> Array:
	return slots.map(func(r): return r.texture.resource_path if r.texture.resource_path != "" else str(r.texture))

func _minigame_controls() -> void:
	say("step: minigame controls")
	var MC = api.minigame_controls
	ok("minigame controls compiled", MC != null)
	if MC == null:
		return
	var D := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]

	# The rule. Couch: the player's own GameCube pad only; online: our own
	# player, for every connected GameCube pad.
	var hunt3 := {}
	for a in ["up", "down", "left", "right"]:
		hunt3["3" + a] = {"erase": D, "keep_for": [], "add": []}
	hunt3["3left_shoulder"] = {"erase": [JOY_BUTTON_LEFT_SHOULDER], "keep_for": [], "add": [[3, JOY_BUTTON_DPAD_LEFT]]}
	hunt3["3right_shoulder"] = {"erase": [JOY_BUTTON_RIGHT_SHOULDER], "keep_for": [], "add": [[3, JOY_BUTTON_DPAD_RIGHT]]}
	var got: Dictionary = MC.plan_edits("duck_hunt", true, false, 3, [3], [5], "nintendo")
	ok("rule: couch hunter on a GameCube pad", got == hunt3, got)
	got = MC.plan_edits("duck_hunt", true, false, 3, [3], [5], "positional")
	ok("rule: couch hunter, positional: the same", got == hunt3, got)
	ok("rule: couch hunter on another pad: nothing", MC.plan_edits("duck_hunt", true, true, 5, [3], [5], "nintendo").is_empty())
	ok("rule: couch hunter bot (900001): nothing", MC.plan_edits("duck_hunt", true, false, 900001, [3], [5], "nintendo").is_empty())
	ok("rule: couch hunter on keyboard (-1): nothing", MC.plan_edits("duck_hunt", true, true, -1, [3], [5], "nintendo").is_empty())
	var burn3 := {"3action_1": {"erase": [], "keep_for": [], "add": [[3, JOY_BUTTON_X]]}, "3action_2": {"erase": [], "keep_for": [], "add": [[3, JOY_BUTTON_Y]]}}
	got = MC.plan_edits("burn_recycle", true, false, 3, [3], [5], "nintendo")
	ok("rule: couch Filter on a GameCube pad, nintendo: X and Y", got == burn3, got)
	ok("rule: couch Filter, positional: nothing", MC.plan_edits("burn_recycle", true, false, 3, [3], [5], "positional").is_empty())
	ok("rule: couch Filter on another pad: nothing", MC.plan_edits("burn_recycle", true, false, 5, [3], [5], "nintendo").is_empty())
	ok("rule: couch Filter bot (900001): nothing", MC.plan_edits("burn_recycle", true, false, 900001, [3], [5], "nintendo").is_empty())
	var hunt_online := {}
	for a in ["up", "down", "left", "right"]:
		hunt_online[a] = {"erase": D, "keep_for": [5, 6], "add": []}
	hunt_online["left_shoulder"] = {"erase": [JOY_BUTTON_LEFT_SHOULDER], "keep_for": [5, 6], "add": [[3, JOY_BUTTON_DPAD_LEFT], [4, JOY_BUTTON_DPAD_LEFT]]}
	hunt_online["right_shoulder"] = {"erase": [JOY_BUTTON_RIGHT_SHOULDER], "keep_for": [5, 6], "add": [[3, JOY_BUTTON_DPAD_RIGHT], [4, JOY_BUTTON_DPAD_RIGHT]]}
	got = MC.plan_edits("duck_hunt", false, true, -1, [3, 4], [5, 6], "nintendo")
	ok("rule: online hunter: aim keeps the D-pad for other pads, GameCube D-pads step", got == hunt_online, got)
	got = MC.plan_edits("duck_hunt", false, true, -1, [3, 4], [5, 6], "positional")
	ok("rule: online hunter, positional: the same", got == hunt_online, got)
	ok("rule: online hunter not ours: nothing", MC.plan_edits("duck_hunt", false, false, -1, [3], [5], "nintendo").is_empty())
	ok("rule: online hunter, no GameCube pad: nothing", MC.plan_edits("duck_hunt", false, true, -1, [], [5], "nintendo").is_empty())
	ok("rule: online bot presence (not ours): nothing", MC.plan_edits("duck_hunt", false, false, 900001, [3], [5], "nintendo").is_empty())
	var burn_online := {"action_1": {"erase": [], "keep_for": [], "add": [[3, JOY_BUTTON_X]]}, "action_2": {"erase": [], "keep_for": [], "add": [[3, JOY_BUTTON_Y]]}}
	got = MC.plan_edits("burn_recycle", false, true, -1, [3], [5], "nintendo")
	ok("rule: online Filter, nintendo: GameCube X and Y", got == burn_online, got)
	ok("rule: online Filter, positional: nothing", MC.plan_edits("burn_recycle", false, true, -1, [3], [5], "positional").is_empty())
	ok("rule: online Filter not ours: nothing", MC.plan_edits("burn_recycle", false, false, -1, [3], [5], "nintendo").is_empty())
	ok("rule: online Filter, no GameCube pad: nothing", MC.plan_edits("burn_recycle", false, true, -1, [], [5], "nintendo").is_empty())
	ok("rule: unknown minigame: nothing", MC.plan_edits("forklift", true, true, 3, [3], [5], "nintendo").is_empty() and MC.plan_edits("forklift", false, true, -1, [3], [5], "nintendo").is_empty())
	var menu := {"action_3": {"erase": [JOY_BUTTON_X], "keep_for": [5, 6], "add": [[3, JOY_BUTTON_B], [4, JOY_BUTTON_B]]}}
	got = MC.plan_edits("main_menu", false, false, -1, [3, 4], [5, 6], "nintendo")
	ok("rule: main menu, nintendo: GameCube B backs out, other pads keep X", got == menu, got)
	got = MC.plan_edits("main_menu", true, true, 3, [3, 4], [5, 6], "nintendo")
	ok("rule: main menu ignores couch, seat and pad", got == menu, got)
	ok("rule: main menu, positional: nothing", MC.plan_edits("main_menu", false, false, -1, [3], [5], "positional").is_empty())
	ok("rule: main menu, no GameCube pad: nothing", MC.plan_edits("main_menu", false, false, -1, [], [5], "nintendo").is_empty())

	var dump := PackedStringArray()
	for a in ["up", "action_1", "left_shoulder"]:
		dump.append("%s %s" % [a, str(_snapshot([a], false)[a])])
	say("INFO global events: " + "; ".join(dump))
	say("INFO MultiplayerInput: %d core actions, device_actions %s, local_game %s" % [MultiplayerInput.core_actions.size(), str(MultiplayerInput.device_actions.keys()), str(GameManager.local_game)])

	var det = api.detector
	ok("detector running for the live checks", det != null)
	if det == null:
		return
	var layout0: String = api.config["button_layout"]
	var local0: bool = GameManager.local_game
	api.set_layout("nintendo", false)
	var fg := 12
	var fo := 11
	det.type_overrides[fg] = false
	det.type_overrides[fo] = false

	# Couch, on fake pads with per-device clones.
	say("step: minigame controls, couch hunter")
	GameManager.local_game = true
	_make_clones(fg)
	_make_clones(fo)
	say("INFO clones: %s" % str(_snapshot(["%dleft" % fg, "%dleft_shoulder" % fg], false)))
	var g_left := "%dleft" % fg
	var g_right := "%dright" % fg
	var g_up := "%dup" % fg
	var g_down := "%ddown" % fg
	var g_ls := "%dleft_shoulder" % fg
	var g_rs := "%dright_shoulder" % fg
	var snap_g := _snapshot(_named(fg), true)
	var snap_o := _snapshot(_named(fo), true)
	var pres := PlayerPresence.new()
	pres.device_id = fg
	var hunter := _spawn(HUNTER, "hunter", "duck_hunt", [fg, fo])
	hunter.player_presence = pres
	var slots := _prompt_slots(hunter)
	ok("prompt: both shoulder slots found", slots.size() == 2, slots.size())
	await frames(2)
	ok("couch: a pad that isn't GameCube left alone", _same(_snapshot(_named(fg), true), snap_g))
	ok("prompt: not GameCube, the shoulder glyphs stay", _prompt_shows(slots, "proxy"), _prompt_now(slots))
	_button(fg, JOY_BUTTON_DPAD_LEFT, true)
	ok("couch: D-pad held before the edit presses left", Input.is_action_pressed(g_left))
	det.type_overrides[fg] = true
	await frames(2)
	_button(fg, JOY_BUTTON_DPAD_LEFT, false)
	ok("couch: D-pad held at edit time doesn't stick", not Input.is_action_pressed(g_left) and Input.get_action_strength(g_left) == 0.0, Input.get_action_strength(g_left))
	ok("prompt: a GameCube hunter's prompt shows the D-pad", _prompt_shows(slots, api.config["art"]), _prompt_now(slots))
	var art0: String = api.config["art"]
	api.set_art("outline", false)
	await frames(1)
	ok("prompt: the D-pad follows the art set", _prompt_shows(slots, "outline"), _prompt_now(slots))
	api.set_art(art0, false)
	var style0: String = api.config["style"]
	api.set_style("xbox", false)
	await frames(1)
	ok("prompt: forced xbox style still shows the D-pad", _prompt_shows(slots, art0), _prompt_now(slots))
	api.set_style(style0, false)
	var t: Array = _tap(fg, JOY_BUTTON_DPAD_LEFT, [g_ls, g_left])
	ok("couch: D-pad Left presses left_shoulder, not left", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_DPAD_RIGHT, [g_rs, g_right])
	ok("couch: D-pad Right presses right_shoulder, not right", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_DPAD_UP, [g_up, g_ls, g_rs])
	ok("couch: D-pad Up does nothing", t == [0.0, 0.0, 0.0], t)
	t = _tap(fg, JOY_BUTTON_DPAD_DOWN, [g_down, g_ls, g_rs])
	ok("couch: D-pad Down does nothing", t == [0.0, 0.0, 0.0], t)
	_raw(fg, JOY_AXIS_LEFT_X, -1.0)
	var stick_l := Input.get_action_strength(g_left)
	_raw(fg, JOY_AXIS_LEFT_X, 1.0)
	var stick_r := Input.get_action_strength(g_right)
	_raw(fg, JOY_AXIS_LEFT_X, 0.0)
	ok("couch: the stick still aims", stick_l > 0.5 and stick_r > 0.5, [stick_l, stick_r])
	t = _tap(fg, JOY_BUTTON_LEFT_SHOULDER, [g_ls])
	ok("couch: L click (LB) no longer steps", t[0] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_RIGHT_SHOULDER, [g_rs])
	ok("couch: Z (RB) no longer steps", t[0] == 0.0, t)
	t = _tap(fo, JOY_BUTTON_LEFT_SHOULDER, ["%dleft_shoulder" % fo])
	ok("couch: another pad's LB still steps", t[0] > 0.5, t)
	var applied := _snapshot(_named(fg), true)
	await frames(3)
	ok("couch: applying every frame changes nothing", _same(_snapshot(_named(fg), true), applied))

	_drop_clones(fg)
	_make_clones(fg)
	t = _tap(fg, JOY_BUTTON_DPAD_LEFT, [g_left])
	ok("reconnect: rebuilt clones aim with the D-pad again", t[0] > 0.5, t)
	await frames(1)
	t = _tap(fg, JOY_BUTTON_DPAD_LEFT, [g_ls, g_left])
	ok("reconnect: re-patched within a frame", t[0] > 0.5 and t[1] == 0.0, t)

	det.type_overrides[fo] = true
	pres.device_id = fo
	await frames(2)
	ok("seat change: the old device's clones restored", _same(_snapshot(_named(fg), false), _snapshot_values(snap_g)), _snapshot(_named(fg), false))
	t = _tap(fo, JOY_BUTTON_DPAD_LEFT, ["%dleft_shoulder" % fo, "%dleft" % fo])
	ok("seat change: the new device patched", t[0] > 0.5 and t[1] == 0.0, t)
	det.type_overrides[fo] = false
	await frames(2)
	ok("prompt: the seat's pad no longer GameCube, the shoulder glyphs return", _prompt_shows(slots, "proxy"), _prompt_now(slots))
	det.type_overrides[fo] = true
	pres.device_id = fg
	await frames(2)
	ok("seat change back: the other device restored exactly", _same(_snapshot(_named(fo), true), snap_o))
	hunter.free()
	await frames(1)
	ok("couch hunter freed: InputMap as before", _same(_snapshot(_named(fg), false), _snapshot_values(snap_g)) and _same(_snapshot(_named(fo), true), snap_o), _snapshot(_named(fg), false))
	det.type_overrides[fo] = false

	say("step: minigame controls, couch Filter")
	snap_g = _snapshot(_named(fg), true)
	var a1 := "%daction_1" % fg
	var a2 := "%daction_2" % fg
	var burn := _spawn(BURN, "Filter", "burn_recycle", [fg, fo])
	burn.player_presence = pres
	await frames(2)
	t = _tap(fg, JOY_BUTTON_X, [a1, a2])
	ok("couch Filter, nintendo: X burns", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_Y, [a2, a1])
	ok("couch Filter, nintendo: Y recycles", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_A, [a1])
	ok("couch Filter: A still burns", t[0] > 0.5, t)
	ok("couch Filter: aim and shoulders untouched", _same(_snapshot([g_left, g_ls], true), _snapshot_only(snap_g, [g_left, g_ls])))
	api.set_layout("positional", false)
	await frames(2)
	t = _tap(fg, JOY_BUTTON_X, [a1])
	var ty: Array = _tap(fg, JOY_BUTTON_Y, [a2])
	ok("couch Filter, positional: X and Y unchanged", t[0] == 0.0 and ty[0] == 0.0, [t, ty])
	ok("couch Filter, positional: edit undone exactly", _same(_snapshot(_named(fg), true), snap_g))
	api.set_layout("nintendo", false)
	await frames(2)
	t = _tap(fg, JOY_BUTTON_X, [a1])
	ok("couch Filter, back to nintendo: X burns again", t[0] > 0.5, t)
	burn.free()
	await frames(1)
	ok("couch Filter freed: InputMap as before", _same(_snapshot(_named(fg), true), snap_g))
	_drop_clones(fg)
	_drop_clones(fo)

	# Online: the global actions, for our own player only.
	say("step: minigame controls, online")
	GameManager.local_game = false
	det.type_overrides[fg] = true
	var snap_global := _snapshot(PLAYER_ACTIONS, true)
	t = _tap(fo, JOY_BUTTON_DPAD_LEFT, ["left"])
	ok("online precondition: any pad's D-pad aims left", t[0] > 0.5, t)
	pres.device_id = -1
	pres.network_id = multiplayer.get_unique_id() + 1
	var hunter2 := _spawn(HUNTER, "online hunter", "duck_hunt", [fg, fo])
	hunter2.player_presence = pres
	await frames(2)
	ok("online: someone else's hunter changes nothing", _same(_snapshot(PLAYER_ACTIONS, true), snap_global))
	pres.network_id = multiplayer.get_unique_id()
	await frames(2)
	t = _tap(fo, JOY_BUTTON_DPAD_LEFT, ["left", "left_shoulder"])
	ok("online: another pad's D-pad still aims", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_DPAD_LEFT, ["left_shoulder", "left"])
	ok("online: GameCube D-pad Left steps, doesn't aim", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_DPAD_RIGHT, ["right_shoulder", "right"])
	ok("online: GameCube D-pad Right steps, doesn't aim", t[0] > 0.5 and t[1] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_DPAD_UP, ["up"])
	ok("online: GameCube D-pad Up doesn't aim", t[0] == 0.0, t)
	t = _tap(fg, JOY_BUTTON_LEFT_SHOULDER, ["left_shoulder"])
	ty = _tap(fo, JOY_BUTTON_LEFT_SHOULDER, ["left_shoulder"])
	ok("online: GameCube L click doesn't step, another pad's LB does", t[0] == 0.0 and ty[0] > 0.5, [t, ty])
	say("INFO online global events: " + str(_snapshot(["left", "left_shoulder"], false)))
	var online_applied := _snapshot(PLAYER_ACTIONS, true)
	await frames(3)
	ok("online: applying every frame changes nothing", _same(_snapshot(PLAYER_ACTIONS, true), online_applied))
	pres.network_id = multiplayer.get_unique_id() + 1
	await frames(2)
	ok("online: undone exactly when the hunter isn't ours", _same(_snapshot(PLAYER_ACTIONS, true), snap_global))
	pres.network_id = multiplayer.get_unique_id()
	await frames(2)
	hunter2.free()
	await frames(1)
	ok("online hunter freed: global actions as before", _same(_snapshot(PLAYER_ACTIONS, true), snap_global))
	var burn2 := _spawn(BURN, "online Filter", "burn_recycle", [fg, fo])
	burn2.player_presence = pres
	await frames(2)
	t = _tap(fg, JOY_BUTTON_X, ["action_1"])
	ty = _tap(fg, JOY_BUTTON_Y, ["action_2"])
	ok("online Filter: GameCube X burns and Y recycles", t[0] > 0.5 and ty[0] > 0.5, [t, ty])
	t = _tap(fo, JOY_BUTTON_X, ["action_1"])
	ok("online Filter: another pad's X doesn't burn", t[0] == 0.0, t)
	burn2.free()
	await frames(1)
	ok("online Filter freed: global actions as before", _same(_snapshot(PLAYER_ACTIONS, true), snap_global))

	# The main menu backs out on ui_cancel or action_3 (west, X's spot).
	say("step: minigame controls, main menu")
	if not api._at_main_menu():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		await frames(10)
	var menu_node: Node = api._main_menu
	var menu_helpers: Array = menu_node.get_children().filter(func(c): return String(c.name).begins_with(CONTROLS)) if api._at_main_menu() else []
	ok("main menu: the hook attached one controls helper", menu_helpers.size() == 1 and menu_helpers[0].kind == "main_menu", menu_helpers.size())
	if menu_helpers.size() == 1:
		var mh: Node = menu_helpers[0]
		await frames(2)
		var snap_back := _snapshot(["action_3"], true)
		mh.pads = func(): return [fg, fo]
		await frames(2)
		t = _tap(fg, JOY_BUTTON_B, ["action_3"])
		ty = _tap(fg, JOY_BUTTON_X, ["action_3"])
		ok("main menu: GameCube B backs out, GameCube X doesn't", t[0] > 0.5 and ty[0] == 0.0, [t, ty])
		t = _tap(fo, JOY_BUTTON_X, ["action_3"])
		ty = _tap(fo, JOY_BUTTON_B, ["action_3"])
		ok("main menu: another pad's X still backs out, its B doesn't", t[0] > 0.5 and ty[0] == 0.0, [t, ty])
		var menu_applied := _snapshot(["action_3"], true)
		await frames(3)
		ok("main menu: applying every frame changes nothing", _same(_snapshot(["action_3"], true), menu_applied))
		api.set_layout("positional", false)
		await frames(2)
		ok("main menu, positional: undone exactly", _same(_snapshot(["action_3"], true), snap_back), _snapshot(["action_3"], false))
		api.set_layout("nintendo", false)
		await frames(2)
		t = _tap(fg, JOY_BUTTON_B, ["action_3"])
		ok("main menu, back to nintendo: GameCube B backs out again", t[0] > 0.5, t)
		# After a lobby, MultiplayerInput.initialize() leaves the game's own X on
		# device 8, where it backs out for no pad; other pads get no copy of it.
		api.set_layout("positional", false)
		await frames(2)
		var xe: InputEventJoypadButton = null
		for e in InputMap.action_get_events("action_3"):
			if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X:
				xe = e
		ok("main menu: action_3's pad X found", xe != null)
		if xe != null:
			var dev0 := xe.device
			xe.device = 8
			api.set_layout("nintendo", false)
			await frames(2)
			t = _tap(fo, JOY_BUTTON_X, ["action_3"])
			ty = _tap(fg, JOY_BUTTON_B, ["action_3"])
			ok("main menu, X on device 8: another pad's X still backs out for nobody, GameCube B does", t[0] == 0.0 and ty[0] > 0.5, [t, ty])
			api.set_layout("positional", false)
			await frames(2)
			xe.device = dev0
			api.set_layout("nintendo", false)
			await frames(2)
		# A pad connecting at the menu clones the edited action, as
		# MultiplayerInput._create_actions_for_device does.
		var fc := 13
		var clone := "%daction_3" % fc
		InputMap.add_action(clone, InputMap.action_get_deadzone("action_3"))
		for e in InputMap.action_get_events("action_3"):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				var c = e.duplicate()
				c.device = fc
				InputMap.action_add_event(clone, c)
		menu_node.remove_child(mh)
		ok("main menu left: action_3 as before", _same(_snapshot(["action_3"], true), snap_back), _snapshot(["action_3"], false))
		mh.free()
		ok("precondition: a clone made at the menu has the edit", _snapshot([clone], false)[clone] is PackedStringArray and str(_snapshot([clone], false)[clone]).contains("button %d" % JOY_BUTTON_B), _snapshot([clone], false))
		# Clones reach play only through the couch lobby, whose _ready runs
		# initialize(); it parks the pad events, and the lobby's Leave runs
		# reload_defaults(), which puts them back.
		MultiplayerInput.initialize()
		var after := str(_snapshot(["action_3"], false))
		ok("the lobby's initialize() drops that clone and our edits", not InputMap.has_action(clone) and not after.contains("button %d" % JOY_BUTTON_B) and after.count("button %d" % JOY_BUTTON_X) == 1, [InputMap.has_action(clone), after])
		MultiplayerInput.reload_defaults()
		ok("the lobby's reload_defaults() leaves action_3 as stored", _same(_snapshot_values(_snapshot(["action_3"], true)), _snapshot_values(snap_back)), _snapshot(["action_3"], false))

	pres.free()
	det.type_overrides.erase(fg)
	det.type_overrides.erase(fo)
	GameManager.local_game = local0
	api.set_layout(layout0, false)
