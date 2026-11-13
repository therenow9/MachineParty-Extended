extends Node

# Dev-only recon for the local lobby's 8-seat layout. Dumps the lobby as authored
# (an instance that never entered the tree, so no mod's _enter_tree has moved it)
# and as live, into result.txt. Windowed, it also saves a shot of 8 joined seats
# to %TEMP%/machine-party-tests/cl_recon/, never into the tree.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"

var fails := 0
var out: FileAccess

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_recon/result.txt"), FileAccess.WRITE)
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
	ok("loads %s" % LOBBY, packed != null)
	if packed == null:
		finish()
		return
	var authored: Node = packed.instantiate()
	say("\n=== authored: script %s" % authored.get_script().resource_path)
	_seats(authored)
	_dump(authored, authored, 0, Transform3D.IDENTITY)
	authored.free()

	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	var lobby: Node = get_tree().current_scene
	say("\n=== live after _enter_tree: script %s, MAX_PLAYERS %s" % [lobby.get_script().resource_path,
		lobby.get_script().get_script_constant_map().get("MAX_PLAYERS")])
	var seats: int = lobby.local_lobby_player_controls.size()
	ok("live seat count", seats > 0, seats)
	# Device -1 is the keyboard; the rest are device ids no pad uses, so nothing reads them as input.
	lobby.join(-1, false)
	for i in range(1, seats):
		lobby.join(100 + i, true)
	await frames(20)
	ok("every seat joined", lobby.player_data.size() == seats, lobby.player_data.size())
	_seats(lobby)
	_dump(lobby, lobby, 0, Transform3D.IDENTITY)
	_contacts(lobby)
	if DisplayServer.get_name() != "headless":
		await _shot()
	if lobby.players_node.get_child_count() == 8:
		await _what_if(lobby)
	finish()

func _seats(lobby: Node) -> void:
	var players: Node3D = lobby.players_node
	say("players_node %s pos=%s viewport=%s" % [lobby.get_path_to(players), _v(players.position),
		players.get_viewport().get_class() if players.is_inside_tree() else "-"])
	for m in players.get_children():
		if m is Node3D:
			say("  model %s pos=%s rot_deg=%s scale=%s%s%s" % [m.name, _v(m.position), _v(m.rotation_degrees),
				_v(m.scale), "" if m.visible else " hidden", _body(m)])
	for c in lobby.local_lobby_player_controls:
		say("  controls %s seat=%s pos=%s scale=%s size=%s%s" % [c.name, str(c.get("seat_index")), c.position,
			c.scale, c.size, "" if c.visible else " hidden"])

# The seated pose is baked below the model root, so the root's position is not where the body sits.
func _body(model: Node3D) -> String:
	if not model.is_inside_tree():
		return ""
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return " no skeleton"
	var skel: Skeleton3D = skels[0]
	var box := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
	for b in skel.get_bone_count():
		box = box.expand(skel.global_transform * skel.get_bone_global_pose(b).origin)
	return " body=%s" % _aabb(box)

