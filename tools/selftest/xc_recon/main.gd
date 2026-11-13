extends Node

# Dev-only recon for the planned more_cosmetics mod. Dumps the vanilla
# cosmetic scenes, materials, bones and hat-gib physics into result.txt, times
# the suit recolor, and exports reference .glb files outside the repo
# (%TEMP%/machine-party-tests/xc_recon/), never into the tree.

const ASSIGNER_SCENE := "res://modules/character_customization/customization_assigner_instance.tscn"
const HAT_GIB_SCENE := "res://prefabs/managed_props/hat_gib.tscn"
const SELECTION_SCENE := "res://modules/character_customization/cosmetic_selection_instance.tscn"
const PLAYER_SCENE := "res://minigames/memorize_path/components/player/memorize_path_player.tscn"
const SUITS := "res://modules/character_customization/character_customization_textures/"
const MATERIAL_PROPS := ["shading_mode", "diffuse_mode", "specular_mode", "albedo_color", "roughness",
	"metallic", "metallic_specular", "texture_filter", "texture_repeat", "transparency", "cull_mode",
	"vertex_color_use_as_albedo", "normal_enabled", "rim_enabled", "emission_enabled", "ao_enabled",
	"disable_receive_shadows", "uv1_scale", "uv1_offset", "uv1_triplanar"]

var fails := 0
var out: FileAccess
var out_dir: String
var _seen_materials := {}

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/xc_recon/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(_loader) -> void:
	out_dir = OS.get_environment("TEMP").path_join("machine-party-tests/xc_recon")
	# Exports hold game textures: a relative path would land them in the game folder or the repo.
	if not out_dir.is_absolute_path():
		ok("TEMP is set", false, out_dir)
		finish()
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	say("mod_ready, exports to %s, renderer %s" % [out_dir, RenderingServer.get_current_rendering_method()])
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	if DisplayServer.get_name() != "headless":
		await _render()
		finish()
		return
	for path in [ASSIGNER_SCENE, HAT_GIB_SCENE, SELECTION_SCENE, PLAYER_SCENE]:
		var scene: PackedScene = load(path)
		ok("loads %s" % path, scene != null)
		if scene == null:
			continue
		var root := scene.instantiate()
		say("\n=== %s" % path)
		_dump(root, root, 0)
		if path == HAT_GIB_SCENE:
			say("hat_meshes keys: %s" % str(root.get("hat_meshes").keys()))
		if path == PLAYER_SCENE:
			_dump_player(root)
		root.free()
	_export_references()
	_fit()
	_suit_textures()
	finish()

func _dump(node: Node, root: Node, depth: int) -> void:
	var line := "%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()]
	var script: Script = node.get_script()
	if script:
		line += " script=%s" % script.resource_path.get_file()
	if node is Node3D:
		var t: Transform3D = node.transform
		line += " pos=%s rot_deg=%s scale=%s" % [_v(t.origin), _v(node.rotation_degrees), _v(node.scale)]
		if not node.visible:
			line += " hidden"
	if node is BoneAttachment3D:
		line += " bone=%s/%d" % [node.bone_name, node.bone_idx]
	if node is VisualInstance3D:
		line += " layers=%d" % node.layers
	say(line)
	if node is MeshInstance3D and node.mesh:
		_dump_mesh(node, depth + 1)
	if node is CollisionShape3D and node.shape:
		say("%s  shape %s %s" % ["  ".repeat(depth), node.shape.get_class(), _shape(node.shape)])
	if node is RigidBody3D:
		say("%s  mass=%s gravity_scale=%s freeze=%s damp=%s/%s phys_mat=%s" % ["  ".repeat(depth), node.mass, node.gravity_scale,
			node.freeze, node.linear_damp, node.angular_damp, _phys(node.physics_material_override)])
	for child in node.get_children():
		_dump(child, root, depth + 1)

func _dump_mesh(mi: MeshInstance3D, depth: int) -> void:
	var mesh: Mesh = mi.mesh
	var pad := "  ".repeat(depth)
	say("%smesh %s aabb=%s surfaces=%d tris=%d skin=%s" % [pad, mesh.resource_path.get_file(), _aabb(mesh.get_aabb()),
		mesh.get_surface_count(), mesh.get_faces().size() / 3, mi.skin != null])
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: int = arrays[Mesh.ARRAY_VERTEX].size() if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null else -1
		var mat: Material = mi.get_active_material(s)
		say("%s surface %d verts=%d material=%s" % [pad, s, verts, _material(mat)])

