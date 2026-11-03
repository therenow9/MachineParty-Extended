extends Node

# Dev-only headless regression test for couch_lobby (its glasses row, folded in
# from Local Glasses). See README. Works with other mods installed (seat count /
# layout checks adapt).

const VANILLA_GLASSES := ["none", "sunglasses", "reading_glasses"]
# More Cosmetics' ids, which it never renames; its registry publishes them here.
const XC_GLASSES := ["xc_disguise_glasses", "xc_cyclops_glasses", "xc_monocle_glasses", "xc_eyepatch_glasses",
	"xc_tanning_glasses", "xc_scuba_glasses"]

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
	finish()

# PD12: a player who leaves seat 0 and joins again takes it back, comes first in the
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

# A mod's folder whether it has its own or sits inside Extended's bundle (D157), where dir_of() knows nothing of it.
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
