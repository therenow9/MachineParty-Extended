extends Node

# Dev-only prototype of the 8-seat local lobby fix, applied at runtime on top of
# Overtime so no fork build is needed: seats 1-4 back to their authored
# transforms, seats 5-8 rebuilt as clones of seats 1-4 one offset away (Overtime's
# online-lobby method), a cloned chair row, and a pulled-back camera.
# Headless it sweeps row offsets and logs the geometry; windowed it also saves
# shots to %TEMP%/machine-party-tests/cl_render/, never into the tree.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const WALL_X := 6.517
const FRONT_Z := 10.877
# Overtime's online lobby: MP8_ROW2_OFFSET and the camera scale in _mp8_extend_lobby.
const RENDERS := [
	{"name": "a_upstream", "offset": Vector3(0.6, 0.0, 5.2), "cam_y": 1.08, "cam_z": 1.22},
	{"name": "b_inside_walls", "offset": Vector3(0.6, 0.0, 4.2), "cam_y": 1.08, "cam_z": 1.22},
	{"name": "c_no_overlap", "offset": Vector3(0.2, 0.0, 5.8), "cam_y": 1.08, "cam_z": 1.22},
]
# The picked layout; the panel labels are rendered on it.
const PICKED := {"offset": Vector3(0.2, 0.0, 5.8), "cam_y": 1.08, "cam_z": 1.22}
# Overtime's _mp8_refresh_identity writes "P%d  %s\n%s  %s" (seat, name, device, ready).
const LABELS := [
	{"name": "now", "format": "P%d  %s\n%s  %s"},
	{"name": "three_lines", "format": "P%d  %s\n%s\n%s"},
	{"name": "aligned", "format": "P%d  %s\n%s\n%s", "float_crown": true},
]
# Names are 4 letters at most (four character selectors); WWWW is the widest.
const NAMES := ["JERM", "ALEX", "SAM", "MAYA", "LEO", "ZOEY", "WWWW", "KAI"]
const READY_SEATS := [1, 4, 6]
const SWEEP_X := [-1.0, -0.6, -0.2, 0.2, 0.6, 1.0, 1.4]
const SWEEP_Z := [3.0, 3.6, 4.2, 4.8, 5.2, 5.8, 6.4]
# One look per seat: hat, glasses, suit. The xc_ ids need more_cosmetics, which the runner installs unless --without.
const LOOKS := [
	["tophat", "sunglasses", "red"], ["xc_sombrero", "none", "xc_teal"],
	["hard_hat", "reading_glasses", "yellow"], ["xc_chef_hat", "xc_monocle_glasses", "green"],
	["traffic_cone", "none", "purple"], ["xc_captain_hat", "xc_eyepatch_glasses", "xc_orange"],
	["maska_helmet", "sunglasses", "blue"], ["xc_propeller_beanie", "xc_disguise_glasses", "xc_pink"],
]

var fails := 0
var out: FileAccess
var lobby: Node
var authored_seats: Array[Transform3D] = []
var authored_cam: Transform3D
var cam: Camera3D
var env: Node3D
var row1 := 4

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_render/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(_loader) -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var packed: PackedScene = load(LOBBY)
	var authored: Node = packed.instantiate()
	for m in authored.players_node.get_children():
		authored_seats.append(m.transform)
	authored_cam = authored.players_node.get_parent().get_node("Camera3D").transform
	row1 = authored_seats.size()
	authored.free()
	say("authored seats %d, camera %s" % [row1, _v(authored_cam.origin)])

	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	lobby = get_tree().current_scene
	var seats: int = lobby.local_lobby_player_controls.size()
	ok("8 seats (Overtime installed)", seats == 8, seats)
	if seats != 8:
		finish()
		return
	var parent: Node3D = lobby.players_node.get_parent()
	cam = parent.get_node("Camera3D")
	env = parent.get_node("lobby environment1")
	# Device -1 is the keyboard; the rest are device ids no pad uses, so nothing reads them as input.
	lobby.join(-1, false)
	for i in range(1, seats):
		lobby.join(100 + i, true)
	await frames(10)
	for i in seats:
		lobby.local_lobby_player_controls[i]._on_name_confirmed(NAMES[i])
	await frames(10)
	var windowed := DisplayServer.get_name() != "headless"
	_dress()
	await frames(5)
	say("\n=== z_overtime_1_7")
	say(_measure(Vector3.ZERO))
	_seat_report()
	if windowed:
		# The lobby fades in from a loading screen (fade_loading_screen, 2 s) behind a 0.5 s overlay fade.
		await get_tree().create_timer(3.5).timeout
		await _shot("z_overtime_1_7")
	_rebuild_row2()
	await frames(5)
	_dress()
	await frames(10)

	say("\n=== sweep: offset -> wall margin, front-z margin, worst head cover, heads in frame")
	for x in SWEEP_X:
		for z in SWEEP_Z:
			await _apply(Vector3(x, 0.0, z), 1.08, 1.22)
			say(_measure(Vector3(x, 0.0, z)))
	for r in RENDERS:
		await _apply(r.offset, r.cam_y, r.cam_z)
		say("\n=== %s" % r.name)
		say(_measure(r.offset))
		_seat_report()
		if windowed:
			await _shot(r.name)
	await _apply(PICKED.offset, PICKED.cam_y, PICKED.cam_z)
	for f in LABELS:
		_label_text(f.format)
		if f.get("float_crown", false):
			_float_crown()
		await frames(3)
		say("\n=== panels_%s" % f.name)
		_label_report()
		if f.get("float_crown", false):
			var tops := {}
			for c in lobby.local_lobby_player_controls:
				tops[snappedf(c.name_label.get_global_rect().position.y, 0.1)] = true
			ok("aligned: all 8 labels start at one height", tops.size() == 1, tops.keys())
		if windowed:
			await _shot("panels_" + f.name)
	finish()

