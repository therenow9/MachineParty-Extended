extends Node

# Makes a GameCube adapter in PC (DInput) mode play like a normal pad.
#
# Godot hands its controller-DB line for the adapter to SDL before any mod
# runs, and SDL can't be reconfigured afterwards, so this works on what SDL
# delivers:
# - Face buttons: a clone's DB line is positional (X, right of A, reports as
#   east = the game's back/unready; B as west). A Godot mapping on top of
#   SDL's output (add_joy_mapping with the pad's exact GUID) swaps them for
#   the Nintendo layout. Godot drops it on reconnect, so it is re-applied then.
# - Sticks only reach ~0.75 and triggers rest at ~0.06: corrected values are
#   injected with parse_input_event, which overwrites the axis state and the
#   per-device action strengths the game reads. This runs on the tree's
#   physics_frame and process_frame signals, i.e. after SDL's events land but
#   before any game node reads input. SDL's raw event still updates actions
#   and menu focus first, so the correction keeps every action deadzone as a
#   fixed point (curve()): otherwise the two events take turns pressing and
#   releasing, and one push moves a menu several times.
# - The DB line has no LB, so L's full click never arrives: a full L squeeze
#   on the analog trigger is turned into an LB press instead.
# HIDAPI-driver pads (official adapter, Wii U mode) are left alone: SDL
# calibrates those itself. Duplicate devices can only be fixed before launch
# (SDL_JOYSTICK_HIDAPI_GAMECUBE=0); duplicate_problem() spots them.

const VENDOR := 0x0079
const PRODUCTS := [0x1843, 0x1844, 0x1846, 0x1847]
# vid:pid -> what the adapter's DB line gives the game. Godot 4.5.2's DB maps
# Mayflash 1843/1844 by label (B east), clones 1846/1847 by position (X east).
# 1843's line also has an unverified leftshoulder: the synthesized LB stays,
# as a missing LB would go unnoticed. config adapter_overrides corrects one.
const KNOWN_ADAPTERS := {
	"0079:1843": {"face": "nintendo", "has_lb": false},
	"0079:1844": {"face": "nintendo", "has_lb": false},
	"0079:1846": {"face": "positional", "has_lb": false},
	"0079:1847": {"face": "positional", "has_lb": false},
}
const HIDAPI_GC_NAME := "nintendo gamecube controller"
const MAX_JOYPADS := 16
# Pass-through of SDL's gamepad indices with B/X swapped (or not). Triggers
# use half-axis syntax: a plain lefttrigger:a4 would make Godot rescale the
# 0..1 trigger to 0.5..1.
const MAP_BODY := ",GameCube Controller Adapter,a:b0,b:%s,x:%s,y:b3,back:b4,guide:b5,start:b6,leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10,dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,leftx:a0,lefty:a1,rightx:a2,righty:a3,+lefttrigger:+a4,+righttrigger:+a5,platform:Windows"
const TRIGGER_TOP := 0.9
const L_RELEASE_GAP := 0.1

var layout := "nintendo"
var calibration := "auto"
var stick_range := 0.75
var trigger_rest := 0.07
var l_click := true
var l_click_threshold := 0.85
var overrides := {}

var _pads := {}      # device -> state, see _track()
var _swapped := {}   # guid -> true while our B/X swap is applied
# direction_key() -> sorted deadzones of the actions bound to that axis
# direction. Read in refresh(): deadzones come from the project settings, and
# the per-device clones copy them, so they never change while the game runs.
var _deadzones := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_tree().physics_frame.connect(fix)
	get_tree().process_frame.connect(fix)
	refresh()

func refresh() -> void:
	_deadzones = read_deadzones()
	_pads.clear()
	for d in Input.get_connected_joypads():
		_track(d)
	apply_layout()

func is_handled(device: int) -> bool:
	return _pads.has(device)

# --- pure helpers (self-tested) ------------------------------------------------

static func vid_pid(info: Dictionary) -> String:
	if info.has("vendor_id") and info.has("product_id"):
		return "%04x:%04x" % [int(info["vendor_id"]), int(info["product_id"])]
	return ""

