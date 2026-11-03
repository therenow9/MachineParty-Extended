extends Node

# Dev-only and windowed, beside a cl_playtest launch on 8 Player Support (7 bots, 8 seats):
# renders for roadmap steps 9 and 10, today's look and each candidate, applied to the live game.
#   MP8_RENDER=duckhunt[:1]            Duck Hunt's two hunter tiles (":1": one hunter, for 2-5 players): MAG/RATE,
#                                      the look-speed prompt, the seat list
#   MP8_RENDER=intro[:<layout>]        the session intro, not skipped; layout squeeze|half|neighbour|compact|decker|stack;
#                                      MP8_LIGHT=<energy>, MP8_VIEW=down,back[,right] and MP8_SWEEP=1 tune decker and stack;
#                                      MP8_PACE=<s> previews a pace per insert,
#                                      MP8_BEEP=semitone|major|whole a name-tag beep rising per tube
#   MP8_RENDER=intro:outro              the build's own intro, then the session end's camera move over the rack
#   MP8_RENDER=intro:dump               the same, and the rack panel and every mesh over its slot block to panel.json
#   MP8_RENDER=intro:explore            the same, and at the 5th insert the camera pulled back and panned, the racks logged
#   MP8_RENDER=snap[:<every s>[:<count>]]  a shot every 1.5 s (40 shots) from the first minigame's load;
#                                      MP8_LOCALE=EN|ZHS|ZHT sets the game's language then, MP8_TAG=<x> names the folder
#   MP8_RENDER=text                    Duck Hunt (8 players): the online role reveal for one, two and two long names,
#                                      and the shouts, in the game's EN then ZHS
#   MP8_RENDER=refusal[:<wait s>]      alone (run_selftest.sh mp8_render --windowed --overtime=mp8): each refusal dialog on the main
#                                      menu, EN then ZHS, then quits
#   MP8_RENDER=title[:<wait s>]        alone, like refusal: the main menu without the splash, then each candidate of
#                                      tools/make_title.py (MP8_TITLE_ART=<folder>, default %TEMP%/.../title_art) placed
#                                      just after the logo, one shot each, then quits
#   MP8_RENDER=fade                    Debris Platforms (run_playtest.sh launch JunkPlatform --local, 8 seats): 3 s into
#                                      play the two front decks collapse; shots before, 0.3 s after (slammed) and 1.5 s
#                                      and 4 s after (faded), each press's transparency logged; again in round 2, then quits.
#                                      MP_GAME_ARGS="mp8junkfade=<opacity>" picks the candidate (a -test build only),
#                                      MP8_TAG names it
# Shots and result.txt go to %TEMP%/machine-party-tests/mp8_render/<mode>/. The launch ends the run.

const HUNTER_SCRIPT := "hunter_player.gd"
const DUCK_SCRIPT := "minigames/duck_hunt/scripts/duck_hunt.gd"
const DIALOG_SCRIPT := "dialog_message_handler.gd"
const INTRO_SCRIPT := "intermission_cutscene_intro.gd"
const MAIN_MENU_SCRIPT := "scenes/main_menu/scripts/main_menu.gd"
const LOCAL_GAME := "res://scenes/local_game/local_game.tscn"
const LB := "hires/controller_left_shoulder_button_wide_2x.png"
const RB := "hires/controller_right_shoulder_button_wide_2x.png"
const LAYOUTS := ["squeeze", "half", "neighbour"]
const BUILT := ["compact", "decker", "stack"]
# The slot block is separate nodes under intermission intro2: a backing (holes baked in), and per bar a
# housing, a screen and a lamp; the sockets are fake vessel parent/real vessel0-3.
const BACKING := "Cube_003"
const BARS := [["Cube_002", "Cube_004", "Cube_005"], ["Cube_006", "Cube_007", "Cube_008"],
	["Cube_009", "Cube_010", "Cube_011"], ["Cube_012", "Cube_013", "Cube_014"]]
const FRONT_X := 0.579
const DECK_DROP := 1.13
const DECK_WIDE := 1.6
const STACK_SCALE := 0.7
const STACK_GAP := 0.02
const INSERT_ANIM := 1.65

var _fill: OmniLight3D = null
# The slot block's centre (tags and sockets, from the explore log) and half its width.
const HALF_CENTER := Vector3(0.75, 2.55, 0.0)
const HALF_SHIFT := 0.585

var _loader
var _mode := ""
var _rack := ""
var _tags := ""
var _dir := ""
var _out: FileAccess
var _hunters: Array = []
var _intro: Node = null
var _busy := false
var _done := false
var _duck: Node = null
var _dialog: Node = null
var _menu: Node = null
var _snap_t := -1.0
var _snaps := 0
var _junk: Node = null
var _junk_round := 0

func say(msg: String) -> void:
	if _out == null:
		_out = FileAccess.open(_dir.path_join("result.txt"), FileAccess.WRITE)
	_out.store_line(msg)
	_out.flush()

func _mod_ready(loader) -> void:
	_loader = loader
	process_priority = 1000
	var parts := OS.get_environment("MP8_RENDER").split(":")
	_mode = parts[0]
	if parts.size() >= 3:
		_rack = parts[1]
		_tags = parts[2]
	elif parts.size() == 2:
		_rack = parts[1]
	var name := _mode if _rack == "" else "%s_%s" % [_mode, ":".join(parts.slice(1)).replace(":", "_")]
	if OS.get_environment("MP8_TAG") != "":
		name += "_" + OS.get_environment("MP8_TAG")
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/mp8_render").path_join(name)
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().node_added.connect(_on_node_added)
	say("mp8_render %s" % name)
	if _mode == "title":
		Globals.splash_screen_viewed = true

