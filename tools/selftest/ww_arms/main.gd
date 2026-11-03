extends Node

# Dev-only and windowed, beside a cl_playtest launch of EscalatorPit on 8 Player Support (7 bots, 8 seats):
# each seat gets an arm candidate, every seat is held jogging in place, and a close-up camera visits each.
#   WW_ARMS=today,A,B1,B2,A/h,B1/h,B2/h,B1/0   per seat, in spawn order; "/h" half the torso lean, "/0" none
#   A   both hand IKs off: the clip's own run arms (Spine Breaker's)
#   B1  A, plus TuckArms: upper arms at the sides, elbows bent, the clip's swing kept
#   B2  a tighter tuck and a smaller swing
# Shots and result.txt go to %TEMP%/machine-party-tests/ww_arms/. The run quits itself.

const PLAYER_SCRIPT := "escalator_pit_player.gd"
const DEFAULT_SEATS := "today,A,B1,B2,A/h,B1/h,B2/h,B1/0"
# [spread, bend, inward, swing scale, swing centre], radians except the scale.
const TUCK := {
	"B1": [0.20, 1.25, 0.08, 0.55, -0.10],
	"B2": [0.12, 1.45, 0.12, 0.35, -0.15],
}
const SEAT_HOLD := 2.4
# Skeleton space: +x is the way the player faces, +y up, the left hand on -z. "game" looks over the shoulder
# as the minigame's own camera does, from behind and above.
const VIEWS := {"front": Vector3(7.5, 2.0, 3.0), "game": Vector3(-6.5, 6.0, 1.0)}
const LOOK_AT := Vector3(0.0, 0.4, 0.0)

var _dir := ""
var _out: FileAccess
var _seats: PackedStringArray
var _players: Array = []
var _set := {}
var _pins := {}
var _mods := {}
var _busy := false
var _cam: Camera3D


class TuckArms extends SkeletonModifier3D:
	var spread := 0.2
	var bend := 1.4
	var inward := 0.2
	var swing := 1.0
	var centre := -0.1
	var calls := 0
	var lo := 9.0
	var hi := -9.0
	var _mid := {-1.0: 0.0, 1.0: 0.0}
	var _last := 0

	func _process_modification() -> void:
		calls += 1
		var sk := get_skeleton()
		if sk == null:
			return
		var now := Time.get_ticks_msec()
		var dt: float = clampf((now - _last) / 1000.0, 0.0, 0.1) if _last > 0 else 0.0
		_last = now
		for side in [-1.0, 1.0]:
			var suffix := ".L" if side < 0.0 else ".R"
			var ua := sk.find_bone("upper_arm" + suffix)
			var fa := sk.find_bone("forearm" + suffix)
			if ua < 0 or fa < 0:
				continue
			var pg := sk.get_bone_global_pose(sk.get_bone_parent(ua))
			var ug := sk.get_bone_global_pose(ua)
			var u := ug.basis.y.normalized()
			# The clip's swing, measured around its own running mean, so the arms keep the legs' timing.
			var pitch := atan2(u.x, -u.y)
			_mid[side] = lerpf(_mid[side], pitch, minf(1.0, dt / 0.8))
			if calls > 120:
				lo = minf(lo, pitch - _mid[side])
				hi = maxf(hi, pitch - _mid[side])
			var p: float = centre + swing * (pitch - _mid[side])
			var du := Vector3(sin(p) * cos(spread), -cos(p) * cos(spread), side * sin(spread))
			var new_ub := Basis(Quaternion(u, du.normalized())) * ug.basis
			sk.set_bone_pose_rotation(ua, (pg.basis.inverse() * new_ub).orthonormalized().get_rotation_quaternion())

			var new_ug := Transform3D(new_ub, ug.origin)
			var fg := new_ug * sk.get_bone_pose(fa)
			var f := fg.basis.y.normalized()
			var pf := p + bend
			var df := Vector3(sin(pf) * cos(inward), -cos(pf) * cos(inward), -side * sin(inward))
			var new_fb := Basis(Quaternion(f, df.normalized())) * fg.basis
			sk.set_bone_pose_rotation(fa, (new_ub.inverse() * new_fb).orthonormalized().get_rotation_quaternion())


func say(msg: String) -> void:
	if _out == null:
		_out = FileAccess.open(_dir.path_join("result.txt"), FileAccess.WRITE)
	_out.store_line(msg)
	_out.flush()


func _mod_ready(_loader) -> void:
	process_priority = 1000
	process_physics_priority = 1000
	var env := OS.get_environment("WW_ARMS")
	_seats = (env if env != "" else DEFAULT_SEATS).split(",")
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/ww_arms")
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().node_added.connect(_on_node_added)
	say("ww_arms seats %s" % ",".join(_seats))


