extends Node

# Dev-only and windowed, beside `run_playtest.sh launch SpineBreaker --overtime=mp8 --bots 5 --auto 2 --grace 0
# --record <clip.avi> --extra tools/selftest/sb_grace` (one round; --auto 1 --grace N restarts per round): stages Spine Breaker's two spiders on the live round for the
# owner's pick of the throw grace. Offline Bots' manager is paused, so the other players stand still; the actors are
# driven through movement_input and throw through the player's own throw_spine_breaker_rpc.
#   SB_GRACE_SCENES=drop,passing,heels,throwback   the scenes, in order (default all)
#   SB_GRACE_TAG=b116-1.5                           the output folder and the build line on screen
#   SB_GRACE_FPS=30                                 Movie Maker's frame rate, for events.csv's seconds
# events.csv (scene, event, Movie Maker frame, seconds, note) and result.txt go to
# %TEMP%/machine-party-tests/sb_grace/<tag>/.

const SCENES := ["drop", "passing", "heels", "throwback"]
const BOT_DEVICE_BASE := 900001     # Offline Bots' bot devices (local_lobby_override.gd)
const R := 3.0                      # the circle the runner runs in drop and heels
const RUN := 6.0                    # the player's speed (spine_breaker_player.tscn move_speed)
const CATCH := 3.5                  # a catcher stands this far from a thrower, in the throw's path
const CLEAR := 6.5                  # the stage's wanted clear radius

var _dir := ""
var _out: FileAccess
var _csv: FileAccess
var _tag := ""
var _fps := 30.0
var _scenes: PackedStringArray
var _game: Node = null
var _busy := false
var _staging := false
var _c := Vector3.ZERO
var _u := Vector3.RIGHT
var _v := Vector3.BACK
var _drive := {}                    # player -> world movement_input
var _circle := {}                   # player -> centre of the circle they run
var _throw_frame := -1
var _thrower_name := ""
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _clock: Label
var _hidden: Array = []
var _cast := {}                     # role -> player
var _cam: Camera3D
var _clear := CLEAR                 # the stage's clear radius as found; the scenes are sized from it
var _r := R
var _catch := CATCH


func say(msg: String) -> void:
	if _out == null:
		_out = FileAccess.open(_dir.path_join("result.txt"), FileAccess.WRITE)
	_out.store_line(msg)
	_out.flush()
	print("[sb_grace] " + msg)


func _event(scene: String, ev: String, note: String = "") -> void:
	var f := Engine.get_frames_drawn()
	if _csv == null:
		_csv = FileAccess.open(_dir.path_join("events.csv"), FileAccess.WRITE)
		_csv.store_line("scene,event,frame,seconds,note")
	_csv.store_line("%s,%s,%d,%.3f,%s" % [scene, ev, f, f / _fps, note.replace(",", ";")])
	_csv.flush()
	say("%s %s at frame %d (%.2f s) %s" % [scene, ev, f, f / _fps, note])


func _mod_ready(_loader) -> void:
	process_priority = 1000
	process_physics_priority = -1000
	var env := OS.get_environment("SB_GRACE_SCENES")
	_scenes = (env if env != "" else ",".join(SCENES)).split(",")
	_tag = OS.get_environment("SB_GRACE_TAG")
	if _tag == "":
		_tag = "run"
	var fps := OS.get_environment("SB_GRACE_FPS")
	if fps.is_valid_float():
		_fps = float(fps)
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/sb_grace").path_join(_tag)
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().node_added.connect(_on_node_added)
	say("sb_grace %s scenes %s" % [_tag, ",".join(_scenes)])


func _on_node_added(node: Node) -> void:
	if node is Minigame and _game == null and String(node.get_script().resource_path).contains("spine_breaker"):
		_game = node
		say("minigame %s" % node.name)


func _devices() -> Array:
	if _game == null or not is_instance_valid(_game):
		return []
	var list = _game.get("_mp8_devices")
	return list if list is Array else []