# Each seated body's leg and foot bones against every shown chair: a bone inside a chair's box, and
# the distance from the bone's segment to the chair's nearest triangle (the box alone is coarse).
func _contacts(lobby: Node) -> void:
	say("
=== contacts")
	var chairs: Array = []
	# Extended's cloned row is MP8chair_*; Better Couch Lobby's room copy for the close-ups is far off at x 400.
	for m in lobby.find_children("*chair*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and m.mesh and absf(m.global_position.x) < 100.0:
			var faces: PackedVector3Array = m.mesh.get_faces()
			var xf: Transform3D = m.global_transform
			for i in faces.size():
				faces[i] = xf * faces[i]
			chairs.append({"name": "%s/%s" % [m.get_parent().name, m.name], "box": xf * m.mesh.get_aabb(), "faces": faces})
	say("chairs shown: %d" % chairs.size())
	for model in lobby.players_node.get_children():
		if not (model is Node3D and model.is_visible_in_tree()):
			continue
		var body := _body(model)
		var skels: Array = model.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			continue
		var skel: Skeleton3D = skels[0]
		var hips := skel.global_transform * skel.get_bone_global_pose(0).origin
		var own := ""
		var own_d := INF
		for c in chairs:
			var d: float = c["box"].get_center().distance_to(hips)
			if d < own_d:
				own_d = d
				own = c["name"]
		say("%s hips %s, own chair %s (%.2f)%s" % [model.name, _v(hips), own, own_d, body])
		if model.get_index() == 0:
			var bones: Array = []
			for bi in skel.get_bone_count():
				bones.append(skel.get_bone_name(bi))
			say("bones: %s" % ", ".join(bones))
		for bi in skel.get_bone_count():
			var bn := skel.get_bone_name(bi).to_lower()
			if not (bn.contains("leg") or bn.contains("foot") or bn.contains("thigh") or bn.contains("shin") or bn.contains("calf") or bn.contains("knee") or bn.contains("toe")):
				continue
			var a := skel.global_transform * skel.get_bone_global_pose(bi).origin
			var parent := skel.get_bone_parent(bi)
			var pa := skel.global_transform * skel.get_bone_global_pose(parent).origin if parent >= 0 else a
			for c in chairs:
				if c["name"] == own:
					continue
				var near: AABB = c["box"].grow(0.3)
				if not (near.has_point(a) or near.has_point(pa) or near.has_point(pa.lerp(a, 0.5))):
					continue
				var d := _seg_to_faces(pa, a, c["faces"])
				var inside: bool = c["box"].has_point(a)
				if inside or d < 0.25:
					say("  %s bone %s %s: chair %s, inside box %s, segment to chair %.3f" % [model.name, skel.get_bone_name(bi), _v(a), c["name"], inside, d])

# Extended's second row as built, then as the online lobby builds it (its offset and seat 6's nudge, less the
# couch lobby's, read from both scripts), each seat moved with its own chair, then measured: the least clearance
# from any seated leg to a chair not its own or to another seated body. The online camera is not used.
const ROW2 := [4, 5, 6, 7]

func _cases(lobby: Node) -> Array:
	var net: Dictionary = NetworkManager.get_script().get_script_constant_map()
	var loc: Dictionary = lobby.get_script().get_script_constant_map()
	var keys := ["MP8_ROW2_OFFSET", "MP8_ROW2_SEAT6_NUDGE"]
	var local_keys := ["MP8_LOCAL_ROW2_OFFSET", "MP8_LOCAL_SEAT6_NUDGE"]
	var out: Array = [{"id": "as_built", "moves": {}}]
	if keys.all(func(k): return net.has(k)) and local_keys.all(func(k): return loc.has(k)):
		out.append({"id": "online_row", "row2": net["MP8_ROW2_OFFSET"] - loc["MP8_LOCAL_ROW2_OFFSET"],
			"moves": {5: net["MP8_ROW2_SEAT6_NUDGE"] - loc["MP8_LOCAL_SEAT6_NUDGE"]}})
	else:
		say("online_row skipped: this build has no seat 6 nudge constants")
	return out

func _what_if(lobby: Node) -> void:
	say("
=== what if")
	# The seats' panels cover the bodies in a shot; the what-if shots are of the room only.
	for c in lobby.local_lobby_player_controls:
		c.visible = false
	await get_tree().create_timer(2.0).timeout
	var seats: Array = lobby.players_node.get_children()
	var own := {}
	for i in seats.size():
		own[i] = _own_chair(lobby, seats[i])
	for w in _cases(lobby):
		var moves: Dictionary = w.get("moves", {}).duplicate()
		if w.has("row2"):
			for i in ROW2:
				moves[i] = w["row2"] + moves.get(i, Vector3.ZERO)
		for i in moves:
			seats[i].position += moves[i]
			if own[i]:
				own[i].position += moves[i]
		await frames(3)
		var r := _clearance(lobby)
		say("WHATIF %s: least clearance %.3f m (%s)" % [w["id"], r["min"], r["worst"]])
		for line in r["close"]:
			say("  " + line)
		if DisplayServer.get_name() != "headless" and not String(w["id"]).begins_with("online_row"):
			await _shot_as("whatif_" + w["id"])
		for i in moves:
			seats[i].position -= moves[i]
			if own[i]:
				own[i].position -= moves[i]
		await frames(2)

func _own_chair(lobby: Node, model: Node3D) -> Node3D:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var hips := skel.global_transform * skel.get_bone_global_pose(0).origin
	var best: Node3D = null
	var best_d := INF
	for m in lobby.find_children("*chair*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and m.mesh and absf(m.global_position.x) < 100.0:
			var d: float = (m.global_transform * m.mesh.get_aabb()).get_center().distance_to(hips)
			if d < best_d:
				best_d = d
				best = m
	return best

func _segments(skel: Skeleton3D, legs_only: bool) -> Array:
	var out: Array = []
	for bi in skel.get_bone_count():
		var bn := skel.get_bone_name(bi)
		if legs_only and not (bn.begins_with("thigh") or bn.begins_with("shin") or bn.begins_with("foot") or bn.begins_with("toe")):
			continue
		var parent := skel.get_bone_parent(bi)
		if parent < 0:
			continue
		out.append([bn, skel.global_transform * skel.get_bone_global_pose(parent).origin, skel.global_transform * skel.get_bone_global_pose(bi).origin])
	return out

func _clearance(lobby: Node) -> Dictionary:
	var models: Array = []
	for m in lobby.players_node.get_children():
		if m is Node3D and m.is_visible_in_tree():
			models.append(m)
	var chairs: Array = []
	for m in lobby.find_children("*chair*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree() and m.mesh and absf(m.global_position.x) < 100.0:
			var faces: PackedVector3Array = m.mesh.get_faces()
			var xf: Transform3D = m.global_transform
			for i in faces.size():
				faces[i] = xf * faces[i]
			chairs.append({"node": m, "box": xf * m.mesh.get_aabb(), "faces": faces})
	var least := INF
	var worst := ""
	var close: Array = []
	for m in models:
		var skel: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		var mine := _own_chair(lobby, m)
		var legs := _segments(skel, true)
		for c in chairs:
			if c["node"] == mine:
				continue
			var near: AABB = c["box"].grow(0.6)
			for g in legs:
				if not (near.has_point(g[1]) or near.has_point(g[2])):
					continue
				var d := _seg_to_faces(g[1], g[2], c["faces"])
				if d < least:
					least = d
					worst = "%s %s to %s" % [m.name, g[0], c["node"].name]
				if d < 0.25:
					close.append("%s %s to chair %s: %.3f" % [m.name, g[0], c["node"].name, d])
		for o in models:
			if o == m:
				continue
			var oskel: Skeleton3D = o.find_children("*", "Skeleton3D", true, false)[0]
			for g in legs:
				for h in _segments(oskel, false):
					var pts := Geometry3D.get_closest_points_between_segments(g[1], g[2], h[1], h[2])
					var d: float = pts[0].distance_to(pts[1])
					if d < least:
						least = d
						worst = "%s %s to %s %s" % [m.name, g[0], o.name, h[0]]
					if d < 0.25:
						close.append("%s %s to %s %s: %.3f" % [m.name, g[0], o.name, h[0], d])
	return {"min": least, "worst": worst, "close": close}

func _seg_to_faces(p: Vector3, q: Vector3, faces: PackedVector3Array) -> float:
	var best := INF
	for t in range(0, faces.size(), 3):
		for k in 5:
			var x := p.lerp(q, k / 4.0)
			var cp := _closest_on_tri(x, faces[t], faces[t + 1], faces[t + 2])
			best = minf(best, cp.distance_to(x))
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

# Player models print two levels only: their skeletons and cosmetics are xc_recon's.
func _dump(node: Node, root: Node, depth: int, parent_xf: Transform3D) -> void:
	var line := "%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()]
	var xf := Transform3D.IDENTITY
	if node is Node3D:
		xf = parent_xf * node.transform
		line += " pos=%s rot_deg=%s scale=%s world=%s" % [_v(node.position), _v(node.rotation_degrees), _v(node.scale), _v(xf.origin)]
		if not node.visible:
			line += " hidden"
	elif node is Control:
		line += " pos=%s size=%s scale=%s" % [node.position, node.size, node.scale]
		if not node.visible:
			line += " hidden"
	elif node is SubViewport:
		line += " size=%s" % node.size
	if node is Camera3D:
		line += " fov=%.2f projection=%d near=%.2f far=%.1f current=%s" % [node.fov, node.projection, node.near, node.far, node.current]
	if node is MeshInstance3D and node.mesh:
		line += " mesh=%s world_aabb=%s" % [node.mesh.resource_path.get_file(), _aabb(xf * node.mesh.get_aabb())]
	say(line)
	var players: Node = root.get("players_node")
	if players and node.get_parent() == players:
		return
	for child in node.get_children():
		_dump(child, root, depth + 1, xf if node is Node3D else Transform3D.IDENTITY)

func _shot_as(id: String) -> void:
	var dir := OS.get_environment("TEMP").path_join("machine-party-tests/cl_recon")
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(10)
	await RenderingServer.frame_post_draw
	var file := dir.path_join("%s.png" % id)
	ok("shot %s" % id, get_viewport().get_texture().get_image().save_png(file) == OK, file)

func _shot() -> void:
	var dir := OS.get_environment("TEMP").path_join("machine-party-tests/cl_recon")
	if not dir.is_absolute_path():
		ok("TEMP is set", false, dir)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(30)
	await RenderingServer.frame_post_draw
	var file := dir.path_join("lobby_live.png")
	var err := get_viewport().get_texture().get_image().save_png(file)
	ok("shot saved", err == OK, file)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _aabb(a: AABB) -> String:
	return "%s..%s" % [_v(a.position), _v(a.end)]