func _on_node_added(node: Node) -> void:
	var s = node.get_script()
	if s != null and String(s.resource_path).ends_with(PLAYER_SCRIPT):
		_players.append(node)


func _configure(p: Node, seat: int) -> void:
	var c: String = _seats[seat] if seat < _seats.size() else "today"
	var arms := c.split("/")[0]
	var lean := c.split("/")[1] if "/" in c else ""
	if arms != "today":
		p.ik_left_hand.influence = 0.0
		p.ik_right_hand.influence = 0.0
	if lean == "h":
		p.ik_torso.influence = 0.5
	elif lean == "0":
		p.ik_torso.influence = 0.0
	if TUCK.has(arms):
		var m := TuckArms.new()
		var t: Array = TUCK[arms]
		m.spread = t[0]; m.bend = t[1]; m.inward = t[2]; m.swing = t[3]; m.centre = t[4]
		p.skeleton.add_child(m)
		_mods[p] = m
	var sk: Skeleton3D = p.skeleton
	say("seat %d %s: %s, skeleton scale %s at %s" % [seat + 1, c, p.player_presence.network_name,
		sk.global_transform.basis.get_scale(), sk.global_position])


func _process(_delta: float) -> void:
	_players = _players.filter(func(p): return is_instance_valid(p))
	for i in _players.size():
		var p = _players[i]
		if not _set.has(p) and p.player_presence != null and p.is_node_ready():
			_set[p] = true
			_configure(p, i)
	_hold()
	if not _busy and _players.size() >= 8 and _set.size() == _players.size():
		_busy = true
		_run.call_deferred()


func _physics_process(_delta: float) -> void:
	_hold()


# Every seat jogs in place at the player script's own blend (its clamp() always yields 1.5 while active).
func _hold() -> void:
	for p in _set.keys():
		if not is_instance_valid(p) or not p.active:
			continue
		if not _pins.has(p):
			_pins[p] = p.path_follow_3d.progress_ratio
		p.path_follow_3d.progress_ratio = _pins[p]
		p.character_animation_tree.set("parameters/run_blend/blend_amount", 1.5)
		if _mods.has(p):
			_mods[p].influence = 1.0
	for p in _mods.keys():
		if is_instance_valid(p) and not p.active:
			_mods[p].influence = clampf(p.character_animation_tree.get("parameters/run_blend/blend_amount"), 0.0, 1.0)


func _ui(show: bool) -> void:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if show:
			n.visible = n.get_meta("ww_was", true)
		else:
			n.set_meta("ww_was", n.visible)
			n.visible = false


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))


func _visit(p: Node, view: String) -> void:
	var sk: Skeleton3D = p.skeleton
	var t := sk.global_transform
	_cam.global_position = t * VIEWS[view]
	_cam.look_at(t * LOOK_AT, Vector3.UP)


func _run() -> void:
	_cam = Camera3D.new()
	_cam.fov = 40.0
	get_tree().current_scene.add_child(_cam)
	# A soft fill for the close-ups only: the pit is lit for the wide camera, and arms read as silhouettes up close.
	var fill := OmniLight3D.new()
	fill.light_energy = 1.2
	fill.omni_range = 14.0
	fill.shadow_enabled = false
	_cam.add_child(fill)
	var game_cam := get_viewport().get_camera_3d()
	await get_tree().create_timer(1.0).timeout

	# Idle: the countdown pose, before anyone is active.
	_cam.make_current()
	_ui(false)
	for i in _players.size():
		_visit(_players[i], "front")
		await get_tree().process_frame
		await _shot("idle_s%d_%s" % [i + 1, _seats[i].replace("/", "-")])
	_ui(true)
	if game_cam:
		game_cam.make_current()
	say("idle shots at frame %d" % Engine.get_process_frames())

	while not _players.all(func(p): return is_instance_valid(p) and p.active):
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	await _shot("wide")

	_cam.make_current()
	_ui(false)
	for view in VIEWS.keys():
		for i in _players.size():
			var p = _players[i]
			say("clip %s s%d %s from frame %d" % [view, i + 1, _seats[i], Engine.get_process_frames()])
			var t0 := 0.0
			var k := 0
			while t0 < SEAT_HOLD:
				_visit(p, view)
				await get_tree().process_frame
				t0 += get_process_delta_time()
				if k < 3 and t0 >= 0.6 + k * 0.27:
					await _shot("run_%s_s%d_%s_%d" % [view, i + 1, _seats[i].replace("/", "-"), k])
					k += 1
	_ui(true)
	for p in _mods.keys():
		say("TuckArms on %s: %d calls, swing %.2f..%.2f rad around the mean" % [
			p.player_presence.network_name, _mods[p].calls, _mods[p].lo, _mods[p].hi])
	say("DONE at frame %d" % Engine.get_process_frames())
	get_tree().quit()
