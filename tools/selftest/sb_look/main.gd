extends Node

# Dev-only and windowed, beside a cl_playtest launch of SpineBreaker on 8 Player Support (7 bots, 8 seats):
# candidate looks for the second spider, each applied to the live device with the tree paused, so every
# look is shot on the same frame. Shots: calibration, close-up, both spiders (device 1 staged beside device 2),
# the game's own view and a 3x crop of it at two moments, and the spider on a victim's back.
#   SB_LOOK=widow_a,widow_c,widow_d,widow_e,widow_f   the looks, in order (default: every key in LOOKS)
#   built: the build's own look (8 Player Support 0.14.0 or later), as it was before any other look applied.
# Shots and result.txt go to %TEMP%/machine-party-tests/sb_look/. The run quits itself.

const BODY_BONE := "main body"
const ATTACH_TIMEOUT := 120.0
const REAR := 0.18
# body: albedo multiply on the body texture. prop: "" | "hourglass" | "canister". size: the hourglass's
# length, or the canister's height. lay: the canister along the spine. glow: emission energy. light: an OmniLight's energy.
# hg: the hourglass's own colour under the scene's light, beside its glow.
const LOOKS := {
	"built": {"prop": ""},
	"red": {"body": Color(1.0, 0.25, 0.2), "prop": ""},
	"widow_a": {"body": Color(0.12, 0.12, 0.13), "prop": "hourglass", "size": 0.5, "glow": 2.0, "light": 0.0},
	"widow_c": {"body": Color(0.06, 0.06, 0.07), "prop": "hourglass", "size": 0.5, "glow": 0.6, "light": 0.0, "hg": Color(0.5, 0.03, 0.02)},
	"widow_d": {"body": Color(0.06, 0.06, 0.07), "prop": "hourglass", "size": 0.5, "glow": 0.3, "light": 0.0, "hg": Color(0.4, 0.02, 0.01)},
	"widow_e": {"body": Color(0.06, 0.06, 0.07), "prop": "hourglass", "size": 0.5, "glow": 0.15, "light": 0.0, "hg": Color(0.35, 0.02, 0.01)},
	"widow_f": {"body": Color(0.03, 0.03, 0.035), "prop": "hourglass", "size": 0.5, "glow": 0.3, "light": 0.0, "hg": Color(0.4, 0.02, 0.01)},
	"widow_b": {"body": Color(0.2, 0.2, 0.22), "prop": "hourglass", "size": 0.7, "glow": 4.0, "light": 0.45},
	"canister_a": {"body": Color(0.35, 0.35, 0.38), "prop": "canister", "size": 0.55, "glow": 1.5, "light": 0.0, "lay": false},
	"canister_b": {"body": Color(0.28, 0.28, 0.3), "prop": "canister", "size": 0.7, "glow": 2.5, "light": 0.7, "lay": true},
}
const RED := Color(1.0, 0.05, 0.02)
# The title screen's racks: emission_mask_cycle.gdshader's cycle_color (main_menu.tscn:5385-5778).
const GREEN := Color(0.0, 1.0, 0.0)

var _dir := ""
var _out: FileAccess
var _looks: PackedStringArray
var _game: Node = null
var _players: Array = []
var _busy := false
var _cam: Camera3D
# The prop's frame in the body bone's space, measured once on device 2 and reused on the victim's back.
var _anchor := Transform3D.IDENTITY
var _anchors := {}
# Per device: [the body's surface override, mp8_tint] as the build left them, for the `built` look.
var _built := {}


func say(msg: String) -> void:
	if _out == null:
		_out = FileAccess.open(_dir.path_join("result.txt"), FileAccess.WRITE)
	_out.store_line(msg)
	_out.flush()


func _mod_ready(_loader) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	var env := OS.get_environment("SB_LOOK")
	_looks = (env if env != "" else ",".join(LOOKS.keys())).split(",")
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/sb_look")
	DirAccess.make_dir_recursive_absolute(_dir)
	for f in DirAccess.get_files_at(_dir):
		if f.ends_with(".png"):
			DirAccess.remove_absolute(_dir.path_join(f))
	get_tree().node_added.connect(_on_node_added)
	say("sb_look looks %s" % ",".join(_looks))