func _on_node_added(node: Node) -> void:
	if node.scene_file_path == LOCAL_GAME and _mode == "intro":
		Globals.skipping_intro_cutscene = false
		say("intro not skipped")
	if _mode == "fade" and node is Minigame and "junk_handler" in node:
		_junk = node
	if _mode == "snap" and node is Minigame and _snap_t < 0.0:
		_snap_t = 0.0
		say("snap from %s" % node.name)
		if OS.get_environment("MP8_LOCALE") != "":
			TranslationServer.set_locale(OS.get_environment("MP8_LOCALE"))
	var s = node.get_script()
	if s == null:
		return
	var path: String = s.resource_path
	if path.ends_with(DUCK_SCRIPT) and _mode == "text":
		_duck = node
	elif path.ends_with(MAIN_MENU_SCRIPT) and _mode == "title":
		_menu = node
	elif path.ends_with(DIALOG_SCRIPT) and _mode == "refusal":
		_dialog = node
	elif path.ends_with(HUNTER_SCRIPT) and _mode == "duckhunt":
		_hunters.append(node)
	elif path.ends_with(INTRO_SCRIPT) and _mode == "intro":
		_intro = node
		node.ready.connect(_on_intro_ready, CONNECT_ONE_SHOT)

func _process(delta: float) -> void:
	_pace(delta)
	_beep()
	if _busy or _done:
		return
	if _mode == "intro" and is_instance_valid(_intro) and _rack in ["neighbour", "decker", "stack"]:
		_pan(_intro.vessel_to_insert_index)
	if _mode == "fade" and is_instance_valid(_junk) and _junk.is_inside_tree() and _junk.junk_handler.active:
		_busy = true
		_fade.call_deferred()
	if _mode == "duckhunt" and _hunters_ready():
		_busy = true
		_duck_hunt.call_deferred()
	if _mode == "snap" and _snap_t >= 0.0:
		_snap_t += delta
		var every := float(_rack) if _rack != "" else 1.5
		if _snap_t >= every:
			_snap_t = 0.0
			_busy = true
			_snap.call_deferred()
	# The shouts are forced after the real countdown, so it can't overwrite them.
	if _mode == "text" and is_instance_valid(_duck) and _duck.minigame_overlay != null \
			and _duck.minigame_overlay.mp8_go_text != "" \
			and _duck.minigame_overlay.countdown_label.text == _duck.minigame_overlay.mp8_go_text:
		_busy = true
		_text.call_deferred()
	if _mode == "refusal" and is_instance_valid(_dialog) and _dialog.is_inside_tree():
		_busy = true
		_refusal.call_deferred()
	if _mode == "title" and is_instance_valid(_menu) and _menu.is_inside_tree():
		_busy = true
		_title.call_deferred()

func _snap() -> void:
	await shot("snap_%02d" % _snaps)
	_snaps += 1
	_done = _snaps >= (int(_tags) if _tags != "" else 40)
	if _done:
		say("DONE")
	_busy = false

func _fade() -> void:
	var mg := _junk
	_junk = null
	_junk_round += 1
	await _wait(3.0)
	var decks: Array = mg.platforms.duplicate()
	decks.sort_custom(func(a, b): return a.global_position.z > b.global_position.z)
	var tag := "r%d" % _junk_round
	_log_presses(mg, tag + " before")
	await shot(tag + "_0_before")
	for d in decks.slice(0, 2):
		say("collapse deck at %s, frame %d" % [d.global_position, Engine.get_process_frames()])
		d.collapse_rpc.rpc()
	await _wait(0.3)
	await shot(tag + "_1_slammed")
	await _wait(1.2)
	await shot(tag + "_2_faded")
	await _wait(2.5)
	await shot(tag + "_3_later")
	_log_presses(mg, tag + " after")
	if _junk_round >= 2:
		say("DONE")
		_done = true
		get_tree().quit()
	_busy = false

# Every compactor's drawn meshes and their transparency, the sparks left out.
func _log_presses(mg: Node, when: String) -> void:
	var parts: PackedStringArray = []
	for c in mg.find_children("*", "JunkPlatformCompactor", true, false):
		var geo: Array = c.find_children("*", "GeometryInstance3D", true, false)
		geo.append(c)
		var ts: PackedStringArray = []
		for g in geo:
			if not g is GPUParticles3D:
				ts.append("%.2f" % g.transparency)
		parts.append("%s(y %.1f)=%s" % [c.name, c.global_position.y, ",".join(ts)])
	say("presses %s: %s" % [when, " ".join(parts)])

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _text() -> void:
	var locale := TranslationServer.get_locale()
	await _wait(3.0)
	await shot("tiles")
	for loc in ["EN", "ZHS"]:
		TranslationServer.set_locale(loc)
		await _reveals(loc)
		await _shouts(loc)
	TranslationServer.set_locale(locale)
	_done = true
	say("DONE")

# reveal_online()'s text, which a local game never shows: role_canvas is the online screen.
# "long" is two 11-character names, the most the game shows.
func _reveals(loc: String) -> void:
	var names: Array = _duck.mp8_hunter_names.duplicate()
	say("hunters %s, %d players" % [names, _duck.mp8_total_players])
	_duck.role_canvas.visible = true
	_duck.ui_overlay.modulate.a = 1.0
	for c in [["one", names.slice(0, 1)], ["two", names.slice(0, 2)], ["long", ["ABCDEFGHIJK", "LMNOPQRSTUV"]]]:
		_duck.mp8_hunter_names = c[1]
		_duck.ui_role_label.text = _duck.mp8_hunters_line()
		_duck.ui_role_label.modulate.a = 1.0
		await shot("reveal_%s_%s" % [c[0], loc])
	_duck.mp8_hunter_names = names
	_duck.ui_overlay.modulate.a = 0.0
	_duck.role_canvas.visible = false