func _material(mat: Material) -> String:
	if mat == null:
		return "null"
	var id := mat.get_instance_id()
	var tag := "%s#%d %s" % [mat.get_class(), id, mat.resource_path.get_file()]
	if _seen_materials.has(id):
		return tag + " (above)"
	_seen_materials[id] = true
	var parts := [tag]
	if mat is BaseMaterial3D:
		for p in MATERIAL_PROPS:
			parts.append("%s=%s" % [p, str(mat.get(p))])
		parts.append("albedo_texture=%s" % _texture(mat.albedo_texture))
	elif mat is ShaderMaterial:
		parts.append("shader=%s" % (mat.shader.resource_path if mat.shader else "null"))
	return " ".join(parts)

func _texture(tex: Texture2D) -> String:
	if tex == null:
		return "null"
	var s := "%s %dx%d %s" % [tex.resource_path.get_file(), tex.get_width(), tex.get_height(), tex.get_class()]
	var img := tex.get_image()
	if img == null:
		return s + " image=null"
	return s + " format=%d mipmaps=%s" % [img.get_format(), img.has_mipmaps()]

func _dump_player(root: Node) -> void:
	for skel in root.find_children("*", "Skeleton3D", true, false):
		say("\nskeleton %s bones=%d" % [root.get_path_to(skel), skel.get_bone_count()])
		for b in skel.get_bone_count():
			say("  bone %d %s parent=%d global_rest=%s basis_scale=%s" % [b, skel.get_bone_name(b), skel.get_bone_parent(b),
				_v(skel.get_bone_global_rest(b).origin), _v(skel.get_bone_global_rest(b).basis.get_scale())])
	for a in root.find_children("*", "", true, false):
		if a.get_script() and a.get_script().resource_path.ends_with("customization_assigner.gd"):
			say("\nassigner %s parent=%s use_cutoff=%s" % [root.get_path_to(a), a.get_parent().name, a.use_cutoff_textures])
			for color in ["red", "blue", "green", "yellow", "purple"]:
				say("  suit %s: %s | cutoff %s" % [color, _texture(a.get("suit_texture_" + color)), _texture(a.get("suit_texture_cutoff_" + color))])

func _export_references() -> void:
	var assigner: Node = load(ASSIGNER_SCENE).instantiate()
	for attach in assigner.find_children("*", "BoneAttachment3D", true, false):
		for item in attach.get_children():
			_export(item, "item_%s.glb" % item.name)
	assigner.free()
	var player: Node = load(PLAYER_SCENE).instantiate()
	_export(player, "player_memorize_path.glb")
	player.free()

func _export(node: Node, file: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(node, state)
	if err == OK:
		err = doc.write_to_filesystem(state, out_dir.path_join(file))
	var size := FileAccess.get_file_as_bytes(out_dir.path_join(file)).size() if err == OK else 0
	ok("export %s" % file, err == OK and size > 0, "err=%d bytes=%d" % [err, size])

# The head and the reference items at rest pose, in each anchor mesh's local
# space, for tools/cosmetics/ to fit against. Only the logged numbers enter the
# tree; the .obj guides are game geometry and stay in out_dir.
func _fit() -> void:
	say("\n=== fit (anchor mesh local space, Godot axes, rest pose)")
	var player: Node = load(PLAYER_SCENE).instantiate()
	var skel: Skeleton3D = player.find_children("*", "Skeleton3D", true, false)[0]
	var body: MeshInstance3D = null
	for mi in skel.get_children():
		if mi is MeshInstance3D and mi.skin != null:
			body = mi
	ok("fit: skinned body found", body != null)
	if body == null:
		player.free()
		return
	var head := _skinned(skel, body, [skel.find_bone("head"), skel.find_bone("hat")])
	var neck := _skinned(skel, body, [skel.find_bone("neck")])
	# Everything below the head, for items that reach the shoulders.
	var below := range(skel.get_bone_count())
	below.erase(skel.find_bone("head"))
	below.erase(skel.find_bone("hat"))
	var torso := _skinned(skel, body, below)
	ok("fit: head triangles", head.size() > 0, head.size() / 3)
	var refs := {}
	for item in ["tophat", "maska_helmet", "sunglasses", "traffic_cone"]:
		var holder := player.find_child(item, true, false)
		for child in holder.get_children():
			if child is MeshInstance3D:
				refs[item] = child
	for space_name in ["tophat", "sunglasses"]:
		var space := _rest(skel, refs[space_name]).affine_inverse()
		var h := space * head
		var hb := _bounds(h)
		say("\n[%s space]" % space_name)
		say("head %s" % _aabb(hb))
		say("neck %s" % _aabb(_bounds(space * neck)))
		say("body %s" % _aabb(_bounds(space * torso)))
		_obj("fit_%s_body.obj" % space_name, space * torso)
		var up := (space.basis * Vector3.UP).normalized()
		var glasses := _bounds(space * _rest(skel, refs["sunglasses"]) * refs["sunglasses"].mesh.get_faces())
		var face := (glasses.get_center() - hb.get_center()).normalized()
		say("up %s face %s side %s" % [_v(up), _v(face), _v(up.cross(face).normalized())])
		for item in refs:
			var faces: PackedVector3Array = space * _rest(skel, refs[item]) * refs[item].mesh.get_faces()
			say("%s %s" % [item, _aabb(_bounds(faces))])
			_obj("fit_%s_%s.obj" % [space_name, item], faces)
		_profile(h, up)
		_obj("fit_%s_head.obj" % space_name, h)
	player.free()

# Triangle soup, in skeleton space, of the triangles whose three vertices are
# weighted mostly to one of `bones`. ARRAY_BONES indexes the skin's binds.
func _skinned(skel: Skeleton3D, mi: MeshInstance3D, bones: Array) -> PackedVector3Array:
	var skin: Skin = mi.skin
	var bind_bone := []
	var bind_xf := []
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(i))
		bind_bone.append(b)
		bind_xf.append(skel.get_bone_global_rest(b) * skin.get_bind_pose(i))
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null or idx.is_empty():
			idx = range(v.size())
		var per := bi.size() / v.size()
		for t in range(0, idx.size(), 3):
			var keep := true
			for k in 3:
				var o: int = idx[t + k] * per
				var best := o
				for j in range(o, o + per):
					if bw[j] > bw[best]:
						best = j
				keep = keep and bones.has(bind_bone[bi[best]])
			if not keep:
				continue
			for k in 3:
				var vi: int = idx[t + k]
				var p := Vector3.ZERO
				for j in range(vi * per, vi * per + per):
					if bw[j] > 0.0:
						p += bw[j] * (bind_xf[bi[j]] * v[vi])
				out.append(p)
	return out