func _players() -> Array:
	var out: Array = []
	if _game == null or not is_instance_valid(_game):
		return out
	var d = _game.get("players")
	if d is Dictionary:
		for k in d:
			if is_instance_valid(d[k]):
				out.append(d[k])
	return out


func _state(d) -> String:
	if d.state_machine == null or d.state_machine.current_state == null:
		return "?"
	return String(d.state_machine.current_state.name)


func _name(p) -> String:
	if p == null or not is_instance_valid(p) or p.player_presence == null:
		return "?"
	return String(p.player_presence.network_name)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _process(_delta: float) -> void:
	if _busy:
		return
	if _game != null and is_instance_valid(_game) and _game.get("playing") == true and _devices().size() >= 2:
		_busy = true
		_run.call_deferred()


# Before the players' own physics: the actors' movement_input, everyone else's zero. Offline Bots' manager, which
# would write it, is paused, and the owner seat's _process input read runs after physics.
func _physics_process(_delta: float) -> void:
	if not _staging:
		return
	for p in _players():
		var mv := Vector3.ZERO
		if _circle.has(p):
			var r: Vector3 = p.global_position - _circle[p]
			r.y = 0.0
			if r.length() > 0.01:
				mv = (Vector3.UP.cross(r).normalized() + r.normalized() * (_r - r.length()) * 0.6).normalized()
		elif _drive.has(p):
			mv = _drive[p]
		p.movement_input = mv
	if _throw_frame >= 0 and _clock != null:
		_clock.text = "since %s's throw: %.2f s" % [_thrower_name, float(Engine.get_physics_frames() - _throw_frame) / Engine.physics_ticks_per_second]


func _wait(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


# Waits until cond() or max_s; true when cond() held.
func _watch(cond: Callable, max_s: float) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return cond.call()


# ---------- setup

var _bot_managers: Array = []

func _pause_bots(on: bool) -> void:
	if on:
		# Offline Bots' manager is compiled from source (no resource_path) and added to the root as OfflineBotsBrain.
		for node in get_tree().root.get_children():
			if String(node.name) == "OfflineBotsBrain" and node.has_method("_tick_minigame"):
				_bot_managers.append(node)
	for node in _bot_managers:
		if is_instance_valid(node):
			node.set_physics_process(not on)
			node.set_process(not on)
	say("Offline Bots managers %s: %d" % ["paused" if on else "resumed", _bot_managers.size()])


func _nav_map() -> RID:
	var d = _devices()[0]
	return d.navigation_agent.get_navigation_map()


# How far from pos the floor runs clear in every direction, up to CLEAR: on the navmesh and with no collider
# between at 1 m up.
func _clearance(pos: Vector3, skip: Array) -> float:
	var map := _nav_map()
	var space := get_viewport().world_3d.direct_space_state
	var best := CLEAR
	for k in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 16.0)
		var r := 0.5
		while r <= CLEAR:
			var p := pos + dir * r
			var near := NavigationServer3D.map_get_closest_point(map, Vector3(p.x, 0.0, p.z))
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, p + Vector3.UP)
			q.exclude = skip
			if _flat(near, p) > 0.3 or not space.intersect_ray(q).is_empty():
				break
			r += 0.5
		best = minf(best, r - 0.5)
	return best


# The most open floor in the arena: a 1 m grid over the spawn pool's extent, each point's clearance measured.
func _pick_stage() -> void:
	var skip: Array = []
	for p in _players():
		skip.append(p.get_rid())
	for d in _devices():
		skip.append(d.get_rid())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in _game.get("_mp8_pool"):
		var q: Vector3 = row[0]
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
	var map := _nav_map()
	var best := -1.0
	var x := lo.x
	while x <= hi.x:
		var z := lo.y
		while z <= hi.y:
			var pos := Vector3(x, 0.0, z)
			if _flat(NavigationServer3D.map_get_closest_point(map, pos), pos) < 0.2:
				var c := _clearance(pos, skip)
				if c > best:
					best = c
					_c = pos
			z += 1.0
		x += 1.0
	_clear = maxf(best, 3.0)
	_r = 2.0
	_catch = clampf(_clear - _r, 2.5, CATCH)
	say("stage at %s, clear %.1f m (wanted %.1f): circle %.1f m, catcher %.1f m" % [_c, best, CLEAR, _r, _catch])


