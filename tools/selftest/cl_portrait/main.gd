extends Node

# Dev-only and windowed: Better Couch Lobby's close-ups, prototyped at runtime for the
# owner's decision rounds (CL_PORTRAIT_ROUND), and the shipped mod rendered for comparison.
# Each photo is a SubViewport on the room's own World3D. Shots hold game art, so they go to
# %TEMP%/machine-party-tests/cl_portrait/<setup>/, never into the tree.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const NAMES := ["JERM", "ALEX", "SAM", "MAYA", "LEO", "ZOEY", "WWWW", "KAI"]
# One look per seat: hat, glasses, suit. The xc_ ids need more_cosmetics, which the runner installs unless --without.
const LOOKS := [
	["xc_beret", "sunglasses", "red"], ["xc_sombrero", "none", "xc_teal"],
	["xc_fez", "reading_glasses", "yellow"], ["xc_dragonborn_helmet", "none", "green"],
	["xc_trapper_hat", "xc_scuba_glasses", "purple"], ["xc_football_helmet", "xc_tanning_glasses", "xc_orange"],
	["maska_helmet", "sunglasses", "blue"], ["xc_propeller_beanie", "xc_disguise_glasses", "xc_pink"],
]
# Where the camera looks from: "room" faces the seat from the room camera's side, level;
# "face" looks into the face (the glasses' side of the head), so it drops under a bowed
# head; "blend" is halfway. Framing "fixed" leaves the same headroom for every hat;
# "adaptive" fits the hat worn.
const PASSES := [
	{"name": "room_adaptive", "aim": "room", "framing": "adaptive", "fill": 0.0},
	{"name": "blend_adaptive", "aim": "blend", "framing": "adaptive", "fill": 0.0},
	{"name": "face_adaptive", "aim": "face", "framing": "adaptive", "fill": 0.0},
	{"name": "face_fixed", "aim": "face", "framing": "fixed", "fill": 0.0},
	{"name": "face_adaptive_fill_soft", "aim": "face", "framing": "adaptive", "fill": 0.5},
	{"name": "face_adaptive_fill", "aim": "face", "framing": "adaptive", "fill": 1.2},
]
const STYLES := ["plain", "cctv", "polaroid", "badge"]
# "over_room": the strip over the full room; "room_shrunk": the room and its panels scaled into the top.
const LAYOUTS := ["over_room", "room_shrunk"]
# "over": drawn after the room's posterize and vignette; "under": inserted before them, so the game's pass applies.
const POSTS := ["over", "under"]
const PHOTO := Vector2i(160, 200)
const FOV := 30.0
# Render layers 11-18 carry one seat each, for that seat's fill light only; layer 1 stays.
const SEAT_LAYER_BIT := 10
const ROOM_SCALE := 0.6
# Strip top and height per layout: over the room it clears the panels' ready row;
# under the shrunk room it takes the space down to the buttons.
const STRIP := {"over_room": Vector2(344, 104), "room_shrunk": Vector2(330, 132), "bottom": Vector2(430, 104), "bottom_raised": Vector2(430, 104),
	"bottom_auto": Vector2(430, 104)}
# Round 3: the doubles stand in a copy of the room, out of view, under a copy of its lamp,
# so each photo's background is the room's own back wall.
const ROOM_COPY := Vector3(400, 0, 0)
const ROOM_COPY_Z := 2.0
const ROOM_COPY_GAP := 1.5
# At 1.5 m the outer seats' diagonal cameras stand past the room copy's side walls.
const ROUND4_GAP := 1.2
# The character-select screen's backdrop: a tiled noise texture dimmed to 12% on black.
const MENU_BACKDROP := "res://textures/noise/Techno_13-512x512.png"
const MENU_BACKDROP_GREY := 0.12103007
# Round 2: a portrait double per seat, the character-select screen's own character in its
# "standing idle" pose, far outside the room camera's view and its lamp's range (17.7).
const CUSTOMIZATION := "res://scenes/character_customization.tscn"
const DOUBLE_ORIGIN := Vector3(200, 0, 0)
const DOUBLE_GAP := 12.0
const CELL_MAX_W := 112.0
const GAP := 8.0
const WALL_X := 6.517

