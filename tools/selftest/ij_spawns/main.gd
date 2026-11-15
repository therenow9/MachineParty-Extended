extends Node

# Dev-only, beside `run_playtest.sh launch KnifeAtTheOffice --overtime=mp8 --bots 7 --auto 1 --grace 0
# --extra tools/selftest/ij_spawns`: measures Inside Job's spawn markers for a layout pick.
#   IJ_SPAWNS="x,z;x,z;x,z;x,z"   the four added markers' positions under PlayerSpawnPositions (default: as built)
#   IJ_TAG=b133                   the output folder
#   IJ_MIN=2.0                    the wanted spawn-to-spawn distance for the searched layout
# Writes result.txt (each spawn's fit and nearest neighbour, a floor map, a searched layout, the start shove),
# topdown.png and tiles.png to %TEMP%/machine-party-tests/ij_spawns/<tag>/.

const RADIUS := 0.7          # knife_at_the_office_player.tscn's capsule
const HEIGHT := 5.0
const LIFT := 0.1            # the capsule's bottom this far above the floor, so the floor itself never counts
const STEP := 0.25           # the floor map's and the search's grid

var _dir := ""
var _out: FileAccess
var _game: Node = null
var _layout: Array = []
var _min := 2.0
var _done := false


func say(msg: String) -> void:
	if _out == null:
		_out = FileAccess.open(_dir.path_join("result.txt"), FileAccess.WRITE)
	_out.store_line(msg)
	_out.flush()
	print("[ij_spawns] " + msg)


func _mod_ready(_loader) -> void:
	var tag := OS.get_environment("IJ_TAG")
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/ij_spawns").path_join(tag if tag != "" else "run")
	DirAccess.make_dir_recursive_absolute(_dir)
	var m := OS.get_environment("IJ_MIN")
	if m.is_valid_float():
		_min = float(m)
	for pair in OS.get_environment("IJ_SPAWNS").split(";", false):
		var xz := pair.split(",")
		if xz.size() == 2 and xz[0].is_valid_float() and xz[1].is_valid_float():
			_layout.append(Vector3(float(xz[0]), 0.0, float(xz[1])))
	if not _layout.is_empty() and _layout.size() != 4:
		say("IJ_SPAWNS needs 4 positions, got %d: ignored" % _layout.size())
		_layout.clear()
	get_tree().node_added.connect(_on_node_added)
	say("ij_spawns layout %s min %.2f" % [_layout if not _layout.is_empty() else "as built", _min])


func _on_node_added(node: Node) -> void:
	if _game == null and node is Minigame and String(node.get_script().resource_path).contains("knife_at_the_office.gd"):
		_game = node
		# _ready adds the four markers; initialize() reads them later, so moving them here is in time.
		node.ready.connect(_on_game_ready, CONNECT_ONE_SHOT)


func _on_game_ready() -> void:
	var added := _added()
	if added.size() != 4:
		say("added markers: %d (a mixed room or a changed scene); nothing moved" % added.size())
		return
	if not _layout.is_empty():
		for i in 4:
			added[i].position = _layout[i]
	_measure.call_deferred()


func _markers() -> Array:
	return _game.player_spawn_positions_node.get_children()


func _added() -> Array:
	return _markers().filter(func(m): return String(m.name).ends_with("_MP8V"))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _fits(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, at: Vector3) -> bool:
	q.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, at.y + LIFT + HEIGHT * 0.5, at.z))
	return space.intersect_shape(q, 1).is_empty()