func _shouts(loc: String) -> void:
	var ov = _duck.minigame_overlay
	var names: Array = _duck.mp8_hunter_names.duplicate()
	var total: int = _duck.mp8_total_players
	var hunter: bool = _duck.is_hunter
	for c in [["normal", 8, 2], ["lone", 7, 1]]:
		_duck.mp8_total_players = c[1]
		_duck.mp8_hunter_names = names.slice(0, c[2])
		for role in [true, false]:
			_duck.is_hunter = role
			_duck._mp8_setup_countdown()
			if c[0] == "lone" and role:
				ov.set_countdown("1")
				await _wait(0.5)
				await shot("one_lone_%s" % loc)
			ov.set_countdown("GO!")
			await _wait(0.5)
			await shot("go_%s_%s_%s" % [c[0], "hunter" if role else "duck", loc])
	_duck.mp8_hunter_names = names
	_duck.mp8_total_players = total
	_duck.is_hunter = hunter
	_duck._mp8_setup_countdown()
	await _wait(1.5)

func _refusal() -> void:
	var locale := TranslationServer.get_locale()
	# The dialog's node is in the tree during the studio intro, before the menu shows.
	await _wait(float(_rack) if _rack != "" else 20.0)
	var nm = NetworkManager
	var mine: String = nm.mp8_full_version()
	# "roomfull" is the MP8RoomFull dialog (lobby_scene.gd), not a version case.
	var cases := [["unreported", ""], ["same", mine], ["base", "v9.9.9+" + nm._mp8_tag_of(mine)],
		["differ", nm._mp8_base_of(mine) + "+mp8-0.23"], ["roomfull", ""]]
	for loc in ["EN", "ZHS"]:
		TranslationServer.set_locale(loc)
		for c in cases:
			nm._mp8_host_version = c[1]
			GameManager.main_menu_dialog_message = nm.MP8_ROOM_FULL_TEXT if c[0] == "roomfull" else nm.mp8_mismatch_text()
			_dialog.check_for_message()
			await _wait(1.0)
			await shot("refusal_%s_%s" % [c[0], loc])
		say("host notice %s: %s" % [loc, nm._mp8_blocked_text_for_host(nm._mp8_base_of(mine) + "+mp8-0.21")])
	nm._mp8_host_version = ""
	_dialog.root.visible = false
	TranslationServer.set_locale(locale)
	_done = true
	say("DONE")
	get_tree().quit()

func _title() -> void:
	await _wait(float(_rack) if _rack != "" else 6.0)
	var logo: Control = _menu.find_child("logo", true, false)
	say("viewport %s, logo %s scale %s" % [get_viewport().get_visible_rect().size, logo.get_global_rect(), logo.scale])
	for b in [_menu.start_button, _menu.exit_button]:
		say("button %s %s" % [b.name, b.get_global_rect()])
	await shot("title_stock")
	var dir := OS.get_environment("MP8_TITLE_ART")
	if dir == "":
		dir = OS.get_environment("TEMP").path_join("machine-party-tests/title_art")
	var cands = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("candidates.json")))
	if typeof(cands) != TYPE_ARRAY:
		say("FAIL no candidates in " + dir)
		cands = []
	for c in cands:
		var node: Control
		if c.has("file"):
			var rect := TextureRect.new()
			rect.texture = ImageTexture.create_from_image(Image.load_from_file(dir.path_join(c["file"])))
			rect.scale = Vector2(c["scale"], c["scale"])
			node = rect
		else:
			var label := Label.new()
			label.text = c["text"]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_override("font", load("res://fonts/Terminal F4.ttf"))
			label.add_theme_font_size_override("font_size", int(c["font_size"]))
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_x", 0)
			label.add_theme_constant_override("shadow_offset_y", maxi(1, int(c["font_size"]) / 12))
			node = label
		node.name = "mp8_extended"
		logo.get_parent().add_child(node)
		logo.get_parent().move_child(node, logo.get_index() + 1)
		await get_tree().process_frame
		var size := node.size
		node.pivot_offset = size / 2
		node.position = Vector2(c["centre"][0], c["centre"][1]) - size / 2
		node.rotation_degrees = c["rot"]
		await shot("title_" + c["name"])
		say("  %s at %s, drawn %s" % [c["name"], node.position, node.get_global_rect()])
		node.queue_free()
		await get_tree().process_frame
	_done = true
	say("DONE")
	get_tree().quit()

func _hunters_ready() -> bool:
	_hunters = _hunters.filter(func(h): return is_instance_valid(h) and h.is_inside_tree())
	if _hunters.size() < (1 if _rack == "1" else 2):
		return false
	for h in _hunters:
		if h.player_presence == null or not (h.hud.get_parent() is SubViewport) or h.get("_mp8_id_label") == null:
			return false
	return true

func shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	if _mode == "duckhunt":
		# Offline Bots hides a bot hunter's tile HUD (bot_ai.gd _drive_duck_hunter); a human hunter keeps it.
		for h in _hunters:
			if is_instance_valid(h):
				h.hud.visible = true
		_diag()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
	say("shot " + name)

func _duck_hunt() -> void:
	say("hunters %d, window %s" % [_hunters.size(), get_viewport().get_visible_rect().size])
	for h in _hunters:
		var vp: SubViewport = h.hud.get_parent()
		say("hunter %s tile %s, MAG/RATE layer parent %s" % [h.player_presence.network_name, vp.size, h._mp8_id_label.get_parent().get_parent().name])
	for i in 10:
		await shot("spawn_%02d" % i)
		await get_tree().create_timer(1.0).timeout
	await _prompts()
	await _mag_rate()
	await _seat_list()
	_done = true
	say("DONE")