# A text map of the floor at 0.5 m, x across and z down: '.' free navmesh, '#' a collider at 1 m up, ' ' off the
# navmesh, a letter for each spawn pool point (a = the first).
func _survey() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pool = _game.get("_mp8_pool")
	for row in pool:
		var q: Vector3 = row[0]
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
	lo -= Vector2(4, 4)
	hi += Vector2(4, 4)
	var map := _nav_map()
	var space := get_viewport().world_3d.direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	var skip: Array = []
	for p in _players():
		skip.append(p.get_rid())
	for d in _devices():
		skip.append(d.get_rid())
	q.exclude = skip
	say("survey x %.1f..%.1f, z %.1f..%.1f, 0.5 m per character" % [lo.x, hi.x, lo.y, hi.y])
	var z := lo.y
	while z <= hi.y:
		var line := ""
		var x := lo.x
		while x <= hi.x:
			var pos := Vector3(x, 0.0, z)
			var ch := " "
			if _flat(NavigationServer3D.map_get_closest_point(map, pos), pos) < 0.2:
				ch = "."
			q.transform = Transform3D(Basis(), pos + Vector3.UP)
			if not space.intersect_shape(q, 1).is_empty():
				ch = "#"
			for i in pool.size():
				var pp: Vector3 = pool[i][0]
				if absf(pp.x - x) < 0.25 and absf(pp.z - z) < 0.25:
					ch = char(97 + i)
			line += ch
			x += 0.5
		say("%6.1f |%s|" % [z, line])
		z += 0.5


func _far_points(n: int) -> Array:
	var pts: Array = []
	for row in _game.get("_mp8_pool"):
		pts.append(row[0])
	pts.sort_custom(func(a, b): return _flat(a, _c) > _flat(b, _c))
	return pts.slice(0, n)