var fails := 0
var out: FileAccess
var out_dir: String
var setup: String
var lobby: Node
var room_vp: SubViewport
var room_cam: Camera3D
var seats: Array = []
var font: Font
var composite_pass: String
var round_id: String
var menu_rel: Transform3D
var menu_fov := 0.0
var menu_faces_right := false

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_portrait/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	setup = OS.get_environment("CL_PORTRAIT_SETUP")
	if setup == "":
		setup = "overtime" if loader.has_mod("overtime") else "mp8" if loader.has_mod("mp8_support") else "vanilla"
	round_id = OS.get_environment("CL_PORTRAIT_ROUND")
	if round_id == "":
		round_id = "3"
	composite_pass = OS.get_environment("CL_PORTRAIT_PASS")
	if composite_pass == "":
		composite_pass = "face_adaptive_fill"
	out_dir = OS.get_environment("TEMP").path_join("machine-party-tests/cl_portrait").path_join(setup)
	# Renders hold game art: a relative path would land them in the game folder or the repo.
	if not out_dir.is_absolute_path():
		ok("TEMP is set", false, out_dir)
		finish()
		return
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		ok("needs --windowed", false)
		finish()
		return
	var started := Time.get_ticks_msec()
	for sub in ["", "portraits"]:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join(sub))
		for f in DirAccess.get_files_at(out_dir.path_join(sub)):
			DirAccess.remove_absolute(out_dir.path_join(sub).path_join(f))
	say("setup %s, renders to %s, composites from pass %s" % [setup, out_dir, composite_pass])
	await get_tree().create_timer(1.0).timeout
	if round_id == "4":
		await _menu_recon()
	if round_id == "3":
		# The character-select screen itself, as the owner's reference for its backdrop.
		get_tree().change_scene_to_file(CUSTOMIZATION)
		await get_tree().create_timer(3.0).timeout
		await _shot("r3_menu_reference")
	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	lobby = get_tree().current_scene
	room_vp = lobby.get_node("LobbyPreviewViewport")
	room_cam = lobby.players_node.get_parent().get_node("Camera3D")
	var n: int = lobby.local_lobby_player_controls.size()
	# Device -1 is the keyboard; the rest are device ids no pad uses, so nothing reads them as input.
	lobby.join(-1, false)
	for i in range(1, n):
		lobby.join(100 + i, true)
	await frames(10)
	for i in n:
		lobby.local_lobby_player_controls[i]._on_name_confirmed(NAMES[i])
		var a = lobby.local_lobby_player_controls[i].customization_assigner
		a.assign_hat(LOOKS[i][0])
		a.assign_glasses(LOOKS[i][1])
		a.assign_suit_color(LOOKS[i][2])
	font = lobby.local_lobby_player_controls[0].name_label.get_theme_font("font")
	say("seats %d, canvas %s, room world is the root's: %s" % [n, get_viewport().get_visible_rect().size,
		room_vp.find_world_3d() == get_tree().root.find_world_3d()])
	_room_light_report()
	for i in n:
		var a = lobby.local_lobby_player_controls[i].customization_assigner
		var glasses: Node3D = a.bone_attachment_glasses
		var mesh = glasses.find_children("*", "MeshInstance3D", true, false)
		var player: AnimationPlayer = lobby.players_node.get_child(i).find_children("*", "AnimationPlayer", true, false)[0]
		var anim := player.get_animation(player.current_animation) if player.current_animation != "" else null
		say("P%d anim %s length %s loop %s; glasses offset (head-local) %s" % [i + 1, player.current_animation,
			anim.length if anim else "-", anim.loop_mode if anim else "-",
			_v(((glasses.global_transform.affine_inverse() * mesh[0].global_transform) * mesh[0].get_aabb().get_center())) if mesh.size() > 0 else "-"])
	# The lobby fades in from a loading screen (fade_loading_screen, 2 s) behind a 0.5 s overlay fade.
	await get_tree().create_timer(3.5).timeout
	await _shot("room_only")

	if round_id == "built":
		await _built(n)
		finish()
		return
	for i in n:
		seats.append(_make_seat(i))
	if round_id in ["2", "3", "4", "5"]:
		if round_id == "2":
			await _round2()
		elif round_id == "3":
			await _round3()
		elif round_id == "4":
			await _round4()
		else:
			await _round5()
		say("elapsed %.1f s (the runner stops the game at 180 s)" % ((Time.get_ticks_msec() - started) / 1000.0))
		finish()
		return
	for p in PASSES:
		say("\n=== pass %s" % p.name)
		for s in seats:
			_aim(s, p)
		await frames(4)
		await RenderingServer.frame_post_draw
		for s in seats:
			_save(s.vp.get_texture().get_image(), "portraits/%s_p%d" % [p.name, s.i + 1])
		await _shot("pass_" + p.name, _overlay("plain", "over_room", "over"))
	for p in PASSES:
		if p.name == composite_pass:
			for s in seats:
				_aim(s, p)
	for layout in LAYOUTS:
		for style in STYLES:
			for post in POSTS:
				await _shot("%s_%s_%s" % [layout, style, post], _overlay(style, layout, post))
	await _perf()
	say("elapsed %.1f s (the runner stops the game at 180 s)" % ((Time.get_ticks_msec() - started) / 1000.0))
	finish()

func _room_light_report() -> void:
	for l in lobby.players_node.get_parent().find_children("*", "Light3D", true, false):
		var o := l as OmniLight3D
		say("room light %s at %s energy %.1f range %s attenuation %s shadow %s" % [l.name, _v(l.global_position), l.light_energy,
			o.omni_range if o else "-", o.omni_attenuation if o else "-", l.shadow_enabled])

# A seat's close-up: its own SubViewport on the room's world, a camera, and a fill
# light that only that seat's meshes receive (their layer 11+i).
func _make_seat(i: int) -> Dictionary:
	var c = lobby.local_lobby_player_controls[i]
	var a = c.customization_assigner
	var skel: Skeleton3D = a.get_parent()
	var vp := SubViewport.new()
	vp.name = "CLPortrait%d" % (i + 1)
	vp.size = PHOTO
	vp.world_3d = room_vp.find_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	cam.current = true
	var fill := OmniLight3D.new()
	fill.light_cull_mask = 1 << (SEAT_LAYER_BIT + i)
	fill.light_color = Color(1.0, 0.97, 0.92)
	fill.shadow_enabled = false
	fill.visible = false
	lobby.players_node.get_parent().add_child(fill)
	return {"i": i, "controls": c, "assigner": a, "skel": skel, "model": lobby.players_node.get_child(i), "vp": vp, "cam": cam, "fill": fill}

func _bone(skel: Skeleton3D, bone: String) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin

