extends Node

# Auto style: reports whether the last controller to press a button is a
# GameCube pad.
#
# Polls button state each frame instead of using _input: GameManager accepts
# the first joypad event when it flips Keyboard -> Controller, so an _input
# listener under ModLoader would miss it. Polling also skips Offline Bots'
# virtual devices (never connected joypads), phantom adapter ports (never
# press anything) and GameCube sticks/triggers that rest off-centre, since
# only digital buttons count unless use_sticks is set.

signal type_changed(gamecube: bool)
signal button_pressed(device: int, now: int)

const BUTTONS := 15  # JOY_BUTTON_A .. JOY_BUTTON_DPAD_RIGHT
# An adapter port has sent a burst of every axis and five buttons for 1-2
# frames while another pad connected, so no press claims the menus that soon
# after any connect, or after start.
const CLAIM_GUARD_MS := 1500
# Mayflash adapter (PC mode, all known product ids) and the official
# Nintendo adapter (WUP-028), as vendor:product.
const GC_IDS := ["0079:1843", "0079:1844", "0079:1846", "0079:1847", "057e:0337"]
const GC_NAMES := ["gamecube", "game cube", "wup-028"]

var cooldown_ms := 1000
var use_sticks := false
var extra_guids: Array = []
var clock := Callable(Time, "get_ticks_msec")
var type_overrides := {}  # device -> bool, for tests

var gamecube := false     # the type currently reported
var last_device := -1
var _pending = null       # newest type waiting out the cooldown
var _last_switch := -1 << 40
var _kinds := {}          # device -> bool (cache)
var _held := {}           # device -> button bitmask last frame
var _started := 0
var _last_connect := -1 << 40

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started = clock.call()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _process(_delta: float) -> void:
	var now: int = clock.call()
	if get_window().has_focus():
		for d in Input.get_connected_joypads():
			var mask := 0
			for b in BUTTONS:
				if Input.is_joy_button_pressed(d, b):
					mask |= 1 << b
			if use_sticks and Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)).length() > 0.8:
				mask |= 1 << BUTTONS
			var fresh: int = mask & ~int(_held.get(d, 0))
			if fresh:
				last_device = d
				feed(is_gamecube(d), now)
			if fresh & ((1 << BUTTONS) - 1):
				button_pressed.emit(d, now)
			_held[d] = mask
	flush(now)

# Decision core, kept free of Input so the self-test can drive it.
func feed(gc: bool, now: int) -> void:
	if gc == gamecube and _pending == null:
		return
	_pending = gc
	flush(now)

func flush(now: int) -> void:
	if _pending == null or now - _last_switch < cooldown_ms:
		return
	var gc: bool = _pending
	_pending = null
	if gc != gamecube:
		gamecube = gc
		_last_switch = now
		type_changed.emit(gc)

func may_claim(now: int) -> bool:
	return claim_allowed(now, _started, _last_connect)

static func claim_allowed(now: int, started: int, last_connect: int) -> bool:
	return now - started >= CLAIM_GUARD_MS and now - last_connect >= CLAIM_GUARD_MS

func is_gamecube(device: int) -> bool:
	if type_overrides.has(device):
		return type_overrides[device]
	if not _kinds.has(device):
		_kinds[device] = _classify(device)
	return _kinds[device]

func all_connected_gamecube() -> bool:
	var pads := Input.get_connected_joypads()
	return not pads.is_empty() and pads.all(is_gamecube)

func describe(device: int) -> String:
	return "%d '%s' %s %s" % [device, Input.get_joy_name(device), _vid_pid(device), "GameCube" if is_gamecube(device) else "other"]

func _classify(device: int) -> bool:
	var guid := Input.get_joy_guid(device).to_lower()
	if guid in extra_guids.map(func(g): return str(g).to_lower()):
		return true
	if _vid_pid(device) in GC_IDS:
		return true
	var joy_name := Input.get_joy_name(device).to_lower()
	return GC_NAMES.any(func(n): return joy_name.contains(n))

# "vvvv:pppp" from get_joy_info, falling back to the SDL GUID layout
# (bus, crc, vendor LE, 0000, product LE, ...).
func _vid_pid(device: int) -> String:
	var info := Input.get_joy_info(device)
	if info.has("vendor_id") and info.has("product_id"):
		return "%04x:%04x" % [int(info["vendor_id"]), int(info["product_id"])]
	var guid := Input.get_joy_guid(device).to_lower()
	if guid.length() >= 20:
		var v := guid.substr(10, 2) + guid.substr(8, 2)
		var p := guid.substr(18, 2) + guid.substr(16, 2)
		return v + ":" + p
	return "????:????"

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_kinds.erase(device)
	_held.erase(device)
	if connected:
		_last_connect = clock.call()