# Real-play label text: the keyboard on seat 1, pads numbered as Overtime prints them (device + 1).
func _label_text(format: String) -> void:
	var controls: Array = lobby.local_lobby_player_controls
	for i in 8:
		var device := "KEYBOARD" if i == 0 else "PAD %d" % i
		var ready := "READY" if READY_SEATS.has(i) else "NOT READY"
		controls[i].name_label.text = format % [i + 1, NAMES[i], device, ready]
		# A Control never shrinks by itself: drop the width the join's longer test text left
		# behind, then lay the panel out the game's way (position, scale 0.65, width 170).
		controls[i].name_label.reset_size()
		controls[i].reset_size()
		controls[i].set_container_position(true)

# The host's crown is a row of the panel's VBox, so it pushes only that panel down; lift the panel by that row.
func _float_crown() -> void:
	for c in lobby.local_lobby_player_controls:
		if c.main_player_icon.visible:
			say("  crown on %s: icon size=%s min=%s separation=%d label_y=%.1f" % [c.name, c.main_player_icon.size,
				c.main_player_icon.get_combined_minimum_size(), c.get_theme_constant("separation"), c.name_label.position.y])
			c.position.y -= (c.main_player_icon.size.y + c.get_theme_constant("separation")) * c.scale.y

# Label boxes on screen (scale included). The text is centred in its box, which can be wider;
# gap is the space between this label's text and the next seat's, negative when they overlap.
func _label_report() -> void:
	var controls: Array = lobby.local_lobby_player_controls
	var worst := INF
	for i in 8:
		var r: Rect2 = controls[i].name_label.get_global_rect()
		var gap := INF
		if i < 7:
			gap = _text_span(controls[i + 1]).x - _text_span(controls[i]).y
			worst = minf(worst, gap)
		say("  P%d label x=%.1f..%.1f y=%.1f..%.1f local_width=%.1f text_width=%.1f align=%d gap_to_next=%.1f" % [i + 1,
			r.position.x, r.end.x, r.position.y, r.end.y, controls[i].name_label.size.x,
			controls[i].name_label.get_minimum_size().x, controls[i].name_label.horizontal_alignment, gap])
	say("  worst gap %.1f px" % worst)

func _text_span(c: Control) -> Vector2:
	var r: Rect2 = c.name_label.get_global_rect()
	var w: float = c.name_label.get_minimum_size().x * c.get_global_transform().get_scale().x
	var x0: float = r.position.x + (r.size.x - w) * 0.5
	return Vector2(x0, x0 + w)

# Overtime's clones are all copies of seat 1; replace them with copies of seats 1-4 in turn.
func _rebuild_row2() -> void:
	var players: Node3D = lobby.players_node
	var controls: Array = lobby.local_lobby_player_controls
	for j in range(row1, 8):
		var src: Node3D = players.get_child(j % row1)
		var old: Node3D = players.get_child(j)
		var assigner_path: NodePath = src.get_path_to(controls[j % row1].customization_assigner)
		var dup: Node3D = src.duplicate(14)
		_rebind(src, dup, src, dup)
		dup.name = "CLSeat%d" % (j + 1)
		players.add_child(dup)
		players.move_child(dup, j)
		players.remove_child(old)
		old.queue_free()
		controls[j].customization_assigner = dup.get_node(assigner_path)
		dup.visible = true
	ok("row 2 rebuilt from seats 1-4", players.get_child_count() == 8, players.get_child_count())