func _aim(s: Dictionary, p: Dictionary) -> void:
	var a = s.double.assigner if p.get("double", false) else s.assigner
	var skel: Skeleton3D = a.get_parent()
	var head: Vector3 = a.bone_attachment_glasses.global_position
	var neck := _bone(skel, "neck")
	var chest := _bone(skel, "chest")
	var head_len := head.distance_to(neck)
	var top := head.y + head_len * 2.4
	if p.framing == "adaptive":
		top = head.y + head_len * 1.2
		for mi in a.bone_attachment_hat.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree():
				var box: AABB = mi.global_transform * mi.get_aabb()
				top = maxf(top, box.end.y)
	top += head_len * 0.25
	var bottom := chest.y - head_len * 0.3
	var center := Vector3(head.x, (top + bottom) * 0.5, head.z)
	var face := _face_dir(a)
	var to_room: Vector3 = face if p.get("double", false) else room_cam.global_position - head
	to_room.y = 0.0
	to_room = to_room.normalized()
	var dir := to_room
	if p.aim == "face":
		dir = face
	elif p.aim == "blend":
		dir = (face + to_room).normalized()
	dir.y = clampf(dir.y, -0.6, 0.35)
	dir = dir.normalized()
	var distance := ((top - bottom) * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var cam: Camera3D = s.cam
	cam.global_position = center + dir * distance
	cam.look_at(center, Vector3.UP)
	if p.get("double", false):
		_place_backdrop(s, p.get("backdrop", "dark"), head, dir)
	var fill: OmniLight3D = s.fill
	fill.visible = p.fill > 0.0
	if p.fill > 0.0:
		_set_seat_layer(s)
		fill.global_position = center + dir * distance * 0.7 + Vector3.UP * distance * 0.3
		fill.omni_range = distance * 2.5
		fill.light_energy = p.fill
	say("  P%d head %s neck-head %.3f top %.2f bottom %.2f face %s dir %s dist %.2f cam %s%s" % [s.i + 1, _v(head), head_len,
		top, bottom, _v(_face_dir(a)), _v(dir), distance, _v(cam.global_position), "  CAM PAST WALL" if absf(cam.global_position.x) > WALL_X else ""])

# The glasses hang in front of the eyes, so the head bone's offset to any glasses
# mesh (shown or not), less its part along the head's own up (head to hat bone),
# points out of the face; every seat shares the rig.
func _face_dir(a) -> Vector3:
	var attach: Node3D = a.bone_attachment_glasses
	var up: Vector3 = (a.bone_attachment_hat.global_position - attach.global_position).normalized()
	var inv := attach.global_transform.affine_inverse()
	for mi in attach.find_children("*", "MeshInstance3D", true, false):
		var local: Vector3 = (inv * mi.global_transform) * mi.get_aabb().get_center()
		var off: Vector3 = attach.global_basis.orthonormalized() * local
		off -= up * off.dot(up)
		if off.length() > 0.001:
			return off.normalized()
	return Vector3.BACK

func _set_seat_layer(s: Dictionary) -> void:
	for g in (s.model as Node).find_children("*", "VisualInstance3D", true, false):
		g.layers |= 1 << (SEAT_LAYER_BIT + s.i)

# The strip of close-ups in one style; the room_shrunk layout also scales the room and its panels.
func _overlay(style: String, layout: String, post: String) -> Dictionary:
	var root: Control = lobby.get_node("Control")
	var room: Control = root.get_node("TextureRect")
	var panels: Control = root.get_node("PlayerControls")
	var size := get_viewport().get_visible_rect().size
	var made := {"nodes": [], "restore": []}
	if layout == "room_shrunk":
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.045, 0.04)
		bg.size = size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		root.move_child(bg, 0)
		made.nodes.append(bg)
		for c in [room, panels]:
			made.restore.append([c, c.position, c.scale])
			c.scale = Vector2.ONE * ROOM_SCALE
			c.position = Vector2(size.x * (1.0 - ROOM_SCALE) * 0.5, 0.0)
	var n := seats.size()
	var strip_h: float = STRIP[layout].y
	var cw := minf(CELL_MAX_W * strip_h / 104.0, (size.x - 48.0 - GAP * (n - 1)) / n)
	var x0 := (size.x - (cw * n + GAP * (n - 1))) * 0.5
	if layout == "bottom_raised" or layout == "bottom_auto":
		# The game's button rows (LEAVE; START, PLAYLIST, SKIP INTRO) lifted to end just above the strip;
		# "bottom_auto" only when a shown button overlaps the strip (with rotation's slack).
		var band := Rect2(x0 - 6.0, STRIP[layout].x - 6.0, cw * n + GAP * (n - 1) + 12.0, strip_h + 12.0)
		var rows: Array = ["Lobby/Control/HFlowContainer", "Lobby/Control/HFlowContainer2", "Lobby/Control/HFlowContainer3"].map(func(p): return root.get_node(p))
		var bottom := 0.0
		var covered := false
		for c in rows:
			for b in c.get_children():
				if b is Control and b.visible:
					bottom = maxf(bottom, b.get_global_rect().end.y)
					covered = covered or b.get_global_rect().intersects(band)
		var lift: float = bottom - (STRIP[layout].x - 4.0)
		if layout == "bottom_auto" and not covered:
			lift = 0.0
		say("buttons' bottom %.1f, cover the strip %s, lifted %.1f" % [bottom, covered, lift])
		for c in rows:
			made.restore.append([c, c.position, c.scale])
			c.position.y -= lift
	var strip := Control.new()
	strip.name = "CLStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	root.move_child(strip, room.get_index() + 1 if post == "under" else panels.get_index() + 1)
	made.nodes.append(strip)
	for s in seats:
		var card := _card(style, s, Vector2(cw, strip_h))
		card.position = Vector2(x0 + s.i * (cw + GAP), STRIP[layout].x)
		strip.add_child(card)
	return made