# Why a shot of a tile can come out blank: the HUD's state as the shot is taken.
func _diag() -> void:
	for h in _hunters:
		if not is_instance_valid(h):
			say("  hunter freed")
			continue
		var sp: Control = h.hud.get_node_or_null("sensitivity prompt")
		var lbl: Control = h._mp8_id_label
		say("  %s hud visible=%s in=%s | prompt in_tree_visible=%s alpha=%.2f rect=%s | label in_tree_visible=%s rect=%s" % [
			h.player_presence.network_name, h.hud.visible, h.hud.get_parent().name,
			sp.is_visible_in_tree() if sp else "none", sp.modulate.a if sp else -1.0, sp.get_global_rect() if sp else "",
			lbl.is_visible_in_tree(), lbl.get_global_rect()])

func _seat_list() -> void:
	var game := get_tree().current_scene
	var labels = game.get("_mp8_device_labels") if game != null else null
	if not (labels is Dictionary) or labels.is_empty():
		say("no seat list")
		return
	var column: Node = (labels.values()[0] as Node).get_parent()
	var home: Node = column.get_parent()
	var layer := CanvasLayer.new()
	layer.layer = 128
	get_tree().root.add_child(layer)
	column.reparent(layer, false)
	await get_tree().process_frame
	say("seat column %s visible_in_tree=%s" % [column.get_global_rect(), column.is_visible_in_tree()])
	for l in labels.values():
		say("seat row visible=%s rect=%s %s" % [l.visible, l.get_global_rect(), l.text])
	await shot("seats_today")
	column.reparent(home, false)
	layer.queue_free()
	# Candidate: the away seat's line in its own tile, under the tile's name tag.
	var tile_rows: Array = []
	for h in _hunters:
		var presence = h.player_presence
		if presence.local_controller_connected:
			continue
		var row := Label.new()
		row.text = presence.mp8_local_status_text()
		row.position = Vector2(8, 26)
		row.add_theme_font_override("font", load("res://fonts/Terminal F4.ttf"))
		row.add_theme_font_size_override("font_size", 16)
		row.add_theme_color_override("font_outline_color", Color.BLACK)
		row.add_theme_constant_override("outline_size", 4)
		row.modulate = Color(1.0, 0.55, 0.2)
		h.hud.add_child(row)
		tile_rows.append(row)
	await shot("seats_in_tile")
	for row in tile_rows:
		row.queue_free()

func _mag_rate() -> void:
	await shot("mag_today")
	for h in _hunters:
		h._mp8_id_label.reparent(h.hud, false)
	for size in [26, 18, 14]:
		for h in _hunters:
			var lbl: RichTextLabel = h._mp8_id_label
			lbl.add_theme_font_size_override("normal_font_size", size)
			lbl.offset_left = -16.0 - size * 12.0
		await shot("mag_tile_%d" % size)
	for h in _hunters:
		var lbl: RichTextLabel = h._mp8_id_label
		lbl.text = lbl.text.replace("\n", "  ")
		lbl.offset_left = -16.0 - 14 * 24.0
	await shot("mag_tile_14_oneline")
	for h in _hunters:
		h._mp8_id_label.visible = false
	await shot("mag_none")

func _prompts() -> void:
	var api = _loader.registry("gamecube_support").get("api")
	for h in _hunters:
		h.checking_to_hide_sens_prompt = false
		h.sens_prompt_counting = false
		h.sens_prompt_full.visible = true
		h.sensitivity_prompt_parent.visible = true
		h.sens_prompt_slider_only.visible = false
		h.keyboard_sensitivity_prompt.visible = false
		h.controller_sensitivity_prompt.visible = true
		h.anim_sensitivity_prompt.play("show")
	await get_tree().create_timer(1.0).timeout
	for scale in [1.0, 0.6, 0.5, 0.45, 0.4]:
		for h in _hunters:
			h.hud.get_node("sensitivity prompt").scale = Vector2(scale, scale)
		await shot("prompt_%d" % int(scale * 100))
	if api == null or api.swapper == null:
		say("no gamecube_support api")
		return
	var glyphs: Dictionary = api.swapper.glyphs.get(api.config["art"], {})
	for h in _hunters:
		for r in h.controller_sensitivity_prompt.find_children("*", "TextureRect", true, false):
			if r.texture == api.swapper.proxies.get(LB):
				r.texture = glyphs.get("Dpad_left_wide", r.texture)
			elif r.texture == api.swapper.proxies.get(RB):
				r.texture = glyphs.get("Dpad_right_wide", r.texture)
	for scale in [0.6, 0.5, 0.45, 0.4]:
		for h in _hunters:
			h.hud.get_node("sensitivity prompt").scale = Vector2(scale, scale)
		await shot("prompt_gc_%d" % int(scale * 100))
	for h in _hunters:
		h.sens_prompt_full.visible = false
		h.sens_prompt_slider_only.visible = true
	await shot("prompt_gc_50_slider_and_buttons")
	for h in _hunters:
		h.sensitivity_prompt_parent.visible = false
	await shot("prompt_slider_only_40")

# ready fires while the intermission scene still adds its children, which refuses add_child there.
func _on_intro_ready() -> void:
	await get_tree().process_frame
	say("intro ready: %d vessels, %d hand positions, %d tags; %d players" % [
		_intro.vessels_in_main_rack.size(), _intro.hand_armature_parent_position_by_rack_index.size(),
		_intro.rack_nametags.size(), PlayerManager.player_presences.size()])
	if _rack == "dump":
		_dump(_intro.get_parent())
	if _rack in LAYOUTS:
		_extend(_intro, PlayerManager.player_presences.size())
	elif _rack in BUILT:
		_build(_intro, PlayerManager.player_presences.size())
	if OS.get_environment("MP8_PACE") != "":
		_intro.anim_scientist_ik.animation_started.connect(_on_ik_animation)
	_film_intro.call_deferred()