static func is_hidapi(guid: String) -> bool:
	return guid.length() >= 30 and guid.substr(28, 2).to_lower() == "68"

static func is_dinput_adapter(info: Dictionary, guid: String) -> bool:
	return int(info.get("vendor_id", "0")) == VENDOR and int(info.get("product_id", "0")) in PRODUCTS and not is_hidapi(guid)

static func adapter_profile(vidpid: String, adapter_overrides: Dictionary) -> Dictionary:
	var p: Dictionary = KNOWN_ADAPTERS.get(vidpid, {"face": "positional", "has_lb": false}).duplicate()
	var o = adapter_overrides.get(vidpid)
	if o is Dictionary:
		for k in p:
			if o.has(k) and typeof(o[k]) == typeof(p[k]):
				p[k] = o[k]
	return p

static func needs_swap(profile: Dictionary, target_layout: String) -> bool:
	return profile["face"] != target_layout

static func remap_line(guid: String, swap: bool) -> String:
	return guid + (MAP_BODY % (["b2", "b1"] if swap else ["b1", "b2"]))

static func direction_key(axis: int, value: float) -> int:
	return axis * 2 + (0 if value >= 0.0 else 1)

# Piecewise linear through (lo, 0), (d, d) for each deadzone d between lo and
# hi, and (hi, 1), on the magnitude: the result is past a deadzone exactly
# when `v` is. With lo = 0 that is the identity up to the largest deadzone.
static func curve(v: float, lo: float, hi: float, deadzones: Array) -> float:
	var a := absf(v)
	# Plain floats, not Vector2: its 32-bit components would move the knots.
	var xs := [lo]
	var ys := [0.0]
	var sorted := deadzones.duplicate()
	sorted.sort()
	for d in sorted:
		if d > lo and d < hi:
			xs.append(d)
			ys.append(d)
	xs.append(hi)
	ys.append(1.0)
	var out := 1.0
	if a <= lo:
		out = 0.0
	elif a < hi:
		for i in range(1, xs.size()):
			if a <= xs[i]:
				out = ys[i] if a == xs[i] else ys[i - 1] + (a - xs[i - 1]) * (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1])
				break
	# Deadzones at or outside lo..hi (a hand-set stick_range or trigger_rest)
	# have no knot, so the side of each one is enforced here too.
	out = clampf(out, deadzone_floor(a, sorted), deadzone_cap(a, sorted))
	return out if v >= 0.0 else -out

# The largest deadzone `v` is past, or 0.
static func deadzone_floor(v: float, deadzones: Array) -> float:
	var f := 0.0
	for d in deadzones:
		if absf(v) >= d:
			f = maxf(f, d)
	return f

# Just under the smallest deadzone `v` hasn't reached, or 1. The margin
# survives Godot's 32-bit axis storage.
static func deadzone_cap(v: float, deadzones: Array) -> float:
	var c := 1.0
	for d in deadzones:
		if absf(v) < d:
			c = minf(c, d * (1.0 - 1e-6))
	return c

# Calibrated per axis up to `range`, then kept inside the unit circle, but
# never pulled back under a deadzone the raw value is past.
static func scale_stick(raw: Vector2, range: Vector2, dz_x: Array = [], dz_y: Array = []) -> Vector2:
	var v := Vector2(curve(raw.x, 0.0, range.x, dz_x), curve(raw.y, 0.0, range.y, dz_y)).limit_length(1.0)
	return Vector2(signf(raw.x) * maxf(absf(v.x), deadzone_floor(raw.x, dz_x)), signf(raw.y) * maxf(absf(v.y), deadzone_floor(raw.y, dz_y)))

static func scale_trigger(raw: float, rest: float, top: float, deadzones: Array = []) -> float:
	return clampf(curve(raw, rest, maxf(top, rest + 0.01), deadzones), 0.0, 1.0)

