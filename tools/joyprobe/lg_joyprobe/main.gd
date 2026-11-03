extends Node

# Dev-only hardware probe for GameCube Controller Support. Needs a person at
# the pads.
# Run the game normally (windowed) with this in mods/. It waits for a press on
# the GameCube pad, then asks for one button or stick at a time and moves on
# as soon as it sees it (20 s per step at most). Writes
# mods/lg_joyprobe/result.txt (flushed per line) and quits.
#
# Godot 4.5 reads pads through SDL3, and SDL maps the adapter before Godot
# sees it, dropping buttons its mapping leaves out (such as L's full click).
# To see raw buttons, launch with SDL_GAMECONTROLLERCONFIG set to RAW_SDL
# below (see README); the probe also gives every adapter pad an identity
# mapping on Godot's side, so reported numbers are then raw indices. Without
# that variable it reports what the game actually receives (with
# gamecube_support installed: after its button swap, stick calibration and
# L-click-as-LB).
# With JOYPROBE_WATCH=<seconds> set it skips the steps and just logs every
# trigger change and button press on the GameCube pads for that long.
# With JOYPROBE_PLAY=<seconds> the game is not paused and nothing is
# swallowed: the owner plays menus and the lobby while the probe logs pad
# events, action edges, UI focus and the lobby's state (see _play()).

