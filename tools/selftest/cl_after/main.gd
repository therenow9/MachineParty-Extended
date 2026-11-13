extends Node

# Dev-only acceptance test of the fork's 8-seat local lobby, through Overtime's own code path
# with no runtime re-layout (cl_render prototypes the layout; this checks the build).
# On stock Overtime 1.7 it fails by design. Windowed it also saves shots to
# %TEMP%/machine-party-tests/cl_after/, never into the tree.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const WALL_X := 6.517
# Row 2's offset and the camera scale, as picked from renders.
const OFFSET := Vector3(0.2, 0.0, 5.8)
# Seat 6 and its chair (the copy of chair_001) sit further toward the camera, clear of seat 3's legs.
const SEAT6 := 5
const SEAT6_NUDGE := Vector3(0.0, 0.0, 0.6)
# A leg's centre line to a chair or body not its own; a shoe or trouser leg takes up the first 0.1-0.15 m.
const LEG_CLEARANCE := 0.2
const CAM_Y := 1.08
const CAM_Z := 1.22
# The lobby camera drifts by itself (about 0.001 over a run); a scaled-twice camera is metres off.
const CAM_DRIFT := 0.05
const NAMES := ["JERM", "ALEX", "SAM", "MAYA", "LEO", "ZOEY", "WWWWWWW", "KAI"]
# P1 is among them: the host's crown must not move its panel off the others' height when ready.
const READY_SEATS := [0, 4, 6]
# The xc_ ids need more_cosmetics, which the runner installs unless --without.
const LOOKS := [
	["tophat", "sunglasses", "red"], ["xc_sombrero", "none", "xc_teal"],
	["hard_hat", "reading_glasses", "yellow"], ["xc_chef_hat", "xc_monocle_glasses", "green"],
	["traffic_cone", "none", "purple"], ["xc_captain_hat", "xc_eyepatch_glasses", "xc_orange"],
	["maska_helmet", "sunglasses", "blue"], ["xc_propeller_beanie", "xc_disguise_glasses", "xc_pink"],
]

