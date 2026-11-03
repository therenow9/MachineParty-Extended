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
	if DisplayServer.get_name() != "headless":
		await _shot()
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
