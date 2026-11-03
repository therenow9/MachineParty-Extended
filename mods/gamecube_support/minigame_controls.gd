extends Node

# Child of a Duck Hunt hunter or a Burn Recycle (The Filter) player. Both read
# DynamicInput: MultiplayerInput's clones "<device><action>" in a couch game,
# the global actions online. Editing those InputMap events keeps the game's own
# reads and gating, and moves the GameCube D-pad and X/Y onto other actions.
# A GameCube hunter steps look speed with the D-pad only, so L click and Z
# leave the shoulders and their prompt shows the D-pad.
# Also a child of the main menu, whose back reads action_3 (west, X's spot):
# a GameCube pad backs out with B there instead. A pad connecting meanwhile
# clones the edited action, but every way into play reloads the InputMap
# (the local lobby's MultiplayerInput.initialize(), online reload_defaults()).

const DUCK_HUNT := "duck_hunt"
const FILTER := "burn_recycle"
const MAIN_MENU := "main_menu"
const AIM := ["up", "down", "left", "right"]
const DPAD := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
# The look-speed prompt's two slots (shared shoulder proxies) -> our glyph key.
const PROMPT_SLOTS := {
	"hires/controller_left_shoulder_button_wide_2x.png": "Dpad_left_wide",
	"hires/controller_right_shoulder_button_wide_2x.png": "Dpad_right_wide",
}

var kind := ""
var api  # gamecube_support's main.gd: detector, config, swapper
var pads := Callable(Input, "get_connected_joypads")  # replaced by the self-test

var _plan := {}
var _erased := {}  # action -> {"device:button": [event, index in the action]}
var _added := {}   # action -> [event]
var _prompt := {}  # TextureRect -> [its shoulder proxy, glyph key]
var _prompt_searched := false

# action -> {"erase": [button], "keep_for": [device], "add": [[device, button]]}.
# erase: joypad button events with these indices leave the action; keep_for:
# each erased event comes back as a copy for each of these devices; add: new
# button events.
static func plan_edits(minigame: String, local: bool, ours: bool, device: int, gc_devices: Array, other_devices: Array, layout: String) -> Dictionary:
	var plan := {}
	# The main menu reads the global action, so other pads keep X through copies.
	if minigame == MAIN_MENU:
		if layout != "nintendo" or gc_devices.is_empty():
			return plan
		var bs := []
		for g in gc_devices:
			bs.append([g, JOY_BUTTON_B])
		plan["action_3"] = _edit([JOY_BUTTON_X], other_devices, bs)
		return plan
	if local:
		if not device in gc_devices:
			return plan
		var p := str(device)
		if minigame == DUCK_HUNT:
			for a in AIM:
				plan[p + a] = _edit(DPAD, [], [])
			plan[p + "left_shoulder"] = _edit([JOY_BUTTON_LEFT_SHOULDER], [], [[device, JOY_BUTTON_DPAD_LEFT]])
			plan[p + "right_shoulder"] = _edit([JOY_BUTTON_RIGHT_SHOULDER], [], [[device, JOY_BUTTON_DPAD_RIGHT]])
		elif minigame == FILTER and layout == "nintendo":
			plan[p + "action_1"] = _edit([], [], [[device, JOY_BUTTON_X]])
			plan[p + "action_2"] = _edit([], [], [[device, JOY_BUTTON_Y]])
		return plan
	# Online the global actions take every pad, so they change only for our
	# own player, and only while a GameCube pad is connected.
	if not ours or gc_devices.is_empty():
		return plan
	if minigame == DUCK_HUNT:
		var lefts := []
		var rights := []
		for g in gc_devices:
			lefts.append([g, JOY_BUTTON_DPAD_LEFT])
			rights.append([g, JOY_BUTTON_DPAD_RIGHT])
		for a in AIM:
			plan[a] = _edit(DPAD, other_devices, [])
		plan["left_shoulder"] = _edit([JOY_BUTTON_LEFT_SHOULDER], other_devices, lefts)
		plan["right_shoulder"] = _edit([JOY_BUTTON_RIGHT_SHOULDER], other_devices, rights)
	elif minigame == FILTER and layout == "nintendo":
		var xs := []
		var ys := []
		for g in gc_devices:
			xs.append([g, JOY_BUTTON_X])
			ys.append([g, JOY_BUTTON_Y])
		plan["action_1"] = _edit([], [], xs)
		plan["action_2"] = _edit([], [], ys)
	return plan

static func _edit(erase: Array, keep_for: Array, add: Array) -> Dictionary:
	return {"erase": erase.duplicate(), "keep_for": keep_for.duplicate(), "add": add.duplicate(true)}

func _enter_tree() -> void:
	if not get_tree().process_frame.is_connected(_update):
		get_tree().process_frame.connect(_update)

func _exit_tree() -> void:
	if get_tree().process_frame.is_connected(_update):
		get_tree().process_frame.disconnect(_update)
	_undo()
	_plan = {}
	_show_dpad(false)