var fails := 0
var out: FileAccess
var lobby: Node
var cam: Camera3D

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_after/result.txt"), FileAccess.WRITE)
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
	# An instance that never entered the tree is the scene as authored: no _enter_tree has run.
	var authored: Node = (load(LOBBY) as PackedScene).instantiate()
	var seats: Array[Transform3D] = []
	for m in authored.players_node.get_children():
		seats.append(m.transform)
	var room: Node3D = authored.players_node.get_parent()
	var cam0: Vector3 = room.get_node("Camera3D").position
	var chairs := {}
	for c in room.get_node("lobby environment1").get_children():
		if c is Node3D and c.visible and String(c.name).to_lower().begins_with("chair"):
			chairs[String(c.name)] = c.position
	authored.free()
	var n := seats.size()
	say("authored seats %d, camera %s, visible chairs %d" % [n, cam0, chairs.size()])

	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	lobby = get_tree().current_scene
	var players: Node3D = lobby.players_node
	var controls: Array = lobby.local_lobby_player_controls
	ok("8 seats", controls.size() == 8 and players.get_child_count() == 8, [controls.size(), players.get_child_count()])
	if controls.size() != 8 or players.get_child_count() != 8:
		finish()
		return
	room = players.get_parent()
	cam = room.get_node("Camera3D")

	for i in 8:
		var want: Transform3D = seats[i % n]
		if i >= n:
			want.origin += OFFSET
		if i == SEAT6:
			want.origin += SEAT6_NUDGE
		var t: Transform3D = players.get_child(i).transform
		ok("P%d model at its picked transform" % (i + 1), t.is_equal_approx(want), "%s want %s" % [t.origin, want.origin])
	var assigners := {}
	for i in 8:
		var a: Node = controls[i].customization_assigner
		assigners[a] = true
		ok("P%d dresser is inside its own model" % (i + 1), players.get_child(i).is_ancestor_of(a), a.get_path())
	ok("8 distinct dressers", assigners.size() == 8, assigners.size())

	var row: Node = room.get_node("lobby environment1").get_node_or_null("MP8ChairRow")
	ok("chair row exists", row != null)
	if row:
		ok("one chair copy per visible chair", row.get_child_count() == chairs.size(), [row.get_child_count(), chairs.size()])
		for c in row.get_children():
			var src := String(c.name).trim_prefix("MP8")
			var shift: Vector3 = OFFSET + (SEAT6_NUDGE if src == "chair_001" else Vector3.ZERO)
			ok("chair %s at +offset" % src, chairs.has(src) and c.position.is_equal_approx(chairs[src] + shift), c.position)
	var cam_want := Vector3(cam0.x, cam0.y * CAM_Y, cam0.z * CAM_Z)
	ok("camera pulled back", cam.position.distance_to(cam_want) < CAM_DRIFT, "%s want %s" % [cam.position, cam_want])

	# Device -1 is the keyboard; the rest are device ids no pad uses, so nothing reads them as input.
	lobby.join(-1, false)
	for i in range(1, 8):
		lobby.join(100 + i, true)
	await frames(10)
	for i in 8:
		controls[i]._on_name_confirmed(NAMES[i])
	_dress()
	await frames(10)

	for i in 8:
		var b := _body(i)
		ok("P%d body inside the side walls" % (i + 1), b.position.x > -WALL_X and b.end.x < WALL_X, _aabb(b))
		var h := _head(i)
		var on_screen := not cam.is_position_behind(h) and cam.get_viewport().get_visible_rect().has_point(cam.unproject_position(h))
		ok("P%d head in frame" % (i + 1), on_screen, cam.unproject_position(h))
	var clear := _clearance()
	ok("every seated leg clears the chairs and bodies not its own (m)", clear["min"] >= LEG_CLEARANCE, "%.3f, %s" % [clear["min"], clear["worst"]])
	for i in 8:
		ok("P%d label has three lines" % (i + 1), controls[i].name_label.text.split("\n").size() == 3, controls[i].name_label.text.c_escape())
	_label_report()
	ok("all 8 labels start at one height", _tops([0, 1, 2, 3, 4, 5, 6, 7]).size() == 1, _tops([0, 1, 2, 3, 4, 5, 6, 7]))
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		# The lobby fades in from a loading screen (fade_loading_screen, 2 s) behind a 0.5 s overlay fade.
		await get_tree().create_timer(3.5).timeout
		await _shot("after")

	for s in READY_SEATS:
		controls[s].set_player_ready(true)
	await frames(5)
	var others := range(8).filter(func(i): return not READY_SEATS.has(i))
	ok("ready labels start at one height", _tops(READY_SEATS).size() == 1, _tops(READY_SEATS))
	ok("unready labels start at one height", _tops(others).size() == 1, _tops(others))
	if windowed:
		await _shot("after_ready")
	for s in READY_SEATS:
		controls[s].set_player_ready(false)
	await frames(5)
	ok("all 8 labels level again after unready", _tops([0, 1, 2, 3, 4, 5, 6, 7]).size() == 1, _tops([0, 1, 2, 3, 4, 5, 6, 7]))

	# _enter_tree runs again on re-entry; the layout must not apply twice.
	var cam_before := cam.position
	var parent := lobby.get_parent()
	parent.remove_child(lobby)
	parent.add_child(lobby)
	await frames(3)
	ok("re-entry keeps the camera", cam.position.distance_to(cam_before) < CAM_DRIFT, "%s before %s" % [cam.position, cam_before])
	ok("re-entry keeps 8 seats", controls.size() == 8 and players.get_child_count() == 8, [controls.size(), players.get_child_count()])
	# A second holder would get another name (MP8ChairRow2), so count every holder, not the one found earlier.
	var holders := room.get_node("lobby environment1").get_children().filter(func(c): return String(c.name).begins_with("MP8ChairRow"))
	ok("re-entry keeps one chair row", holders.size() == 1 and holders[0].get_child_count() == chairs.size(), holders.map(func(h): return [h.name, h.get_child_count()]))
	var moved := []
	for i in 8:
		var want: Transform3D = seats[i % n]
		if i >= n:
			want.origin += OFFSET
		if i == SEAT6:
			want.origin += SEAT6_NUDGE
		if not players.get_child(i).transform.is_equal_approx(want):
			moved.append(i + 1)
	ok("re-entry keeps every model where it was", moved.is_empty(), moved)
	# Panels are not checked here: on re-entry they move by the same amount on stock 1.7.
	say("  after re-entry, label tops %s" % [_tops([0, 1, 2, 3, 4, 5, 6, 7])])
	finish()

func _tops(ids: Array) -> Array:
	var tops := {}
	for i in ids:
		tops[snappedf(lobby.local_lobby_player_controls[i].name_label.get_global_rect().position.y, 0.1)] = true
	return tops.keys()

# Gap: the space between this label's text and the next seat's text on screen, negative when they overlap.
func _label_report() -> void:
	var controls: Array = lobby.local_lobby_player_controls
	var worst := INF
	for i in 7:
		worst = minf(worst, _text_span(controls[i + 1]).x - _text_span(controls[i]).y)
	ok("label texts do not run into the next panel", worst > 0.0, "worst gap %.1f px" % worst)

func _text_span(c: Control) -> Vector2:
	var r: Rect2 = c.name_label.get_global_rect()
	var w: float = c.name_label.get_minimum_size().x * c.get_global_transform().get_scale().x
	var x0: float = r.position.x + (r.size.x - w) * 0.5
	return Vector2(x0, x0 + w)

func _dress() -> void:
	var controls: Array = lobby.local_lobby_player_controls
	for i in 8:
		var a = controls[i].customization_assigner
		a.assign_hat(LOOKS[i][0])
		a.assign_glasses(LOOKS[i][1])
		a.assign_suit_color(LOOKS[i][2])

