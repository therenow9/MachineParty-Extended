extends Node

# Dev-only acceptance test of the fork's local split-screen HUD, through Overtime's own code:
# the device list past the lobby, and the name tags of the three minigames that draw one.
# 8 Player Support draws no device list (D76): there the same reconnect steps are read from each
# seat's status text. On stock Overtime 1.7 it fails by design.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const PRESENCE := "res://modules/player_presence/player_presence.tscn"
const CANVAS := Vector2(1920, 1080)
# Seat 8's name is wider than its tile even at Knife at the Office's 16 px, so only the trim keeps it inside.
const NAMES := ["JERM", "ALEX", "SAM", "MAYA", "LEO", "ZOEY", "WWWW", "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"]
const HANDLERS := [
	["chisel gauntlet", "res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet_local_handler.gd",
		"res://minigames/chisel_gauntlet_multiplayer/components/player/chisel_gauntlet_player.tscn"],
	["burn recycle", "res://minigames/burn_recycle/scripts/burn_recycle_local_handler.gd",
		"res://minigames/burn_recycle/components/player/burn_recycle_player.tscn"],
	["knife at the office", "res://minigames/knife_at_the_office/scripts/knife_at_the_office_local_handler.gd",
		"res://minigames/knife_at_the_office/components/player/knife_at_the_office_player.tscn"],
]

var fails := 0
var out: FileAccess
var mp8 := false

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_hud/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func frames(k: int) -> void:
	for i in k: await get_tree().process_frame

func _mod_ready(loader) -> void:
	mp8 = loader.has_mod("mp8_support")
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	for h in HANDLERS:
		await _tags(h[0], h[1], h[2])
	await _device_list()
	finish()

# Each handler laid out for 8 pads on a 1920x1080 canvas, as its minigame calls it.
func _tags(label: String, handler_path: String, player_path: String) -> void:
	say("step: %s tags" % label)
	var canvas := CanvasLayer.new()
	get_tree().root.add_child(canvas)
	var area := Control.new()
	area.size = CANVAS
	canvas.add_child(area)
	var post := Control.new()
	post.size = CANVAS
	canvas.add_child(post)
	var handler: Node = load(handler_path).new()
	handler.local_canvas_root = area
	handler.local_after_post_processing_root = post
	get_tree().root.add_child(handler)

	var scene: PackedScene = load(player_path)
	var players: Array = []
	for i in 8:
		var p: Node = scene.instantiate()
		var pres: Node = (load(PRESENCE) as PackedScene).instantiate()
		pres.network_name = NAMES[i]
		pres.using_joystick = true
		pres.device_id = 100 + i
		pres.set_meta("mp8_local_seat", i)
		p.player_presence = pres
		get_tree().root.add_child(p)
		players.append(p)
	await frames(3)
	var typed := Array([], TYPE_OBJECT, StringName(players[0].get_class()), players[0].get_script())
	typed.assign(players)
	handler.set_players(typed)
	await frames(3)

	for i in 8:
		var tile: Rect2 = handler.texture_rects[i].get_global_rect()
		var tag: Label
		if "overlay_templates" in handler:
			tag = handler.overlay_templates[players[i]].name_label
		else:
			tag = handler.vignette_color_rects[players[i]].get_child(0)
		var r := tag.get_global_rect()
		ok("%s P%d tag is the name only" % [label, i + 1], tag.text == NAMES[i], tag.text)
		# Bottom left keeps the tag off what sits at the bottom centre (Chisel Gauntlet's cube).
		ok("%s P%d tag at the left" % [label, i + 1],
			tag.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and r.position.x < tile.position.x + 24.0, [tag.horizontal_alignment, r.position.x, tile.position.x])
		ok("%s P%d tag trims long names" % [label, i + 1], tag.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, tag.text_overrun_behavior)
		ok("%s P%d tag inside its screen" % [label, i + 1], tile.grow(0.5).encloses(r), "%s in %s" % [r, tile])
		if i == 7:
			var wide := tag.get_theme_font("font").get_string_size(NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, tag.get_theme_font_size("font_size")).x
			ok("%s seat 8's name is wider than its screen" % label, wide > tile.size.x, [wide, tile.size.x])
		ok("%s P%d tag at the bottom" % [label, i + 1],
			tag.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM and r.end.y > tile.end.y - 24.0, [tag.vertical_alignment, r.end.y, tile.end.y])

	handler.queue_free()
	canvas.queue_free()
	for p in players:
		p.player_presence.free()
		p.queue_free()
	await frames(3)