func _card(style: String, s: Dictionary, size: Vector2) -> Control:
	var card := Control.new()
	card.size = size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var photo := TextureRect.new()
	photo.texture = (s.vp as SubViewport).get_texture()
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var player: String = s.controls.player_name
	match style:
		"plain":
			card.add_child(_box(Rect2(Vector2.ZERO, size), Color(0.07, 0.065, 0.06, 0.92), Color(0.32, 0.29, 0.25), 2, 3))
			_place(card, photo, s.vp, Rect2(4, 4, size.x - 8, size.y - 24))
			card.add_child(_label(player, Rect2(0, size.y - 20, size.x, 18), Color(0.92, 0.9, 0.85), 13))
		"cctv":
			card.add_child(_box(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.1), Color(0.22, 0.22, 0.21), 3, 7))
			var pr := Rect2(6, 6, size.x - 12, size.y - 28)
			_place(card, photo, s.vp, pr)
			var lines := ColorRect.new()
			lines.material = _shader_material(SCANLINES)
			lines.position = pr.position
			lines.size = pr.size
			lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(lines)
			card.add_child(_label("CAM %02d" % (s.i + 1), Rect2(pr.position + Vector2(3, 1), Vector2(60, 12)), Color(0.9, 0.95, 0.9, 0.85), 9, HORIZONTAL_ALIGNMENT_LEFT))
			var dot := ColorRect.new()
			dot.color = Color(0.9, 0.12, 0.1)
			dot.position = Vector2(pr.end.x - 9, pr.position.y + 4)
			dot.size = Vector2(5, 5)
			card.add_child(dot)
			card.add_child(_label("00:%02d:%02d" % [s.i + 1, 13 + s.i * 7], Rect2(pr.position.x + 3, pr.end.y - 13, 70, 12), Color(0.9, 0.95, 0.9, 0.85), 9, HORIZONTAL_ALIGNMENT_LEFT))
			card.add_child(_label(player, Rect2(0, size.y - 21, size.x, 18), Color(0.85, 0.85, 0.82), 13))
		"polaroid":
			card.add_child(_box(Rect2(Vector2.ZERO, size), Color(0.86, 0.84, 0.77), Color(0.7, 0.67, 0.6), 1, 0))
			var pr := Rect2(6, 6, size.x - 12, size.y - 30)
			if s.get("menu", false):
				card.add_child(_box(pr, Color.BLACK, Color.BLACK, 0, 0))
				var noise := TextureRect.new()
				noise.texture = load(MENU_BACKDROP)
				noise.stretch_mode = TextureRect.STRETCH_TILE
				noise.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				noise.modulate = Color(MENU_BACKDROP_GREY, MENU_BACKDROP_GREY, MENU_BACKDROP_GREY)
				noise.position = pr.position
				noise.size = pr.size
				noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(noise)
			_place(card, photo, s.vp, pr)
			card.add_child(_grime(Rect2(Vector2.ZERO, size), s.i))
			card.add_child(_label(player, Rect2(0, size.y - 23, size.x, 18), Color(0.18, 0.16, 0.14), 13))
			var tape := ColorRect.new()
			tape.color = Color(0.83, 0.78, 0.58, 0.8)
			tape.size = Vector2(size.x * 0.42, 11)
			tape.position = Vector2(size.x * 0.29, -5)
			tape.pivot_offset = tape.size * 0.5
			tape.rotation = deg_to_rad(-4.0 if s.i % 2 == 0 else 3.0)
			card.add_child(tape)
			card.pivot_offset = size * 0.5
			card.rotation = deg_to_rad([-2.5, 1.8, -1.2, 2.6, -2.0, 1.2, -2.8, 2.2][s.i % 8])
		"badge":
			card.add_child(_box(Rect2(Vector2.ZERO, size), Color(0.8, 0.79, 0.74), Color(0.45, 0.43, 0.4), 1, 6))
			card.add_child(_box(Rect2(size.x * 0.5 - 12, 4, 24, 5), Color(0.25, 0.24, 0.22), Color(0.25, 0.24, 0.22), 0, 2))
			card.add_child(_box(Rect2(0, 12, size.x, 14), Color(0.48, 0.16, 0.1), Color(0.48, 0.16, 0.1), 0, 0))
			card.add_child(_label("STAFF  %03d" % (s.i + 1), Rect2(0, 12, size.x, 14), Color(0.96, 0.92, 0.85), 10))
			_place(card, photo, s.vp, Rect2(8, 30, size.x - 16, size.y - 50))
			card.add_child(_grime(Rect2(Vector2.ZERO, size), s.i))
			card.add_child(_label(player, Rect2(0, size.y - 20, size.x, 18), Color(0.15, 0.14, 0.13), 13))
	return card

func _place(card: Control, photo: TextureRect, vp: SubViewport, r: Rect2) -> void:
	# The camera renders at the window's own shape (twice its size), so nothing is cropped away.
	vp.size = Vector2i(roundi(r.size.x * 2.0), roundi(r.size.y * 2.0))
	photo.position = r.position
	photo.size = r.size
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(photo)