static func read_deadzones() -> Dictionary:
	var found := {}
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion and e.axis < 6 and e.axis_value != 0.0:
				var key := direction_key(e.axis, e.axis_value)
				if not found.has(key):
					found[key] = []
				var dz := InputMap.action_get_deadzone(action)
				if not dz in found[key]:
					found[key].append(dz)
	for key in found:
		found[key].sort()
	return found

func deadzones(axis: int, value: float) -> Array:
	return _deadzones.get(direction_key(axis, value), [])

# Auto range: the largest value seen so far, never below the start, at most 1.
static func widen(current: float, raw: float) -> float:
	return minf(maxf(current, absf(raw)), 1.0)

static func l_click_step(was_down: bool, raw: float, threshold: float) -> bool:
	return raw >= threshold if not was_down else raw > threshold - L_RELEASE_GAP

# pads: [{name, guid}]. Returns "" or what is wrong, in English unless lang says otherwise.
static func duplicate_problem(pads: Array, hidapi_disabled: bool, lang := "EN") -> String:
	var hidapi := pads.filter(func(p): return HIDAPI_GC_NAME in str(p.get("name", "")).to_lower())
	if hidapi.size() > 4 and not hidapi_disabled:
		return pick(lang, "the GameCube adapter shows up as %d pads", "GameCube 适配器被识别为 %d 个手柄",
			"GameCube 轉接器被識別為 %d 個手把") % hidapi.size()
	if pads.size() >= MAX_JOYPADS:
		return pick(lang, "%d controllers connected, the most the game can see", "已连接 %d 个控制器，已达游戏可识别的上限",
			"已連接 %d 個控制器，已達遊戲可識別的上限") % pads.size()
	return ""

# The game's language as "EN", "ZHS" or "ZHT": the game sets its loc sheet's codes, and the zh_* forms are
# taken too. Only the toasts follow it (D173); the log and the console stay English.
static func lang_of(raw: String) -> String:
	var value := raw.to_upper().replace("-", "_")
	if value == "ZHT" or value == "ZH_TW" or value == "ZH_HK" or value == "ZH_MO" or value.begins_with("ZH_HANT"):
		return "ZHT"
	if value == "ZHS" or value == "ZH" or value == "ZH_CN" or value == "ZH_SG" or value.begins_with("ZH_HANS"):
		return "ZHS"
	return "EN"

static func pick(lang: String, en: String, zhs: String, zht: String) -> String:
	if lang == "ZHS":
		return zhs
	if lang == "ZHT":
		return zht
	return en

# --- face buttons -------------------------------------------------------------

func apply_layout() -> void:
	var done := {}
	for d in _pads:
		var guid: String = _pads[d]["guid"]
		if done.has(guid):
			continue
		done[guid] = true
		var swap := needs_swap(_pads[d]["profile"], layout)
		# Re-add on every call: Godot forgets the mapping when a pad reconnects.
		if swap or _swapped.has(guid):
			Input.add_joy_mapping(remap_line(guid, swap), true)
		if swap:
			_swapped[guid] = true
		else:
			_swapped.erase(guid)

func is_swapped(device: int) -> bool:
	return _pads.has(device) and _swapped.has(_pads[device]["guid"])

# --- calibration and L click ---------------------------------------------------

func _track(d: int) -> void:
	var info := Input.get_joy_info(d)
	var guid := Input.get_joy_guid(d)
	if is_dinput_adapter(info, guid):
		track_pad(d, guid, vid_pid(info))
	else:
		_pads.erase(d)

# Separate from _track() so the self-test can drive a fake device.
func track_pad(d: int, guid: String, vidpid: String) -> void:
	_pads[d] = {
		"guid": guid,
		"vidpid": vidpid,
		"profile": adapter_profile(vidpid, overrides),
		"range": [stick_range, stick_range, stick_range, stick_range],
		"top": [TRIGGER_TOP, TRIGGER_TOP],
		"raw": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"out": [INF, INF, INF, INF, INF, INF],  # what get_joy_axis read after our last injection
		"lb": false,        # our synthesized LB is down
		"lb_real": false,   # a real LB was seen, so stop synthesizing
	}