# Skeleton-space transform of a node under a BoneAttachment3D, at rest pose.
func _rest(skel: Skeleton3D, node: Node3D) -> Transform3D:
	var t := node.transform
	var n := node.get_parent()
	while not n is BoneAttachment3D:
		t = n.transform * t
		n = n.get_parent()
	return skel.get_bone_global_rest(n.bone_idx) * t

func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box

# The head's extent in 8 slices along the local axis nearest to up.
func _profile(points: PackedVector3Array, up: Vector3) -> void:
	var axis := up.abs().max_axis_index()
	var others := [0, 1, 2]
	others.erase(axis)
	var box := _bounds(points)
	var lo := box.position[axis]
	var step := box.size[axis] / 8.0
	for i in 8:
		var s := AABB()
		var first := true
		for p in points:
			if p[axis] >= lo + step * i and p[axis] <= lo + step * (i + 1):
				if first:
					s = AABB(p, Vector3.ZERO)
					first = false
				else:
					s = s.expand(p)
		if not first:
			say("  slice %s %.3f..%.3f: %s %.3f..%.3f, %s %.3f..%.3f" % ["xyz"[axis], lo + step * i, lo + step * (i + 1),
				"xyz"[others[0]], s.position[others[0]], s.end[others[0]], "xyz"[others[1]], s.position[others[1]], s.end[others[1]]])

# Blender axes (x, -z, y), so an import with forward Y and up Z keeps them.
func _obj(file: String, faces: PackedVector3Array) -> void:
	var f := FileAccess.open(out_dir.path_join(file), FileAccess.WRITE)
	for p in faces:
		f.store_line("v %.5f %.5f %.5f" % [p.x, -p.z, p.y])
	for i in range(0, faces.size(), 3):
		f.store_line("f %d %d %d" % [i + 1, i + 2, i + 3])
	f.close()

func _suit_textures() -> void:
	say("\n=== suit textures")
	var red: Texture2D = load(SUITS + "main character painted red.png")
	var blue: Texture2D = load(SUITS + "main character painted blue.png")
	ok("suit textures load", red != null and blue != null)
	if red == null or blue == null:
		return
	say("red %s" % _texture(red))
	var a := red.get_image()
	var b := blue.get_image()
	ok("suit get_image headless", a != null and b != null and not a.is_empty())
	if a == null or b == null or a.is_empty():
		return
	for img in [a, b]:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	var t0 := Time.get_ticks_msec()
	var da := a.get_data()
	var db := b.get_data()
	var differ := 0
	for i in range(0, da.size(), 4):
		if absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2]) > 24:
			differ += 1
	var ms := Time.get_ticks_msec() - t0
	say("mask pass %dx%d: %d ms, %d of %d texels differ (%.1f%%)" % [a.get_width(), a.get_height(), ms, differ,
		da.size() / 4, 100.0 * differ / (da.size() / 4)])
	a.save_png(out_dir.path_join("suit_red.png"))
	b.save_png(out_dir.path_join("suit_blue.png"))
	var orange: Texture2D = load("res://minigames/smoke_break/models/smoke break near final3/smoke break near final3_main character painted orange.png")
	say("smoke_break orange %s" % _texture(orange))