# compact: one block, a plain plate, 8 half-height bars and a 2x4 grid of half-size sockets; the arm at half size.
# decker: slots 4-7 on a full-size copy of the block, DECK_DROP below the original.
# stack: two copies of the block at STACK_SCALE, one above the other from the original's top; the arm to match.
# MP8_LIGHT=<energy> adds a fill light on the lower deck (decker, stack), which the scene's own light misses.
func _build(intro: Node, count: int) -> void:
	var root: Node = intro.get_parent()
	var intro2: Node = root.get_node("intermission intro2")
	var backing: Node3D = intro2.get_node(BACKING)
	var rig: Vector3 = intro.visual_parent_scientist_hand.global_position
	var tags: Array = intro.rack_nametags.duplicate()
	var tubes: Array = intro.vessels_in_main_rack.duplicate()
	var hands: Array = intro.hand_armature_parent_position_by_rack_index.duplicate()
	var bars: Array = BARS.map(func(b): return b.map(func(n): return intro2.get_node(n)))
	var sockets: Array = range(4).map(func(i): return intro2.get_node("fake vessel parent/real vessel%d" % i))
	var gx := func(n): return n.global_transform
	var tag_xf: Array = tags.map(gx)
	var lamp_xf: Array = tags.map(func(t): return t.get_child(0).global_transform)
	var tube_xf: Array = tubes.map(gx)
	var socket_xf: Array = sockets.map(gx)
	var bar_xf: Array = bars.map(func(b): return b.map(gx))
	intro.rack_nametags.clear()
	intro.vessels_in_main_rack.clear()
	intro.hand_armature_parent_position_by_rack_index.clear()
	var box: AABB = backing.global_transform * backing.get_aabb()
	var decks: Array = []
	if _rack == "decker":
		decks = [Transform3D.IDENTITY, Transform3D(Basis(), Vector3(0, -DECK_DROP, 0))]
	elif _rack == "stack":
		var top := Vector3(FRONT_X, box.end.y, box.get_center().z)
		for d in 2:
			var to := top - Vector3(0, d * (STACK_SCALE * box.size.y + STACK_GAP), 0)
			decks.append(Transform3D(Basis.from_scale(Vector3.ONE * STACK_SCALE), to - STACK_SCALE * top))
		_plate(intro2, backing, false)
	else:
		_plate(intro2, backing, true)
	if not decks.is_empty():
		var backing_xf: Transform3D = backing.global_transform
		var low: Node3D = backing.duplicate()
		low.name = BACKING + "_mp8_deck"
		intro2.add_child(low)
		backing.global_transform = decks[0] * backing_xf
		low.global_transform = decks[1] * backing_xf
		_fill_light(intro2, decks[1] * box.get_center(), OS.get_environment("MP8_LIGHT").to_float())
	var arm := {"compact": 0.5, "stack": STACK_SCALE}.get(_rack, 1.0) as float
	intro.hand_armature_parent.scale = Vector3.ONE * arm
	for k in count:
		var s := k % 4
		var bar_map: Transform3D
		var socket_map: Transform3D
		var tag_scale := 1.0
		if not decks.is_empty():
			bar_map = decks[k / 4]
			socket_map = bar_map
			tag_scale = STACK_SCALE if _rack == "stack" else 1.0
		else:
			# Bar k of 8 at half height in the original column; socket k at row k/2, column k%2.
			var c_old: Vector3 = tag_xf[s].origin
			var c_new := Vector3(c_old.x, tag_xf[0].origin.y + 0.05 - k * 0.1313, c_old.z)
			var squash := Basis.from_scale(Vector3(1, 0.5, 1))
			bar_map = Transform3D(squash, c_new - squash * c_old)
			var p: Vector3 = socket_xf[s].origin
			p.x = FRONT_X
			var row_y: float = tag_xf[0].origin.y - 0.0156 - (k / 2) * 0.2626
			var q := Vector3(FRONT_X, row_y, -0.2 if k % 2 == 0 else -0.6)
			socket_map = Transform3D(Basis.from_scale(Vector3.ONE * 0.5), q - 0.5 * p)
			tag_scale = 0.5
			_recess(intro2, q)
		for j in 3:
			_copy(bars[s][j], k, bar_map * bar_xf[s][j])
		_copy(sockets[s], k, socket_map * socket_xf[s])
		var t: Node3D = _copy(tags[s], k, Transform3D.IDENTITY)
		var tag_origin: Vector3 = bar_map * tag_xf[s].origin
		if _rack == "compact":
			tag_origin.z = tag_xf[s].origin.z
		t.global_transform = Transform3D(tag_xf[s].basis.scaled(Vector3.ONE * tag_scale), tag_origin)
		(t.get_child(0) as Node3D).global_transform = bar_map * lamp_xf[s]
		var v: Node3D = _copy(tubes[s], k, socket_map * tube_xf[s])
		if k >= 4:
			intro.visuals_to_hide.append(v)
		intro.rack_nametags.append(t)
		intro.vessels_in_main_rack.append(v)
		# The arm scales about its own origin, so its origin goes where the socket map sends it.
		intro.hand_armature_parent_position_by_rack_index.append(socket_map * (rig + hands[s]) - rig)
	say("built %d slots (%s), arm %.2f, light %s" % [intro.vessels_in_main_rack.size(), _rack, arm, OS.get_environment("MP8_LIGHT")])