func untrack_pad(d: int) -> void:
	_pads.erase(d)

func pad_state(d: int) -> Dictionary:
	return _pads.get(d, {})

func fix() -> void:
	for d in _pads:
		var s: Dictionary = _pads[d]
		var fresh := [false, false, false, false, false, false]
		for a in 6:
			var v := Input.get_joy_axis(d, a)
			if v != s["out"][a]:
				s["raw"][a] = v
				fresh[a] = true
		if fresh.has(true) and calibration != "off":
			_calibrate(d, s, fresh)
		if l_click and not s["profile"]["has_lb"]:
			_l_click(d, s)

# fresh[a]: the axis holds a new raw value, so it must be overwritten even if
# it scales to what we sent last time (e.g. a stick pinned at 1.0).
func _calibrate(d: int, s: Dictionary, fresh: Array) -> void:
	var raw: Array = s["raw"]
	var out := []
	out.resize(6)
	for pair in [0, 2]:
		if calibration == "auto":
			s["range"][pair] = widen(s["range"][pair], raw[pair])
			s["range"][pair + 1] = widen(s["range"][pair + 1], raw[pair + 1])
		var r := Vector2(s["range"][pair], s["range"][pair + 1]) if calibration == "auto" else Vector2(stick_range, stick_range)
		var v := scale_stick(Vector2(raw[pair], raw[pair + 1]), r, deadzones(pair, raw[pair]), deadzones(pair + 1, raw[pair + 1]))
		out[pair] = v.x
		out[pair + 1] = v.y
	for t in 2:
		if calibration == "auto":
			s["top"][t] = widen(s["top"][t], raw[4 + t])
		out[4 + t] = scale_trigger(raw[4 + t], trigger_rest, s["top"][t] if calibration == "auto" else TRIGGER_TOP, deadzones(4 + t, raw[4 + t]))
	var sent := []
	for a in 6:
		if fresh[a] or absf(out[a] - s["out"][a]) > 1e-6:
			var e := InputEventJoypadMotion.new()
			e.device = d
			e.axis = a
			e.axis_value = out[a]
			Input.parse_input_event(e)
			sent.append(a)
	if sent:
		Input.flush_buffered_events()
		# Godot stores axes as 32-bit floats, so remember what it actually holds;
		# comparing with our 64-bit value would take our own output for new input
		# and scale it again every frame.
		for a in sent:
			s["out"][a] = Input.get_joy_axis(d, a)

func _l_click(d: int, s: Dictionary) -> void:
	if s["lb_real"]:
		return
	if not s["lb"] and Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER):
		s["lb_real"] = true  # e.g. an SDL_GAMECONTROLLERCONFIG with leftshoulder
		return
	var down := l_click_step(s["lb"], s["raw"][4], l_click_threshold)
	if down == s["lb"]:
		return
	s["lb"] = down
	var e := InputEventJoypadButton.new()
	e.device = d
	e.button_index = JOY_BUTTON_LEFT_SHOULDER
	e.pressed = down
	e.pressure = 1.0 if down else 0.0
	Input.parse_input_event(e)
	Input.flush_buffered_events()

# --- status ------------------------------------------------------------------

func describe(device: int) -> String:
	if not _pads.has(device):
		return ""
	var s: Dictionary = _pads[device]
	var parts := PackedStringArray()
	parts.append("B/X swapped" if is_swapped(device) else "buttons as-is")
	if calibration != "off":
		parts.append("stick range %.2f/%.2f c %.2f/%.2f" % s["range"])
	if l_click and not s["profile"]["has_lb"]:
		parts.append("real LB found" if s["lb_real"] else "L click = LB")
	return ", ".join(parts)

func current_problem(lang := "EN") -> String:
	var pads := Input.get_connected_joypads().map(func(d): return {"name": Input.get_joy_name(d), "guid": Input.get_joy_guid(d)})
	return duplicate_problem(pads, OS.get_environment("SDL_JOYSTICK_HIDAPI_GAMECUBE") == "0", lang)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_track(device)
		apply_layout()
	else:
		_pads.erase(device)
