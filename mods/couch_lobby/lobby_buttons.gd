extends Node

# The lobby's shared buttons (Leave, Playlist, Start, BOTS) take A through the menu
# actions, which the game narrows to the host only when seat 0 is a pad: with a
# keyboard or bot host any pad's A pressed Leave. They follow seat 0's pad, else
# GameCube Controller Support's menu pad, else no pad while anyone is seated.

# 8 Player Support's own "no pad" device id: no joypad ever has it.
const NO_PAD := 2147483647

var lobby: Node
var menu_pad := Callable()  # -> int, -1 when there is none
var _kept := []             # [event, device] as the lobby found them
var _target = null

func _ready() -> void:
	for a in menu_actions():
		for e in stored_events(a):
			_kept.append([e, e.device])

func _process(_delta: float) -> void:
	var target = target_device(lobby.player_data, menu_pad.call() if menu_pad.is_valid() else -1)
	if target == null:
		if _target != null:
			_restore()
		return
	if target == _target and _in_place(target):
		return
	_target = target
	set_device(target)

# What the game does on its own (its host pad keeps the menus into the
# minigames, where the pause menu is the host's) is left as it is.
func _exit_tree() -> void:
	if _target != null and _target != host_pad(lobby.player_data):
		_restore()

# Back to the bindings the lobby opened with, once nobody is seated or on leaving.
func _restore() -> void:
	_target = null
	for k in _kept:
		k[0].device = k[1]
	for a in menu_actions():
		_put_back(a)

func _in_place(device: int) -> bool:
	var live := pad_devices(InputMap.action_get_events(&"ui_accept"))
	return live.all(func(d): return d == device) and live.size() == stored_events("ui_accept").size()

static func host_pad(player_data: Dictionary):
	var host = player_data.get(0)
	if host is Dictionary and host.get("is_joystick", false):
		return host["device"]
	return null

# null: an empty lobby, which gets back the bindings it opened with.
static func target_device(player_data: Dictionary, menu_pad: int):
	var host = host_pad(player_data)
	if host != null:
		return host
	if menu_pad >= 0:
		return menu_pad
	return NO_PAD if not player_data.is_empty() else null

static func menu_actions() -> Array:
	return InputMap.get_actions().map(func(a): return String(a)).filter(func(a): return a.begins_with("ui_") or a.begins_with("playlist_"))

static func stored_events(action: String) -> Array:
	return ProjectSettings.get_setting("input/" + action, {}).get("events", []).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)

static func pad_devices(events: Array) -> Array:
	return events.filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)

# The InputMap shares ProjectSettings' event objects; the ones the lobby erased
# when its host pad left are put back.
static func set_device(device: int) -> void:
	for a in menu_actions():
		for e in stored_events(a):
			e.device = device
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				e.device = device
		_put_back(a)

static func _put_back(action: String) -> void:
	for e in stored_events(action):
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)