const STEP_TIMEOUT := 20.0
const BUTTON_STEPS := [
	["A", "Press A"], ["B", "Press B"], ["X", "Press X"], ["Y", "Press Y"],
	["Z", "Press Z"], ["START", "Press START"],
	["L_CLICK", "Squeeze L all the way until it clicks"],
	["R_CLICK", "Squeeze R all the way until it clicks
(in game mode nothing arrives: the game never gets R's click)"],
]
const AXIS_STEPS := [
	["L_ANALOG", "Squeeze L slowly to the bottom and hold"],
	["R_ANALOG", "Squeeze R slowly to the bottom and hold"],
	["STICK_RIGHT", "Push the control stick right and hold"],
	["STICK_DOWN", "Push the control stick down and hold"],
	["C_RIGHT", "Push the C-stick right and hold"],
	["C_DOWN", "Push the C-stick down and hold"],
]
const IDENTITY := ",GameCube raw probe,a:b0,b:b1,x:b2,y:b3,back:b4,guide:b5,start:b6,leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10,dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,misc1:b15,paddle1:b16,paddle2:b17,paddle3:b18,paddle4:b19,touchpad:b20,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,platform:Windows"
const GC_VENDOR := 121  # 0x0079
# SDL-side identity mapping for the Mayflash adapter in PC mode (0079:1846).
# Probe results on a 0079:1846 clone: b0 X, b1 A, b2 B, b3 Y, b4 L click,
# b5 R click, b7 Z, b9 START. FIXED_SDL is SDL's built-in line plus
# leftshoulder:b4 so L's full click reaches the game as LB.
const FIXED_SDL := "03000000790000004618000000000000,GameCube Controller Adapter,a:b1,b:b0,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,leftshoulder:b4,lefttrigger:a3,leftx:a0,lefty:a1,rightshoulder:b7,righttrigger:a4,rightx:a5,righty:a2,start:b9,x:b2,y:b3,platform:Windows"
const RAW_SDL := "03000000790000004618000000000000,GameCube raw probe,a:b0,b:b1,x:b2,y:b3,back:b4,guide:b5,start:b6,leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,misc1:b11,paddle1:b12,paddle2:b13,paddle3:b14,paddle4:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,platform:Windows"

var out: FileAccess
var _label: Label
var _t0 := Time.get_ticks_msec()
var _found := {}   # step key -> description
var _loader

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/lg_joyprobe/result.txt"), FileAccess.WRITE)
	out.store_line("%6.2f  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])
	out.flush()

func _mod_ready(loader) -> void:
	_loader = loader
	process_mode = Node.PROCESS_MODE_ALWAYS
	_play_left = OS.get_environment("JOYPROBE_PLAY").to_float()
	_run.call_deferred()

# The main menu sits under the probe and would act on the presses (two
# "back" presses quit the game), so the game is paused, its scene disabled,
# and a node at the end of the tree (first to get _input) swallows every
# joypad event. The probe reads Input state directly, which still updates.
const SWALLOW := "extends Node
func _input(e):
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
"
var _swallow: Node
var _status: Label
var _was_focused := -1
var _seen := {}

# Live feedback: window focus and every button the probe can see.
func _show_status() -> void:
	var focused := get_window().has_focus()
	if int(focused) != _was_focused:
		_was_focused = int(focused)
		say("FOCUS %s" % focused)
	var held := _held_buttons()
	for key in held:
		if not _seen.has(key):
			say("SEEN device %d button %d" % key)
	_seen = held
	if _status != null:
		var txt := "window focused" if focused else "CLICK THE WINDOW FIRST (not focused)"
		if _play_left > 0.0:
			txt = "probe watching, play normally (%d s left)   |   %s" % [ceili(_play_left), txt]
		if not held.is_empty():
			txt += "   |   pressed: " + ", ".join(held.keys().map(func(k): return "pad %d btn %d" % k))
		_status.text = txt

func _process(_delta: float) -> void:
	_show_status()
	if _play_left > 0.0:
		return
	if not _menu_up():
		return
	if not get_tree().paused:
		get_tree().paused = true
	var scene := get_tree().current_scene
	if scene != null and scene.process_mode != Node.PROCESS_MODE_DISABLED:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	if _swallow == null:
		var gs := GDScript.new()
		gs.source_code = SWALLOW
		gs.reload()
		_swallow = Node.new()
		_swallow.set_script(gs)
		_swallow.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child.call_deferred(_swallow)

# Pausing during the splash froze its fade-from-black over everything, which
# looked like a hung black window, so the game is only paused once the main
# menu is up (or after 20 s).
func _menu_up() -> bool:
	var scene := get_tree().current_scene
	return (scene != null and "main_menu" in scene.scene_file_path) or Time.get_ticks_msec() - _t0 > 20000

func _gc_pads() -> Array:
	return Input.get_connected_joypads().filter(func(d): return int(Input.get_joy_info(d).get("vendor_id", "0")) == GC_VENDOR)

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	if _play_left > 0.0:
		await _play()
		_finish()
		return
	var layer := CanvasLayer.new()
	layer.layer = 128  # above any game fade overlay
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08, 0.1, 0.14)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_constant_override("outline_size", 12)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -80
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_constant_override("outline_size", 8)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_status)

	say("env SDL_JOYSTICK_HIDAPI_GAMECUBE=%s" % OS.get_environment("SDL_JOYSTICK_HIDAPI_GAMECUBE"))
	say("env SDL_GAMECONTROLLERCONFIG=%s" % OS.get_environment("SDL_GAMECONTROLLERCONFIG"))
	_dump_pads("at start")
	# Only alongside RAW_SDL; otherwise report what the game receives.
	var raw := "raw probe" in OS.get_environment("SDL_GAMECONTROLLERCONFIG")
	for d in (_gc_pads() if raw else []):
		var line := Input.get_joy_guid(d) + IDENTITY
		Input.add_joy_mapping(line, true)
		say("IDENTITY device %d: %s" % [d, line])
	await get_tree().create_timer(0.3).timeout
	_dump_pads("identity mapped")

	_label.text = "Controller probe (game paused, not frozen)\nWaiting for the main menu to load..."
	while not _menu_up():
		await get_tree().process_frame
	_label.text = "Controller probe (game paused, not frozen)\nClick this window, then press any button\non the GameCube pad to start"
	var start = await _wait_button(90.0)
	if start == null:
		say("no GameCube press seen in 90 s, giving up")
		_finish()
		return
	await _wait_release()

	var watch := OS.get_environment("JOYPROBE_WATCH").to_float()
	if watch > 0.0:
		await _watch(watch)
		_finish()
		return

	var used := {}  # button index -> step key, so a repeat press can't fill two steps
	for s in BUTTON_STEPS:
		_found[s[0]] = "not seen"
		var left := STEP_TIMEOUT
		_label.text = s[1]
		say("STEP " + s[1])
		while left > 0.0:
			var t := Time.get_ticks_msec()
			var hit = await _wait_button(left, true, 0.6)
			left -= (Time.get_ticks_msec() - t) / 1000.0
			if hit == null:
				break
			if used.has(hit[1]):
				say("  ignored b%d, already %s" % [hit[1], used[hit[1]]])
				_label.text = "%s\n(that one was %s)" % [s[1], used[hit[1]]]
				await _wait_release()
				continue
			used[hit[1]] = s[0]
			_found[s[0]] = "b%d (device %d)" % [hit[1], hit[0]]
			_label.text = "Got it"
			break
		say("BUTTON %s = %s" % [s[0], _found[s[0]]])
		await _wait_release()
		await get_tree().create_timer(0.5).timeout
	for s in AXIS_STEPS:
		var hit = await _ask_axis(s[1])
		_found[s[0]] = "not seen"
		if hit != null:
			_found[s[0]] = "a%d %s (device %d, peak %.3f, rest %.3f)" % [hit[1], "+" if hit[2] > hit[3] else "-", hit[0], hit[2], hit[3]]
		say("AXIS %s = %s" % [s[0], _found[s[0]]])
		_label.text = "Let go"
		await get_tree().create_timer(1.5).timeout

	_label.text = "Press A on an 8BitDo pad (or wait)"
	var other = await _wait_button(8.0, false)
	if other != null:
		say("OTHER PAD device %d button %d" % other)
	else:
		say("OTHER PAD none pressed")
	_finish()

# Logs the triggers as the game sees them (and gc_input's raw reading, when
# gamecube_support is installed) plus every button edge.
func _watch(seconds: float) -> void:
	_label.text = "Squeeze R slowly all the way (until it clicks), let go.
Repeat a few times, then the same with L.
(%d s)" % int(seconds)
	say("WATCH %.0f s" % seconds)
	var gi = _gc_input()
	var last := {}
	var held := _held_buttons()
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		for d in _gc_pads():
			for a in [4, 5]:
				var v := Input.get_joy_axis(d, a)
				if absf(v - last.get([d, a], -9.0)) > 0.03:
					last[[d, a]] = v
					var raw := ""
					if gi != null and not gi.pad_state(d).is_empty():
						raw = "  (gc_input raw %.3f)" % gi.pad_state(d)["raw"][a]
					say("TRIGGER device %d %s = %.3f%s" % [d, "L" if a == 4 else "R", v, raw])
		var now := _held_buttons()
		for key in now:
			if not held.has(key):
				say("PRESS device %d b%d" % key)
		for key in held:
			if not now.has(key):
				say("RELEASE device %d b%d" % key)
		held = now

const UI_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]
# Per-device clones made by addons/multiplayer_input ("<device><action>").
const PLAY_ACTIONS := ["up", "down", "left", "right", "action_1", "action_2", "action_3", "local_leave"]
const LOBBY_FIELDS := ["host_is_joystick", "players_ready", "player_data", "can_control", "active"]
const LOBBY_BUTTONS := ["leave_button", "playlist_button", "start_button"]