# Headless no pad is connected, so the pad seats really are waiting on their pads and the keyboard seat is not.
func _device_list() -> void:
	say("step: device list past the lobby")
	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	var lobby := get_tree().current_scene
	var controls: Array = lobby.local_lobby_player_controls
	lobby.join(-1, false)
	for i in range(1, 8):
		lobby.join(100 + i, true)
	await frames(10)
	for i in 8:
		controls[i]._on_name_confirmed(NAMES[i])
	lobby.update_player_manager()
	GameManager.local_game = true
	GameManager.local_game_data = lobby.player_data
	get_tree().change_scene_to_file("res://scenes/local_game/local_game.tscn")
	await frames(10)
	var game := get_tree().current_scene
	say("scene: " + str(game.name))
	var labels = game.get("_mp8_device_labels")
	if mp8:
		ok("no device list (8 Player Support)", labels == null, labels)
		labels = null
	else:
		ok("one status row per seat", labels is Dictionary and labels.size() == 8, labels.size() if labels is Dictionary else labels)
		if not labels is Dictionary:
			return
	ok("keyboard seat not listed", not _seat(labels, -1)[0], _seat(labels, -1)[1])
	for i in range(1, 8):
		var s = _seat(labels, 100 + i)
		ok("pad seat %d listed while its pad is away" % (i + 1), s[0] and "DISCONNECTED" in s[1], s[1])

	# Seat 2's pad comes back: listed until confirmed, then gone once A is released.
	var pres = PlayerManager.player_presences.get(101)
	if pres == null or (labels != null and labels.get(101) == null):
		ok("seat 2 presence and row exist", false)
		return
	pres._on_joy_connection_changed(101, true)
	await frames(2)
	ok("replugged pad listed until confirmed", _seat(labels, 101)[0] and "confirm" in _seat(labels, 101)[1], _seat(labels, 101)[1])
	ok("confirm accepted", pres.mp8_confirm_local_device(101))
	# The fork's row is refreshed in local_game's _process, a frame later. A seat's own status is
	# current, and headless A is never held, so the next physics tick already resumes the seat.
	if labels != null:
		await frames(1)
	ok("confirmed pad listed until A is released", _seat(labels, 101)[0] and "release" in _seat(labels, 101)[1], _seat(labels, 101)[1])
	# Offline Bots' update_player_manager never adds the presences to the tree, so the release is never seen there.
	if not pres.is_inside_tree():
		say("NOTE presence outside the tree (Offline Bots' lobby override): the resume step can't run; docs/issues.md inbox")
	else:
		for i in 3: await get_tree().physics_frame
		await frames(2)
		ok("resumed pad no longer listed", pres.local_controller_connected and not _seat(labels, 101)[0], _seat(labels, 101)[1])
	ok("other pad seats still listed", range(2, 8).all(func(i): return _seat(labels, 100 + i)[0]))

# [listed, text] for a seat: the fork's device-list row, or with no list (8 Player Support)
# whether the seat's pad is away and its status text.
func _seat(labels, device: int) -> Array:
	if labels is Dictionary:
		var l: Label = labels.get(device)
		return [l != null and l.visible, l.text if l != null else "missing"]
	var p = PlayerManager.player_presences.get(device)
	if p == null:
		return [false, "missing"]
	return [not p.local_controller_connected, p.mp8_local_status_text()]