func _box(r: Rect2, bg: Color, border: Color, bw: int, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _label(text: String, r: Rect2, color: Color, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

const SCANLINES := """shader_type canvas_item;
void fragment() {
	float line = step(0.5, fract(FRAGCOORD.y / 3.0));
	vec2 d = UV - 0.5;
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - line) * 0.2 + dot(d, d) * 1.1);
}
"""
# Brown stains: a noise threshold, so the card reads handled rather than printed.
const GRIME := """shader_type canvas_item;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float n = noise(UV * 6.0) * 0.6 + noise(UV * 19.0) * 0.4;
	COLOR = vec4(0.32, 0.24, 0.14, smoothstep(0.55, 0.85, n) * 0.35);
}
"""

func _grime(r: Rect2, i: int) -> ColorRect:
	var g := ColorRect.new()
	var m := _shader_material(GRIME)
	m.set_shader_parameter("seed", float(i) * 3.7)
	g.material = m
	g.position = r.position
	g.size = r.size
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _round2() -> void:
	say("\n=== round 2")
	var seat_pick := {"name": "seat_face", "aim": "face", "framing": "adaptive", "fill": 0.0}
	for s in seats:
		_aim(s, seat_pick)
	await _portraits("seat_face")
	await _shot("r2_seat_face", _overlay("polaroid", "bottom", "under"))
	var packed: PackedScene = load(CUSTOMIZATION)
	for s in seats:
		s["double"] = _make_double(packed, s)
	# The double's assigner dresses it in the menu's own look on _ready; More Cosmetics' hook fires then too.
	await frames(10)
	var anim: AnimationPlayer = seats[0].double.node.find_children("*", "AnimationPlayer", true, false)[0]
	var clip := anim.get_animation(anim.current_animation) if anim.current_animation != "" else null
	say("double anim %s length %s loop %s, blink %s" % [anim.current_animation, clip.length if clip else "-",
		clip.loop_mode if clip else "-", seats[0].double.node.get_node_or_null("character blink") != null])
	await frames(3)
	_check_doubles("doubles wear their seat's look")
	for backdrop in ["dark", "wall"]:
		var p := {"name": "double_" + backdrop, "aim": "face", "framing": "adaptive", "fill": 0.0, "double": true, "backdrop": backdrop}
		say("\n=== pass %s" % p.name)
		for s in seats:
			_aim(s, p)
		await _portraits(p.name)
		await _shot("r2_" + p.name, _overlay("polaroid", "bottom", "under"))
	await _shot("r2_double_wall_raised", _overlay("polaroid", "bottom_raised", "under"))
	# A custom game adds START, PLAYLIST and SKIP INTRO to the bottom band.
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = true
	await _shot("r2_double_wall_custom_buttons", _overlay("polaroid", "bottom", "under"))
	await _shot("r2_double_wall_raised_custom_buttons", _overlay("polaroid", "bottom_raised", "under"))
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = false
	var changes := [["assign_hat", "cap_blade"], ["assign_glasses", "xc_cyclops_glasses"], ["assign_suit_color", "xc_pink"], ["assign_hat", "none"]]
	for k in mini(changes.size(), seats.size()):
		seats[k].assigner.call(changes[k][0], changes[k][1])
	await frames(3)
	_check_doubles("doubles follow a changed look")
	for s in seats:
		_aim(s, {"name": "double_wall", "aim": "face", "framing": "adaptive", "fill": 0.0, "double": true, "backdrop": "wall"})
	await _shot("r2_after_change", _overlay("polaroid", "bottom", "under"))
	await _perf2()

func _round3() -> void:
	say("\n=== round 3")
	var packed: PackedScene = load(CUSTOMIZATION)
	for s in seats:
		s["double"] = _make_double(packed, s)
	await frames(10)
	_check_doubles("doubles wear their seat's look")
	var room_parent: Node3D = lobby.players_node.get_parent()
	var lamp_src: OmniLight3D = room_parent.get_node("OmniLight3D")
	var copy: Node3D = room_parent.get_node("lobby environment1").duplicate()
	copy.name = "CLRoomCopy"
	room_parent.add_child(copy)
	copy.position = ROOM_COPY
	var lamp: OmniLight3D = lamp_src.duplicate()
	room_parent.add_child(lamp)
	lamp.position = ROOM_COPY + lamp_src.position
	var n := seats.size()
	for s in seats:
		var h: Node3D = s.double.holder
		h.position = ROOM_COPY + Vector3((s.i - (n - 1) * 0.5) * ROOM_COPY_GAP, 0.0, ROOM_COPY_Z)
		h.rotation.y = PI
		# Lit by the room's lamp alone, as the seated players are.
		s.double.lamps.visible = false
		# Each camera sees the room (layer 1) and its own double, never a neighbour.
		for g in (s.double.node as Node).find_children("*", "GeometryInstance3D", true, false):
			g.layers = 1 << (SEAT_LAYER_BIT + s.i)
		s.cam.cull_mask = 1 | (1 << (SEAT_LAYER_BIT + s.i))
	var p := {"name": "lobby_wall", "aim": "face", "framing": "adaptive", "fill": 0.0, "double": true, "backdrop": "none"}
	say("\n=== pass lobby_wall")
	for s in seats:
		_aim(s, p)
	await _portraits("lobby_wall")
	await _shot("r3_lobby_wall", _overlay("polaroid", "bottom_auto", "under"))
	await _custom_buttons_shot("r3_lobby_wall_custom")
	await _perf2()
	copy.visible = false
	lamp.visible = false
	for s in seats:
		var h: Node3D = s.double.holder
		h.visible = true
		h.position = DOUBLE_ORIGIN + Vector3(s.i * DOUBLE_GAP, 0, 0)
		h.rotation.y = 0.0
		s.cam.cull_mask = 0xFFFFF
		s.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# The character-select screen's own surround: its lamps and the textured sphere.
		s.double.lamps.visible = true
		s.double.sphere.visible = true
	p = {"name": "menu_backdrop", "aim": "face", "framing": "adaptive", "fill": 0.0, "double": true, "backdrop": "none"}
	say("\n=== pass menu_backdrop")
	for s in seats:
		_aim(s, p)
	await _portraits("menu_backdrop")
	await _shot("r3_menu_backdrop", _overlay("polaroid", "bottom_auto", "under"))
	await _custom_buttons_shot("r3_menu_backdrop_custom")

# couch_lobby's own close-ups, as shipped, for comparison with the picked round-3 shots.
func _built(n: int) -> void:
	ok("couch_lobby close-ups present", lobby.get_node_or_null("CouchLobbyCloseUps") != null)
	await _shot("built_%d_seats" % n)
	await _still(lobby.get_node("CouchLobbyCloseUps/CouchLobbyPhoto1"), "the shipped P1 photo still over 4.5 s (no blink)")
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = true
	await _shot("built_%d_seats_custom" % n)
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = false
	for i in range(n - 1, 1, -1):
		lobby.leave(i)
	await _shot("built_2_seats")

func _custom_buttons_shot(label: String) -> void:
	# A custom game adds START, PLAYLIST and SKIP INTRO to the bottom band.
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = true
	await _shot(label, _overlay("polaroid", "bottom_auto", "under"))
	for b in [lobby.playlist_button, lobby.skip_intro_button, lobby.start_button]:
		b.visible = false

# The character-select screen's character and its three lamps, lifted out of a scene that
# never enters the tree, so the menu's own scripts never run.
func _make_double(packed: PackedScene, s: Dictionary) -> Dictionary:
	var scene: Node = packed.instantiate()
	var ch: Node3D = scene.get_node("main character2")
	var lamps: Node3D = scene.get_node("light parent")
	var sphere: Node3D = scene.get_node("sphere")
	for n in [ch, lamps, sphere]:
		_unown(n)
		n.get_parent().remove_child(n)
	scene.free()
	var mesh: MeshInstance3D = ch.get_node("Armature/Skeleton3D/character mesh")
	# The blink swaps the eye texture on the mesh's material, which every instance of the scene shares.
	mesh.set_surface_override_material(2, mesh.get_active_material(2).duplicate())
	if round_id in ["4", "5"]:
		var blink = ch.get_node("character blink")
		mesh.get_surface_override_material(2).set("albedo_texture", blink.texture_eye_open)
		blink.free()
	var holder := Node3D.new()
	holder.name = "CLDouble%d" % (s.i + 1)
	holder.position = DOUBLE_ORIGIN + Vector3(s.i * DOUBLE_GAP, 0, 0)
	lobby.players_node.get_parent().add_child(holder)
	holder.add_child(ch)
	holder.add_child(lamps)
	holder.add_child(sphere)
	sphere.visible = false
	return {"node": ch, "holder": holder, "assigner": ch.get_node("Armature/Skeleton3D/customization assigner"), "backdrop": null,
		"lamps": lamps, "sphere": sphere}

func _unown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_unown(c)

# The character-select screen's camera, measured live: its pose relative to the character,
# whether anything moves it, and how its feed reaches the screen.
func _menu_recon() -> void:
	say("\n=== character-select screen")
	get_tree().change_scene_to_file(CUSTOMIZATION)
	await frames(2)
	var scene := get_tree().current_scene
	var parent := scene.find_child("character preview camera parent", true, false) as Node3D
	var ch := scene.find_child("main character2", true, false) as Node3D
	ok("menu camera parent and character found", parent != null and ch != null)
	if parent == null or ch == null:
		return
	var cam := parent.get_child(0) as Camera3D
	say("camera %s fov %.3f keep_aspect %d projection %d near %.3f far %.1f cull_mask %d" % [scene.get_path_to(cam), cam.fov,
		cam.keep_aspect, cam.projection, cam.near, cam.far, cam.cull_mask])
	say("character %s scale %s; camera parent rotation_degrees %s" % [scene.get_path_to(ch), _v(ch.global_basis.get_scale()),
		_v(parent.rotation_degrees)])
	var vp := cam.get_viewport()
	say("camera's viewport %s size %s own_world %s" % [vp.name, (vp as SubViewport).size if vp is SubViewport else Vector2i(get_viewport().get_visible_rect().size),
		vp.own_world_3d])
	for tr in scene.find_children("*", "TextureRect", true, false):
		if tr.texture is ViewportTexture:
			say("feed shown by %s rect %s visible %s" % [scene.get_path_to(tr), tr.get_global_rect(), tr.is_visible_in_tree()])
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		say("player %s autoplay '%s' current '%s' root %s" % [scene.get_path_to(ap), ap.autoplay, ap.current_animation, ap.root_node])
		for an in ap.get_animation_list():
			var anim: Animation = ap.get_animation(an)
			var tracks := []
			if anim.get_track_count() <= 8:
				for t in anim.get_track_count():
					var keys := []
					if str(ap.name) == "anim_camera movement":
						for k in anim.track_get_key_count(t):
							keys.append("%.2f: %s" % [anim.track_get_key_time(t, k), anim.track_get_key_value(t, k)])
					tracks.append("%s (%d keys) %s" % [anim.track_get_path(t), anim.track_get_key_count(t), keys])
			say("  %s length %.3f loop %d tracks %d %s" % [an, anim.length, anim.loop_mode, anim.get_track_count(), tracks])
	var t0 := Time.get_ticks_msec()
	for at in [0.3, 1.0, 2.0, 3.0, 4.0]:
		while Time.get_ticks_msec() - t0 < at * 1000.0:
			await get_tree().process_frame
		var rel := ch.global_transform.affine_inverse() * cam.global_transform
		say("t %.1f camera %s %s; relative to the character %s rot %s" % [at, _v(cam.global_position), _v(cam.global_rotation_degrees),
			_v(rel.origin), _v(rel.basis.get_euler() * 180.0 / PI)])
		menu_rel = rel
		if at == 3.0:
			await _shot("r4_menu_reference")
	menu_fov = cam.fov
	var a = ch.get_node("Armature/Skeleton3D/customization assigner")
	menu_faces_right = _face_dir(a).dot(cam.global_basis.x) > 0.0
	say("menu face %s, turned to screen %s; head %s" % [_v(_face_dir(a)), "right" if menu_faces_right else "left",
		_v(a.bone_attachment_glasses.global_position)])

# Round 4: the menu camera's pose on each double, at the menu's own zoom or head and
# shoulders, at the menu's angle on every card or mirrored so each half faces the middle.
func _round4() -> void:
	say("\n=== round 4")
	if menu_fov == 0.0:
		ok("menu camera measured", false)
		return
	var packed: PackedScene = load(CUSTOMIZATION)
	var live := menu_rel
	_authored_pose(packed)
	say("authored pose relative to the character %s rot %s fov %.2f (live at 4 s: %s rot %s)" % [_v(menu_rel.origin),
		_v(menu_rel.basis.get_euler() * 180.0 / PI), menu_fov, _v(live.origin), _v(live.basis.get_euler() * 180.0 / PI)])
	await _doubles_in_room_copy(packed)
	for zoom in ["menu_view", "head_shoulders"]:
		for direction in ["menu", "mirrored"]:
			var label := "%s_%s" % [zoom, direction]
			say("\n=== pass " + label)
			for s in seats:
				_aim4(s, zoom, direction)
			await _portraits(label)
			await _shot("r4_" + label, _overlay("polaroid", "bottom_auto", "under"))
	await _still(seats[0].vp, "P1's photo still over 4.5 s (no blink)")

# The shipped close-ups parked, and a still double per seat in a 1.2 m row in the room copy,
# each on its own render layer.
func _doubles_in_room_copy(packed: PackedScene) -> void:
	_park_shipped()
	for s in seats:
		s["double"] = _make_double(packed, s)
	await frames(10)
	_check_doubles("doubles wear their seat's look")
	ok("no double blinks", seats.all(func(s): return s.double.node.get_node_or_null("character blink") == null))
	var room_parent: Node3D = lobby.players_node.get_parent()
	var lamp_src: OmniLight3D = room_parent.get_node("OmniLight3D")
	var copy: Node3D = room_parent.get_node("lobby environment1").duplicate()
	copy.name = "CLRoomCopy"
	room_parent.add_child(copy)
	copy.position = ROOM_COPY
	var lamp: OmniLight3D = lamp_src.duplicate()
	room_parent.add_child(lamp)
	lamp.position = ROOM_COPY + lamp_src.position
	var n := seats.size()
	for s in seats:
		var h: Node3D = s.double.holder
		h.position = ROOM_COPY + Vector3((s.i - (n - 1) * 0.5) * ROUND4_GAP, 0.0, ROOM_COPY_Z)
		h.rotation.y = PI
		s.double.lamps.visible = false
		for g in (s.double.node as Node).find_children("*", "GeometryInstance3D", true, false):
			g.layers = 1 << (SEAT_LAYER_BIT + s.i)
		s.cam.cull_mask = 1 | (1 << (SEAT_LAYER_BIT + s.i))
	say("double scale %s" % _v((seats[0].double.node as Node3D).global_basis.get_scale()))

# Round 5: the menu pose against head-on, level or keeping the menu's roll.
func _round5() -> void:
	say("\n=== round 5")
	var packed: PackedScene = load(CUSTOMIZATION)
	_authored_pose(packed)
	say("authored pose relative to the character %s rot %s fov %.2f" % [_v(menu_rel.origin),
		_v(menu_rel.basis.get_euler() * 180.0 / PI), menu_fov])
	await _doubles_in_room_copy(packed)
	# Placing the cards sizes the photos to their 8-seat shape, so every pass's portraits match.
	_clear(_overlay("polaroid", "bottom_auto", "under"))
	for label in ["menu", "front_level", "front_menu_roll"]:
		say("\n=== pass " + label)
		for s in seats:
			_aim5(s, label)
		await _portraits(label)
		await _shot("r5_" + label, _overlay("polaroid", "bottom_auto", "under"))
	for s in seats:
		_aim5(s, "front_level")
	await _custom_buttons_shot("r5_front_level_custom")

# "menu" is the menu camera's pose. "front" swings the camera round the vertical line through the
# head onto the face's level direction, keeping the menu camera's distance, height above the
# head, pitch and lens, and looks straight back at the face.
func _aim5(s: Dictionary, label: String) -> void:
	var ch: Node3D = s.double.node
	var a = s.double.assigner
	var cam: Camera3D = s.cam
	cam.fov = menu_fov
	var menu := (ch.global_transform * menu_rel).orthonormalized()
	cam.global_transform = menu
	if label.begins_with("front"):
		var head: Vector3 = a.bone_attachment_glasses.global_position
		var face := _face_dir(a)
		face.y = 0.0
		face = face.normalized()
		var off := menu.origin - head
		var e := menu.basis.get_euler()
		var roll := e.z if label == "front_menu_roll" else 0.0
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(e.x, atan2(face.x, face.z), roll)),
			head + face * Vector2(off.x, off.z).length() + Vector3.UP * off.y)
	var from_head: Vector3 = cam.global_position - a.bone_attachment_glasses.global_position
	var face_flat := _face_dir(a)
	face_flat.y = 0.0
	var off_wall := cam.global_position - ROOM_COPY
	say("  P%d cam %s rot %s, %.1f deg round the head off the face's line, %.2f m from the head%s" % [s.i + 1,
		_v(cam.global_position), _v(cam.global_rotation_degrees),
		rad_to_deg(Vector3(from_head.x, 0.0, from_head.z).angle_to(face_flat)), from_head.length(),
		"  CAM PAST WALL" if absf(off_wall.x) > WALL_X else ""])