var _play_left := 0.0
var _last_motion := {}  # [device, axis] -> value of the last motion event

func _gc_input():
	if _loader == null or not _loader.has_method("registry"):
		return null
	var api = _loader.registry("gamecube_support").get("api")
	return api.gc_input if api != null else null

func sayf(msg: String) -> void:
	say("f%d  %s" % [Engine.get_process_frames(), msg])

# Polls once per frame after gc_input's process_frame fix (connected first),
# so states are what game nodes read; _input() logs the raw and injected
# events in between, where a release and re-press within one frame shows.
func _play() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -40
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_status)

	say("PLAY %.0f s: game not paused, no input swallowed" % _play_left)
	say("env SDL_JOYSTICK_HIDAPI_GAMECUBE=%s" % OS.get_environment("SDL_JOYSTICK_HIDAPI_GAMECUBE"))
	say("env SDL_GAMECONTROLLERCONFIG=%s" % OS.get_environment("SDL_GAMECONTROLLERCONFIG"))
	_dump_pads("at start")
	var gi = _gc_input()
	say("gc_input %s" % ("found" if gi != null else "NOT FOUND: gamecube_support missing or failed to load"))
	_describe_gc(gi)
	Input.joy_connection_changed.connect(func(d: int, c: bool): sayf("JOY device %d %s" % [d, "connected" if c else "disconnected"]))
	get_viewport().gui_focus_changed.connect(func(c: Control): sayf("focus changed -> " + _control_text(c)))

	var seen := {}     # key -> what was last logged for it
	var was_down := {} # action -> pressed at the previous poll
	while _play_left > 0.0:
		await get_tree().process_frame
		_play_left -= get_process_delta_time()
		var scene := get_tree().current_scene
		_note(seen, "scene", scene.scene_file_path if scene != null else "none")
		_note(seen, "focus owner", _control_text(get_viewport().gui_get_focus_owner()))
		var gm := get_tree().root.get_node_or_null("GameManager")
		if gm != null:
			_note(seen, "GameManager.current_input_device", str(gm.get("current_input_device")))
		for d in _gc_pads():
			var how := "not handled by gc_input"
			if gi != null and gi.is_handled(d):
				how = "B/X swapped" if gi.is_swapped(d) else "buttons as-is"
			_note(seen, "gc device %d" % d, how)
		_note(seen, "ui joypad devices", _ui_devices())
		if scene != null and "local_lobby" in scene.scene_file_path:
			_note(seen, "lobby", _lobby_text(scene))
		_log_action_edges(was_down)
	_describe_gc(gi)