# On process_frame, before the player's _process reads. Re-applied every frame
# (a no-op once in place): a reconnect rebuilds the device's clones without our
# edits, and the presence, its device and the layout can change under us.
func _update() -> void:
	var plan := current_plan()
	if plan != _plan:
		_undo()
		_plan = plan
	_apply()
	if kind == DUCK_HUNT:
		_show_dpad(not _plan.is_empty())

func current_plan() -> Dictionary:
	if api == null or api.detector == null:
		return {}
	var gc := []
	var other := []
	for d in pads.call():
		if api.detector.is_gamecube(d):
			gc.append(d)
		else:
			other.append(d)
	var layout: String = api.config["button_layout"]
	if kind == MAIN_MENU:
		return plan_edits(kind, false, false, -1, gc, other, layout)
	var player := get_parent()
	var presence = player.get("player_presence") if player != null else null
	if not is_instance_valid(presence):
		return {}
	var local: bool = GameManager.local_game
	var ours: bool = presence.network_id == multiplayer.get_unique_id()
	return plan_edits(kind, local, ours, presence.device_id, gc, other, layout)

func _apply() -> void:
	for action in _plan:
		if not InputMap.has_action(action):
			continue
		var edit: Dictionary = _plan[action]
		if not _added.has(action):
			_added[action] = []
		var mine: Array = _added[action]
		var events: Array = InputMap.action_get_events(action)
		for i in events.size():
			var e = events[i]
			if e is InputEventJoypadButton and e.button_index in edit["erase"] and not mine.has(e):
				_erase(action, e, i)
		if _erased.has(action):
			for r in _erased[action].values():
				# Copies stand in for an any-pad event only: MultiplayerInput.initialize()
				# moves the core actions' pad events to device 8 (Overtime: an unused id).
				if r[0].device != -1:
					continue
				for d in edit["keep_for"]:
					_ensure(action, d, r[0].button_index, r[0])
		for pair in edit["add"]:
			_ensure(action, pair[0], pair[1], null)

func _erase(action: String, e: InputEventJoypadButton, index: int) -> void:
	# Godot releases a pressed action here; the self-test's held D-pad check
	# guards that, since a stranded press would turn the hunter forever.
	InputMap.action_erase_event(action, e)
	if not _erased.has(action):
		_erased[action] = {}
	_erased[action]["%d:%d" % [e.device, e.button_index]] = [e, index]

# Events in the InputMap are shared with ProjectSettings, so they are never
# edited: a changed device goes on a copy.
func _ensure(action: String, device: int, button: int, template: InputEventJoypadButton) -> void:
	if _covers(InputMap.action_get_events(action), device, button):
		return
	var e := InputEventJoypadButton.new()
	if template != null:
		e = template.duplicate() as InputEventJoypadButton
	e.device = device
	e.button_index = button
	InputMap.action_add_event(action, e)
	_added[action].append(e)

# action_add_event skips an event that one on device -1 already covers.
static func _covers(events: Array, device: int, button: int) -> bool:
	for e in events:
		if e is InputEventJoypadButton and e.button_index == button and (e.device == device or e.device == -1):
			return true
	return false

func _undo() -> void:
	for action in _added:
		if not InputMap.has_action(action):
			continue
		for e in _added[action]:
			if InputMap.action_get_events(action).has(e):
				InputMap.action_erase_event(action, e)
	_added.clear()
	for action in _erased:
		if InputMap.has_action(action):
			_restore(action, _erased[action].values())
	_erased.clear()

# Puts the erased events back where they were, so the action reads as before.
func _restore(action: String, records: Array) -> void:
	records.sort_custom(func(a, b): return a[1] < b[1])
	var events: Array = InputMap.action_get_events(action)
	var changed := false
	for r in records:
		var e: InputEventJoypadButton = r[0]
		if not _covers(events, e.device, e.button_index):
			events.insert(mini(r[1], events.size()), e)
			changed = true
	if not changed:
		return
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)

# The prompt's slots draw the shared shoulder proxies, which follow the last
# pad pressed; this hunter's own slots show the D-pad while their pad is a
# GameCube pad, whatever the shared style, since L click and Z do nothing.
func _show_dpad(on: bool) -> void:
	if api == null or api.swapper == null:
		return
	if not _prompt_searched:
		if not on:
			return
		_prompt_searched = true
		_find_prompt()
	var by_key: Dictionary = api.swapper.glyphs.get(api.config["art"], {})
	for r in _prompt:
		if not is_instance_valid(r):
			continue
		var want: Texture2D = _prompt[r][0]
		var glyph = by_key.get(_prompt[r][1])
		if on and glyph is Texture2D:
			want = glyph
		if r.texture != want:
			r.texture = want

func _find_prompt() -> void:
	var player := get_parent()
	var root = player.get("controller_sensitivity_prompt") if player != null else null
	if not (root is Node):
		root = player
	if root == null:
		return
	for r in root.find_children("*", "TextureRect", true, false):
		for rel in PROMPT_SLOTS:
			if r.texture != null and r.texture == api.swapper.proxies.get(rel):
				_prompt[r] = [r.texture, PROMPT_SLOTS[rel]]