# Windowed only: seat 0's lobby character in the lobby's own lighting, each
# vanilla hat and glasses from 8 sides and each suit front and back.
func _render() -> void:
	var dir := out_dir.path_join("renders")
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")
	await frames(30)
	var lobby = get_tree().current_scene
	lobby.join(-1, false)
	await frames(10)
	var controls = lobby.local_lobby_player_controls[0]
	controls._on_name_confirmed("XC")
	await frames(20)
	var a = controls.customization_assigner
	var vp: Viewport = a.get_viewport()
	if vp is SubViewport:
		vp.size = Vector2i(768, 768)
	# The lobby seats the character facing a wall: hide every other mesh, keep the lights.
	var character: Node = a.get_parent().get_parent()
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not character.is_ancestor_of(g):
			g.visible = false
	var cam := Camera3D.new()
	cam.fov = 30.0
	a.get_parent().add_child(cam)
	cam.make_current()
	say("render viewport %s %s, assigner scale %s" % [vp.get_class(), vp.get_visible_rect().size, _v(a.global_transform.basis.get_scale())])
	a.remove_glasses()
	for hat in a.bone_attachment_hat.get_children():
		if not hat is Node3D or hat.get_child_count() == 0:
			continue
		a.assign_hat(hat.name)
		await _shoot_around(cam, vp, _frame(a.bone_attachment_hat, a.bone_attachment_glasses.global_position), dir, "hat_" + hat.name, 8)
	a.remove_hat()
	for glasses in a.bone_attachment_glasses.get_children():
		if not glasses is Node3D or glasses.get_child_count() == 0:
			continue
		a.assign_glasses(glasses.name)
		await _shoot_around(cam, vp, _frame(a.bone_attachment_glasses, a.bone_attachment_glasses.global_position), dir, "glasses_" + glasses.name, 8)
	a.remove_glasses()
	var skel: Skeleton3D = a.get_parent()
	var body := AABB(skel.global_transform * skel.get_bone_global_pose(0).origin, Vector3.ZERO)
	for b in skel.get_bone_count():
		body = body.expand(skel.global_transform * skel.get_bone_global_pose(b).origin)
	for color in controls.get_script().get_script_constant_map().get("suit_colors", []):
		a.assign_suit_color(color)
		await _shoot_around(cam, vp, body.grow(body.get_longest_axis_size() * 0.12), dir, "suit_" + color, 2)
	ok("renders written", DirAccess.get_files_at(dir).size() > 0, DirAccess.get_files_at(dir).size())

func _frame(attach: Node3D, head: Vector3) -> AABB:
	var box := AABB(head, Vector3.ZERO)
	for mi in attach.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree():
			box = box.merge(mi.global_transform * mi.get_aabb())
	return box.grow(box.get_longest_axis_size() * 0.15)

func _shoot_around(cam: Camera3D, vp: Viewport, box: AABB, dir: String, label: String, sides: int) -> void:
	var center := box.get_center()
	var distance := (box.size.length() * 0.5) / sin(deg_to_rad(cam.fov * 0.5))
	for i in sides:
		var yaw := TAU * i / sides
		cam.global_position = center + Vector3(cos(yaw), 0.15, sin(yaw)).normalized() * distance
		cam.look_at(center)
		await frames(2)
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(dir.path_join("%s_%03d.png" % [label, int(rad_to_deg(yaw))]))

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _aabb(a: AABB) -> String:
	return "pos%s size%s" % [_v(a.position), _v(a.size)]

func _shape(s: Shape3D) -> String:
	if s is BoxShape3D: return "size=%s" % _v(s.size)
	if s is SphereShape3D: return "radius=%.3f" % s.radius
	if s is CylinderShape3D or s is CapsuleShape3D: return "radius=%.3f height=%.3f" % [s.radius, s.height]
	if s is ConvexPolygonShape3D: return "points=%d" % s.points.size()
	return ""

func _phys(m: PhysicsMaterial) -> String:
	return "null" if m == null else "friction=%.2f bounce=%.2f rough=%s" % [m.friction, m.bounce, m.rough]