func _note(seen: Dictionary, key: String, value: String) -> void:
	if not seen.has(key) or seen[key] != value:
		seen[key] = value
		sayf("%s: %s" % [key, value])

func _log_action_edges(was_down: Dictionary) -> void:
	var names: Array = UI_ACTIONS.duplicate()
	var mi := get_tree().root.get_node_or_null("MultiplayerInput")
	var per_device = mi.get("device_actions") if mi != null else null
	if per_device is Dictionary:
		for d in per_device:
			for a in PLAY_ACTIONS:
				if per_device[d].has(a):
					names.append(per_device[d][a])
	for n in names:
		if not InputMap.has_action(n):
			continue
		var down := Input.is_action_pressed(n)
		var was: bool = was_down.get(n, false)
		var jp := Input.is_action_just_pressed(n)
		var jr := Input.is_action_just_released(n)
		if jp and jr:
			sayf("ACTION %s released and pressed again in one frame (now %s)" % [n, "down" if down else "up"])
		elif jp:
			sayf("ACTION %s pressed%s" % [n, " (was already down last frame)" if was else ""])
		elif jr or (was and not down):
			sayf("ACTION %s released" % n)
		elif down and not was:
			sayf("ACTION %s down without a just_pressed" % n)
		was_down[n] = down

func _ui_devices() -> String:
	var parts := PackedStringArray()
	for a in UI_ACTIONS:
		var devs := []
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				devs.append(e.device)
		parts.append("%s %s" % [a, str(devs)])
	return ", ".join(parts)

func _lobby_text(scene: Node) -> String:
	var parts := PackedStringArray()
	for f in LOBBY_FIELDS:
		parts.append("%s=%s" % [f, str(scene.get(f))])
	for b in LOBBY_BUTTONS:
		var n = scene.get(b)
		if n is Control:
			parts.append("%s(visible=%s disabled=%s focus_mode=%d focus_behavior=%s)" % [b, n.is_visible_in_tree(), str(n.get("disabled")), n.focus_mode, str(n.get("focus_behavior_recursive"))])
	return "  ".join(parts)

func _control_text(c: Control) -> String:
	if c == null:
		return "none"
	return "%s (%s, visible=%s)" % [c.get_path(), c.get_class(), c.is_visible_in_tree()]

func _describe_gc(gi) -> void:
	for d in _gc_pads():
		sayf("gc device %d: %s" % [d, gi.describe(d) if gi != null and gi.is_handled(d) else "not handled by gc_input"])

# Which side of the 0.2 and 0.5 deadzones a value is on, by sign.
static func _band(v: float) -> int:
	var b := 0 if absf(v) < 0.2 else (1 if absf(v) < 0.5 else 2)
	return b if v >= 0.0 else -b