# No shadow, so the hand and tubes passing in front don't darken the deck.
func _fill_light(intro2: Node, centre: Vector3, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = "mp8_fill"
	light.light_energy = energy
	light.light_color = Color(0.8, 0.95, 0.9)
	light.omni_range = 3.5
	intro2.add_child(light)
	light.global_position = centre + Vector3(2.0, 0.3, 0)
	_fill = light

# Slot k < 4 moves the scene's own node; k >= 4 gets a copy beside it.
func _copy(n: Node3D, k: int, xf: Transform3D) -> Node3D:
	var c: Node3D = n
	if k >= 4:
		c = n.duplicate()
		c.name = "%s_mp8_%d" % [n.name, k]
		n.get_parent().add_child(c)
	c.global_transform = xf
	return c

# The backing has 4 bar holes and 4 socket recesses baked in, so compact covers it with a plain plate in its material;
# stack keeps the backings and puts the plate behind them, over the rack's hole they no longer fill.
func _plate(intro2: Node, backing: MeshInstance3D, cover: bool) -> void:
	var box: AABB = backing.global_transform * backing.get_aabb()
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, box.size.y, box.size.z)
	plate.mesh = mesh
	plate.material_override = backing.get_active_material(0)
	intro2.add_child(plate)
	plate.global_position = Vector3(FRONT_X - (0.03 if cover else 0.05), box.get_center().y, box.get_center().z)
	backing.visible = not cover
	say("plate %s, material %s" % [box, plate.material_override])

# The plate's stand-in for a baked socket recess (0.46 m across at full size), so an empty socket shows.
func _recess(intro2: Node, centre: Vector3) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.115
	mesh.bottom_radius = 0.115
	mesh.height = 0.01
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.025, 0.02)
	mat.roughness = 1.0
	mesh.material = mat
	disc.mesh = mesh
	intro2.add_child(disc)
	disc.global_transform = Transform3D(Basis(Vector3(0, 0, 1), -PI / 2), centre + Vector3(0.003, 0, 0))