func _measure() -> void:
	for i in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collide_with_areas = false

	var marks := _markers()
	var pts: Array = marks.map(func(m): return m.global_position)
	var names := "1234abcd"
	var y: float = pts[0].y
	say("PlayerSpawnPositions at %s" % _game.player_spawn_positions_node.global_position)
	var worst := INF
	for i in pts.size():
		var near := INF
		for j in pts.size():
			if j != i:
				near = minf(near, _flat(pts[i], pts[j]))
		worst = minf(worst, near)
		say("%s %s local %s global (%.2f, %.2f): fits %s, nearest spawn %.2f m" % [names[i], marks[i].name,
			marks[i].position, pts[i].x, pts[i].z, _fits(space, q, pts[i]), near])
	say("min spawn-to-spawn %.2f m (bodies touch below %.2f)" % [worst, RADIUS * 2.0])

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(4, 4)
	hi += Vector2(4, 4)
	var free := {}
	var rows: PackedStringArray = []
	var z := lo.y
	while z <= hi.y:
		var line := "%6.2f " % z
		var x := lo.x
		while x <= hi.x:
			var at := Vector3(x, y, z)
			var ok := _fits(space, q, at)
			if ok:
				free[Vector2(x, z)] = true
			var c := "." if ok else "#"
			for i in pts.size():
				if _flat(pts[i], at) < STEP * 0.5:
					c = names[i]
			line += c
			x += STEP
		rows.append(line)
		z += STEP
	say("floor map, x %.2f..%.2f across at %.2f m, z down; '.' a body fits, '#' it doesn't:" % [lo.x, hi.x, STEP])
	for r in rows:
		say(r)

	# The searched layout: each added marker at the free point nearest its twin, at least _min from every other spawn.
	var placed: Array = pts.slice(0, 4)
	var found: Array = []
	for i in 4:
		var twin: Vector3 = pts[i]
		var best := Vector2.INF
		var best_d := INF
		for k in free:
			var p := Vector3(k.x, y, k.y)
			var clear := true
			for o in placed:
				if _flat(o, p) < _min:
					clear = false
					break
			if clear and _flat(twin, p) < best_d:
				best_d = _flat(twin, p)
				best = k
		if best == Vector2.INF:
			say("searched layout: no free point for %s" % names[4 + i])
			break
		placed.append(Vector3(best.x, y, best.y))
		found.append(best - Vector2(_game.player_spawn_positions_node.global_position.x, _game.player_spawn_positions_node.global_position.z))
	say("searched layout (min %.2f): IJ_SPAWNS=\"%s\"" % [_min, ";".join(found.map(func(v): return "%.2f,%.2f" % [v.x, v.y]))])

	await _topdown(pts, lo, hi)
	await _shove(pts)


func _topdown(pts: Array, lo: Vector2, hi: Vector2) -> void:
	var cut := 7.0
	var c := OS.get_environment("IJ_CUT")
	if c.is_valid_float():
		cut = float(c)
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, int(1600 * (hi.y - lo.y) / (hi.x - lo.x)))
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = hi.x - lo.x
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.cull_mask = 0b1111      # the world layers; seats' fog layers start at 5
	cam.near = 40.0 - cut       # renders from IJ_CUT m up down to the floor: the ceiling is cut away
	cam.far = 45.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	cam.environment = env
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3((lo.x + hi.x) * 0.5, pts[0].y + 40.0, (lo.y + hi.y) * 0.5))
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var colours := [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.RED, Color.YELLOW, Color.CYAN, Color.MAGENTA]
	for i in pts.size():
		var s := cam.unproject_position(pts[i])
		var r := RADIUS / cam.size * vp.size.x
		for a in 64:
			var e := s + Vector2.from_angle(a * TAU / 64.0) * r
			img.fill_rect(Rect2i(Vector2i(e) - Vector2i(2, 2), Vector2i(4, 4)), colours[i])
		img.fill_rect(Rect2i(Vector2i(s) - Vector2i(3, 3), Vector2i(6, 6)), colours[i])
	img.save_png(_dir.path_join("topdown.png"))
	say("topdown.png: %dx%d, x %.2f..%.2f, z %.2f..%.2f, cut at %.1f m; shipped white, added red/yellow/cyan/magenta (a-d)" % [
		vp.size.x, vp.size.y, lo.x, hi.x, lo.y, hi.y, cut])
	vp.queue_free()


# Each player's distance from the spawn they were put on, 0.5 s after the last one spawned (before play starts).
func _shove(pts: Array) -> void:
	var t := 0.0
	while _game.players.size() < PlayerManager.player_presences.size() and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var start := {}
	for k in _game.players:
		start[k] = _game.players[k].global_position
	await get_tree().create_timer(0.5).timeout
	var moved: PackedStringArray = []
	for k in _game.players:
		var p: Node3D = _game.players[k]
		var near := INF
		for s in pts:
			near = minf(near, _flat(s, start[k]))
		moved.append("%.2f from spawn, moved %.2f" % [near, _flat(start[k], p.global_position)])
	say("players %d: %s" % [_game.players.size(), " | ".join(moved)])
	var t2 := 0.0
	while _game.get("playing") != true and t2 < 12.0:
		await get_tree().process_frame
		t2 += get_process_delta_time()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(_dir.path_join("tiles.png"))
	say("tiles.png saved; DONE")