func _rebind(source: Node, copy: Node, source_root: Node, copy_root: Node) -> void:
	for p in source.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value = source.get(p.name)
		if value is Node and (value == source_root or source_root.is_ancestor_of(value)):
			copy.set(p.name, copy_root.get_node(source_root.get_path_to(value)))
		elif value is Array:
			var arr: Array = value.duplicate()
			for i in arr.size():
				if arr[i] is Node and (arr[i] == source_root or source_root.is_ancestor_of(arr[i])):
					arr[i] = copy_root.get_node(source_root.get_path_to(arr[i]))
			copy.set(p.name, arr)
	for i in source.get_child_count():
		_rebind(source.get_child(i), copy.get_child(i), source_root, copy_root)

func _dress() -> void:
	var controls: Array = lobby.local_lobby_player_controls
	for i in 8:
		var a = controls[i].customization_assigner
		a.assign_hat(LOOKS[i][0])
		a.assign_glasses(LOOKS[i][1])
		a.assign_suit_color(LOOKS[i][2])

func _apply(offset: Vector3, cam_y: float, cam_z: float) -> void:
	var players: Node3D = lobby.players_node
	for i in 8:
		var t: Transform3D = authored_seats[i % row1]
		if i >= row1:
			t.origin += offset
		players.get_child(i).transform = t
	var holder := env.get_node_or_null("CLChairRow")
	if holder:
		env.remove_child(holder)
		holder.free()
	holder = Node3D.new()
	holder.name = "CLChairRow"
	env.add_child(holder)
	for c in env.get_children():
		if c != holder and c is Node3D and c.visible and String(c.name).to_lower().begins_with("chair"):
			var d: Node3D = c.duplicate()
			holder.add_child(d)
			d.transform = c.transform
			d.position = c.position + offset
	var ct := authored_cam
	ct.origin = Vector3(ct.origin.x, ct.origin.y * cam_y, ct.origin.z * cam_z)
	cam.transform = ct
	await frames(3)

func _body(i: int) -> AABB:
	var skel: Skeleton3D = lobby.players_node.get_child(i).find_children("*", "Skeleton3D", true, false)[0]
	var box := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
	for b in skel.get_bone_count():
		box = box.expand(skel.global_transform * skel.get_bone_global_pose(b).origin)
	return box

func _head(i: int) -> Vector3:
	return lobby.local_lobby_player_controls[i].customization_assigner.bone_attachment_glasses.global_position

func _screen_rect(box: AABB) -> Rect2:
	var r := Rect2(cam.unproject_position(box.get_endpoint(0)), Vector2.ZERO)
	for k in range(1, 8):
		r = r.expand(cam.unproject_position(box.get_endpoint(k)))
	return r

# Head cover: the share of a head's screen box (0.5 m around the head bone) that a
# nearer body's screen box covers. A screen-box estimate, not a pixel count.
func _measure(offset: Vector3) -> String:
	var wall := INF
	var front := INF
	var bodies: Array[AABB] = []
	for i in 8:
		var b := _body(i)
		bodies.append(b)
		wall = minf(wall, minf(b.position.x + WALL_X, WALL_X - b.end.x))
		front = minf(front, FRONT_Z - b.end.z)
	var size := cam.get_viewport().get_visible_rect().size
	var worst := 0.0
	var worst_pair := ""
	var in_frame := 0
	for i in 8:
		var h := _head(i)
		var p := cam.unproject_position(h)
		if not cam.is_position_behind(h) and Rect2(Vector2.ZERO, size).has_point(p):
			in_frame += 1
		var head_rect := _screen_rect(AABB(h - Vector3.ONE * 0.25, Vector3.ONE * 0.5))
		for j in 8:
			if j == i or cam.global_position.distance_to(bodies[j].get_center()) >= cam.global_position.distance_to(h):
				continue
			var cover := head_rect.intersection(_screen_rect(bodies[j])).get_area() / maxf(head_rect.get_area(), 0.001)
			if cover > worst:
				worst = cover
				worst_pair = "P%d behind P%d" % [i + 1, j + 1]
	return "offset %s  wall %.2f  front %.2f  head_cover %.2f %s  in_frame %d/8" % [_v(offset), wall, front, worst, worst_pair, in_frame]

func _seat_report() -> void:
	for i in 8:
		var h := _head(i)
		say("  P%d body=%s head_screen=%s" % [i + 1, _aabb(_body(i)), cam.unproject_position(h)])

func _shot(label: String) -> void:
	var dir := OS.get_environment("TEMP").path_join("machine-party-tests/cl_render")
	if not dir.is_absolute_path():
		ok("TEMP is set", false, dir)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(20)
	await RenderingServer.frame_post_draw
	var file := dir.path_join("%s.png" % label)
	ok("shot %s" % label, get_viewport().get_texture().get_image().save_png(file) == OK, file)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _aabb(a: AABB) -> String:
	return "%s..%s" % [_v(a.position), _v(a.end)]