func _on_node_added(node: Node) -> void:
	if node is Minigame and _game == null:
		_game = node
		say("minigame %s" % node.name)
	elif node is SpineBreakerPlayer:
		_players.append(node)


func _devices() -> Array:
	if _game == null or not is_instance_valid(_game):
		return []
	var list = _game.get("_mp8_devices")
	return list if list is Array else []


func _state(d) -> String:
	if d.state_machine == null or d.state_machine.current_state == null:
		return "?"
	return String(d.state_machine.current_state.name)


func _process(_delta: float) -> void:
	if _busy:
		return
	var devs := _devices()
	if devs.size() >= 2 and is_instance_valid(devs[1]) and _state(devs[1]) == "Follow":
		_busy = true
		_run.call_deferred(devs[0], devs[1])


# ---------- looks

func _body_mesh(sk: Skeleton3D) -> MeshInstance3D:
	for c in sk.get_children():
		if c is MeshInstance3D and c.visible and c.mesh != null:
			return c
	return null


# The body's top in the body bone's space, from the vertices that bone carries most: a bind pose maps a
# vertex into its bone's space. Up and forward come from the device standing on the floor.
func _measure(d) -> void:
	var sk: Skeleton3D = d.skeleton
	var mi := _body_mesh(sk)
	var bone := sk.find_bone(BODY_BONE)
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones = arr[Mesh.ARRAY_BONES]
	var weights = arr[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / verts.size()
	var skin: Skin = mi.skin
	var pts := PackedVector3Array()
	for v in verts.size():
		var best := 0
		var bw := -1.0
		for k in per:
			if weights[v * per + k] > bw:
				bw = weights[v * per + k]
				best = int(bones[v * per + k])
		var sb := best
		if skin != null:
			sb = skin.get_bind_bone(best)
			if sb < 0:
				sb = sk.find_bone(skin.get_bind_name(best))
		if sb != bone:
			continue
		pts.append(skin.get_bind_pose(best) * verts[v] if skin != null else sk.get_bone_global_rest(bone).affine_inverse() * verts[v])
	var to_bone: Basis = (sk.global_transform * sk.get_bone_global_pose(bone)).basis.inverse()
	var up: Vector3 = (to_bone * Vector3.UP).normalized()
	var fwd: Vector3 = (to_bone * (d.visuals.global_basis * Vector3.FORWARD)).normalized()
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	# Behind the body's middle, at the surface's height there: the head stands over the front.
	var c := (lo + hi) * 0.5 - fwd * REAR
	var top := -INF
	for p in pts:
		var off := p - c
		if (off - up * off.dot(up)).length() < 0.22:
			top = maxf(top, p.dot(up))
	var origin := c + up * (top - c.dot(up))
	var x := up.cross(-fwd).normalized()
	_anchor = Transform3D(Basis(x, up, -fwd), origin)
	say("body bone %d: %d of %d vertices, extent %s, up %s, forward %s, top %s" % [
		bone, pts.size(), verts.size(), hi - lo, up, fwd, origin])


func _mat(albedo: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = energy
	if albedo.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
	return m


# Two triangles tip to tip in the anchor's plane, the long axis along the spine.
func _hourglass(look: Dictionary) -> Node3D:
	var l: float = look.size
	var w := l * 0.55
	var waist := l * 0.06
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for t in [[Vector3(-w / 2, 0, -l / 2), Vector3(w / 2, 0, -l / 2), Vector3(0, 0, waist)],
			[Vector3(0, 0, -waist), Vector3(w / 2, 0, l / 2), Vector3(-w / 2, 0, l / 2)]]:
		for p in t:
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(look.get("hg", Color(0.9, 0.04, 0.02)), RED, look.glow)
	mi.position = Vector3.UP * 0.03
	var root := Node3D.new()
	root.add_child(mi)
	return root


func _cyl(r: float, h: float, y: float, m: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3.UP * y
	return mi


# A glass tube over a glowing core, with dark metal caps and a valve; upright, or laid along the spine.
func _canister(look: Dictionary) -> Node3D:
	var h: float = look.size
	var r := h * 0.26
	var metal := _mat(Color(0.12, 0.12, 0.13), Color.BLACK, 0.0)
	metal.metallic = 0.85
	metal.roughness = 0.35
	var body := Node3D.new()
	body.add_child(_cyl(r * 0.78, h * 0.78, 0.0, _mat(Color(0.25, 1.0, 0.3), GREEN, look.glow)))
	body.add_child(_cyl(r, h * 0.8, 0.0, _mat(Color(0.75, 1.0, 0.8, 0.22), Color.BLACK, 0.0)))
	body.add_child(_cyl(r * 1.15, h * 0.12, h * 0.46, metal))
	body.add_child(_cyl(r * 1.15, h * 0.12, -h * 0.46, metal))
	body.add_child(_cyl(r * 0.35, h * 0.1, h * 0.57, metal))
	var root := Node3D.new()
	root.add_child(body)
	if look.lay:
		body.rotation = Vector3(PI / 2, 0, 0)
		body.position = Vector3.UP * r * 1.1
	else:
		body.position = Vector3.UP * h * 0.52
	return root


func _prop(look: Dictionary) -> Node3D:
	var root: Node3D = _hourglass(look) if look.prop == "hourglass" else _canister(look)
	if look.light > 0.0:
		var o := OmniLight3D.new()
		o.light_color = RED if look.prop == "hourglass" else GREEN
		o.light_energy = look.light
		o.omni_range = 1.3
		o.position = Vector3.UP * 0.35
		root.add_child(o)
	return root


# The anchor under a BoneAttachment3D on the body bone, so the prop follows the walk.
func _anchor_on(sk: Skeleton3D) -> Node3D:
	if _anchors.has(sk) and is_instance_valid(_anchors[sk]):
		return _anchors[sk]
	var ba := BoneAttachment3D.new()
	ba.bone_name = BODY_BONE
	sk.add_child(ba)
	var a := Node3D.new()
	a.transform = _anchor
	ba.add_child(a)
	_anchors[sk] = a
	return a


func _set_prop(sk: Skeleton3D, key: String) -> Node3D:
	var a := _anchor_on(sk)
	for c in a.get_children():
		c.queue_free()
		a.remove_child(c)
	var look: Dictionary = LOOKS[key]
	if look.prop != "":
		a.add_child(_prop(look))
	return a


# A per-node override on a duplicate: the material is embedded in device.tscn and shared by both devices.
# The build's own hourglass (MP8Mark) shows only in the `built` look.
func _apply_device(d, key: String) -> void:
	var mi := _body_mesh(d.skeleton)
	if not _built.has(d):
		_built[d] = [mi.get_surface_override_material(0), d.mp8_tint]
	var own: Node3D = d.skeleton.get_node_or_null("MP8Mark")
	if own != null:
		own.visible = key == "built"
	_set_prop(d.skeleton, key)
	if key == "built":
		mi.set_surface_override_material(0, _built[d][0])
		d.mp8_tint = _built[d][1]
		return
	var m: StandardMaterial3D = mi.mesh.surface_get_material(0).duplicate()
	m.albedo_color = LOOKS[key].body
	mi.set_surface_override_material(0, m)
	d.mp8_tint = LOOKS[key].body


# `built` goes through the build's own bind path: its tint and a fresh hourglass from the device.
func _apply_victim(p, d, key: String) -> void:
	_set_prop(p.skeleton_attached, key)
	if key == "built":
		var tint: Color = _built[d][1] if _built.has(d) else d.mp8_tint
		p.mp8_set_visual_tint(tint, d.mp8_tex_key, d.mp8_make_mark() if d.has_method("mp8_make_mark") else null)
		return
	p.mp8_set_visual_tint(LOOKS[key].body, d.mp8_tex_key)


# ---------- shots

func _ui(show: bool) -> void:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if show:
			n.visible = n.get_meta("sb_was", true)
		else:
			n.set_meta("sb_was", n.visible)
			n.visible = false


func _frame() -> Image:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _shot(name: String) -> void:
	var img: Image = await _frame()
	img.save_png(_dir.path_join(name + ".png"))
	say("shot " + name)


func _aim(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	var dir := (at - from).normalized()
	_cam.look_at(at, Vector3.FORWARD if absf(dir.y) > 0.98 else Vector3.UP)


# A quarter-size region of the game's frame around `at`, in the saved image's pixels. At 8 players
# Spine Breaker draws one shared camera, not a tile per seat.
func _crop_of(c: Camera3D, at: Vector3) -> Rect2i:
	if c == null or c.is_position_behind(at):
		return Rect2i()
	var size := get_viewport().get_texture().get_size()
	var p := c.unproject_position(at) * Vector2(size) / get_viewport().get_visible_rect().size
	var r := Vector2i(size / 4)
	var o := Vector2i(clampi(int(p.x) - r.x / 2, 0, size.x - r.x), clampi(int(p.y) - r.y / 2, 0, size.y - r.y))
	return Rect2i(o, r)


func _save_crop(img: Image, r: Rect2i, name: String) -> void:
	if r.size.x <= 0:
		return
	var c := img.get_region(r)
	c.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
	c.save_png(_dir.path_join(name + ".png"))
	say("shot " + name)


# The first of eight directions around `at` whose line of sight hits no collider, else the first.
func _clear(at: Vector3, dist: float, height: float, start: Vector3, skip: Array) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var flat := Vector3(start.x, 0, start.z).normalized()
	for k in 8:
		var dir := flat.rotated(Vector3.UP, k * PI / 4)
		var from := at + dir * dist + Vector3.UP * height
		var q := PhysicsRayQueryParameters3D.create(at, from)
		q.exclude = skip
		if space.intersect_ray(q).is_empty():
			return from
	return at + flat * dist + Vector3.UP * height


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _roaming(d2) -> void:
	while _state(d2) != "Follow" or d2.global_position.y < -1.0:
		await get_tree().process_frame


# The game's own view, every look on one frame.
func _game_shots(d2, game_cam: Camera3D, tag: String) -> void:
	var crop := _crop_of(game_cam, d2.global_position)
	say("device 2 at %s, crop %s" % [d2.global_position, crop])
	for key in _looks:
		_apply_device(d2, key)
		var img: Image = await _frame()
		img.save_png(_dir.path_join("game%s_%s.png" % [tag, key]))
		say("shot game%s_%s" % [tag, key])
		_save_crop(img, crop, "gamecrop%s_%s" % [tag, key])


func _run(d1, d2) -> void:
	say("devices: 1 %s, 2 %s, state %s" % [d1.name, d2.name, _state(d2)])
	var env := get_viewport().world_3d.environment
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		env = we.environment
	if env != null:
		say("environment glow %s, intensity %.2f, bloom %.2f, hdr threshold %.2f" % [
			env.glow_enabled, env.glow_intensity, env.glow_bloom, env.glow_hdr_threshold])
	# Paused while device 2 roams: an attached device waits hidden 100 m below the floor. The state, not
	# `is_attached`, which the game sets true and never clears within a round.
	await _wait(1.5)
	await _roaming(d2)
	get_tree().paused = true
	_measure(d2)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	get_tree().current_scene.add_child(_cam)
	var game_cam := get_viewport().get_camera_3d()

	await _game_shots(d2, game_cam, "")

	_cam.make_current()
	_ui(false)
	var a: Node3D = _anchor_on(d2.skeleton)
	var fwd: Vector3 = d2.visuals.global_basis * Vector3.FORWARD
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var skip: Array = [d1.get_rid(), d2.get_rid()]
	for p in _players:
		if is_instance_valid(p):
			skip.append(p.get_rid())

	# Calibration: the anchor from above, the side and the front, with widow_b and canister_b.
	for key in ["widow_b", "canister_b"]:
		_apply_device(d2, key)
		var t: Vector3 = a.global_position
		for v in [["top", t + Vector3.UP * 4.0], ["side", t + side * 3.5 + Vector3.UP * 0.6],
				["front", t + fwd * 3.5 + Vector3.UP * 1.2]]:
			_aim(v[1], t)
			await _shot("calib_%s_%s" % [v[0], key])

	# Steep, as the game's own camera looks: the arena's walls are meshes without colliders, which
	# _clear's rays cannot see.
	var close: Vector3 = _clear(a.global_position, 1.5, 3.0, -fwd + side * 0.6, skip)
	for key in _looks:
		_apply_device(d2, key)
		_aim(close, a.global_position)
		await _shot("close_%s" % key)

	# Both spiders: device 1 moved beside the roaming device 2, facing the same way, shown, and put back
	# afterwards. Device 1 may be attached: 100 m below the floor, and its root hidden by attach_entered_rpc.
	var keep_pos: Vector3 = d1.global_position
	var keep_rot: float = d1.visuals.rotation.y
	var keep_vis: bool = d1.visuals.visible
	var keep_root: bool = d1.visible
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(d2.global_position + Vector3.UP * 0.5, d2.global_position + side * 3.5 + Vector3.UP * 0.5)
	q.exclude = skip
	var s1: Vector3 = side if space.intersect_ray(q).is_empty() else -side
	d1.global_position = d2.global_position + s1 * 2.8
	d1.visuals.rotation.y = d2.visuals.rotation.y
	d1.visuals.visible = true
	d1.visible = true
	say("device 1 staged beside device 2 (it was at %s, state %s)" % [keep_pos, _state(d1)])
	var mid: Vector3 = d2.global_position + s1 * 1.4 + Vector3.UP * 0.8
	var pair: Vector3 = mid - fwd * 1.8 + Vector3.UP * 7.0
	for key in _looks:
		_apply_device(d2, key)
		_aim(pair, mid)
		await _shot("pair_%s" % key)
	d1.global_position = keep_pos
	d1.visuals.rotation.y = keep_rot
	d1.visuals.visible = keep_vis
	d1.visible = keep_root

	_ui(true)
	if game_cam:
		game_cam.make_current()
	get_tree().paused = false

	# A second moment of the game's view: one frame can put a cable over the spider.
	await _wait(6.0)
	await _roaming(d2)
	get_tree().paused = true
	await _game_shots(d2, game_cam, "2")
	get_tree().paused = false

	# On a victim's back: wait for device 2 to attach and settle, then every look on that frame. The
	# device's attached_to, not the player's mp8_current_device, which a retired device leaves set.
	# An attach whose fuse already ran out breaks the spine within the settle, so it is checked again.
	var victim = null
	var t0 := 0.0
	while victim == null and t0 < ATTACH_TIMEOUT:
		await get_tree().process_frame
		t0 += get_process_delta_time()
		if _state(d2) == "Attached" and is_instance_valid(d2.attached_to):
			var v = d2.attached_to
			await _wait(1.2)
			t0 += 1.2
			if _state(d2) == "Attached" and d2.attached_to == v:
				victim = v
			else:
				say("device 2 left %s within the settle, waiting for the next attach" % v.name)
	if victim == null:
		say("no settled attach by device 2 in %.0f s: no back shots" % ATTACH_TIMEOUT)
	else:
		get_tree().paused = true
		say("device 2 on %s after %.1f s" % [victim.name, t0])
		var vcrop := _crop_of(game_cam, victim.global_position + Vector3.UP)
		for key in _looks:
			_apply_victim(victim, d2, key)
			var img: Image = await _frame()
			img.save_png(_dir.path_join("backgame_%s.png" % key))
			say("shot backgame_%s" % key)
			_save_crop(img, vcrop, "backcrop_%s" % key)
		_cam.make_current()
		_ui(false)
		var va: Node3D = _anchor_on(victim.skeleton_attached)
		await get_tree().process_frame
		var back: Vector3 = va.global_basis.y.normalized()
		var from: Vector3 = _clear(va.global_position, 1.8, 2.8, back, skip)
		for key in _looks:
			_apply_victim(victim, d2, key)
			_aim(from, va.global_position)
			await _shot("back_%s" % key)
		_ui(true)
		if game_cam:
			game_cam.make_current()
		get_tree().paused = false

	say("DONE at frame %d" % Engine.get_process_frames())
	get_tree().quit()
