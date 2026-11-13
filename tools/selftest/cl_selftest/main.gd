extends Node

# Dev-only headless regression test for couch_lobby (its glasses row, folded in
# from Local Glasses). See README. Works with other mods installed (seat count /
# layout checks adapt).

const VANILLA_GLASSES := ["none", "sunglasses", "reading_glasses"]
# More Cosmetics' ids, which it never renames; its registry publishes them here.
const XC_GLASSES := ["xc_disguise_glasses", "xc_cyclops_glasses", "xc_monocle_glasses", "xc_eyepatch_glasses",
	"xc_tanning_glasses", "xc_scuba_glasses", "xc_3d_glasses", "xc_nightvision_glasses", "xc_snow_glasses"]

var fails := 0
var out: FileAccess
var _loader

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_selftest/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

# A node's transform in its 3D chain, out of tree; written apart from close_ups.gd's on purpose.
func _chain(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

# Out of the face: the head's offset to a glasses mesh, less its part along the head's up (head
# to hat bone). Measured from the glasses so it checks close_ups.gd's use of the body's forward.
func _face_dir(a) -> Vector3:
	var attach: Node3D = a.bone_attachment_glasses
	var up: Vector3 = (a.bone_attachment_hat.global_position - attach.global_position).normalized()
	var inv := attach.global_transform.affine_inverse()
	for mi in attach.find_children("*", "MeshInstance3D", true, false):
		var off: Vector3 = attach.global_basis.orthonormalized() * ((inv * mi.global_transform) * mi.get_aabb().get_center())
		off -= up * off.dot(up)
		if off.length() > 0.001:
			return off.normalized()
	return Vector3.ZERO

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	_loader = loader
	say("mod_ready")
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")
	await frames(30)
	var lobby = get_tree().current_scene
	say("scene: %s, seats: %d, mods: %s" % [lobby.name, lobby.MAX_PLAYERS, str(_loader.mod_list())])
	_registry_layout()
	ok("lobby controls array intact", lobby.local_lobby_player_controls.size() == lobby.MAX_PLAYERS, [lobby.local_lobby_player_controls.size(), lobby.MAX_PLAYERS])
	var c = lobby.local_lobby_player_controls[0]
	var p = c.get_node_or_null("CouchLobbyGlassesPicker")
	ok("picker attached", p != null)
	if p == null:
		finish(); return
	ok("picker on every seat", lobby.local_lobby_player_controls.all(func(x): return x.get_node_or_null("CouchLobbyGlassesPicker") != null))
	ok("row after hat row", p.glasses_row.get_index() == c.hbox_selection_hat.get_index() + 1, [p.glasses_row.get_index(), c.hbox_selection_hat.get_index()])
	ok("icon replaced", p.glasses_picker_element.texture != c.hat_picker_element.texture)
	var names = c.active_elements.map(func(e): return str(c.get_path_to(e)))
	ok("nav order", names.size() == 4 and c.active_elements[1] == p.glasses_picker_element, names)
	ok("hat arrows not duplicated onto glasses", p.glasses_prev.mouse_entered.get_connections().size() == 1, p.glasses_prev.mouse_entered.get_connections().size())

	var xc: bool = _mod_dir("more_cosmetics") != ""
	say("setup: more_cosmetics %s" % ("present" if xc else "absent"))
	var want: Array = VANILLA_GLASSES + (XC_GLASSES if xc else [])
	ok("glasses list for this setup (%d)" % want.size(), p.glasses == want, p.glasses)
	ok("blocking hats for this setup", p.no_glasses_hats == ["maska_helmet", "rubiks_cube"] + (["xc_diving_helmet", "xc_dragonborn_helmet"] if xc else []), p.no_glasses_hats)
	if not xc:
		ok("no more_cosmetics registry entries", _loader.registry("more_cosmetics").is_empty(), _loader.registry("more_cosmetics").keys())
	_merged(p.get_script())
	await _name_tags(lobby)
	await _name_list(lobby)
	await _name_saved_paths(lobby)
	await _name_back(lobby)

	say("step: join + layout")
	lobby.join(-1, false)
	await frames(5)
	ok("join set controls active (vanilla path)", c.visible)
	c._on_name_confirmed("TEST")
	await frames(3)
	ok("row visible after name", p.glasses_row.visible)
	var pos1 = c.position
	await frames(10)
	ok("position stable", c.position == pos1, [pos1, c.position])
	ok("panel not above join banner", c.position.y >= 71, c.position)
	lobby.join(0, true)
	await frames(3)
	var c1 = lobby.local_lobby_player_controls[1]
	c1._on_name_confirmed("PAD")
	await frames(3)
	if lobby.MAX_PLAYERS == 4:
		ok("seat 0 stays at vanilla 71 (banner cap)", c.position.y == 71, c.position)
		ok("seat 1 shifted up one row from vanilla 128", c1.position.y < 128 and c1.position.y >= 71, c1.position)
	else:
		say("seat positions (modded layout): %s %s" % [c.position, c1.position])
	lobby.leave(1)
	await frames(2)
	ok("registry entry dropped when seat empties", not _glasses_by_device().has(0), _glasses_by_device())

	say("step: cycle")
	c.customization_assigner.assign_glasses("none")
	var seen := []
	for i in want.size():
		p.change_glasses(1)
		seen.append(p.get_assigned_glasses())
	ok("cycle through every glasses and back to none", seen == want.slice(1) + ["none"], seen)
	p.change_glasses(-1); ok("cycle back -> %s" % want[-1], p.get_assigned_glasses() == want[-1], p.get_assigned_glasses())

	say("step: simulated click")
	c.customization_assigner.assign_glasses("none")
	var hat_before = str(c.customization_assigner.get_assigned_hat())
	c.active_element = p.glasses_picker_element
	c.mouse_and_keyboard_direction = 1
	p._cooldown = 0.0
	Input.action_press("action_1")
	await frames(1)
	Input.action_release("action_1")
	await frames(2)
	ok("click on glasses arrow changes glasses", p.get_assigned_glasses() == "sunglasses", p.get_assigned_glasses())
	ok("click leaves hat alone", str(c.customization_assigner.get_assigned_hat()) == hat_before, [hat_before, c.customization_assigner.get_assigned_hat()])

	say("step: maska")
	c.active_element = null
	c.customization_assigner.assign_hat("drill_sgt_hat")
	await frames(1)
	c.change_hat(-1)
	await frames(1)
	ok("hat -> maska", str(c.customization_assigner.get_assigned_hat()) == "maska_helmet", c.customization_assigner.get_assigned_hat())
	ok("maska clears glasses", p.get_assigned_glasses() == "none", p.get_assigned_glasses())
	p.change_glasses(1)
	ok("maska blocks glasses", p.get_assigned_glasses() == "none", p.get_assigned_glasses())
	ok("row dimmed while blocked", p.glasses_row.modulate.a < 1.0, p.glasses_row.modulate.a)
	c.change_hat(1)
	await frames(1)
	p.change_glasses(1)
	ok("glasses allowed with next hat", p.get_assigned_glasses() == "sunglasses", [c.customization_assigner.get_assigned_hat(), p.get_assigned_glasses()])

	if xc:
		await _diving_helmet(c, p)

	say("step: ready")
	var pos_default = c.position
	c.set_player_ready(true)
	await frames(2)
	ok("ready hides row", not p.glasses_row.visible)
	c.set_player_ready(false)
	await frames(2)
	ok("unready shows row", p.glasses_row.visible)
	ok("default pos restored", c.position == pos_default, [pos_default, c.position])

	await _close_ups(lobby)

	say("step: presence via local game load")
	await frames(1)
	var bot_dev = null
	if lobby.has_method("add_bot"):
		bot_dev = lobby.add_bot("BotTest", ["", "reading_glasses", "red"])
	lobby.update_player_manager()
	GameManager.local_game = true
	GameManager.local_game_data = lobby.player_data

	await _chisel_gauntlet_layers()

	get_tree().change_scene_to_file("res://scenes/local_game/local_game.tscn")
	await frames(10)
	say("scene: " + str(get_tree().current_scene.name))
	var pres = PlayerManager.player_presences.get(-1)
	ok("presence carries glasses into local game", pres != null and str(pres.customization[1]) == "sunglasses", pres.customization if pres else null)
	if bot_dev != null:
		var bot_pres = PlayerManager.player_presences.get(bot_dev)
		ok("bot keeps its own glasses", bot_pres != null and str(bot_pres.customization[1]) == "reading_glasses", bot_pres.customization if bot_pres else null)

	await _lobby_buttons()
	await _rejoin_seat_0()
	await _options_page()
	finish()

# A player who leaves seat 0 and joins again takes it back, comes first in the
# game's order, and their card waits for their own name, not the last occupant's.
func _rejoin_seat_0() -> void:
	say("step: rejoin seat 0")
	var lobby = get_tree().current_scene
	var controls: Array = lobby.local_lobby_player_controls
	var n: int = mini(3, controls.size())
	for i in n:
		lobby.join(HOST + i, true)
		controls[i]._on_name_confirmed("OLD%d" % i)
	await frames(6)
	lobby.leave(0)
	await frames(2)
	lobby.join(MENU_PAD + 1, true)
	await frames(6)
	ok("a rejoiner takes the freed seat 0", lobby.player_data.has(0) and lobby.player_data[0]["device"] == MENU_PAD + 1, lobby.player_data)
	ok("the lobby's players stay in seat order after a rejoin", lobby.player_data.keys() == range(n), lobby.player_data.keys())
	var strip = lobby.get_node_or_null("Control/CouchLobbyStrip")
	var card = strip.get_node_or_null("CouchLobbyCard1") if strip else null
	if card == null:
		say("INFO no close-ups strip, card checks skipped")
	else:
		var label: Label = card.find_children("*", "Label", true, false)[0]
		ok("on the name screen seat 0's card is hidden (it would read OLD0)", not card.visible, [card.visible, label.text])
		controls[0]._on_name_confirmed("NEW")
		await frames(3)
		ok("named, seat 0's card shows the new name", card.visible and label.text == "NEW", [card.visible, label.text])
		controls[0].show_name_entry()
		await frames(3)
		ok("back on the name screen (B), the card hides again", not card.visible)
		controls[0]._on_name_confirmed("NEW")
	lobby.update_player_manager()
	var order: Array = PlayerManager.player_presences.values().map(func(p): return p.device_id)
	ok("the game's players come in seat order", order == [MENU_PAD + 1] + range(1, n).map(func(i): return HOST + i), order)
	# Offline Bots' add_bot fills the lowest free seat without player_joined.
	if lobby.has_method("add_bot"):
		lobby.leave(0)
		await frames(2)
		var bot: int = lobby.add_bot("BotSeat", ["", "none", "red"])
		await frames(2)
		ok("a bot in the freed seat 0: the lobby stays in seat order", lobby.player_data.keys() == range(n) and lobby.player_data[0]["device"] == bot, [lobby.player_data.keys(), bot])
		lobby.update_player_manager()
		order = PlayerManager.player_presences.values().map(func(p): return p.device_id)
		ok("a bot in the freed seat 0 comes first in the game", not order.is_empty() and order[0] == bot, order)
	await _empty_seats(lobby)
	PlayerManager.reset()

# --- lobby buttons ----------------------------------------------------------------

const MENU_ACTIONS := ["ui_accept", "ui_up", "ui_down", "ui_left", "ui_right"]
const HOST := 100
const OTHER := 101
const MENU_PAD := 102

func _pad_devices(action: String) -> Array:
	if not InputMap.has_action(action):
		return ["missing"]
	return InputMap.action_get_events(action).filter(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion).map(func(e): return e.device)

# The ProjectSettings event objects the InputMap shares, with their devices, so
# each case starts from the same bindings.
func _stored_devices() -> Array:
	var kept := []
	for a in InputMap.get_actions():
		var s := "input/" + String(a)
		if not (String(a).begins_with("ui_") or String(a).begins_with("playlist_")) or not ProjectSettings.has_setting(s):
			continue
		for e in ProjectSettings.get_setting(s).get("events", []):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				kept.append([e, e.device])
	return kept

func _put_back(kept: Array) -> void:
	for k in kept:
		k[0].device = k[1]
	MultiplayerInput.initialize()

# A press and release of A, as a pad sends it to the GUI (buttons fire on release).
func _gui_a(device: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = JOY_BUTTON_A
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		get_viewport().push_input(e)
		await frames(1)

func _presses_leave(lobby, device: int, hits: Array) -> bool:
	var before: int = hits[0]
	lobby.leave_button.grab_focus()
	await frames(1)
	await _gui_a(device)
	await frames(2)
	return hits[0] > before

func _empty_seats(lobby) -> void:
	for i in range(lobby.MAX_PLAYERS - 1, -1, -1):
		lobby.leave(i)
	await frames(2)

func _lobby_buttons() -> void:
	say("step: lobby buttons")
	PlayerManager.reset()
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")
	await frames(30)
	await get_tree().create_timer(1.0).timeout
	var lobby = get_tree().current_scene
	var order := InputMap.get_actions().map(func(a): return String(a))
	var first_custom: int = order.find(order.filter(func(a): return not (a.begins_with("ui_") or a.begins_with("playlist_")))[0])
	say("INFO first non-ui action at %d of %d; ui actions after it: %s" % [first_custom, order.size(), str(order.slice(first_custom).filter(func(a): return a.begins_with("ui_") or a.begins_with("playlist_")))])
	var leave_calls: Array = lobby.leave_button.pressed.get_connections().map(func(c): return c.callable)
	for c in leave_calls:
		lobby.leave_button.pressed.disconnect(c)
	var hits := [0]
	var count := func(): hits[0] += 1
	lobby.leave_button.pressed.connect(count)
	var input0 = GameManager.current_input_device
	GameManager.current_input_device = GameManager.InputDevice.Controller
	var gcs: Dictionary = _loader.registry("gamecube_support")
	var menu0 = gcs.get("menu_pad")
	gcs["menu_pad"] = MENU_PAD
	var kept := _stored_devices()
	var entry := _pad_devices("ui_accept")
	ok("one buttons helper per lobby", lobby.get_children().filter(func(n): return String(n.name).begins_with("CouchLobbyButtons")).size() == 1)

	lobby.join(HOST, true)
	lobby.join(OTHER, true)
	await frames(2)
	say("INFO pad host: %s" % str(MENU_ACTIONS.map(func(a): return [a, _pad_devices(a)])))
	ok("pad host: another pad's A can't press Leave", not await _presses_leave(lobby, OTHER, hits))
	ok("pad host: the menu pad's A can't press Leave", not await _presses_leave(lobby, MENU_PAD, hits))
	ok("pad host: the host's A presses Leave", await _presses_leave(lobby, HOST, hits))
	lobby.leave(0)
	await frames(2)
	say("INFO host pad left: %s" % str(MENU_ACTIONS.map(func(a): return [a, _pad_devices(a)])))
	ok("host pad left: another pad's A can't press Leave", not await _presses_leave(lobby, OTHER, hits))
	ok("host pad left: the menu pad's A presses Leave", await _presses_leave(lobby, MENU_PAD, hits))
	await _empty_seats(lobby)
	_put_back(kept)

	lobby.join(-1, false)
	lobby.join(OTHER, true)
	await frames(2)
	say("INFO keyboard host: %s" % str(MENU_ACTIONS.map(func(a): return [a, _pad_devices(a)])))
	ok("keyboard host: another pad's A can't press Leave", not await _presses_leave(lobby, OTHER, hits))
	ok("keyboard host: the menu pad's A presses Leave", await _presses_leave(lobby, MENU_PAD, hits))
	gcs["menu_pad"] = -1
	await frames(2)
	ok("keyboard host, no menu pad: no pad presses Leave", not await _presses_leave(lobby, OTHER, hits) and not await _presses_leave(lobby, MENU_PAD, hits))
	await _empty_seats(lobby)
	ok("everyone gone after a keyboard host: the lobby's own bindings are back", _pad_devices("ui_accept") == entry and not entry.has(2147483647), [_pad_devices("ui_accept"), entry])
	gcs["menu_pad"] = MENU_PAD
	_put_back(kept)

	if lobby.has_method("add_bot"):
		lobby.add_bot("BotTest", ["", "none", "red"])
		lobby.join(OTHER, true)
		await frames(2)
		say("INFO bot host: %s" % str(MENU_ACTIONS.map(func(a): return [a, _pad_devices(a)])))
		ok("bot host: another pad's A can't press Leave", not await _presses_leave(lobby, OTHER, hits))
		ok("bot host: the menu pad's A presses Leave", await _presses_leave(lobby, MENU_PAD, hits))
		await _empty_seats(lobby)
		_put_back(kept)
	else:
		say("INFO no Offline Bots, bot host skipped")

	await _empty_leave(lobby, hits)
	_put_back(kept)

	lobby.join(-1, false)
	gcs["menu_pad"] = -1
	await frames(2)
	ok("keyboard host, no menu pad: the bindings are on no pad", _pad_devices("ui_accept").all(func(d): return d == 2147483647), _pad_devices("ui_accept"))
	var helper: Node = lobby.get_node("CouchLobbyButtons")
	lobby.remove_child(helper)
	ok("leaving the lobby puts its bindings back", _pad_devices("ui_accept") == entry and not entry.has(2147483647), [_pad_devices("ui_accept"), entry])
	helper.free()
	await _empty_seats(lobby)

	if menu0 == null:
		gcs.erase("menu_pad")
	else:
		gcs["menu_pad"] = menu0
	GameManager.current_input_device = input0
	lobby.leave_button.pressed.disconnect(count)
	for c in leave_calls:
		lobby.leave_button.pressed.connect(c)

# With nobody past the name screen, an unseated pad's back lights LEAVE and back or A
# presses it; the press joins nobody.
const EMPTY_PAD := 75
var _join_watch := -1
var _joins_seen := 0
var _watch_lobby: Node

# Runs after the buttons helper (process_priority -1), in the lobby's frame: a join is what the
# lobby's _process would act on, local_join just pressed while its can_control is on.
func _process(_delta: float) -> void:
	if _join_watch < 0 or not is_instance_valid(_watch_lobby):
		return
	var a = MultiplayerInput.device_actions.get(_join_watch, {}).get(&"local_join", &"")
	if a != &"" and InputMap.has_action(a) and Input.is_action_just_pressed(a) and _watch_lobby.can_control:
		_joins_seen += 1

func _empty_leave(lobby, hits: Array) -> void:
	say("step: LEAVE with nobody past the name screen")
	var B = lobby.get_node("CouchLobbyButtons").get_script()
	ok("empty_press: back lights, back or A while lit leaves, another join unlights", B.empty_press(false, true, false, true) == "light" and B.empty_press(true, true, false, true) == "leave" and B.empty_press(true, false, true, true) == "leave" and B.empty_press(true, false, false, true) == "unlight" and B.empty_press(false, false, true, true) == "" and B.empty_press(false, false, false, true) == "")
	if not MultiplayerInput.core_actions.has(&"local_join"):
		say("INFO no core actions, the presses are skipped")
		return
	await _empty_seats(lobby)
	var leave: Button = lobby.leave_button
	var dev := EMPTY_PAD
	MultiplayerInput._create_actions_for_device(dev)
	var neighbours := [leave.focus_neighbor_top, leave.focus_neighbor_bottom, leave.focus_neighbor_left, leave.focus_neighbor_right, leave.focus_next, leave.focus_previous]
	_watch_lobby = lobby
	_join_watch = dev
	_joins_seen = 0
	var before: int = hits[0]
	await _tap(dev, JOY_BUTTON_X)
	ok("nobody seated, a pad's X (back): LEAVE lit, nothing pressed", leave.has_focus() and hits[0] == before, [leave.has_focus(), hits[0] - before])
	ok("and that X joins nobody (the lobby's can_control off in its frame)", _joins_seen == 0, _joins_seen)
	ok("and the lobby's can_control is back after that frame", lobby.can_control)
	ok("lit, LEAVE's focus neighbours are itself", leave.focus_neighbor_bottom == NodePath(".") and leave.focus_next == NodePath("."))
	await _tap(dev, JOY_BUTTON_Y)
	ok("lit, Y joins as usual and unlights LEAVE", not leave.has_focus() and _joins_seen == 1 and hits[0] == before, [leave.has_focus(), _joins_seen])
	ok("unlit, LEAVE's focus neighbours are back", [leave.focus_neighbor_top, leave.focus_neighbor_bottom, leave.focus_neighbor_left, leave.focus_neighbor_right, leave.focus_next, leave.focus_previous] == neighbours)
	await _tap(dev, JOY_BUTTON_X)
	await _tap(dev, JOY_BUTTON_X)
	ok("lit, X again presses LEAVE, and neither X joins", hits[0] == before + 1 and _joins_seen == 1 and not leave.has_focus(), [hits[0] - before, _joins_seen])
	await _tap(dev, JOY_BUTTON_X)
	await _tap(dev, JOY_BUTTON_A)
	ok("lit, A presses LEAVE and joins nobody", hits[0] == before + 2 and _joins_seen == 1, [hits[0] - before, _joins_seen])
	await _tap(dev, JOY_BUTTON_A)
	ok("unlit, A joins as usual and presses nothing", hits[0] == before + 2 and _joins_seen == 2 and not leave.has_focus(), [hits[0] - before, _joins_seen])
	_key(KEY_X, true)
	await frames(2)
	_key(KEY_X, false)
	await frames(2)
	ok("the keyboard's X key lights LEAVE", leave.has_focus())
	_key(KEY_X, true)
	await frames(2)
	_key(KEY_X, false)
	await frames(2)
	ok("and presses it again", hits[0] == before + 3 and not leave.has_focus(), hits[0] - before)

	# Seated players still on the name screen don't stop it (the owner's 8BitDo, 2026-11-12).
	var C: Array = lobby.local_lobby_player_controls
	ok("nobody_past_names: nobody seated", B.nobody_past_names(lobby.player_data, C))
	lobby.join(OTHER, true)
	await frames(2)
	MultiplayerInput._create_actions_for_device(dev)
	var base: int = _joins_seen
	ok("nobody_past_names: seat 0 on the name screen", B.nobody_past_names(lobby.player_data, C) and not C[0].active, C[0].active)
	await _tap(dev, JOY_BUTTON_X)
	ok("seat 0 on the name screen: an unseated pad's X lights LEAVE and joins nobody", leave.has_focus() and _joins_seen == base and hits[0] == before + 3, [leave.has_focus(), _joins_seen - base, hits[0] - before])
	ok("and seat 0's pad has the ui actions", _pad_devices("ui_accept").all(func(d): return d == OTHER), _pad_devices("ui_accept"))
	await _tap(OTHER, JOY_BUTTON_A)
	ok("lit, seat 0's A presses nothing and LEAVE stays lit", hits[0] == before + 3 and leave.has_focus(), [hits[0] - before, leave.has_focus()])
	await _tap(dev, JOY_BUTTON_A)
	ok("lit, the unseated pad's A presses it", hits[0] == before + 4 and not leave.has_focus(), [hits[0] - before, leave.has_focus()])
	const SECOND_PAD := EMPTY_PAD + 1
	MultiplayerInput._create_actions_for_device(SECOND_PAD)
	await _tap(dev, JOY_BUTTON_X)
	await _tap(SECOND_PAD, JOY_BUTTON_Y)
	ok("lit, another unseated pad's join press unlights it", not leave.has_focus() and hits[0] == before + 4)
	MultiplayerInput._delete_actions_for_device(SECOND_PAD)
	await _tap(dev, JOY_BUTTON_X)
	C[0]._on_name_confirmed("CLST")
	await frames(2)
	ok("seat 0 confirms a name: LEAVE unlit", not leave.has_focus() and not B.nobody_past_names(lobby.player_data, C), leave.has_focus())
	base = _joins_seen
	await _tap(dev, JOY_BUTTON_X)
	ok("someone past the name screen: X joins as usual and lights nothing", not leave.has_focus() and _joins_seen == base + 1 and hits[0] == before + 4, [leave.has_focus(), _joins_seen - base])
	await _empty_seats(lobby)
	MultiplayerInput._create_actions_for_device(dev)
	await _tap(dev, JOY_BUTTON_X)
	ok("lit again once empty", leave.has_focus())
	await _tap(dev, JOY_BUTTON_Y)

	# The owner's case: player 1 backs out while player 2 is on the name screen.
	lobby.join(dev, true)
	lobby.join(OTHER, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	_pad(dev, JOY_BUTTON_X, true)
	await frames(2)
	lobby.leave(0)
	MultiplayerInput._create_actions_for_device(dev)
	await frames(4)
	_pad(dev, JOY_BUTTON_X, false)
	await frames(3)
	ok("player 1 out, player 2 on the name screen: the held X lights nothing", not leave.has_focus())
	await _tap(dev, JOY_BUTTON_X)
	ok("and a new X lights LEAVE", leave.has_focus())
	await _tap(dev, JOY_BUTTON_X)
	ok("and X again presses it", hits[0] == before + 5 and not leave.has_focus(), hits[0] - before)
	await _empty_seats(lobby)
	MultiplayerInput._create_actions_for_device(dev)

	# A seated keyboard confirms its letters with Enter (name_panel's _unhandled_input), also ui_accept.
	lobby.join(-1, false)
	await frames(2)
	MultiplayerInput._create_actions_for_device(dev)
	await _tap(dev, JOY_BUTTON_X)
	ok("the keyboard seated on the name screen: an unseated pad's X lights LEAVE", leave.has_focus())
	# The confirmed name goes into the saved names: not to the owner's file.
	var store = _loader.registry("couch_lobby").get("names")
	var kept_names: Array = store.names.duplicate() if store != null else []
	var kept_persist: bool = store.persist if store != null else true
	if store != null:
		store.persist = false
	var kp: Node = C[0].get_node_or_null("CouchLobbyNamePanel")
	if kp != null and kp._list != null:
		kp._pick(0)
		await frames(2)
	C[0].name_entry_selector.set_player_name("KB")
	for down in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		enter.pressed = down
		Input.parse_input_event(enter)
		Input.flush_buffered_events()
		await frames(2)
	ok("lit, the seated keyboard's Enter unlights LEAVE, presses nothing and confirms its name", not leave.has_focus() and hits[0] == before + 5 and C[0].active, [leave.has_focus(), hits[0] - before, C[0].active])
	if store != null:
		store.names = kept_names
		store.persist = kept_persist
	await _empty_seats(lobby)
	MultiplayerInput._create_actions_for_device(dev)

	# Offline Bots' add_bot seats a bot without player_joined: its seat's controls aren't its own.
	if lobby.has_method("add_bot"):
		lobby.join(OTHER, true)
		lobby.add_bot("BotLeave", ["", "none", "red"])
		await frames(2)
		MultiplayerInput._create_actions_for_device(dev)
		ok("nobody_past_names: a bot's seat is past the name screen", not B.nobody_past_names(lobby.player_data, C), lobby.player_data.keys())
		base = _joins_seen
		await _tap(dev, JOY_BUTTON_X)
		ok("a bot seated, seat 0 on the name screen: X joins as usual and lights nothing", not leave.has_focus() and _joins_seen == base + 1 and hits[0] == before + 5, [leave.has_focus(), _joins_seen - base])
		await _empty_seats(lobby)
		MultiplayerInput._create_actions_for_device(dev)

	# The X that drops the last player out is still down; only a new press lights LEAVE.
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	_pad(dev, JOY_BUTTON_X, true)
	await frames(2)
	lobby.leave(0)
	MultiplayerInput._create_actions_for_device(dev)
	await frames(4)
	ok("the X held through a drop-out lights nothing", not leave.has_focus())
	_pad(dev, JOY_BUTTON_X, false)
	await frames(3)
	ok("nor its release", not leave.has_focus())
	await _tap(dev, JOY_BUTTON_X)
	ok("a new X lights LEAVE", leave.has_focus())
	await _tap(dev, JOY_BUTTON_Y)
	_join_watch = -1
	MultiplayerInput._delete_actions_for_device(dev)

# Split-screen first person: own glasses must be hidden from own camera,
# same as the hat (vanilla only moves hat meshes in set_visibility_layer).
func _chisel_gauntlet_layers() -> void:
	say("step: chisel gauntlet layers")
	var scene = load("res://minigames/chisel_gauntlet_multiplayer/components/player/chisel_gauntlet_player.tscn")
	var player = scene.instantiate()
	get_tree().root.add_child(player)
	await frames(3)
	var a = player.customization_assigner
	ok("layer sync attached", a.get_node_or_null("CouchLobbyGlassesLayerSync") != null)
	a.assign_hat("tophat")
	a.assign_glasses("sunglasses")
	player.setup_local_visuals(0)
	await frames(2)
	var hat_layers := -1
	for hp in a.bone_attachment_hat.get_children():
		for m in hp.get_children():
			if m is MeshInstance3D and hat_layers < 0: hat_layers = m.layers
	var glasses_meshes = a.bone_attachment_glasses.find_children("*", "MeshInstance3D", true, false)
	var glasses_layers = glasses_meshes.map(func(m): return m.layers)
	ok("glasses meshes found", glasses_meshes.size() > 0, glasses_meshes.size())
	ok("glasses on hat layer", glasses_layers.all(func(l): return l == hat_layers), [hat_layers, glasses_layers])
	ok("own camera skips glasses layer", (player.local_camera.cull_mask & hat_layers) == 0, [player.local_camera.cull_mask, hat_layers])
	var other = scene.instantiate()
	get_tree().root.add_child(other)
	await frames(2)
	other.setup_local_visuals(1)
	ok("other seat's camera sees glasses", (other.local_camera.cull_mask & hat_layers) != 0, [other.local_camera.cull_mask, hat_layers])
	player.queue_free()
	other.queue_free()

# Headless: the nodes, the doubles' looks and the layout logic; what the photos look
# like is cl_portrait's (windowed) and the owner's.
func _close_ups(lobby) -> void:
	say("step: close-ups")
	var cu = lobby.get_node_or_null("CouchLobbyCloseUps")
	ok("one close-ups node on the lobby", cu != null and lobby.get_children().filter(func(n): return n.name.begins_with("CouchLobbyCloseUps")).size() == 1)
	if cu == null:
		return
	var screen: Control = lobby.get_node("Control/TextureRect")
	var strip = lobby.get_node_or_null("Control/CouchLobbyStrip")
	ok("strip right after the room's picture (under its grime pass)", strip != null and strip.get_index() == screen.get_index() + 1, strip.get_index() if strip else null)
	var room: Node3D = lobby.players_node.get_parent()
	ok("room copy and lamp copy", room.get_node_or_null("CouchLobbyRoomCopy") != null and room.get_node_or_null("CouchLobbyLampCopy") != null)
	var controls: Array = lobby.local_lobby_player_controls
	if controls[1].assigned_player_id < 0:
		lobby.join(5, true)
		await frames(3)
		controls[1]._on_name_confirmed("PAD")
	await frames(4)
	var seated: Array = range(controls.size()).filter(func(i): return controls[i].assigned_player_id >= 0)
	var cards: Array = seated.map(func(i): return strip.get_node_or_null("CouchLobbyCard%d" % (i + 1)))
	ok("a shown card per seated player (%d)" % seated.size(), cards.all(func(c): return c != null and c.visible), seated)
	ok("cards carry the names", seated.all(func(i): return strip.get_node("CouchLobbyCard%d" % (i + 1)).find_children("*", "Label", true, false)[0].text == controls[i].player_name))
	var cam_room: Camera3D = room.get_node("Camera3D")
	for i in seated:
		var d: Node3D = room.get_node_or_null("CouchLobbyDouble%d" % (i + 1))
		ok("P%d double exists, out of the room camera's view" % (i + 1), d != null and not cam_room.is_position_in_frustum(d.global_position))
		if d == null:
			continue
		var meshes: Array = d.find_children("*", "GeometryInstance3D", true, false)
		ok("P%d double only on its own layer" % (i + 1), meshes.size() > 0 and meshes.all(func(g): return g.layers == 1 << (10 + i)))
		var cam: Camera3D = cu.get_node("CouchLobbyPhoto%d" % (i + 1)).get_child(0)
		ok("P%d camera sees the room and its own double" % (i + 1), cam.cull_mask == 1 | (1 << (10 + i)), cam.cull_mask)
		ok("P%d double has no blink" % (i + 1), d.find_children("*", "", true, false).all(func(n): return not "texture_eye_closed" in n))
		var body: MeshInstance3D = d.find_child("character mesh", true, false)
		var eyes: Material = body.get_surface_override_material(2) if body else null
		ok("P%d double's eyes: its own material, open" % (i + 1), eyes != null and eyes != body.mesh.surface_get_material(2)
			and str(eyes.get("albedo_texture").resource_path).contains("eye open"), eyes.get("albedo_texture").resource_path if eyes else null)
	var cs = cu.get_script()
	var a0 = controls[0].customization_assigner
	var d0 = room.get_node("CouchLobbyDouble1").find_children("customization assigner", "", true, false)[0]
	var kept: Array = cs.look_of(a0)
	ok("P1 double wears P1's look", cs.look_of(d0) == cs.look_of(a0), [cs.look_of(a0), cs.look_of(d0)])
	var cam1: Camera3D = cu.get_node("CouchLobbyPhoto1").get_child(0)
	var menu: Node = load("res://scenes/character_customization.tscn").instantiate()
	var menu_cam: Camera3D = menu.get_node("viewport_character preview/character preview camera parent/camera_character preview feed")
	var pose: Transform3D = _chain(menu.get_node("main character2")).affine_inverse() * _chain(menu_cam)
	var menu_fov: float = menu_cam.fov
	menu.free()
	var double1: Node3D = room.get_node("CouchLobbyDouble1/main character2")
	var menu_at: Transform3D = (double1.global_transform * pose).orthonormalized()
	var head: Vector3 = d0.bone_attachment_glasses.global_position
	var face := _face_dir(d0)
	face.y = 0.0
	var from_head: Vector3 = cam1.global_position - head
	var flat := Vector3(from_head.x, 0.0, from_head.z)
	var menu_off: Vector3 = menu_at.origin - head
	var look := -cam1.global_basis.z
	ok("P1 camera head-on: on the face's line, looking straight back", rad_to_deg(flat.angle_to(face)) < 1.0
		and rad_to_deg(Vector3(look.x, 0.0, look.z).angle_to(-flat)) < 0.5, [rad_to_deg(flat.angle_to(face)), cam1.global_position, head])
	ok("P1 camera at the menu camera's distance, height, tilt and lens, level", is_equal_approx(flat.length(), Vector2(menu_off.x, menu_off.z).length())
		and absf(from_head.y - menu_off.y) < 0.001 and absf(cam1.global_rotation.x - menu_at.basis.get_euler().x) < 0.001
		and absf(cam1.global_basis.x.y) < 0.001 and is_equal_approx(cam1.fov, menu_fov), [flat.length(), from_head.y, menu_off.y, cam1.global_rotation_degrees, cam1.fov])
	var before: Transform3D = cam1.global_transform
	a0.assign_hat("tophat")
	a0.assign_glasses("reading_glasses")
	a0.assign_suit_color("green")
	await frames(3)
	ok("P1 double follows a changed look", cs.look_of(d0) == ["tophat", "reading_glasses", "green"], cs.look_of(d0))
	ok("P1 camera holds its pose through a hat change (fixed zoom)", cam1.global_transform.is_equal_approx(before), [before.origin, cam1.global_position])
	var d1meshes: Array = room.get_node("CouchLobbyDouble1").find_children("*", "GeometryInstance3D", true, false)
	ok("P1 double still only on its own layer after the change", d1meshes.all(func(g): return g.layers == 1 << 10))
	a0.remove_hat()
	await frames(3)
	ok("P1 camera holds its pose with no hat", cam1.global_transform.is_equal_approx(before), cam1.global_position)

	var canvas: float = lobby.get_viewport().get_visible_rect().size.x
	var r8: Array = cs.card_rects(8, canvas)
	var caption: Label = strip.get_node("CouchLobbyCard1").find_children("*", "Label", true, false)[0]
	var w7: float = caption.get_theme_font("font").get_string_size("WWWWWWW", HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
	ok("a 7-letter name fits a Polaroid caption at 8 cards", w7 <= r8[0].size.x, [w7, r8[0].size.x])
	ok("8 cards fit inside the margins", r8[0].position.x >= 23.9 and r8[7].end.x <= canvas - 23.9 and r8[7].end.y <= 540.0, [r8[0], r8[7]])
	var leave := Rect2(35, 470, 96, 35)
	ok("LEAVE over 8 cards: rows lift to clear the strip", is_equal_approx(cs.lift_for([leave], r8), 505.0 - 426.0), cs.lift_for([leave], r8))
	ok("LEAVE beside 4 cards: no lift", cs.lift_for([leave], cs.card_rects(4, canvas)) == 0.0, cs.card_rects(4, canvas)[0])
	ok("no cards: no lift", cs.lift_for([leave], []) == 0.0)

	var leave_row: Control = lobby.get_node("Control/Lobby/Control/HFlowContainer")
	var home_y: float = leave_row.position.y + cu._lift
	if controls.size() == 8:
		# Named at once, so only the pose holds the cards back (a seat on its name screen has none).
		for i in range(seated.size(), 8):
			lobby.join(20 + i, true)
			controls[i]._on_name_confirmed("P%d" % (i + 1))
		# A new seat's camera sits at the world origin until its double is posed; its card must wait.
		var early := []
		for f in 4:
			await get_tree().process_frame
			for i in range(seated.size(), 8):
				var card := strip.get_node_or_null("CouchLobbyCard%d" % (i + 1)) as Control
				var photo := cu.get_node_or_null("CouchLobbyPhoto%d" % (i + 1)) as SubViewport
				if card and card.visible and (photo.get_child(0) as Camera3D).global_position.is_zero_approx():
					early.append("P%d frame %d" % [i + 1, f])
		ok("joining seats: no card shows before its camera is posed", early.is_empty(), early)
		await frames(4)
		ok("8 seated: the button rows rise above the strip", leave_row.position.y < home_y - 50.0, [home_y, leave_row.position.y])
		for i in range(seated.size(), 8):
			lobby.leave(i)
		await frames(3)
	ok("button rows back home when the strip clears them", is_equal_approx(leave_row.position.y, home_y), [home_y, leave_row.position.y])
	lobby.leave(1)
	await frames(3)
	ok("a left seat's card hides and its camera stops", not strip.get_node("CouchLobbyCard2").visible and
		cu.get_node("CouchLobbyPhoto2").render_target_update_mode == SubViewport.UPDATE_DISABLED)
	# The later steps expect P1's look from before this one.
	a0.assign_hat(kept[0])
	a0.assign_glasses(kept[1])
	a0.assign_suit_color(kept[2])
	await frames(2)

# --- saved names --------------------------------------------------------------

const NAME_PAD := 60

func _name_tags(lobby) -> void:
	say("step: saved names")
	var store = _loader.registry("couch_lobby").get("names")
	ok("the names store is in the registry", store != null and store.has_method("remember"), store)
	if store == null:
		return
	var T: GDScript = store.get_script()
	for n in ["A", "ABCDEFG", "WWWWWWW"]:
		ok("saveable: %s" % n, T.is_saveable(n))
	for n in ["", "ABCDEFGH", "P1", "P-1", "abc", "A-B", "A B", 7, null]:
		ok("not saveable: %s" % str(n), not T.is_saveable(n))
	ok("remembered: a new name goes on top", T.remembered(["B", "C"], "A") == ["A", "B", "C"])
	ok("remembered: a known name moves to the top", T.remembered(["B", "A", "C"], "A") == ["A", "B", "C"])
	var full: Array = range(T.CAP).map(func(i): return "N" + String.chr(65 + i / 26) + String.chr(65 + i % 26))
	var plus: Array = T.remembered(full, "NEW")
	ok("remembered: a new name on a full list drops the least recently used", plus.size() == T.CAP and plus[0] == "NEW" and not plus.has(full[-1]) and plus.has(full[-2]), [plus.size(), plus[0], plus[-1]])
	ok("remembered on a full list: a known name drops nothing", T.remembered(full, full[-1]).size() == T.CAP)
	ok("forgotten", T.forgotten(["A", "B", "C"], "B") == ["A", "C"] and T.forgotten(["A"], "Z") == ["A"])
	ok("validated: a good list", T.validated({"saved_names": ["A", "B"]}) == {"names": ["A", "B"], "ok": true})
	for bad in [null, [], "x", {}, {"saved_names": "A"}, {"saved_names": null}]:
		ok("validated: unusable root %s" % str(bad), T.validated(bad) == {"names": [], "ok": false})
	ok("validated: bad entries and repeats dropped, the first copy kept", T.validated({"saved_names": ["B", 3, "a", "B", "TOOLONGX", "C"]}) == {"names": ["B", "C"], "ok": false})
	ok("validated: cut to the cap", T.validated({"saved_names": full + ["XYZ"]}) == {"names": full, "ok": false})
	var trip: Dictionary = T.validated(JSON.parse_string(JSON.stringify({"saved_names": ["JERM", "WWWWWWW"]}, "	")))
	ok("validated: a JSON round trip", trip == {"names": ["JERM", "WWWWWWW"], "ok": true}, trip)
	# Not a *.json: the runner fails a run that changes one in the saves folder.
	var scratch := "user://cl_selftest_names.txt"
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string("{\"saved_names\": [\"JERM\",")
	f.close()
	var spare = T.new()
	ok("an unreadable names file loads as empty, reported", not spare.load_from(scratch) and spare.names.is_empty())
	spare.remember("ABC")
	ok("the first save keeps the unreadable file as .bad", FileAccess.get_file_as_string(scratch + ".bad") == "{\"saved_names\": [\"JERM\",", FileAccess.file_exists(scratch + ".bad"))
	ok("and writes the new list", T.validated(JSON.parse_string(FileAccess.get_file_as_string(scratch))) == {"names": ["ABC"], "ok": true}, FileAccess.get_file_as_string(scratch))
	spare.remember("DEF")
	ok("later saves leave the .bad copy alone", FileAccess.get_file_as_string(scratch + ".bad").begins_with("{\"saved_names\": [\"JERM\""))
	for leftover in [scratch, scratch + ".bad", scratch + ".tmp"]:
		DirAccess.remove_absolute(leftover)

	var kept_names: Array = store.names.duplicate()
	var kept_persist: bool = store.persist
	store.persist = false
	store.names = []
	var controls: Array = lobby.local_lobby_player_controls
	var entries: Array = controls.map(func(c): return c.name_entry_selector)
	ok("a names panel on every seat", controls.all(func(c): return c.get_node_or_null("CouchLobbyNamePanel") != null))
	ok("every seat has 7 name letters", entries.all(func(e): return e.character_selectors.size() == 7), entries.map(func(e): return e.character_selectors.size()))
	ok("the letters are the game's selectors, in the name box", entries.all(func(e): return e.character_selectors.all(func(s): return s is LocalLobbyPlayerNameCharacterSelector and s.get_parent() == e)))
	ok("the letters are 18 px before a card scales them (the owner's pick)", entries.all(func(e): return e.character_selectors.all(func(s): return s.character_label.get_theme_font_size("font_size") == 18)))
	ok("every letter has the panel's sounds", entries.all(func(e): return e.hover_speaker != null and e.character_selectors.all(func(s): return s.hover_speaker == e.hover_speaker and s.press_speaker == e.press_speaker)))

	lobby.join(NAME_PAD, true)
	await frames(3)
	# A pad in seat 0 reloads the InputMap (set_ui_action_device), which drops a fake pad's clones.
	var made: bool = MultiplayerInput.core_actions.has(&"right")
	if made:
		MultiplayerInput._create_actions_for_device(NAME_PAD)
	var c = controls[0]
	var e = c.name_entry_selector
	ok("a joined pad is on its name screen", e.active and e.visible)
	ok("with nothing saved, a join goes straight to the letters", e.get_node_or_null("CouchLobbyNameList") == null and e.is_joystick and e.character_selectors[0].visible)
	store.names = ["OLD"]
	if made:
		var steps := []
		for i in 7:
			await _stick_right(NAME_PAD)
			steps.append(e.active_selector_index)
		ok("right steps over all 7 letters and wraps", steps == [1, 2, 3, 4, 5, 6, 0], steps)
		await _stick_right(NAME_PAD)
		await frames(1)
		var arrows: Array = e.character_selectors.map(func(sel): return sel.cycle_previous_element.self_modulate.a + sel.cycle_next_element.self_modulate.a)
		ok("a pad sees arrows on the edited letter only", arrows[1] > 0.0 and arrows.filter(func(a): return a > 0.0).size() == 1, arrows)
	else:
		say("INFO no core actions, the letter steps are skipped")
	e.set_player_name("ABCDEFG")
	e.accept_name()
	await frames(2)
	ok("7 letters confirm as the name", c.player_name == "ABCDEFG", c.player_name)
	ok("a confirmed name is saved, on top", store.names == ["ABCDEFG", "OLD"], store.names)
	c.show_name_entry()
	e.set_player_name("OLD")
	e.accept_name()
	await frames(2)
	ok("confirming a saved name moves it to the top", store.names == ["OLD", "ABCDEFG"], store.names)
	c.show_name_entry()
	e.set_player_name("")
	e.accept_name()
	await frames(2)
	ok("an empty name gets the default and isn't saved", c.player_name.begins_with("P") and store.names == ["OLD", "ABCDEFG"], [c.player_name, store.names])
	c._on_name_confirmed("DIRECT")
	ok("a name set directly (tests, rejoins, bots) isn't saved", not store.names.has("DIRECT"), store.names)
	lobby.join(-1, false)
	await frames(3)
	var kb = controls[1].name_entry_selector
	ok("a keyboard player keeps every letter's arrows", kb.active and kb.character_selectors.all(func(sel): return sel.cycle_previous_element.self_modulate.a > 0.0 and sel.cycle_next_element.self_modulate.a > 0.0))
	lobby.leave(1)
	lobby.leave(0)
	await frames(2)
	if made:
		MultiplayerInput._delete_actions_for_device(NAME_PAD)
	store.names = kept_names
	store.persist = kept_persist

# The join list. Pad presses go through Input, as a real pad's do.
func _name_list(lobby) -> void:
	say("step: the saved names' join list")
	var store = _loader.registry("couch_lobby").get("names")
	if store == null:
		return
	var P: GDScript = load(_mod_dir("couch_lobby").path_join("name_panel.gd"))
	ok("next_row skips names in use and stops at the ends", P.next_row(["", "A", "B", "C"], ["B"], 1, 1) == 3 and P.next_row(["", "A", "B"], ["B"], 1, 1) == 1 and P.next_row(["", "A"], ["A"], 1, -1) == 0 and P.next_row(["", "A"], [], 0, -1) == 0)
	ok("first_row opens centred on the highlight", P.first_row(12, 0) == 0 and P.first_row(12, 7) == 5 and P.first_row(12, 11) == 7 and P.first_row(3, 2) == 0)
	ok("kept_in_view scrolls only at the edges", P.kept_in_view(0, 3, 12) == 0 and P.kept_in_view(0, 4, 12) == 0 and P.kept_in_view(0, 5, 12) == 1 and P.kept_in_view(5, 4, 12) == 4 and P.kept_in_view(9, 11, 12) == 7)
	var kept_names: Array = store.names.duplicate()
	var kept_persist: bool = store.persist
	store.persist = false
	store.names = ["AAA", "BBB", "CCC", "DDD", "EEE", "FFF"]
	var controls: Array = lobby.local_lobby_player_controls
	var made: bool = MultiplayerInput.core_actions.has(&"right")
	if not made:
		say("INFO no core actions, the list's pad checks are skipped")
		store.names = kept_names
		store.persist = kept_persist
		return
	var dev := NAME_PAD + 1
	lobby.join(dev, true)
	await frames(4)
	# A pad in seat 0 reloads the InputMap (set_ui_action_device), which drops a fake pad's clones.
	MultiplayerInput._create_actions_for_device(dev)
	var c = controls[0]
	var e = c.name_entry_selector
	var panel = c.get_node("CouchLobbyNamePanel")
	var list = func(x): return x.name_entry_selector.get_node_or_null("CouchLobbyNameList")
	ok("a join with names saved opens the list", list.call(c) != null)
	ok("while it shows the seat stays active, the letters and accept button hidden, the pad off the letters", e.active and not e.character_selectors.any(func(s2): return s2.visible) and not c.name_accept_button.visible and not e.is_joystick)
	ok("a join starts on the pencil", panel._lit == 0, panel._lit)
	ok("the list shows 5 rows and its arrows", list.call(c) != null and list.call(c).get_child_count() == 7, list.call(c).get_child_count() if list.call(c) else -1)
	await frames(2)
	await _list_shape(P, panel, list.call(c))
	# The A that opened the list (a join's, or B's way back here) is still down when it opens.
	_pad(dev, 0, true)
	await frames(2)
	c._on_name_confirmed("TMP")
	c.show_name_entry()
	await frames(4)
	_pad(dev, 0, false)
	await frames(3)
	ok("an A held as the list opens picks nothing", list.call(c) != null and not c.active and panel._lit == 0, [list.call(c) != null, c.active, panel._lit])
	await _tap(dev, 0)
	ok("A on the pencil shows the letters, the name not confirmed", list.call(c) == null and e.is_joystick and e.character_selectors[0].visible and not c.active)
	ok("and they start blank", P.shown_name(e) == "", P.shown_name(e))
	e.set_player_name("TMP")
	await _tap(dev, 0)
	ok("a second A confirms from the letters", c.active, c.player_name)
	c.show_name_entry()
	await frames(3)
	ok("B back from the outfit opens the list again, on the seat's own saved name", list.call(c) != null and panel._items[panel._lit] == "TMP", panel._items)
	for i in 3:
		await _tap(dev, 12, 1)
	ok("down steps through the names", panel._items[panel._lit] == "CCC", [panel._lit, panel._items])
	await _tap(dev, 0)
	ok("A on a name confirms it", c.active and c.player_name == "CCC", c.player_name)
	ok("and moves it to the top", store.names[0] == "CCC", store.names)
	c.show_name_entry()
	await frames(3)
	ok("back with B, the highlight is on the seat's own name", panel._items.size() > panel._lit and panel._items[panel._lit] == "CCC", panel._items)
	c._on_name_confirmed("CCC")
	await frames(2)
	ok("a name set directly closes the list and puts the letters back", list.call(c) == null and e.character_selectors[0].visible and e.is_joystick == c.is_joystick)

	var dev2 := dev + 1
	MultiplayerInput._create_actions_for_device(dev2)
	lobby.join(dev2, true)
	await frames(4)
	var c2 = controls[1]
	var p2 = c2.get_node("CouchLobbyNamePanel")
	await _tap(dev2, 12, 1)
	ok("a name another seat uses is skipped", store.names[0] == "CCC" and p2._items[p2._lit] == store.names[1], [store.names, p2._lit])
	var rows: Array = list.call(c2).get_children().filter(func(r): return r is Button) if list.call(c2) else []
	var taken: Array = rows.filter(func(r): return r.text == "CCC")
	ok("and shown dimmed", taken.size() == 1 and taken[0].self_modulate.a < 0.5 and taken[0].disabled, taken.map(func(r): return r.self_modulate.a))
	ok("a pad player's rows take no mouse", not rows.is_empty() and rows.all(func(r): return r.mouse_filter == Control.MOUSE_FILTER_IGNORE))
	if list.call(c2) and controls.size() > 2:
		var r0: Rect2 = list.call(c2).get_global_rect()
		var r1: Rect2 = controls[2].name_entry_selector.get_global_rect()
		ok("the list stays clear of the next seat's name box", not r0.intersects(r1), [r0, r1])
	lobby.leave(1)
	await frames(2)
	ok("leaving closes the list", list.call(c2) == null and c2.name_entry_selector.character_selectors[0].visible)

	lobby.join(-1, false)
	await frames(4)
	var kc = controls[1]
	ok("a keyboard player gets the list too", list.call(kc) != null)
	var krows: Array = list.call(kc).get_children().filter(func(r): return r is Button) if list.call(kc) else []
	ok("a keyboard player's rows take the mouse", not krows.is_empty() and krows.all(func(r): return r.mouse_filter == Control.MOUSE_FILTER_STOP))
	var aaa: Array = krows.filter(func(r): return r.text == "AAA")
	if aaa.size() == 1:
		aaa[0].pressed.emit()
		await frames(2)
	ok("a keyboard player's click picks the name", kc.active and kc.player_name == "AAA", kc.player_name)
	lobby.leave(1)
	lobby.leave(0)
	await frames(2)
	MultiplayerInput._delete_actions_for_device(dev)
	MultiplayerInput._delete_actions_for_device(dev2)
	store.names = kept_names
	store.persist = kept_persist

# As wide as the letters' row, names centred, the pencil a filled bar across it,
# the pencil itself 1:1 on screen at a whole scale of its art, as long as the bar's room allows.
func _list_shape(P: GDScript, panel, l: Control) -> void:
	if l == null:
		return
	var w: float = P.letters_width(panel.entry)
	ok("the list is as wide as the 7 letters' row (%.0f on the card)" % w, w > 0.0 and absf(l.size.x - w) < 0.5, [l.size.x, w])
	var rows: Array = l.get_children().filter(func(r): return r is Button)
	ok("the names are centred", rows.slice(1).all(func(r): return r.alignment == HORIZONTAL_ALIGNMENT_CENTER and absf(r.size.x - w) < 0.5))
	var bar: Button = rows[0] if not rows.is_empty() else null
	var fill = bar.get_theme_stylebox("normal") if bar else null
	ok("the pencil row is a filled bar across the list", bar != null and not bar.flat and fill is StyleBoxFlat and fill.bg_color == P.BAR_FILL and absf(bar.size.x - w) < 0.5 and absf(bar.size.y - P.BAR_HEIGHT) < 0.5, [bar.size if bar else null])
	var pens: Array = bar.find_children("*", "TextureRect", true, false) if bar else []
	ok("the bar has its pencil", pens.size() == 1)
	if pens.size() == 1:
		var t: TextureRect = pens[0]
		var tex: Vector2 = t.texture.get_size()
		var shown: Vector2 = t.get_global_rect().size
		var k: float = tex.y / panel._bare.get_height()
		var room: float = bar.get_global_rect().size.x - 2 * P.BAR_PAD
		ok("the pencil is 1:1 on screen at a whole scale (%.0fx), end to end within %d px" % [k, ceili(k)], absf(shown.x - tex.x) < 0.05 and absf(shown.y - tex.y) < 0.05 and absf(k - roundf(k)) < 0.001 and k >= 1.0 and tex.x <= room + 0.05 and room - tex.x < k, [shown, tex, room])
	var a: Image = P.pencil_of_length(panel._bare, 50)
	var same := true
	for y in a.get_height():
		for x in 10:
			same = same and a.get_pixel(x, y) == panel._bare.get_pixel(x, y) and a.get_pixel(a.get_width() - 1 - x, y) == panel._bare.get_pixel(panel._bare.get_width() - 1 - x, y)
		same = same and a.get_pixel(30, y) == panel._bare.get_pixel(P.SHAFT_FROM, y)
	ok("pencil_of_length: 50 long, the point and the end as drawn, the shaft repeated", a.get_width() == 50 and same, a.get_width())
	ok("pencil_scale: the largest whole scale that fits, 0 when none", P.pencil_scale(10, 32, 90) == 3 and P.pencil_scale(10, 22, 106) == 2 and P.pencil_scale(10, 22, 30) == 1 and P.pencil_scale(10, 9, 90) == 0)

# A name saved through the real presses shows in the list afterwards: a pad's A then B, a keyboard's
# Enter and Accept then its X key, and a seat that opened on its letters while nothing was saved.
func _name_saved_paths(lobby) -> void:
	say("step: a saved name shows afterwards")
	var store = _loader.registry("couch_lobby").get("names")
	if store == null or not MultiplayerInput.core_actions.has(&"right"):
		say("INFO no store or core actions, skipped")
		return
	var kept_names: Array = store.names.duplicate()
	var kept_persist: bool = store.persist
	store.persist = false
	store.names = []
	var controls: Array = lobby.local_lobby_player_controls
	var list = func(x): return x.name_entry_selector.get_node_or_null("CouchLobbyNameList")
	var dev := NAME_PAD + 3
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	var c = controls[0]
	var e = c.name_entry_selector
	say("INFO pad join, nothing saved: list %s, letters '%s'" % [list.call(c) != null, e.get_node("../CouchLobbyNamePanel").shown_name(e)])
	e.set_player_name("JO")
	await _tap(dev, JOY_BUTTON_A)
	ok("a pad's A on the letters confirms and saves", c.active and store.names.has("JO"), [c.active, c.player_name, store.names])
	await _tap(dev, JOY_BUTTON_B)
	ok("the pad's B back from the outfit opens the list with the name", list.call(c) != null and c.get_node("CouchLobbyNamePanel")._items.has("JO"), [list.call(c) != null, e.active, store.names])

	lobby.join(-1, false)
	await frames(4)
	var kc = controls[1]
	var ke = kc.name_entry_selector
	var kp = kc.get_node("CouchLobbyNamePanel")
	if list.call(kc) != null:
		kp._pick(0)
		await frames(2)
	ke.set_player_name("KB")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	await frames(2)
	enter = enter.duplicate()
	enter.pressed = false
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	await frames(2)
	ok("the keyboard's Enter on the letters confirms and saves", kc.active and store.names.has("KB"), [kc.active, store.names, get_viewport().gui_get_focus_owner()])
	kc.show_name_entry()
	await frames(3)
	if list.call(kc) != null:
		kp._pick(0)
		await frames(2)
	ke.set_player_name("KBB")
	kc.name_accept_button.pressed.emit()
	await frames(2)
	ok("the keyboard's Accept confirms and saves", kc.active and store.names.has("KBB"), [kc.active, store.names])
	_key(KEY_X, true)
	await frames(2)
	_key(KEY_X, false)
	await frames(3)
	ok("the keyboard's X key back from the outfit opens the list with the name", list.call(kc) != null and kp._items.has("KB"), [list.call(kc) != null, ke.active])
	lobby.leave(1)
	lobby.leave(0)
	await frames(2)
	MultiplayerInput._delete_actions_for_device(dev)
	store.names = kept_names
	store.persist = kept_persist

# Back on the name screen: a pad's X or the keyboard's X key takes the letters back to the
# list; a pad's X on the list, or on the letters with nothing saved, drops the player out.
func _name_back(lobby) -> void:
	say("step: back on the name screen")
	var store = _loader.registry("couch_lobby").get("names")
	if store == null:
		return
	var P: GDScript = load(_mod_dir("couch_lobby").path_join("name_panel.gd"))
	ok("back is a pad's X, the keyboard's X key, a GameCube pad's own B", P.back_action(true, &"") == &"action_3" and P.back_action(false, &"") == &"action_2" and P.back_action(true, &"action_2") == &"action_2")
	ok("back: the letters to the list, the list to dropped out (pads only), no list to dropped out", P.back_does(false, true, true) == "list" and P.back_does(false, true, false) == "list" and P.back_does(true, true, true) == "leave" and P.back_does(false, false, true) == "leave" and P.back_does(true, true, false) == "" and P.back_does(false, false, false) == "")
	if not MultiplayerInput.core_actions.has(&"right"):
		say("INFO no core actions, the presses are skipped")
		return
	var kept_names: Array = store.names.duplicate()
	var kept_persist: bool = store.persist
	store.persist = false
	store.names = ["AAA", "BBB"]
	var controls: Array = lobby.local_lobby_player_controls
	var list = func(x): return x.name_entry_selector.get_node_or_null("CouchLobbyNameList")
	var dev := NAME_PAD + 5
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	var c = controls[0]
	var e = c.name_entry_selector
	var panel = c.get_node("CouchLobbyNamePanel")
	ok("the panel marks its controls, so GameCube Controller Support's drop-out stands aside", c.has_meta(&"couch_lobby_name_back"))
	await _tap(dev, JOY_BUTTON_A)
	e.set_player_name("ZZ")
	ok("A on the pencil: the letters", list.call(c) == null and e.character_selectors[0].visible)
	_pad(dev, JOY_BUTTON_X, true)
	await frames(5)
	ok("X on the letters: back on the list, still seated, nothing confirmed", list.call(c) != null and lobby.player_data.has(0) and not c.active, [list.call(c) != null, lobby.player_data.keys(), c.active])
	ok("and the letters put back as they opened", P.shown_name(e) == "P1", P.shown_name(e))
	ok("the X held from the letters doesn't also drop out", lobby.player_data.has(0), lobby.player_data.keys())
	_pad(dev, JOY_BUTTON_X, false)
	await frames(3)
	await _tap(dev, JOY_BUTTON_B)
	ok("a pad's B on the list does nothing", lobby.player_data.has(0) and list.call(c) != null)
	await _tap(dev, JOY_BUTTON_X)
	ok("X on the list drops the player out", not lobby.player_data.has(0) and c.assigned_player_id == -1, lobby.player_data.keys())

	store.names = []
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	ok("nothing saved: straight to the letters", list.call(c) == null and e.character_selectors[0].visible)
	var dev2 := dev + 1
	MultiplayerInput._create_actions_for_device(dev2)
	lobby.join(dev2, true)
	await frames(4)
	var c2 = controls[1]
	c2.name_entry_selector.set_player_name("QQ")
	store.remember("NEW")
	await frames(2)
	ok("a name saved elsewhere: an untouched seat's letters switch to the list", list.call(c) != null)
	ok("a seat mid-typing stays on its letters", list.call(c2) == null and c2.name_entry_selector.character_selectors[0].visible)
	await _tap(dev2, JOY_BUTTON_X)
	ok("and its X takes it to the list", list.call(c2) != null and lobby.player_data.has(1), [list.call(c2) != null, lobby.player_data.keys()])
	await _tap(dev, JOY_BUTTON_A)
	ok("A on the pencil: seat 1 on its letters", list.call(c) == null and e.character_selectors[0].visible)
	store.remember("NEWER")
	await frames(2)
	ok("a name saved elsewhere leaves a seat that chose the pencil on its letters", list.call(c) == null and e.character_selectors[0].visible)
	lobby.leave(1)
	lobby.leave(0)
	await frames(2)
	store.names = []
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	# Seat 0's drop-out rebuilt the InputMap, so the fake pad's last X release reached no action.
	_pad(dev, JOY_BUTTON_X, false)
	await frames(2)
	await _tap(dev, JOY_BUTTON_X)
	ok("nothing saved: X on the letters drops out", not lobby.player_data.has(0), lobby.player_data.keys())
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	await frames(2)
	var arrows: Array = e.character_selectors.map(func(sel): return sel.cycle_previous_element.self_modulate.a + sel.cycle_next_element.self_modulate.a)
	ok("rejoined after dropping out from the first letter: arrows on the edited letter only", arrows[0] > 0.0 and arrows.filter(func(a): return a > 0.0).size() == 1, arrows)
	lobby.leave(0)
	await frames(2)

	# The owner's report: the pencil opened on the seat's last name instead of blank letters.
	store.names = ["AAA", "BBB"]
	lobby.join(dev, true)
	await frames(4)
	MultiplayerInput._create_actions_for_device(dev)
	_pad(dev, JOY_BUTTON_X, false)
	await frames(2)
	c._on_name_confirmed("AAA")
	c.show_name_entry()
	await frames(3)
	await _tap(dev, JOY_BUTTON_DPAD_UP, 1)
	await _tap(dev, JOY_BUTTON_A)
	ok("the pencil after a name: the letters start blank", list.call(c) == null and P.shown_name(e) == "" and e.active_selector_index == 0, [P.shown_name(e), e.active_selector_index])
	var shrink: float = c.get_global_transform().get_scale().y
	var letters_on_screen: int = P.ROW_FONT if shrink < 1.0 else P.LETTER_SIZE
	ok("the list and letters keep their on-screen size on this card (x%.2f)" % shrink, absf(panel.row_font * shrink - P.ROW_FONT) <= 0.5 and absf(panel.letter_font * shrink - letters_on_screen) <= 0.5, [panel.row_font, panel.letter_font, shrink])
	ok("letter_pitch: the owner's 11 at 18 unscaled; whole screen pixels at 0.7, 0.75, 0.8; never tighter", P.letter_pitch(18, 1.0) == 11 and P.letter_pitch(23, 0.7) == 20 and P.letter_pitch(23, 0.75) == 20 and P.letter_pitch(23, 0.8) == 20 and P.letter_pitch(20, 0.65) == 20 and P.letter_pitch(23, 0.65) == 22, [P.letter_pitch(18, 1.0), P.letter_pitch(23, 0.7), P.letter_pitch(23, 0.65)])
	MultiplayerInput._create_actions_for_device(dev2)
	store.names = []
	lobby.join(dev2, true)
	await frames(4)
	var e2 = controls[1].name_entry_selector
	e.set_player_name("WWWWWWW")
	e2.set_player_name("WWWWWWW")
	await frames(3)
	var r0 := _shown_rect(e)
	var r1 := _shown_rect(e2)
	ok("seven Ws on two neighbouring seats' letters don't touch", r0.end.x <= r1.position.x, [r0, r1])
	lobby.leave(1)
	lobby.leave(0)
	await frames(2)

	store.names = ["AAA"]
	lobby.join(-1, false)
	await frames(4)
	var kc = controls[0]
	var kp = kc.get_node("CouchLobbyNamePanel")
	ok("a keyboard join opens the list", list.call(kc) != null)
	await frames(2)
	kp._pick(0)
	await frames(2)
	_key(KEY_X, true)
	await frames(2)
	_key(KEY_X, false)
	await frames(3)
	ok("the keyboard's X key on the letters: back on the list", list.call(kc) != null and lobby.player_data.has(0))
	_key(KEY_X, true)
	await frames(2)
	_key(KEY_X, false)
	await frames(3)
	ok("the keyboard's X key on the list does nothing", list.call(kc) != null and lobby.player_data.has(0))
	lobby.leave(0)
	await frames(2)
	MultiplayerInput._delete_actions_for_device(dev)
	MultiplayerInput._delete_actions_for_device(dev2)
	store.names = kept_names
	store.persist = kept_persist

const MAIN_MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

# The saved names' page under the main menu's Options: Y twice or the mark clicked twice deletes, B backs out.
func _options_page() -> void:
	say("step: the saved names' Options page")
	var store = _loader.registry("couch_lobby").get("names")
	if store == null:
		return
	var kept_names: Array = store.names.duplicate()
	var kept_persist: bool = store.persist
	store.persist = false
	store.names = ["AAA", "BBB", "CCC"]
	Globals.splash_screen_viewed = true
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	await frames(30)
	await get_tree().create_timer(2.0).timeout
	var menu: Node = null
	var root := get_tree().current_scene
	for n in [root] + root.find_children("*", "Control", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("main_menu/scripts/main_menu.gd"):
			menu = n
	var helper: Node = menu.get_node_or_null("CouchLobbySavedNames") if menu else null
	ok("the main menu has the saved names' helper", helper != null)
	if helper == null:
		store.names = kept_names
		store.persist = kept_persist
		return
	var lang: Button = menu.options_language_button
	var row: Button = lang.get_parent().get_node_or_null("CouchLobbySavedNamesButton")
	ok("a Saved names row right after Language", row != null and row.get_index() == lang.get_index() + 1, row.get_index() if row else -1)
	ok("it reads Saved names in the game's language", row != null and row.text == helper.pick("Saved names", "已保存的名字", "已儲存的名字"), row.text if row else "")
	ok("Language's explicit down neighbour, if any, is the new row", lang.focus_neighbor_bottom.is_empty() or lang.get_node(lang.focus_neighbor_bottom) == row)
	menu.set_current_active_container(&"Options")
	await get_tree().create_timer(1.0).timeout
	row.pressed.emit()
	await frames(3)
	var page: Node = lang.get_parent().get_node_or_null("CouchLobbySavedNamesPage")
	ok("the row opens the page, the Options rows hidden", page != null and not lang.visible)
	if page == null:
		store.names = kept_names
		store.persist = kept_persist
		return
	ok("one row per saved name", ["AAA", "BBB", "CCC"].all(func(n): return page.find_child("Name_" + n, true, false) != null))
	var game_backs: int = helper._parked.size()
	ok("while it shows, the menu's own Back is on screen and closes the page", menu.current_back_button == menu.options_back_button and menu.options_back_button.is_visible_in_tree() and helper._parked.size() > 0)
	var bbb: Button = page.find_child("Name_BBB", true, false)
	bbb.grab_focus()
	await frames(1)
	await _menu_y()
	ok("a first Y marks the name and deletes nothing", store.names == ["AAA", "BBB", "CCC"] and bbb.text.contains(helper.pick("Y again: delete", "再按 Y 删除", "再按 Y 刪除")), bbb.text)
	await _menu_y()
	ok("a second Y deletes it", store.names == ["AAA", "CCC"], store.names)
	var f := get_viewport().gui_get_focus_owner()
	ok("the focus moves to the next name", f != null and f.name == "Name_CCC", f.name if f else null)
	var mark: Button = page.find_child("Delete_AAA", true, false)
	mark.pressed.emit()
	ok("one click on a mark deletes nothing", store.names == ["AAA", "CCC"])
	mark.pressed.emit()
	ok("a second click on it deletes the name", store.names == ["CCC"], store.names)
	await _menu_y()
	# The menu's own Back path: its _process presses current_back_button on action_3 (the C key here).
	_key(KEY_C, true)
	await frames(2)
	_key(KEY_C, false)
	await frames(2)
	ok("Back backs out: the page gone, Options back, the marked name kept", lang.get_parent().get_node_or_null("CouchLobbySavedNamesPage") == null and lang.visible and store.names == ["CCC"], store.names)
	ok("and the menu's own Back is restored, its connections back", menu.current_back_button == menu.options_back_button and menu.options_back_button.pressed.get_connections().size() == game_backs and menu.get("current_active_container") == &"Options", [menu.options_back_button.pressed.get_connections().size(), game_backs, menu.get("current_active_container")])
	store.names = []
	row.pressed.emit()
	await frames(3)
	page = lang.get_parent().get_node_or_null("CouchLobbySavedNamesPage")
	ok("with nothing saved the page says so", page != null and page.find_children("Name_*", "", true, false).is_empty())
	menu.current_back_button.pressed.emit()
	await frames(2)
	await _options_page_walk(menu, row, store)
	store.names = kept_names
	store.persist = kept_persist

# The page with more names than fit, walked with a pad's D-pad as a player does: every name in
# order and wholly in view, onto the menu's Back and back up, and Back's own neighbours restored.
func _options_page_walk(menu: Node, row: Button, store) -> void:
	var back: Button = menu.options_back_button
	var kept_top := back.focus_neighbor_top
	var kept_bottom := back.focus_neighbor_bottom
	store.names = ["AAAAA", "BB", "CCCC", "DDD", "EEEEEEE"]
	row.pressed.emit()
	await frames(4)
	var page: Node = row.get_parent().get_node_or_null("CouchLobbySavedNamesPage")
	var scroll: ScrollContainer = page.find_children("*", "ScrollContainer", true, false)[0] if page else null
	var list: Control = scroll.get_child(0) if scroll else null
	ok("5 names show whole, without a scroll", scroll != null and list.size.y <= scroll.size.y + 0.5, [list.size.y, scroll.size.y] if scroll else null)
	back.pressed.emit()
	await frames(2)
	var names: Array = []
	for i in 20:
		names.append("N%02d" % (i + 1))
	store.names = names
	# A pad press first, so the game counts a pad in use and the page gives it the focus itself.
	await _tap(0, JOY_BUTTON_DPAD_DOWN)
	await frames(2)
	row.pressed.emit()
	await frames(4)
	page = row.get_parent().get_node_or_null("CouchLobbySavedNamesPage")
	if page == null:
		ok("the page opens with 20 names", false)
		return
	var opened := get_viewport().gui_get_focus_owner()
	ok("with a pad in use, the page opens on the first name", GameManager.is_using_controller() and opened != null and opened.name == "Name_N01", [GameManager.is_using_controller(), opened.name if opened else null])
	scroll = page.find_children("*", "ScrollContainer", true, false)[0]
	var hint: Control = page.get_child(page.get_child_count() - 1)
	ok("the list and its hint end above Back", _drawn(hint).end.y <= _drawn(back).position.y, [_drawn(hint).end.y, _drawn(back).position.y])
	var bar := scroll.get_v_scroll_bar()
	var mark: Control = page.find_child("Delete_N01", true, false)
	ok("the scrollbar shows, clear of the marks", bar.is_visible_in_tree() and _drawn(bar).position.x >= _drawn(mark).end.x + 2.0, [_drawn(bar).position.x, _drawn(mark).end.x])
	var first: Button = page.find_child("Name_N01", true, false)
	first.grab_focus()
	await frames(3)
	var walked: Array = []
	var cut: Array = []
	var halves: Array = []
	for i in 20:
		var f := get_viewport().gui_get_focus_owner()
		walked.append(String(f.name) if f else "")
		var over := _outside(scroll, f) if f else 0.0
		if over > 1.0:
			cut.append("%s %.1f" % [f.name, over])
		halves.append_array(_half_rows(scroll))
		await _tap(0, JOY_BUTTON_DPAD_DOWN)
		await frames(2)
	var expect: Array = names.map(func(n): return "Name_" + n)
	ok("down walks every name in order", walked == expect, walked)
	ok("each focused name is wholly in view (px past the edge)", cut.is_empty(), cut)
	ok("no name shows cut at the list's top or bottom edge", halves.is_empty(), halves.slice(0, 6))
	ok("down from the last name reaches Back", get_viewport().gui_get_focus_owner() == back, get_viewport().gui_get_focus_owner())
	await _tap(0, JOY_BUTTON_DPAD_UP)
	await frames(2)
	var f2 := get_viewport().gui_get_focus_owner()
	ok("up from Back reaches the last name", f2 != null and f2.name == "Name_N20", f2.name if f2 else null)
	for i in 19:
		await _tap(0, JOY_BUTTON_DPAD_UP)
		await frames(2)
	f2 = get_viewport().gui_get_focus_owner()
	ok("up walks back to the first name, wholly in view", f2 != null and f2.name == "Name_N01" and _outside(scroll, f2) <= 1.0 and _half_rows(scroll).is_empty(), [f2.name if f2 else null, _half_rows(scroll)])
	await _tap(0, JOY_BUTTON_DPAD_UP)
	await frames(2)
	f2 = get_viewport().gui_get_focus_owner()
	ok("up from the first name wraps to Back, as Options' own first row does", f2 == back, f2)
	# A delete rebuilds the page: the chain is linked again, down to Back and back up.
	var n05: Button = page.find_child("Name_N05", true, false)
	n05.grab_focus()
	await frames(2)
	await _menu_y()
	await _menu_y()
	var f3 := get_viewport().gui_get_focus_owner()
	ok("a delete in the walk takes N05 and focuses N06", not store.names.has("N05") and f3 != null and f3.name == "Name_N06", [store.names.size(), f3.name if f3 else null])
	page = row.get_parent().get_node_or_null("CouchLobbySavedNamesPage")
	await _tap(0, JOY_BUTTON_DPAD_UP)
	await frames(2)
	f3 = get_viewport().gui_get_focus_owner()
	ok("after the delete, up from N06 is N04", f3 != null and f3.name == "Name_N04", f3.name if f3 else null)
	var last: Button = page.find_child("Name_N20", true, false)
	last.grab_focus()
	await frames(2)
	await _tap(0, JOY_BUTTON_DPAD_DOWN)
	await frames(2)
	ok("after the delete, down from the last name reaches Back", get_viewport().gui_get_focus_owner() == back, get_viewport().gui_get_focus_owner())
	await _tap(0, JOY_BUTTON_DPAD_UP)
	await frames(2)
	f3 = get_viewport().gui_get_focus_owner()
	ok("after the delete, up from Back is the last name", f3 != null and f3.name == "Name_N20", f3.name if f3 else null)
	back.pressed.emit()
	await frames(2)
	ok("closing the page restores Back's own neighbours", back.focus_neighbor_top == kept_top and back.focus_neighbor_bottom == kept_bottom, [back.focus_neighbor_top, back.focus_neighbor_bottom])

# How far, in px, a control reaches past the scroll's top or bottom edge.
func _outside(scroll: Control, c: Control) -> float:
	var s := _drawn(scroll)
	var r := _drawn(c)
	return maxf(maxf(s.position.y - r.position.y, r.end.y - s.end.y), 0.0)

# The list's rows that show only in part: more than 1 px in view and more than 1 px out of it.
func _half_rows(scroll: ScrollContainer) -> Array:
	var s := _drawn(scroll)
	var out: Array = []
	for line in scroll.get_child(0).get_children():
		var r := _drawn(line)
		var shown := minf(r.end.y, s.end.y) - maxf(r.position.y, s.position.y)
		if shown > 1.0 and shown < r.size.y - 1.0:
			out.append("%s %.0f/%.0f" % [line.get_child(0).name, shown, r.size.y])
	return out

# A control's rect as drawn: get_global_rect leaves out the menu's scale.
func _drawn(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)

# A name box's visible content: its letters, or its list.
func _shown_rect(e: Control) -> Rect2:
	var r := Rect2()
	for ch in e.get_children():
		if ch is Control and ch.visible:
			var cr: Rect2 = ch.get_global_rect()
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
	return r

func _key(physical: Key, down: bool) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = physical
	k.pressed = down
	Input.parse_input_event(k)
	Input.flush_buffered_events()

func _menu_y() -> void:
	_pad(0, JOY_BUTTON_Y, true)
	await frames(2)
	_pad(0, JOY_BUTTON_Y, false)
	await frames(2)

func _pad(device: int, button: int, down: bool) -> void:
	var b := InputEventJoypadButton.new()
	b.device = device
	b.button_index = button
	b.pressed = down
	Input.parse_input_event(b)
	Input.flush_buffered_events()

# A direction held past the game's 0.2 s cooldown repeats, and headless frames are slow: one frame for those.
func _tap(device: int, button: int, held := 2) -> void:
	_pad(device, button, true)
	await frames(held)
	_pad(device, button, false)
	await frames(3)

func _stick_right(device: int) -> void:
	for v in [1.0, 0.0]:
		var m := InputEventJoypadMotion.new()
		m.device = device
		m.axis = JOY_AXIS_LEFT_X
		m.axis_value = v
		Input.parse_input_event(m)
		Input.flush_buffered_events()
		await frames(2)

# The device -> glasses map sits under one key, so other keys never read as devices.
func _glasses_by_device() -> Dictionary:
	return _loader.registry("couch_lobby").get("glasses", {})

func _registry_layout() -> void:
	say("step: registry and the retired mod")
	var reg: Dictionary = _loader.registry("couch_lobby")
	ok("registry keeps the glasses map under \"glasses\"", reg.get("glasses") is Dictionary, reg.keys())
	ok("no device keys at the registry's top level", reg.keys().all(func(k): return k is String), reg.keys())
	var dir := _mod_dir("couch_lobby")
	var hosted: bool = _loader.get_node_or_null("couch_lobby") != null and _loader.get_node("couch_lobby").has_meta("mpml_dir")
	say("setup: couch_lobby %s" % ("hosted in " + dir.get_base_dir() if hosted else "in its own folder"))
	var main_script: GDScript = _loader.compile(dir.path_join("main.gd"))
	var mods_dir := dir.get_base_dir().get_base_dir() if hosted else dir.get_base_dir()
	ok("installed_folder finds couch_lobby by its mod.json", main_script.installed_folder(dir.get_base_dir(), "couch_lobby") == "couch_lobby")
	ok("no local_glasses mounted beside it (the runner parks a leftover)", main_script.installed_folder(mods_dir, "local_glasses") == "")
	if hosted:
		ok("no separate couch_lobby beside the bundle", main_script.installed_folder(mods_dir, "couch_lobby") == "")

# A mod's folder whether it has its own or sits inside Extended's bundle, where dir_of() knows nothing of it.
func _mod_dir(id: String) -> String:
	var node: Node = _loader.get_node_or_null(id)
	if node != null and node.has_meta("mpml_dir"):
		return node.get_meta("mpml_dir")
	return _loader.dir_of(id)

func _merged(P: GDScript) -> void:
	say("step: registry validation")
	var base := ["none", "a"]
	var m: Dictionary = P.merged(base, ["b", "", "none", "a", 3, "b", StringName("c")])
	ok("merged keeps only new names", m["list"] == ["none", "a", "b", "c"] and not m["ok"], m)
	ok("merged leaves the base alone", base == ["none", "a"], base)
	ok("merged: a missing key is fine", P.merged(base, null)["list"] == base and P.merged(base, null)["ok"])
	ok("merged: an empty list is fine", P.merged(base, [])["ok"])
	ok("merged: not a list is dropped", P.merged(base, "x")["list"] == base and not P.merged(base, "x")["ok"])

# More Cosmetics' diving helmet blocks glasses like the Maska. Its lobby
# stepper turns the game's step into the helmet before this picker runs, so the
# glasses are already off at the end of that frame.
func _diving_helmet(c, p) -> void:
	say("step: diving helmet")
	var a = c.customization_assigner
	a.assign_hat("xc_army_helmet")
	a.assign_glasses("sunglasses")
	await frames(1)
	c.active_element = c.hat_picker_element
	c.mouse_and_keyboard_direction = 1
	c.button_cooldown_timer = 0.0
	Input.action_press("action_1")
	await frames(1)
	ok("step lands on the diving helmet", str(a.get_assigned_hat()) == "xc_diving_helmet", a.get_assigned_hat())
	ok("glasses off in the same frame", p.get_assigned_glasses() == "none", p.get_assigned_glasses())
	Input.action_release("action_1")
	await frames(1)
	c.active_element = null
	p.change_glasses(1)
	ok("diving helmet blocks glasses", p.get_assigned_glasses() == "none", p.get_assigned_glasses())
	ok("row dimmed under the diving helmet", p.glasses_row.modulate.a < 1.0, p.glasses_row.modulate.a)
	a.assign_hat("none")
	await frames(1)
	a.assign_glasses("xc_monocle_glasses")
	ok("our glasses read back", p.get_assigned_glasses() == "xc_monocle_glasses", p.get_assigned_glasses())
	a.assign_hat("drill_sgt_hat")
	a.assign_glasses("sunglasses")
	await frames(1)
