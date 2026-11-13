extends Node

# The lobby's shared buttons (Leave, Playlist, Start, BOTS) take A through the menu
# actions, which the game narrows to the host only when seat 0 is a pad: with a
# keyboard or bot host any pad's A pressed Leave. They follow seat 0's pad, else
# GameCube Controller Support's menu pad, else no pad while anyone is seated.

# 8 Player Support's own "no pad" device id: no joypad ever has it.
const NO_PAD := 2147483647
const FOCUS_PATHS := ["focus_neighbor_left", "focus_neighbor_top", "focus_neighbor_right", "focus_neighbor_bottom", "focus_next", "focus_previous"]

var lobby: Node
var menu_pad := Callable()  # -> int, -1 when there is none
var names_script: GDScript  # name_panel.gd: the name screen's back button, for the empty lobby
var registry := Callable()  # id -> the loader's registry for that mod
var _kept := []             # [event, device] as the lobby found them
var _target = null
var _lit := false
var _kept_focus := []

func _ready() -> void:
	for a in menu_actions():
		for e in stored_events(a):
			_kept.append([e, e.device])
	# Before the lobby's own _process, whose handle_join_input reads this frame's local_join.
	process_priority = -1

func _process(_delta: float) -> void:
	_empty_lobby()
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
	_light(false)
	if _target != null and _target != host_pad(lobby.player_data):
		_restore()

# --- LEAVE with nobody past the name screen --------------------------------------
# Every face button joins an unseated pad and the game's walk to LEAVE is seat 0's, on the
# outfit rows only, so a pad could never leave before making a character. Here an unseated pad's
# back lights LEAVE, and back or A while it's lit presses it; its other join presses join and unlight it.

# What an unseated device's press does with nobody past the name screen: "light", "leave", "unlight" or "".
static func empty_press(lit: bool, back: bool, accept: bool, joins: bool) -> String:
	if back:
		return "leave" if lit else "light"
	if lit and accept:
		return "leave"
	if lit and joins:
		return "unlight"
	return ""

# A joined player is in player_data from the join, on the name screen until a name is confirmed;
# the controls' active is false until then (set_active, show_name_entry, _on_name_confirmed).
# Offline Bots' add_bot seats a bot with no player_joined, so its controls are never its own.
static func nobody_past_names(player_data: Dictionary, controls: Array) -> bool:
	for id in player_data.keys():
		if id >= controls.size() or not is_instance_valid(controls[id]) or controls[id].assigned_player_id != id or controls[id].active:
			return false
	return true

func _empty_lobby() -> void:
	var empty: bool = names_script != null and lobby.active and lobby.can_control and not lobby.get("game_started") and nobody_past_names(lobby.player_data, lobby.local_lobby_player_controls)
	if not empty:
		_light(false)
		return
	# The unseated devices with the game's per-pad actions (MultiplayerInput's), and the keyboard.
	# A seated player's back is the name screen's drop-out.
	for dev in MultiplayerInput.device_actions.keys() + [-1]:
		if lobby.is_device_joined(dev):
			continue
		var pad: bool = dev >= 0
		var back: StringName = names_script.back_action(pad, names_script.gamecube_b(registry, dev) if pad else &"")
		var does := empty_press(_lit, _just(dev, back), _just(dev, &"action_1"), _just(dev, &"local_join"))
		if does in ["light", "leave"]:
			_hold_joins()
		match does:
			"light":
				_light(true)
			"leave":
				_light(false)
				lobby.leave_button.pressed.emit()
				return
			"unlight":
				_light(false)

# The lit LEAVE has the focus, and the ui actions may follow a seated pad (seat 0's): its A on the
# name screen's letters must not press LEAVE. A node's _input runs before the GUI's; Input, which the
# name screen reads, has the press already. A seated keyboard's Enter confirms its name in name_panel's
# _unhandled_input, so it unlights LEAVE instead and goes on to a GUI with nothing focused.
func _input(event: InputEvent) -> void:
	if not _lit or lobby.player_data.is_empty() or not event.is_action_pressed(&"ui_accept"):
		return
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	# A key event's device is 0; the lobby seats the keyboard as -1.
	if not lobby.is_device_joined(event.device if pad else -1):
		return
	if pad:
		get_viewport().set_input_as_handled()
	else:
		_light(false)

# This press joins nobody: the lobby's _process, later this frame, skips handle_join_input while
# can_control is off (Input.action_release can't undo a pad's own press). A seated player's Start or
# name-screen back in that same frame is skipped with it (handle_leave_input, name_panel's _drop_out):
# one frame, and the next press works.
func _hold_joins() -> void:
	if not lobby.can_control:
		return
	lobby.can_control = false
	_resume_joins.call_deferred()

func _resume_joins() -> void:
	if is_instance_valid(lobby):
		lobby.can_control = true

# A pad's copy of a game action (MultiplayerInput's "<device><action>"), the action itself for the
# keyboard; &"" when the InputMap lacks it (its initialize() rebuilds the map and the copies).
static func _action(dev: int, action: StringName) -> StringName:
	var a: StringName = MultiplayerInput.device_actions.get(dev, {}).get(action, &"") if dev >= 0 else action
	return a if a != &"" and InputMap.has_action(a) else &""

static func _just(dev: int, action: StringName) -> bool:
	var a := _action(dev, action)
	return a != &"" and Input.is_action_just_pressed(a)

# Lit is the game's own focused look. Its focus neighbours point at itself meanwhile: the ui
# directions of seat 0's pad, else the menu pad's (or every pad's with nobody seated), and the
# keyboard's reach the GUI, and would walk on to Playlist or Start.
func _light(on: bool) -> void:
	if on == _lit or not is_instance_valid(lobby):
		return
	_lit = on
	var b: Control = lobby.leave_button
	if on:
		_kept_focus = FOCUS_PATHS.map(func(p): return b.get(p))
		for p in FOCUS_PATHS:
			b.set(p, NodePath("."))
		b.grab_focus()
	else:
		for i in FOCUS_PATHS.size():
			b.set(FOCUS_PATHS[i], _kept_focus[i])
		if b.has_focus():
			b.release_focus()

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