func _input(e) -> void:
	if _play_left <= 0.0 or not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	var gc := " gc" if int(Input.get_joy_info(e.device).get("vendor_id", "0")) == GC_VENDOR else ""
	if e is InputEventJoypadButton:
		sayf("EVENT device %d%s b%d %s" % [e.device, gc, e.button_index, "down" if e.pressed else "up"])
	elif e is InputEventJoypadMotion:
		var key := [e.device, e.axis]
		var prev: float = _last_motion.get(key, 0.0)
		_last_motion[key] = e.axis_value
		if _band(prev) != _band(e.axis_value):
			sayf("EVENT device %d%s a%d %.3f (previous event %.3f)" % [e.device, gc, e.axis, e.axis_value, prev])

func _finish() -> void:
	say("SUMMARY")
	for k in _found:
		say("  %-12s %s" % [k, _found[k]])
	say("DONE")
	get_tree().quit()

# Waits for a new button press; returns [device, button] or null. Presses in
# the first `ignore_first` seconds don't count (they're leftovers from the
# previous step).
func _wait_button(timeout: float, gamecube := true, ignore_first := 0.0):
	var held := _held_buttons()
	var left := timeout
	var waited := 0.0
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		waited += get_process_delta_time()
		var now := _held_buttons()
		if waited < ignore_first:
			held = now
			continue
		for key in now:
			if not held.has(key):
				var d: int = key[0]
				var is_gc := int(Input.get_joy_info(d).get("vendor_id", "0")) == GC_VENDOR
				if is_gc == gamecube:
					return key
		held = now
	return null

func _wait_release() -> void:
	var left := 3.0
	while left > 0.0 and not _held_buttons().is_empty():
		await get_tree().process_frame
		left -= get_process_delta_time()
	await get_tree().create_timer(0.3).timeout

func _held_buttons() -> Dictionary:
	var held := {}
	for d in Input.get_connected_joypads():
		for b in 21:
			if Input.is_joy_button_pressed(d, b):
				held[[d, b]] = true
	return held

# Waits until a GameCube axis moves past 0.35 from rest, then follows it
# for a moment to catch its peak. Returns [device, axis, peak, rest] or null.
func _ask_axis(text: String):
	await _wait_still()
	_label.text = text
	say("STEP " + text)
	var rest := {}
	for d in _gc_pads():
		for a in 6:
			rest[[d, a]] = Input.get_joy_axis(d, a)
	var left := STEP_TIMEOUT
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		var best = null
		for key in rest:
			var v := Input.get_joy_axis(key[0], key[1])
			if absf(v - rest[key]) > 0.35 and (best == null or absf(v - rest[key]) > absf(best[2] - rest[[best[0], best[1]]])):
				best = [key[0], key[1], v]
		if best != null:
			var peak: float = best[2]
			var follow := 1.0
			while follow > 0.0:
				await get_tree().process_frame
				follow -= get_process_delta_time()
				var v := Input.get_joy_axis(best[0], best[1])
				if absf(v) > absf(peak):
					peak = v
			return [best[0], best[1], peak, rest[[best[0], best[1]]]]
	return null

# Waits (5 s at most) until every GameCube axis has been near zero and still
# for half a second, so a trigger or stick still held from the last step
# doesn't skew the rest values.
func _wait_still() -> void:
	_label.text = "Let go of everything"
	var last := {}
	var still := 0.0
	var left := 5.0
	while left > 0.0 and still < 0.5:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		left -= dt
		var moved := false
		for d in _gc_pads():
			for a in 6:
				var v := Input.get_joy_axis(d, a)
				# Also wait for sticks to centre and triggers to let go.
				if absf(v - last.get([d, a], v)) > 0.02 or absf(v) > 0.3:
					moved = true
				last[[d, a]] = v
		still = 0.0 if moved else still + dt

func _dump_pads(when: String) -> void:
	var pads := Input.get_connected_joypads()
	say("PADS %s: %d connected" % [when, pads.size()])
	for d in pads:
		say("PAD id=%d name='%s' known=%s guid=%s info=%s" % [d, Input.get_joy_name(d), str(Input.is_joy_known(d)), Input.get_joy_guid(d), str(Input.get_joy_info(d))])