func _ui() -> void:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n.visible:
			n.visible = false
			_hidden.append(n)
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var font = load("res://fonts/Terminal F4.ttf")
	var mk := func(pos: Vector2, size: int, color: Color) -> Label:
		var l := Label.new()
		if font != null:
			l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		l.position = pos
		l.size = Vector2(928, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_layer.add_child(l)
		return l
	_title = mk.call(Vector2(16, 10), 26, Color(1, 1, 1))
	_sub = mk.call(Vector2(16, 44), 18, Color(0.8, 0.95, 1.0))
	_clock = mk.call(Vector2(16, 476), 26, Color(1.0, 0.85, 0.3))


func _camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 52.0
	# The floor is about 16 m away; nearer than 10 m are the pipes and beams overhead, which would hide the stage.
	_cam.near = 10.0
	get_tree().current_scene.add_child(_cam)
	_aim(_c)
	_cam.make_current()


# The camera over a scene's middle; logs where that point lands in the 960x540 frame.
func _aim(at: Vector3) -> void:
	_cam.global_position = at + Vector3(0.0, 13.0, 9.5)
	_cam.look_at(at, Vector3.UP)
	(func(): say("camera on %s: it lands at %s" % [at, _cam.unproject_position(at)])).call_deferred()


func _grace_text() -> String:
	if _game.has_method("_mp8_throw_grace"):
		return "throw grace %.1f s" % float(_game.call("_mp8_throw_grace"))
	return "no throw grace (today's build)"


func _run() -> void:
	await _wait(0.2)
	_pause_bots(true)
	if OS.get_environment("SB_GRACE_SURVEY") != "":
		_survey()
	_pick_stage()
	var bots: Array = []
	for p in _players():
		p.can_act = false
		if p.player_presence != null and p.player_presence.device_id >= BOT_DEVICE_BASE:
			bots.append(p)
	bots.sort_custom(func(a, b): return a.player_presence.network_id < b.player_presence.network_id)
	if bots.size() < 4:
		say("FAIL: %d bot seats, the scenes need 4" % bots.size())
		return
	_cast = {"P": bots[0], "X": bots[1], "S": bots[2], "Q": bots[3]}
	_cast["P"].can_act = true
	_cast["Q"].can_act = true
	say("cast: P %s, X %s, S %s, Q %s; %s" % [_name(_cast["P"]), _name(_cast["X"]), _name(_cast["S"]), _name(_cast["Q"]), _grace_text()])
	_ui()
	_camera()
	_staging = true
	for s in _scenes:
		match s:
			"drop":
				await _scene_drop()
			"passing":
				await _scene_passing()
			"heels":
				await _scene_heels()
			"throwback":
				await _scene_throwback()
			_:
				say("unknown scene %s" % s)
	_staging = false
	for p in _players():
		p.can_act = true
	# A parked device stays Idle for good (Idle asks for a target only after a kill), and with the other retired
	# for the 1v1 the round would never end.
	for d in _devices():
		if _state(d) == "Idle":
			_game.call("choose_new_target", d)
			say("device %d set back on the hunt: %s" % [d.mp8_index, _dev_note(d)])
	_pause_bots(false)
	_title.text = "end"
	_sub.text = ""
	_clock.text = ""
	say("DONE at frame %d" % Engine.get_frames_drawn())


# ---------- staging

func _place(p, pos: Vector3, facing: Vector3) -> void:
	p.global_position = Vector3(pos.x, 0.0, pos.z)
	p.velocity = Vector3.ZERO
	if facing.length() > 0.01:
		p.visuals.rotation.y = atan2(-facing.x, -facing.z)


func _place_dev(d, pos: Vector3) -> void:
	d.global_position = Vector3(pos.x, 0.0, pos.z)
	d.velocity = Vector3.ZERO


func _reset() -> void:
	_circle.clear()
	_drive.clear()
	_throw_frame = -1
	_clock.text = ""
	_game.call("mp8_device_reset_rpc")
	var throws = _game.get("_mp8_throws")
	if throws is Dictionary:
		throws.clear()
	var far := _far_points(8)
	var i := 0
	for p in _players():
		if not _cast.values().has(p):
			_place(p, far[i % far.size()], Vector3.ZERO)
			i += 1
	var devs := _devices()
	for k in devs.size():
		_place_dev(devs[k], far[(i + k) % far.size()])
		devs[k].start_timer()
	for k in 6:
		await get_tree().physics_frame


# d chases p from just ahead of them, so it attaches on its first frame; true once attached.
func _latch(d, p, ahead: Vector3) -> bool:
	_place_dev(d, p.global_position + ahead.normalized() * 1.0)
	d.state_machine.transition_to(&"Follow", {"target": p, "new_target": true})
	var ok: bool = await _watch(func(): return _state(d) == "Attached" and d.attached_to == p, 1.5)
	if not ok:
		say("WARN: device %d did not latch onto %s; %s" % [d.mp8_index, _name(p), _dev_note(d)])
	return ok


func _throw(scene: String, p, at: Vector3) -> void:
	var dir: Vector3 = at - p.global_position
	dir.y = 0.0
	p.visuals.rotation.y = atan2(-dir.x, -dir.z)
	p.can_act = true
	p.throw_spine_breaker_rpc.rpc()
	_throw_frame = Engine.get_physics_frames()
	_thrower_name = _name(p)
	_event(scene, "throw", _name(p))


func _on(p) -> String:
	for d in _devices():
		if is_instance_valid(d) and d.attached_to == p and _state(d) in ["Attached", "BreakSpine"]:
			return "device %d" % d.mp8_index
	return ""


# A device's state, its chase target or victim, and where it is.
func _dev_note(d) -> String:
	var who = d.attached_to
	if who == null and _state(d) == "Follow":
		who = d.state_machine.current_state.get("target")
	return "device %d %s %s at (%.1f, %.1f)" % [d.mp8_index, _state(d), _name(who), d.global_position.x, d.global_position.z]


func _circle_point(theta: float, radius: float) -> Vector3:
	return _c + (_v * cos(theta) + _u * sin(theta)) * radius


# Moves the cast members a scene doesn't use out to the far points with the bystanders.
func _bench(roles: Array) -> void:
	var far := _far_points(12)
	for k in roles.size():
		_place(_cast[roles[k]], far[(far.size() - 1 - k) % far.size()], Vector3.ZERO)


# The runner circles _c at _r with the catcher at the centre, so every throw is 2 m and lands inside the stage.
# The widow takes any free player within 3 m, so the throws here go into open floor with nobody else near; a
# catcher in front of the thrower would stop the spider inside the thrower's reach, and it would come straight back.
func _scene_drop() -> void:
	var P = _cast["P"]
	var a = _devices()[0]
	var b = _devices()[1]
	_title.text = "1. A carrier with the widow right behind"
	_sub.text = "The grey spider is on %s's back and the widow (black) is set on them; they run, then throw the grey one away. %s" % [_name(P), _grace_text()]
	await _reset()
	_bench(["X", "S", "Q"])
	var start := _circle_point(0.0, _r)
	_place(P, start, _u)
	await get_tree().physics_frame
	_event("drop", "start")
	await _latch(a, P, _v)
	_event("drop", "latch", "device 1 on %s" % _name(P))
	_place_dev(b, start - _u * 1.8)
	b.state_machine.transition_to(&"Follow", {"target": P, "new_target": true})
	_circle[P] = _c
	await _wait(0.3)
	_event("drop", "widow 0.3 s after the latch", _dev_note(b))
	await _wait(1.5)
	_circle.erase(P)
	var out: Vector3 = P.global_position - _c
	out.y = 0.0
	_throw("drop", P, _c - out.normalized() * _clear)
	await _watch(func(): return _on(P) != "", 2.0)
	var took := _on(P)
	var since := float(Engine.get_physics_frames() - _throw_frame) / Engine.physics_ticks_per_second
	_throw_frame = -1
	_event("drop", "grab" if took != "" else "no grab", ("%s on %s at %.2f s; %s" % [took, _name(P), since, _dev_note(b)]) if took != "" else _dev_note(b))
	_clock.text = ("the widow takes %s %.2f s after their throw" % [_name(P), since]) if took == "device 2" else "the widow is elsewhere: %s" % _name(b.attached_to if b.attached_to != null else b.state_machine.current_state.get("target"))
	await _wait(1.5)
	_event("drop", "end")


func _scene_passing() -> void:
	var P = _cast["P"]
	var S = _cast["S"]
	var a = _devices()[0]
	var b = _devices()[1]
	_title.text = "2. The widow passes a carrier as they throw"
	_sub.text = "The widow (black) chases %s past %s, who throws the grey spider away (parked once it lands). %s" % [_name(S), _name(P), _grace_text()]
	await _reset()
	_bench(["X", "Q"])
	_place(P, _c, _v)
	_place(S, _c + _u * 2.2 + _v * 1.2, Vector3.ZERO)
	await get_tree().physics_frame
	_event("passing", "start")
	await _latch(a, P, -_v)
	_place_dev(b, _c - _u * (_clear - 0.3))
	b.state_machine.transition_to(&"Follow", {"target": S, "new_target": true})
	await _watch(func(): return _flat(b.global_position, P.global_position) < 2.0, 3.0)
	_throw("passing", P, _c - _v * _clear)
	_park_when_landed(a)
	await _watch(func(): return b.attached_to != null and _state(b) == "Attached", 3.0)
	var who := _name(b.attached_to) if b.attached_to != null else "nobody"
	var since := float(Engine.get_physics_frames() - _throw_frame) / Engine.physics_ticks_per_second
	_throw_frame = -1
	_event("passing", "widow takes", "%s at %.2f s; %s" % [who, since, _dev_note(b)])
	_clock.text = "the widow takes %s, %.2f s after %s's throw" % [who, since, _name(P)]
	await _wait(1.5)
	_event("passing", "end")


func _scene_heels() -> void:
	var P = _cast["P"]
	var a = _devices()[0]
	var b = _devices()[1]
	_title.text = "3. Worst case: the widow on the thrower's heels"
	_sub.text = "The widow (black) is set on %s as they throw (staged; the grey spider is parked once it lands). How long until it can take them? %s" % [_name(P), _grace_text()]
	await _reset()
	_bench(["X", "S", "Q"])
	var start := _circle_point(0.0, _r)
	_place(P, start, _u)
	await get_tree().physics_frame
	_event("heels", "start")
	await _latch(a, P, _v)
	await _wait(0.5)
	_throw("heels", P, _c - _v * _clear)
	_place_dev(b, P.global_position - _u * 1.6)
	b.state_machine.transition_to(&"Follow", {"target": P, "new_target": true})
	_circle[P] = _c
	_park_when_landed(a)
	await _watch(func(): return b.attached_to == P and _state(b) == "Attached", 4.0)
	var since := float(Engine.get_physics_frames() - _throw_frame) / Engine.physics_ticks_per_second
	var took: bool = b.attached_to == P
	_event("heels", "widow takes" if took else "no grab", "%s at %.2f s; %s" % [_name(P), since, _dev_note(b)])
	_circle.erase(P)
	_throw_frame = -1
	_clock.text = ("the widow takes %s at %.2f s" % [_name(P), since]) if took else "no grab in 4 s"
	await _wait(1.5)
	_event("heels", "end")


# Once a thrown device has landed it goes back to Idle, parked at the farthest point.
func _park_when_landed(d) -> void:
	await _watch(func(): return _state(d) != "Thrown", 2.0)
	if _state(d) == "Follow":
		d.state_machine.transition_to(&"Idle")
		_place_dev(d, _far_points(1)[0])
		say("device %d parked after landing" % d.mp8_index)


func _scene_throwback() -> void:
	var P = _cast["P"]
	var Q = _cast["Q"]
	var a = _devices()[0]
	var b = _devices()[1]
	_title.text = "4. A spider thrown straight back"
	_sub.text = "%s throws the grey spider away; %s throws the widow (black) straight at %s. %s" % [_name(P), _name(Q), _name(P), _grace_text()]
	await _reset()
	_bench(["X", "S"])
	_place(P, _c - _u * 1.6, -_v)
	_place(Q, _c + _u * 1.7, -_u)
	await get_tree().physics_frame
	_event("throwback", "start")
	await _latch(a, P, _v)
	await _latch(b, Q, _u)
	await _wait(0.6)
	_throw("throwback", P, P.global_position - _v * _clear)
	await _wait(0.4)
	var dir: Vector3 = P.global_position - Q.global_position
	dir.y = 0.0
	Q.visuals.rotation.y = atan2(-dir.x, -dir.z)
	Q.can_act = true
	Q.throw_spine_breaker_rpc.rpc()
	_event("throwback", "throw back", _name(Q))
	await _watch(func(): return b.attached_to == P and _state(b) == "Attached", 2.5)
	var since := float(Engine.get_physics_frames() - _throw_frame) / Engine.physics_ticks_per_second
	var took: bool = b.attached_to == P
	_event("throwback", "widow on P" if took else "missed", "%s at %.2f s; %s" % [_name(P), since, _dev_note(b)])
	_throw_frame = -1
	_clock.text = ("the thrown widow latches onto %s at %.2f s after their throw" % [_name(P), since]) if took else "the widow missed %s" % _name(P)
	await _wait(1.5)
	_event("throwback", "end")
