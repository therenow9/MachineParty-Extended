extends Node

# Dev-only and windowed: More Cosmetics' items beside vanilla references, hat
# gibs in flight and at rest, and every suit with candidate shades of
# ours, rendered in the local lobby's own lighting into
# %TEMP%/machine-party-tests/xc_render/ for tools/cosmetics/render_page.py.
# Also times the suit recolor under the real renderer.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const BETWEEN := "res://scenes/main_menu/main_menu.tscn"
const HAT_GIB_SCENE := "res://prefabs/managed_props/hat_gib.tscn"
const SYNC_NAME := "XcSuitSync"
# This batch: ours, then the item it is judged against (a candidate is judged
# against the item it would replace).
const PAIRS := [["xc_snow_glasses", "sunglasses"]]
# A hat and glasses worn together, where the two could clip.
const COMBOS := [["traffic_cone", "xc_snow_glasses"], ["xc_pharaoh_headdress", "xc_snow_glasses"], ["xc_trapper_hat", "xc_snow_glasses"],
	["xc_football_helmet", "xc_snow_glasses"], ["xc_turban", "xc_snow_glasses"], ["xc_army_helmet", "xc_snow_glasses"]]
# Other builds of an item in CANDIDATES_DIR, never shipped: generated with
# --out, or a rework's shipped build copied there as <id>_before. Candidate id,
# the item it stands in for.
const CANDIDATES := []
const CANDIDATES_DIR := "candidates"
const YAWS := [0, 45, 180]
# Every pair's items also shot with the whole character this many pixels tall,
# to judge them from a distance: about the 8-seat lobby's and a split-screen
# view's (estimated, not measured in those scenes).
const FAR := [240, 120]
const FAR_YAWS := [0, 45]
const GIB_HATS := []
const GIB_SHOTS := [0.15, 0.4]
const GIB_REST := 4.0
# The suit lineup and its shade candidates. Colours already picked are shot once,
# at their shipped shade; those in NEW are shot at each of their candidates.
const SUITS := false
const NEW := {}

var fails := 0
var out: FileAccess
var out_dir: String
var api
var _far_scale := 0.0

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/xc_render/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	out_dir = OS.get_environment("TEMP").path_join("machine-party-tests/xc_render")
	# Renders hold game art: a relative path would land them in the game folder or the repo.
	if not out_dir.is_absolute_path():
		ok("TEMP is set", false, out_dir)
		finish()
		return
	api = loader.registry("more_cosmetics").get("api")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		ok("needs --windowed", false)
		finish()
		return
	ok("more_cosmetics api", api != null)
	if api == null:
		finish()
		return
	var started := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("renders"))
	for f in DirAccess.get_files_at(out_dir.path_join("renders")):
		DirAccess.remove_absolute(out_dir.path_join("renders").path_join(f))
	say("renders to %s, renderer %s" % [out_dir, RenderingServer.get_current_rendering_method()])
	await get_tree().create_timer(1.0).timeout
	var seat: Dictionary = await _seat()
	await _timing(seat.assigner)
	await _items(seat)
	await _gibs(seat)
	if SUITS:
		await _suits(seat)
	await _scene_change(seat.assigner)
	var files := DirAccess.get_files_at(out_dir.path_join("renders"))
	ok("renders written", files.size() > 0, files.size())
	say("elapsed %.1f s (the runner stops the game at 180 s)" % ((Time.get_ticks_msec() - started) / 1000.0))
	finish()

# Seat 0's lobby character with every other mesh hidden (the seat faces a wall)
# and our own camera; the lobby's lights stay.
func _seat() -> Dictionary:
	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	var lobby = get_tree().current_scene
	lobby.join(-1, false)
	await frames(10)
	var controls = lobby.local_lobby_player_controls[0]
	controls._on_name_confirmed("XC")
	await frames(20)
	var a = controls.customization_assigner
	var vp: Viewport = a.get_viewport()
	var character: Node3D = a.get_parent().get_parent()
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not character.is_ancestor_of(g):
			g.visible = false
	var cam := Camera3D.new()
	cam.fov = 30.0
	a.get_parent().add_child(cam)
	cam.make_current()
	a.remove_hat()
	a.remove_glasses()
	return {"controls": controls, "assigner": a, "viewport": vp, "camera": cam, "character": character}