func _aim4(s: Dictionary, zoom: String, direction: String) -> void:
	var ch: Node3D = s.double.node
	var a = s.double.assigner
	var n := seats.size()
	var left: bool = s.i < (n - 1) * 0.5
	var right: bool = s.i > (n - 1) * 0.5
	var rel := menu_rel
	var mirrored: bool = direction == "mirrored" and ((left and not menu_faces_right) or (right and menu_faces_right))
	if mirrored:
		var flip := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
		rel = flip * rel * flip
	var cam: Camera3D = s.cam
	cam.fov = menu_fov
	cam.global_transform = (ch.global_transform * rel).orthonormalized()
	if zoom == "head_shoulders":
		cam.fov = FOV
		var skel: Skeleton3D = a.get_parent()
		var head: Vector3 = a.bone_attachment_glasses.global_position
		var head_len := head.distance_to(_bone(skel, "neck"))
		# Round 1's "fixed" headroom: the same room above every head.
		var top := head.y + head_len * 2.65
		var bottom := _bone(skel, "chest").y - head_len * 0.3
		var center := Vector3(head.x, (top + bottom) * 0.5, head.z)
		cam.global_position = center + cam.global_basis.z * ((top - bottom) * 0.5) / tan(deg_to_rad(FOV * 0.5))
	var off := cam.global_position - ROOM_COPY
	say("  P%d mirrored %s cam %s%s" % [s.i + 1, mirrored, _v(cam.global_position), "  CAM PAST WALL" if absf(off.x) > WALL_X else ""])