func _body(i: int) -> AABB:
	var skel: Skeleton3D = lobby.players_node.get_child(i).find_children("*", "Skeleton3D", true, false)[0]
	var box := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
	for b in skel.get_bone_count():
		box = box.expand(skel.global_transform * skel.get_bone_global_pose(b).origin)
	return box

# A seat's own chair is the shown chair nearest its hips.
func _own_chair(model: Node3D, chairs: Array) -> Node:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var hips := skel.global_transform * skel.get_bone_global_pose(0).origin
	var best: Node = null
	var best_d := INF
	for c in chairs:
		var d: float = c["box"].get_center().distance_to(hips)
		if d < best_d:
			best_d = d
			best = c["node"]
	return best

func _segments(skel: Skeleton3D, legs_only: bool) -> Array:
	var out: Array = []
	for bi in skel.get_bone_count():
		var bn := skel.get_bone_name(bi)
		if legs_only and not (bn.begins_with("thigh") or bn.begins_with("shin") or bn.begins_with("foot") or bn.begins_with("toe")):
			continue
		var parent := skel.get_bone_parent(bi)
		if parent >= 0:
			out.append([bn, skel.global_transform * skel.get_bone_global_pose(parent).origin, skel.global_transform * skel.get_bone_global_pose(bi).origin])
	return out

# The least distance from any seated leg's bones to a shown chair's triangles or another seated body's
# bones. Better Couch Lobby's room copy for the close-ups is far off at x 400 and left out.
func _clearance() -> Dictionary:
	var chairs: Array = []
	for m in lobby.find_children("*chair*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and m.mesh and absf(m.global_position.x) < 100.0:
			var faces: PackedVector3Array = m.mesh.get_faces()
			var xf: Transform3D = m.global_transform
			for i in faces.size():
				faces[i] = xf * faces[i]
			chairs.append({"node": m, "box": xf * m.mesh.get_aabb(), "faces": faces})
	var models: Array = lobby.players_node.get_children().filter(func(m): return m is Node3D and m.is_visible_in_tree())
	var least := INF
	var worst := ""
	for m in models:
		var mine := _own_chair(m, chairs)
		var legs := _segments(m.find_children("*", "Skeleton3D", true, false)[0], true)
		for c in chairs:
			if c["node"] == mine:
				continue
			var near: AABB = c["box"].grow(0.6)
			for g in legs:
				if near.has_point(g[1]) or near.has_point(g[2]):
					var d := _seg_to_faces(g[1], g[2], c["faces"])
					if d < least:
						least = d
						worst = "%s %s to %s" % [m.name, g[0], c["node"].name]
		for o in models:
			if o == m:
				continue
			for g in legs:
				for h in _segments(o.find_children("*", "Skeleton3D", true, false)[0], false):
					var pts := Geometry3D.get_closest_points_between_segments(g[1], g[2], h[1], h[2])
					var d: float = pts[0].distance_to(pts[1])
					if d < least:
						least = d
						worst = "%s %s to %s %s" % [m.name, g[0], o.name, h[0]]
	return {"min": least, "worst": worst}

func _seg_to_faces(p: Vector3, q: Vector3, faces: PackedVector3Array) -> float:
	var best := INF
	for t in range(0, faces.size(), 3):
		for k in 5:
			var x := p.lerp(q, k / 4.0)
			best = minf(best, _closest_on_tri(x, faces[t], faces[t + 1], faces[t + 2]).distance_to(x))
	return best

func _closest_on_tri(x: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return a
	var proj := Plane(n.normalized(), a).project(x)
	var bary := Geometry3D.get_triangle_barycentric_coords(proj, a, b, c)
	if bary.x >= 0.0 and bary.y >= 0.0 and bary.z >= 0.0:
		return proj
	var best := Geometry3D.get_closest_point_to_segment(x, a, b)
	for e in [[b, c], [c, a]]:
		var cp := Geometry3D.get_closest_point_to_segment(x, e[0], e[1])
		if cp.distance_to(x) < best.distance_to(x):
			best = cp
	return best

func _head(i: int) -> Vector3:
	return lobby.local_lobby_player_controls[i].customization_assigner.bone_attachment_glasses.global_position

func _shot(label: String) -> void:
	var dir := OS.get_environment("TEMP").path_join("machine-party-tests/cl_after")
	if not dir.is_absolute_path():
		ok("TEMP is set", false, dir)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(20)
	await RenderingServer.frame_post_draw
	var file := dir.path_join("%s.png" % label)
	ok("shot %s" % label, get_viewport().get_texture().get_image().save_png(file) == OK, file)

func frames(k: int) -> void:
	for i in k: await get_tree().process_frame

func _aabb(a: AABB) -> String:
	return "(%.2f, %.2f, %.2f)..(%.2f, %.2f, %.2f)" % [a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z]