# The panel mesh, local to rack tower main, for laying out cut boxes offline.
func _dump(root: Node) -> void:
	var main: MeshInstance3D = root.get_node("rack tower main")
	var arrays: Array = main.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out := {"origin": [main.global_position.x, main.global_position.y, main.global_position.z],
		"surfaces": main.mesh.get_surface_count(), "format": main.mesh.surface_get_format(0),
		"verts": Array(verts).map(func(v): return [v.x, v.y, v.z]),
		"index": Array(arrays[Mesh.ARRAY_INDEX]),
		"has_uv2": arrays[Mesh.ARRAY_TEX_UV2] != null, "has_tangent": arrays[Mesh.ARRAY_TANGENT] != null,
		"tags": _intro.rack_nametags.map(func(t): return [t.global_position.x, t.global_position.y, t.global_position.z]),
		"vessels": _intro.vessels_in_main_rack.map(func(v): return [v.global_position.x, v.global_position.y, v.global_position.z]),
		"vessel_aabb": str((_intro.vessels_in_main_rack[0] as Node3D).find_children("*", "MeshInstance3D", true, false).map(func(m): return m.global_transform * m.get_aabb())),
		"rig": str(_intro.visual_parent_scientist_hand.global_position),
		"hands": str(_intro.hand_armature_parent_position_by_rack_index),
		"camera": str(root.get_node("camera main parent/camera sub parent/Camera3D").global_transform),
		"fill": []}
	# The panel has a hole where the bars and sockets are: every other mesh overlapping it, in world space.
	var hole := AABB(Vector3(0.2, 1.9, -1.3), Vector3(0.8, 1.3, 2.3))
	for m in root.find_children("*", "MeshInstance3D", true, false):
		if m == main or m.mesh == null or not (m.global_transform * m.get_aabb()).intersects(hole):
			continue
		var entry := {"path": str(root.get_path_to(m)), "mesh": m.mesh.resource_name, "class": m.mesh.get_class(),
			"visible": m.is_visible_in_tree(), "layers": m.layers, "aabb": str(m.global_transform * m.get_aabb()),
			"surfaces": m.mesh.get_surface_count(), "xf": str(m.global_transform)}
		if m.mesh is ArrayMesh and m.mesh.get_surface_count() > 0:
			var a: Array = m.mesh.surface_get_arrays(0)
			var pts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			entry["count"] = pts.size()
			if pts.size() < 20000:
				entry["verts"] = Array(pts).map(func(v): var w: Vector3 = m.global_transform * v; return [w.x, w.y, w.z])
				entry["index"] = Array(a[Mesh.ARRAY_INDEX]) if a[Mesh.ARRAY_INDEX] != null else []
		out["fill"].append(entry)
	var f := FileAccess.open(_dir.path_join("panel.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	say("dumped %d verts, %d indices" % [verts.size(), out["index"].size()])
	for e in out["fill"]:
		say("  fill %s '%s' %s visible=%s layers=%d count=%s aabb %s" % [e["path"], e["mesh"], e["class"], e["visible"], e["layers"], e.get("count", "-"), e["aabb"]])

# Every layout builds slots 0..count-1 from the scene's four (tags under rack tower main/nametags,
# tubes at the root, hand positions local to the scientist's rig, which has no rotation).
func _extend(intro: Node, count: int) -> void:
	var root: Node = intro.get_parent()
	var main: Node3D = root.get_node("rack tower main")
	var rig: Vector3 = intro.visual_parent_scientist_hand.global_position
	var tags: Array = intro.rack_nametags.duplicate()
	var tubes: Array = intro.vessels_in_main_rack.duplicate()
	var hands: Array = intro.hand_armature_parent_position_by_rack_index.duplicate()
	var tag_xf: Array = tags.map(func(t): return t.global_transform)
	var tube_xf: Array = tubes.map(func(v): return v.global_transform)
	intro.rack_nametags.clear()
	intro.vessels_in_main_rack.clear()
	intro.hand_armature_parent_position_by_rack_index.clear()
	if _rack == "half":
		for t in tags:
			t.reparent(root, true)
	for k in count:
		var t: Node3D = tags[k] if k < 4 else tags[0].duplicate()
		var v: Node3D = tubes[k] if k < 4 else tubes[0].duplicate()
		if k >= 4:
			t.name = "name%d" % k
			tags[0].get_parent().add_child(t)
			v.name = "vessel in main rack%d" % k
			tubes[0].get_parent().add_child(v)
			intro.visuals_to_hide.append(v)
		var place: Array = _place(k, root, main, rig, tag_xf, tube_xf, hands)
		t.global_transform = place[0]
		v.global_transform = place[1]
		intro.rack_nametags.append(t)
		intro.vessels_in_main_rack.append(v)
		intro.hand_armature_parent_position_by_rack_index.append(place[2])
	if _rack == "half":
		_half_racks(root, main)
	elif _rack == "neighbour":
		for l in root.get_node("intermission intro2/fake rack tower4").find_children("*", "Label3D", true, false):
			l.visible = false
	say("extended to %d (%s)" % [intro.vessels_in_main_rack.size(), _rack])

# [tag transform, tube transform, hand position in the rig] for slot k.
func _place(k: int, root: Node, main: Node3D, rig: Vector3, tag_xf: Array, tube_xf: Array, hands: Array) -> Array:
	if _rack == "squeeze":
		# Two per bar and two per socket, smaller.
		var s := k / 2
		var up := 0.032 if k % 2 == 0 else -0.032
		var side := Vector3(0, 0, 0.1 if k % 2 == 0 else -0.1)
		var t: Transform3D = tag_xf[s]
		t = Transform3D(t.basis.scaled(Vector3.ONE * 0.4), t.origin + Vector3(0.01, up, 0))
		var v: Transform3D = tube_xf[s]
		v = Transform3D(v.basis.scaled(Vector3.ONE * 0.5), v.origin + side)
		return [t, v, hands[s] + side]
	if _rack == "half":
		# Two half-size copies of the slot block side by side, over the original block.
		var s := k % 4
		var c := HALF_CENTER + Vector3(0, 0, HALF_SHIFT if k < 4 else -HALF_SHIFT)
		var t: Transform3D = tag_xf[s]
		t = Transform3D(t.basis.scaled(Vector3.ONE * 0.5), c + (t.origin - HALF_CENTER) * 0.5)
		var v: Transform3D = tube_xf[s]
		v = Transform3D(v.basis.scaled(Vector3.ONE * 0.5), c + (v.origin - HALF_CENTER) * 0.5)
		return [t, v, c + (rig + hands[s] - HALF_CENTER) * 0.5 - rig]
	# neighbour: slots 4-7 on fake rack tower4, mapped through its first filler tag and its turn.
	if k < 4:
		return [tag_xf[k], tube_xf[k], hands[k]]
	var s := k - 4
	var fake: Node3D = root.get_node("intermission intro2/fake rack tower4")
	var anchor: Vector3 = fake.find_children("*", "Label3D", true, false)[0].global_position
	var turn: Basis = fake.global_basis.orthonormalized() * main.global_basis.orthonormalized().inverse()
	var from: Vector3 = tag_xf[0].origin
	var map := func(p: Vector3) -> Vector3: return anchor + turn * (p - from)
	var t: Transform3D = tag_xf[s]
	var v: Transform3D = tube_xf[s]
	return [Transform3D(turn * t.basis, map.call(t.origin)), Transform3D(turn * v.basis, map.call(v.origin)), map.call(rig + hands[s]) - rig]

func _half_racks(root: Node, main: Node3D) -> void:
	for side in [HALF_SHIFT, -HALF_SHIFT]:
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = main.mesh
		root.add_child(copy)
		var c := HALF_CENTER + Vector3(0, 0, side)
		copy.global_transform = Transform3D(main.global_basis.scaled(Vector3.ONE * 0.5), c + (main.global_position - HALF_CENTER) * 0.5)
	main.visible = false

# Counts game seconds, not wall time, so a run under the Movie Maker (slower than real time) films the same span.
# Each log line carries the frame drawn, for cutting the recording.
func _film_intro() -> void:
	var i := 0
	var explored := false
	var swept := OS.get_environment("MP8_SWEEP") != "1"
	var outro_played := false
	while i < 50 and is_instance_valid(_intro):
		if _rack == "explore" and not explored and _intro.vessel_to_insert_index >= 4:
			explored = true
			await _explore()
		if _rack == "outro" and not outro_played and _intro.vessel_to_insert_index >= PlayerManager.player_presences.size():
			outro_played = true
			_outro()
		if not swept and _intro.vessel_to_insert_index >= 5:
			swept = true
			await _sweep()
		await shot("intro_%02d" % i)
		say("  t=%d index=%d frame=%d" % [i, _intro.vessel_to_insert_index, Engine.get_frames_drawn()])
		i += 1
		await get_tree().create_timer(1.0).timeout
	if is_instance_valid(_intro):
		say("tubes visible: %s" % [_intro.vessels_in_main_rack.map(func(v): return v.visible)])
	_done = true
	say("DONE")

# The session end's camera move over the rack, right after the intro: a test launch is a custom game, whose session
# end exits before its outro. The session end lights every player's tag first, as here.
func _outro() -> void:
	for i in PlayerManager.player_presences.size():
		var tag = _intro.rack_nametags[i]
		tag.set_nametag_text(PlayerManager.player_presences.values()[i].network_name.to_upper())
		tag.show_nametag()
	_intro.visual_parent_scientist_hand.visible = false
	_intro.anim_intermission_cam.play("outro")
	say("outro at frame %d" % Engine.get_frames_drawn())

# Mid-intro, the fill light's energy and (stack) the camera's pull-back, one shot each.
func _sweep() -> void:
	for e in [0.0, 0.15, 0.3, 0.5, 0.8]:
		if _fill != null:
			_fill.light_energy = e
		await shot("sweep_light_%02d" % int(e * 10))
	if _rack == "stack":
		var sub: Node3D = _intro.get_parent().get_node("camera main parent/camera sub parent")
		_sweeping = true
		for v in [Vector3(0, -0.3, 0.5), Vector3(0, -0.3, 0.6), Vector3(0, -0.35, 0.8)]:
			sub.position = v
			await shot("sweep_view_%d_%d" % [int(v.y * -100), int(v.z * 10)])
		_sweeping = false
		_panned = Vector3(9, 9, 9)
	if _fill != null:
		_fill.light_energy = OS.get_environment("MP8_LIGHT").to_float()

func _explore() -> void:
	var root: Node = _intro.get_parent()
	for n in ["rack tower main", "intermission intro2/fake rack tower3", "intermission intro2/fake rack tower4"]:
		var m = root.get_node_or_null(n)
		if m is MeshInstance3D:
			var box: AABB = m.global_transform * m.get_aabb()
			say("%s at %s, box %s .. %s" % [n, m.global_position, box.position, box.end])
			for t in m.find_children("*", "Label3D", true, false):
				say("  tag %s '%s' at %s" % [t.name, t.text, t.global_position])
	for k in _intro.vessels_in_main_rack.size():
		say("vessel %d at %s" % [k, _intro.vessels_in_main_rack[k].global_position])
	var sub: Node3D = root.get_node("camera main parent/camera sub parent")
	var home: Vector3 = sub.position
	for step in [["back1", Vector3(0, 0, 1.0)], ["back2", Vector3(0, 0, 2.0)], ["back3", Vector3(0, 0, 3.0)],
			["right1_5", Vector3(1.5, 0, 0)], ["right3", Vector3(3.0, 0, 0)], ["right3_back1_5", Vector3(3.0, 0, 1.5)]]:
		sub.position = home + step[1]
		await shot("explore_" + step[0])
	sub.position = home

# Beep preview (MP8_BEEP=semitone|major|whole): the name tag's boot beep rises with each tube, in semitones above the
# middle of the game's random 0.30-0.34. The game sets its pitch just before playing it, so this runs late in the
# frame (process_priority) and overwrites it while it plays.
const BEEP_STEPS := {"semitone": [0, 1, 2, 3, 4, 5, 6, 7], "major": [0, 2, 4, 5, 7, 9, 11, 12], "whole": [0, 2, 4, 6, 8, 10, 12, 14]}
const BEEP_BASE := 0.32

func _beep() -> void:
	var steps: Array = BEEP_STEPS.get(OS.get_environment("MP8_BEEP"), [])
	if steps.is_empty() or not is_instance_valid(_intro):
		return
	var speaker: AudioStreamPlayer = _intro.speaker_intro_show_nametag
	var k: int = clampi(_intro.vessel_to_insert_index, 0, steps.size() - 1)
	if speaker.playing:
		speaker.pitch_scale = BEEP_BASE * pow(2.0, steps[k] / 12.0)

var _insert_clock := -1.0
# Pace preview (MP8_PACE=<seconds per insert>): the game waits a fixed 3 s per insert in its own coroutine, so the
# preview speeds game time only in each insert's idle tail, after its 1.63 s animation.
func _on_ik_animation(anim: StringName) -> void:
	if anim == &"insert vessel":
		_insert_clock = 0.0

func _pace(delta: float) -> void:
	if _insert_clock < 0.0:
		return
	if not is_instance_valid(_intro) or _intro.vessel_to_insert_index >= PlayerManager.player_presences.size():
		Engine.time_scale = 1.0
		_insert_clock = -1.0
		return
	_insert_clock += delta
	var pace := OS.get_environment("MP8_PACE").to_float()
	Engine.time_scale = 1.0 if _insert_clock < INSERT_ANIM else (3.0 - INSERT_ANIM) / (pace - INSERT_ANIM)

var _panned := Vector3.ZERO
var _sweeping := false
# The camera's free sub parent (axes: right, up, back), checked every frame. neighbour: inserts 5-8 on the next
# panel, 1.5 m right. decker: inserts 5-7 on the lower deck, then the last pulled back so both decks show.
# stack: pulled back the whole intro (MP8_VIEW=down,back[,right]). All go home for intro3.
func _pan(index: int) -> void:
	if _sweeping:
		return
	var want := Vector3.ZERO
	if _rack == "neighbour" and index >= 4 and index < 8:
		want = Vector3(1.5, 0, 0)
	elif _rack == "decker" and index >= 4 and index < 7:
		want = Vector3(0, -DECK_DROP, 0)
	elif _rack == "decker" and index == 7:
		want = Vector3(0, -DECK_DROP / 2, DECK_WIDE)
	elif _rack == "stack" and index < 8:
		var view := (OS.get_environment("MP8_VIEW") if OS.get_environment("MP8_VIEW") != "" else "0.3,0.6").split(",")
		want = Vector3(view[2].to_float() if view.size() > 2 else 0.0, -view[0].to_float(), view[1].to_float())
	if want == _panned:
		return
	_panned = want
	var sub: Node3D = _intro.get_parent().get_node("camera main parent/camera sub parent")
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(sub, "position", want, 0.8)