# The camera's pose relative to the character as the scene file holds it, read from an
# instance that never enters the tree: the camera's SubViewport starts its 3D chain.
func _authored_pose(packed: PackedScene) -> void:
	var scene: Node = packed.instantiate()
	var cam: Camera3D = scene.get_node("viewport_character preview/character preview camera parent/camera_character preview feed")
	menu_rel = _chain(scene.get_node("main character2")).affine_inverse() * _chain(cam)
	menu_fov = cam.fov
	scene.free()

func _chain(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

# The shipped close-ups, installed by the runner, would draw over these and share their layers.
func _park_shipped() -> void:
	var cu = lobby.get_node_or_null("CouchLobbyCloseUps")
	if cu == null:
		return
	cu.set_process(false)
	for row in cu._rows:
		row.position.y += cu._lift
	for s in cu._seats.values():
		s.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		(s.double as Node3D).get_parent().visible = false
	lobby.get_node("Control/CouchLobbyStrip").visible = false
	var room: Node3D = lobby.players_node.get_parent()
	for n in ["CouchLobbyRoomCopy", "CouchLobbyLampCopy"]:
		room.get_node(n).visible = false
	say("shipped close-ups parked")

# A blink swaps the eye texture for 0.15 s every 2-4 s; 0.1 s samples over 4.5 s catch one.
func _still(vp: SubViewport, label: String) -> void:
	await RenderingServer.frame_post_draw
	var first := vp.get_texture().get_image()
	var changed := 0
	var flips := 0
	var prev := first
	for k in 45:
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img.get_data() != first.get_data():
			changed += 1
			if changed == 1:
				_save(first, "still_first")
				_save(img, "still_changed")
				say("still: first change at sample %d, %s" % [k, _diff_box(first, img)])
		# One lasting change flips once; a flicker (a blink) flips at least twice.
		if img.get_data() != prev.get_data():
			flips += 1
		prev = img
	ok(label, changed == 0, "%d of 45 samples differ, %d sample-to-sample changes, last sample %s" % [changed, flips,
		"differs" if prev.get_data() != first.get_data() else "matches"])

func _diff_box(a: Image, b: Image) -> String:
	var lo := Vector2i(a.get_width(), a.get_height())
	var hi := Vector2i(-1, -1)
	var most := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var m := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			if m > 0.0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
				most = maxf(most, m)
	return "size %s, changed pixels in %s..%s, largest channel change %.3f" % [a.get_size(), lo, hi, most]

func _look(a) -> Array:
	var g := "none"
	for c in a.bone_attachment_glasses.get_children():
		if c is Node3D and c.visible:
			g = str(c.name)
			break
	return [str(a.get_assigned_hat()), g, str(a.assigned_suit_color)]

func _process(_delta: float) -> void:
	for s in seats:
		if s.has("double"):
			_sync_double(s)

# Three values, each set through the game's own assigner, so More Cosmetics' items and recolour follow.
func _sync_double(s: Dictionary) -> void:
	var want := _look(s.assigner)
	var d = s.double.assigner
	var have := _look(d)
	if want[0] != have[0]:
		if want[0] == "none":
			d.remove_hat()
		else:
			d.assign_hat(want[0])
	if want[1] != have[1]:
		if want[1] == "none":
			d.remove_glasses()
		else:
			d.assign_glasses(want[1])
	if want[2] != have[2]:
		d.assign_suit_color(want[2])

func _check_doubles(label: String) -> void:
	var bad := []
	for s in seats:
		if _look(s.assigner) != _look(s.double.assigner):
			bad.append("P%d %s vs %s" % [s.i + 1, _look(s.assigner), _look(s.double.assigner)])
	ok(label, bad.is_empty(), bad)

# "wall": a panel in the room's own wall material behind the double, for the room's grime.
func _place_backdrop(s: Dictionary, kind: String, head: Vector3, dir: Vector3) -> void:
	var b: MeshInstance3D = s.double.backdrop
	if b == null:
		b = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(8, 8)
		b.mesh = quad
		b.material_override = lobby.players_node.get_parent().get_node("lobby environment1/walls2").get_active_material(0)
		s.double.holder.add_child(b)
		s.double.backdrop = b
	b.visible = kind == "wall"
	# A QuadMesh faces its +Z; this turns that side to the camera.
	b.global_position = head - dir * 1.5
	b.look_at(head - dir * 3.0, Vector3.UP)

func _portraits(label: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	for s in seats:
		_save(s.vp.get_texture().get_image(), "portraits/%s_p%d" % [label, s.i + 1])

func _perf2() -> void:
	say("\n=== perf (ms per frame, averaged over 120 frames)")
	var rids: Array[RID] = [get_tree().root.get_viewport_rid(), room_vp.get_viewport_rid()]
	for s in seats:
		rids.append((s.vp as SubViewport).get_viewport_rid())
	for rid in rids:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	for mode in ["none", "doubles", "staggered"]:
		for s in seats:
			s.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if mode == "doubles" else SubViewport.UPDATE_DISABLED
			s.double.holder.visible = mode != "none"
		await frames(30)
		var gpu := [0.0, 0.0, 0.0]
		var cpu := [0.0, 0.0, 0.0]
		var t0 := Time.get_ticks_usec()
		for f in 120:
			# One close-up redrawn per frame, in turn. A viewport not drawn keeps reporting its last
			# time, so in this mode only the frame time is a measurement.
			if mode == "staggered":
				seats[f % seats.size()].vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			for k in rids.size():
				var slot := mini(k, 2)
				gpu[slot] += RenderingServer.viewport_get_measured_render_time_gpu(rids[k])
				cpu[slot] += RenderingServer.viewport_get_measured_render_time_cpu(rids[k])
		say("%s: frame %.2f  gpu window %.2f room %.2f close-ups %.2f  cpu window %.2f room %.2f close-ups %.2f" % [mode,
			(Time.get_ticks_usec() - t0) / 1000.0 / 120.0, gpu[0] / 120.0, gpu[1] / 120.0, gpu[2] / 120.0, cpu[0] / 120.0, cpu[1] / 120.0, cpu[2] / 120.0])

func _clear(made: Dictionary) -> void:
	for n in made.nodes:
		n.queue_free()
	for r in made.restore:
		r[0].position = r[1]
		r[0].scale = r[2]

func _shot(label: String, made := {}) -> void:
	await frames(12)
	await RenderingServer.frame_post_draw
	var file := out_dir.path_join("%s.png" % label)
	ok("shot %s" % label, get_viewport().get_texture().get_image().save_png(file) == OK, file)
	if not made.is_empty():
		_clear(made)
		await frames(2)

# GPU and CPU render time of the window and of the close-ups, averaged over 120 frames:
# no close-ups, every one rendered each frame, and each rendered once then held.
func _perf() -> void:
	say("\n=== perf (ms per frame, averaged over 120 frames)")
	var made := _overlay("plain", "over_room", "over")
	var rids: Array[RID] = [get_tree().root.get_viewport_rid(), room_vp.get_viewport_rid()]
	for s in seats:
		rids.append((s.vp as SubViewport).get_viewport_rid())
	for rid in rids:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	for mode in ["none", "always", "once"]:
		for s in seats:
			s.vp.render_target_update_mode = {"none": SubViewport.UPDATE_DISABLED, "always": SubViewport.UPDATE_ALWAYS,
				"once": SubViewport.UPDATE_ONCE}[mode]
		await frames(30)
		var gpu := [0.0, 0.0, 0.0]
		var cpu := [0.0, 0.0, 0.0]
		var t0 := Time.get_ticks_usec()
		for f in 120:
			await RenderingServer.frame_post_draw
			for k in rids.size():
				var slot := mini(k, 2)
				gpu[slot] += RenderingServer.viewport_get_measured_render_time_gpu(rids[k])
				cpu[slot] += RenderingServer.viewport_get_measured_render_time_cpu(rids[k])
		var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 120.0
		say("%s: frame %.2f  gpu window %.2f room %.2f close-ups %.2f  cpu window %.2f room %.2f close-ups %.2f" % [mode, frame_ms,
			gpu[0] / 120.0, gpu[1] / 120.0, gpu[2] / 120.0, cpu[0] / 120.0, cpu[1] / 120.0, cpu[2] / 120.0])
	_clear(made)

func _save(img: Image, name: String) -> void:
	var path := out_dir.path_join(name)
	ok("saved %s" % name, img.save_png(path + ".png") == OK)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