# Before any of our colours is used: the GPU readback, the first recolor, the
# cached one and the cutoff pair, then an assign's cost to the next frame.
func _timing(a) -> void:
	say("\n=== timing")
	say("cache empty before: %s (%d)" % [api.recolor._cache.is_empty(), api.recolor._cache.size()])
	for which in ["red", "blue"]:
		var t := Time.get_ticks_usec()
		var img: Image = a.get("suit_texture_" + which).get_image()
		say("get_image %s: %.1f ms (%s)" % [which, (Time.get_ticks_usec() - t) / 1000.0, img.get_size() if img else "null"])
	var color: Color = api.catalog.COLORS["xc_orange"]
	for label in ["texture_for first", "texture_for cached"]:
		var t := Time.get_ticks_usec()
		var tex = api.recolor.texture_for(a, "xc_orange", color)
		say("%s: %.1f ms (%s)" % [label, (Time.get_ticks_usec() - t) / 1000.0, tex != null])
	var cutoff: bool = a.use_cutoff_textures
	a.use_cutoff_textures = true
	var t := Time.get_ticks_usec()
	api.recolor.texture_for(a, "xc_orange", color)
	say("texture_for cutoff first: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	a.use_cutoff_textures = cutoff
	t = Time.get_ticks_usec()
	a.assign_suit_color("xc_pink")
	await get_tree().process_frame
	say("assign_suit_color(xc_pink) to the next frame: %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	a.assign_suit_color("red")

func _items(seat: Dictionary) -> void:
	say("\n=== items")
	var a = seat.assigner
	var vp: Viewport = seat.viewport
	if vp is SubViewport:
		vp.size = Vector2i(640, 640)
	_candidates(a.bone_attachment_hat.get_node_or_null(api.models.HAT_ANCHOR), false)
	_candidates(a.bone_attachment_glasses.get_node_or_null(api.models.GLASSES_ANCHOR), true)
	for c in CANDIDATES:
		say("candidate_item %s %s" % c)
	for pair in PAIRS:
		var glasses: bool = "glasses" in pair[0]
		var box := AABB()
		for i in 2:
			_wear(a, pair[i], glasses)
			await frames(2)
			var b := _frame(a.bone_attachment_glasses if glasses else a.bone_attachment_hat, a.bone_attachment_glasses.global_position)
			box = b if i == 0 else box.merge(b)
		say("pair %s %s" % pair)
		for id in pair:
			_wear(a, id, glasses)
			await _shoot(seat.camera, vp, box, "item_" + id, YAWS)
			for px in FAR:
				await _shoot_far(seat.camera, vp, seat.character, px, "far_%s_%03dpx" % [id, px])
	for combo in COMBOS:
		a.remove_hat()
		a.remove_glasses()
		a.assign_hat(combo[0])
		a.assign_glasses(combo[1])
		await frames(2)
		var both := _frame(a.bone_attachment_hat, a.bone_attachment_glasses.global_position).merge(
			_frame(a.bone_attachment_glasses, a.bone_attachment_glasses.global_position))
		say("combo %s+%s" % combo)
		await _shoot(seat.camera, vp, both, "combo_%s+%s" % combo, YAWS)
	a.remove_hat()
	a.remove_glasses()

# The hats' or the glasses' candidates beside their anchor (the hat anchor is
# named tophat on a character, cosmetic_tophat2 in the gib), through the mod's
# own inject() pointed at the candidates folder for that one call. Returns them by id.
func _candidates(anchor: Node3D, glasses: bool) -> Dictionary:
	var made := {}
	ok("candidate anchor", anchor != null)
	if anchor == null:
		return made
	var parent := anchor.get_parent()
	var shipped: String = api.models.items_dir
	api.models.items_dir = out_dir.path_join(CANDIDATES_DIR)
	for c in CANDIDATES.filter(func(x): return ("glasses" in x[1]) == glasses):
		var node: Node3D = api.models.inject(parent, anchor, c[0])
		ok("candidate %s loads" % c[0], node != null)
		if node != null:
			made[c[0]] = node
	api.models.items_dir = shipped
	return made

func _wear(a, id: String, glasses: bool) -> void:
	a.remove_hat()
	a.remove_glasses()
	if glasses:
		a.assign_glasses(id)
	else:
		a.assign_hat(id)

# Each hat flies from the game's own set_active_rpc (seeded, so every run
# throws the same way) over a floor at the character's feet, then rests. The
# character is hidden and the gib dropped where it stood, in the seat's light.
func _gibs(seat: Dictionary) -> void:
	say("\n=== gibs")
	var character: Node3D = seat.character
	var vp: Viewport = seat.viewport
	var parent: Node = vp
	var cam: Camera3D = seat.camera
	# The armature hangs from the character's root, which stands at its feet.
	var feet: Vector3 = (character.get_parent() as Node3D).global_position
	var floor_y: float = feet.y
	var start: Vector3 = seat.assigner.bone_attachment_hat.global_position + Vector3.UP * 1.5
	character.visible = false
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(60, 1, 60)
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.mesh.size = Vector2(60, 60)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.31, 0.29)
	plane.material_override = mat
	parent.add_child(floor_body)
	parent.add_child(plane)
	floor_body.global_position = Vector3(feet.x, floor_y - 0.5, feet.z)
	plane.global_position = Vector3(feet.x, floor_y, feet.z)
	var hats := GIB_HATS.duplicate()
	for i in hats.size():
		var id: String = hats[i]
		var gib: Node3D = load(HAT_GIB_SCENE).instantiate()
		parent.add_child(gib)
		var made := _candidates(gib.hat_meshes.get(StringName(api.models.HAT_ANCHOR)), false)
		for cid in made:
			gib.hat_meshes[StringName(cid)] = made[cid]
		floor_body.collision_layer = gib.body.collision_mask
		gib.global_position = start
		gib.global_rotation = Vector3.ZERO
		seed(4100 + i)
		gib.set_active_rpc(true, [StringName(id)])
		# The impulse lands two physics frames in; a quarter of its sideways push keeps the gib in the light.
		await get_tree().physics_frame
		await get_tree().physics_frame
		gib.body.linear_velocity *= Vector3(0.25, 1.0, 0.25)
		var shown: Node3D = gib.hat_meshes.get(StringName(id))
		ok("gib shows %s" % id, shown != null and shown.visible)
		if shown == null:
			gib.queue_free()
			continue
		var t0 := Time.get_ticks_msec()
		for when in GIB_SHOTS:
			await get_tree().create_timer(when - (Time.get_ticks_msec() - t0) / 1000.0, true, true).timeout
			# The body flies; the gib's own node stays where it was spawned.
			await _shoot(cam, vp, _frame(gib.body, gib.body.global_position).grow(0.3), "gib_%s_%03dms" % [id, int(when * 1000)], [45])
		# Rolling turns the hat round the sphere's centre, so one moment says little:
		# every physics frame from 1 s on, how far the mesh dips under the floor.
		var deepest := INF
		var below := 0
		var seen := 0
		while Time.get_ticks_msec() - t0 < GIB_REST * 1000.0:
			await get_tree().physics_frame
			if Time.get_ticks_msec() - t0 < 1000:
				continue
			var gap := _lowest(shown) - floor_y
			deepest = minf(deepest, gap)
			below += 1 if gap < -0.02 else 0
			seen += 1
		say("gib %s 1-%.0f s: lowest point min %.3f vs the floor, below it in %d of %d frames; at %.0f s speed %.2f, spin %.2f" % [
			id, GIB_REST, deepest, below, seen, GIB_REST, gib.body.linear_velocity.length(), gib.body.angular_velocity.length()])
		await _shoot(cam, vp, _frame(gib.body, gib.body.global_position).grow(0.4), "gib_%s_rest" % id, [0, 90])
		gib.queue_free()
	floor_body.queue_free()
	plane.queue_free()
	character.visible = true
	say("gib sideways speed scaled to 0.25 after the impulse; spin and fall are the game's")

func _lowest(holder: Node3D) -> float:
	var y := INF
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		for p in mi.global_transform * mi.mesh.get_faces():
			y = minf(y, p.y)
	return y

# Every suit in the lobby's live list, then each of ours at three candidate
# shades through the real recolor path: a fresh recolor (its own cache) and a
# one-colour table on the seat's XcSuitSync.
func _suits(seat: Dictionary) -> void:
	say("\n=== suits")
	var a = seat.assigner
	var vp: Viewport = seat.viewport
	if vp is SubViewport:
		vp.size = Vector2i(512, 512)
	var skel: Skeleton3D = a.get_parent()
	var body := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
	for b in skel.get_bone_count():
		body = body.expand(skel.global_transform * skel.get_bone_global_pose(b).origin)
	body = body.grow(body.get_longest_axis_size() * 0.08)
	for color in seat.controls.get_script().get_script_constant_map().get("suit_colors", []):
		say("suit vanilla %s" % color)
		a.assign_suit_color(color)
		await _shoot(seat.camera, vp, body, "suit_%s" % color, [0])
	var sync = a.get_node_or_null(SYNC_NAME)
	ok("seat has %s" % SYNC_NAME, sync != null)
	if sync == null:
		return
	var shared_recolor = sync.recolor
	var shared_colors: Dictionary = sync.colors
	for id in api.catalog.COLORS:
		var base: Color = api.catalog.COLORS[id]
		var shades: Array = NEW[id] if NEW.has(id) else [base]
		for k in shades.size():
			var c: Color = shades[k]
			say("candidate %s %d #%s" % [id, k + 1, c.to_html(false)])
			sync.recolor = api.recolor.get_script().new()
			sync.colors = {id: c}
			a.assign_suit_color(id)
			await frames(2)
			await _shoot(seat.camera, vp, body, "suit_%s_%d" % [id, k + 1], [0])
	sync.recolor = shared_recolor
	sync.colors = shared_colors
	a.assign_suit_color("red")

# Whether leaving the lobby frees the suit textures, so a colour is recolored
# again on return. Only instance ids are kept: a reference would hold them.
func _scene_change(a) -> void:
	say("\n=== scene change")
	var red_id: int = a.suit_texture_red.get_instance_id()
	var blue_id: int = a.suit_texture_blue.get_instance_id()
	var cached: int = api.recolor._cache.size()
	a = null
	get_tree().change_scene_to_file(BETWEEN)
	await frames(60)
	var between := get_tree().root.find_children("*", "", true, false).filter(func(n): return n.get_node_or_null(SYNC_NAME) != null).size()
	say("in %s: %d assigners" % [BETWEEN, between])
	var seat: Dictionary = await _seat()
	var a2 = seat.assigner
	say("suit textures same objects: red %s, blue %s" % [a2.suit_texture_red.get_instance_id() == red_id, a2.suit_texture_blue.get_instance_id() == blue_id])
	var t := Time.get_ticks_usec()
	a2.assign_suit_color("xc_orange")
	await get_tree().process_frame
	say("assign xc_orange again: %.1f ms, cache %d -> %d" % [(Time.get_ticks_usec() - t) / 1000.0, cached, api.recolor._cache.size()])

func _frame(attach: Node3D, head: Vector3) -> AABB:
	var box := AABB(head, Vector3.ZERO)
	for mi in attach.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree():
			box = box.merge(mi.global_transform * mi.get_aabb())
	return box.grow(box.get_longest_axis_size() * 0.15)

func _shoot(cam: Camera3D, vp: Viewport, box: AABB, label: String, yaws: Array) -> void:
	var center := box.get_center()
	var distance := (box.size.length() * 0.5) / sin(deg_to_rad(cam.fov * 0.5))
	for deg in yaws:
		var yaw := deg_to_rad(deg)
		cam.global_position = center + Vector3(cos(yaw), 0.15, sin(yaw)).normalized() * distance
		cam.look_at(center)
		await frames(2)
		await RenderingServer.frame_post_draw
		_save(vp.get_texture().get_image(), "%s_%03d" % [label, deg])

# The camera backed off until the character stands px pixels tall in the
# viewport, aimed at its middle. Its meshes' bounds are the standing rest pose,
# not the seated one, so the first far shot measures the lit silhouette and
# corrects the distance for the rest of the run.
func _shoot_far(cam: Camera3D, vp: Viewport, character: Node3D, px: int, label: String) -> void:
	var box := AABB()
	var first := true
	for mi in character.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree():
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	var center := box.get_center()
	var distance := box.size.y * vp.get_visible_rect().size.y / (2.0 * px * tan(deg_to_rad(cam.fov * 0.5)))
	if _far_scale == 0.0:
		await _aim(cam, center, distance, 0)
		var tall := _silhouette_height(vp.get_texture().get_image())
		_far_scale = float(tall) / px if tall > 0 else 1.0
		say("far: the character is %d px tall at the rest pose's %d px distance; scale %.3f" % [tall, px, _far_scale])
	distance *= _far_scale
	for deg in FAR_YAWS:
		await _aim(cam, center, distance, deg)
		_save(vp.get_texture().get_image(), "%s_%03d" % [label, deg])

func _aim(cam: Camera3D, center: Vector3, distance: float, deg: int) -> void:
	var yaw := deg_to_rad(deg)
	cam.global_position = center + Vector3(cos(yaw), 0.15, sin(yaw)).normalized() * distance
	cam.look_at(center)
	await frames(2)
	await RenderingServer.frame_post_draw

# Rows holding any lit pixel, top to bottom; the seat's other meshes are hidden,
# so the background is black.
func _silhouette_height(img: Image) -> int:
	var top := -1
	var bottom := -1
	for y in img.get_height():
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).get_luminance() > 0.04:
				if top < 0:
					top = y
				bottom = y
				break
	return bottom - top + 1 if top >= 0 else 0

func _save(img: Image, name: String) -> void:
	var path := out_dir.path_join("renders").path_join(name)
	if img.save_webp(path + ".webp", true, 0.9) != OK:
		img.save_jpg(path + ".jpg", 0.9)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
