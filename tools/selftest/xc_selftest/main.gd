extends Node

# Dev-only headless regression test for more_cosmetics. See README.
# Reads the vanilla names from the live scripts, so Overtime's lists count.

const PLAYER_SCENE := "res://minigames/chisel_gauntlet_multiplayer/components/player/chisel_gauntlet_player.tscn"
const HAT_GIB_SCENE := "res://prefabs/managed_props/hat_gib.tscn"
const TILE_SCENE := "res://modules/character_customization/cosmetic_selection_instance.tscn"
const CONTROLS_PATH := "res://scenes/local_lobby/scripts/local_lobby_player_controls.gd"
const HUNTER_SCENE := "res://minigames/duck_hunt/components/hunter_player/hunter_player.tscn"
const COLLAR_PLAYER_SCENE := "res://minigames/exploding_collar_race/components/player/exploding_collar_race_player.tscn"
const LEGS_SCENE := "res://minigames/exploding_collar_race/components/legs cut off/legs_cut_off_parent.tscn"
const SCREEN_SCENE := "res://scenes/character_customization.tscn"
const SELECTION_PATH := "res://scripts/components/character customization/customization_selection.gd"
const BRANCH_PATH := "res://scripts/components/character customization/customization_selection_branch.gd"

var fails := 0
var out: FileAccess
var _loader
var api
var c
var vanilla_gib_keys: Array

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/xc_selftest/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	_loader = loader
	say("mod_ready, mods: %s" % str(loader.mod_list()))
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	api = _loader.registry("more_cosmetics").get("api")
	ok("more_cosmetics loaded", api != null and api.catalog != null)
	if api == null or api.catalog == null:
		finish(); return
	c = api.catalog
	_registry()
	var player = load(PLAYER_SCENE).instantiate()
	get_tree().root.add_child(player)
	await frames(3)
	var a = player.customization_assigner
	_id_rules(a)
	_assets()
	_assigner(a)
	await _gib()
	await _tile()
	_recolor_functions(a)
	await _suit_sync(a)
	await _hands(player, "chisel")
	var hunter = load(HUNTER_SCENE).instantiate()
	get_tree().root.add_child(hunter)
	_quiet(hunter)
	await frames(2)
	await _hands(hunter, "hunter")
	hunter.queue_free()
	await _legs()
	await _no_duplicates(player)
	player.queue_free()
	_stepper_static()
	await _lobby()
	await _online()
	finish()

func _registry() -> void:
	say("step: registry")
	var reg: Dictionary = _loader.registry("more_cosmetics")
	ok("registry glasses", reg.get("glasses") == c.GLASSES, reg.get("glasses"))
	ok("registry no_glasses_hats", reg.get("no_glasses_hats") == ["xc_diving_helmet", "xc_dragonborn_helmet"], reg.get("no_glasses_hats"))

func _all_ids() -> Array:
	return c.HATS + c.GLASSES + c.COLORS.keys()

func _id_rules(a) -> void:
	say("step: id rules")
	var ids := _all_ids()
	ok("ids carry the xc_ prefix", ids.all(func(i): return i.begins_with("xc_")), ids)
	ok("glasses ids contain glasses", c.GLASSES.all(func(i): return "glasses" in i))
	ok("hat and color ids don't", (c.HATS + c.COLORS.keys()).all(func(i): return not "glasses" in i))
	var seen := {}
	for i in ids: seen[i] = true
	ok("ids unique", seen.size() == ids.size(), [seen.size(), ids.size()])

	var vanilla := {}
	for n in a.bone_attachment_hat.get_children() + a.bone_attachment_glasses.get_children():
		if not seen.has(str(n.name)): vanilla[str(n.name)] = true
	var gib = load(HAT_GIB_SCENE).instantiate()
	vanilla_gib_keys = gib.hat_meshes.keys().map(func(k): return str(k))
	gib.free()
	for k in vanilla_gib_keys: vanilla[k] = true
	var consts: Dictionary = load(CONTROLS_PATH).get_script_constant_map()
	ok("lobby lists readable", consts.has("hats") and consts.has("suit_colors"), consts.keys())
	for list in ["hats", "suit_colors"]:
		for n in consts.get(list, []): vanilla[str(n)] = true
	say("runtime names: %s" % str(vanilla.keys()))
	ok("no id collides with a runtime name", ids.filter(func(i): return vanilla.has(i)).is_empty())

func _assets() -> void:
	say("step: assets")
	for id in c.HATS + c.GLASSES:
		var m: Mesh = api.models.mesh(id)
		var t: Texture2D = api.models.texture(id)
		ok("loads %s" % id, m != null and t != null and t.get_width() == 512 and t.get_height() == 512,
			"tris=%d" % (m.get_faces().size() / 3 if m else -1))
		# Every item's art comes from its generator, tools/cosmetics/<id>.py.
		var tris := m.get_faces().size() / 3 if m else -1
		ok("%s in the 400..2000 triangle budget" % id, tris >= 400 and tris <= 2000, tris)
		ok("%s has one surface with UVs" % id, m != null and m.get_surface_count() == 1
			and m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null, m.get_surface_count() if m else -1)

func _visible_children(parent: Node) -> Array:
	return parent.get_children().filter(func(n): return n is Node3D and n.visible).map(func(n): return str(n.name))

func _assigner(a) -> void:
	say("step: assigner")
	for id in c.HATS:
		a.assign_hat(id)
		var shown := _visible_children(a.bone_attachment_hat)
		ok("assign_hat %s" % id, str(a.get_assigned_hat()) == id and shown == [id], shown)
	var hat_mesh = a.bone_attachment_hat.get_node(c.HATS[0]).get_child(0)
	ok("our hat has mesh and texture", hat_mesh is MeshInstance3D and hat_mesh.mesh != null
		and hat_mesh.get_surface_override_material(0).albedo_texture != null)
	var before: int = hat_mesh.layers
	a.set_visibility_layer(1 << 5)
	ok("set_visibility_layer covers our hats", hat_mesh.layers == 1 << 5, hat_mesh.layers)
	a.set_visibility_layer(before)
	for id in c.GLASSES:
		a.assign_glasses(id)
		var shown := _visible_children(a.bone_attachment_glasses)
		ok("assign_glasses %s" % id, shown == [id], shown)
	a.assign_hat("none")
	a.assign_glasses("none")

func _gib() -> void:
	say("step: hat gib")
	var scene: PackedScene = load(HAT_GIB_SCENE)
	var gib = scene.instantiate()
	var gib2 = scene.instantiate()
	get_tree().root.add_child(gib)
	get_tree().root.add_child(gib2)
	var keys: Array = gib.hat_meshes.keys().map(func(k): return str(k))
	ok("gib has every hat", c.HATS.all(func(i): return keys.has(i)), keys)
	ok("gib keeps the vanilla hats", vanilla_gib_keys.all(func(k): return keys.has(k)) and keys.size() == vanilla_gib_keys.size() + c.HATS.size(), keys.size())
	for id in ["tophat"] + c.HATS:
		gib.set_active_rpc(true, [id])
		var shown: Array = gib.hat_meshes.keys().filter(func(k): return gib.hat_meshes[k].visible).map(func(k): return str(k))
		ok("gib shows only %s" % id, shown == [id], shown)
	var own := true
	for i in c.HATS:
		var n = gib.hat_meshes[StringName(i)]
		own = own and gib.is_ancestor_of(n) and n != gib2.hat_meshes[StringName(i)]
	ok("gib instances own their nodes", own)
	gib.queue_free()
	gib2.queue_free()
	await frames(1)

func _tile() -> void:
	say("step: preview tile")
	var tile = load(TILE_SCENE).instantiate()
	get_tree().root.add_child(tile)
	await frames(2)
	var holder: Node = tile.cosmetic_holder_parent
	var ours: Array = (c.HATS + c.GLASSES).map(func(i): return holder.get_node_or_null(NodePath(i)))
	ok("tile has every item", ours.all(func(n): return n != null))
	# Ours start hidden anyway; show one and rerun _ready to prove it reaches them.
	if ours[0] != null:
		ours[0].visible = true
	tile._ready()
	ok("tile _ready hides ours", ours.all(func(n): return n != null and not n.visible))
	tile.setup_cosmetic(c.HATS[3])
	ok("setup_cosmetic shows ours", holder.get_node(NodePath(c.HATS[3])).visible)
	var g: Node3D = holder.get_node(NodePath(c.GLASSES[0]))
	ok("tile glasses take the anchor's scale", g.scale.is_equal_approx(holder.get_node("sunglasses").scale), g.scale)
	tile.queue_free()
	await frames(1)

func _recolor_functions(a) -> void:
	say("step: recolor functions")
	var r = api.recolor
	# Texel 0 is skin (same in both), 1 and 2 are dark and light cloth.
	var red := Image.create_from_data(3, 1, false, Image.FORMAT_RGB8, PackedByteArray([200, 150, 120, 90, 30, 25, 180, 60, 50]))
	var blue := Image.create_from_data(3, 1, false, Image.FORMAT_RGB8, PackedByteArray([200, 150, 120, 40, 45, 60, 70, 80, 110]))
	var mask: PackedByteArray = r.cloth_mask(red.get_data(), blue.get_data())
	ok("mask finds the cloth", mask == PackedByteArray([0, 1, 1]), mask)
	var teal: Color = c.COLORS["xc_teal"]
	var img: Image = r.recolor(red, blue, teal)
	var px := img.get_data()
	ok("skin unchanged", px.slice(0, 3) == PackedByteArray([200, 150, 120]), px.slice(0, 3))
	var dark := Color8(px[3], px[4], px[5])
	var light := Color8(px[6], px[7], px[8])
	ok("cloth takes the hue", absf(dark.h - teal.h) < 0.03 and absf(light.h - teal.h) < 0.03, [dark.h, light.h, teal.h])
	ok("shading order kept", light.v > dark.v, [dark.v, light.v])
	ok("output RGB8, same size, no mipmaps", img.get_format() == Image.FORMAT_RGB8 and img.get_size() == red.get_size() and not img.has_mipmaps())

	var t0 := Time.get_ticks_msec()
	var tex: Texture2D = r.texture_for(a, "xc_orange", c.COLORS["xc_orange"])
	var ms := Time.get_ticks_msec() - t0
	ok("real suit recolors", tex != null and tex.get_size() == a.suit_texture_red.get_size(), "%d ms, %s" % [ms, tex.get_size() if tex else null])
	t0 = Time.get_ticks_msec()
	ok("second call is cached", r.texture_for(a, "xc_orange", c.COLORS["xc_orange"]) == tex and Time.get_ticks_msec() - t0 < 5)

func _suit_sync(a) -> void:
	say("step: suit sync")
	var r = api.recolor
	ok("helper attached", a.get_node_or_null("XcSuitSync") != null)
	ok("cutoff textures present", a.suit_texture_cutoff_red != null and a.suit_texture_cutoff_blue != null)
	a.use_cutoff_textures = false
	a.assign_suit_color("xc_teal")
	await frames(2)
	var full: Texture2D = r.texture_for(a, "xc_teal", c.COLORS["xc_teal"])
	ok("full: our texture, not blue", full != null and a.character_material.albedo_texture == full and full != a.suit_texture_blue)
	a.use_cutoff_textures = true
	var t0 := Time.get_ticks_msec()
	a.assign_suit_color("xc_teal")
	await frames(2)
	var cut: Texture2D = r.texture_for(a, "xc_teal", c.COLORS["xc_teal"])
	ok("cutoff: the cutoff-sourced texture", cut != null and a.character_material.albedo_texture == cut and cut != full, "%d ms" % (Time.get_ticks_msec() - t0))
	a.use_cutoff_textures = false
	a.assign_suit_color("red")
	await frames(2)
	ok("vanilla color untouched", a.character_material.albedo_texture == a.suit_texture_red)

# Game scripts that expect a running minigame; our helpers process on their own.
func _quiet(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)

# What set_player_presence does to the hands (chisel_gauntlet_player.gd:322-328,
# hunter_player.gd:567-577), without its cameras, mouse capture and PlayerManager.
func _paint_hands_like_the_game(player, color: String) -> void:
	var mat: StandardMaterial3D = player.hand_meshes[0].get_active_material(0).duplicate()
	mat.albedo_texture = player.customization_assigner.get_suit_texture(color)
	for hm in player.hand_meshes:
		hm.set_surface_override_material(0, mat)

func _hand_textures(player) -> Array:
	return player.hand_meshes.map(func(hm):
		var m = hm.get_surface_override_material(0)
		return m.albedo_texture if m else null)

func _hands(player, label: String) -> void:
	say("step: hands, " + label)
	ok("%s: one hands helper" % label, _syncs(player) == 1, _syncs(player))
	var a = player.customization_assigner
	var hands: Array = player.hand_meshes
	ok("%s: hand meshes and assigner" % label, not hands.is_empty() and a != null, hands.size())
	if hands.is_empty() or a == null:
		return
	var shared: BaseMaterial3D = hands[0].get_active_material(0)
	var shared_tex = shared.albedo_texture
	var pres := PlayerPresence.new()
	pres.customization = ["none", "none", "xc_teal"]
	player.player_presence = pres
	await frames(2)
	ok("%s: unpainted hands left alone" % label, hands[0].get_surface_override_material(0) == null and shared.albedo_texture == shared_tex)
	_paint_hands_like_the_game(player, "xc_teal")
	await frames(2)
	var teal: Texture2D = api.recolor.texture_for(a, "xc_teal", c.COLORS["xc_teal"])
	var got := _hand_textures(player)
	ok("%s: our color on every hand" % label, teal != null and teal != a.suit_texture_blue and got.all(func(t): return t == teal), got)
	ok("%s: shared hand material untouched" % label, shared.albedo_texture == shared_tex)
	pres.customization = ["none", "none", "blue"]
	_paint_hands_like_the_game(player, "blue")
	await frames(2)
	got = _hand_textures(player)
	ok("%s: true blue stays blue" % label, got.all(func(t): return t == a.suit_texture_blue), got)
	for hm in hands:
		hm.set_surface_override_material(0, null)
	player.player_presence = null
	pres.free()

# What exploding_collar_race.gd:208-216 spawn_legs does.
func _spawn_legs(parent: Node3D, at: Vector3, color: String) -> Node3D:
	var legs: Node3D = load(LEGS_SCENE).instantiate()
	parent.add_child(legs)
	legs.global_position = at
	legs.get_child(0).assign_suit_color(color)
	legs.get_child(1).assign_suit_color(color)
	return legs

func _legs_textures(legs: Node3D) -> Array:
	return [legs.get_child(0).character_material.albedo_texture, legs.get_child(1).character_material.albedo_texture]

func _legs() -> void:
	say("step: collar race legs")
	var near = api.legs
	ok("nearest: one in reach", near.nearest([Vector3(3, 0, 0), Vector3(0.1, 0, 0)], Vector3.ZERO, 0.5) == 1)
	ok("nearest: none in reach", near.nearest([Vector3(3, 0, 0)], Vector3.ZERO, 0.5) == -1)
	ok("nearest: the closest wins", near.nearest([Vector3(0.3, 0, 0), Vector3(0.05, 0, 0)], Vector3.ZERO, 0.5) == 1)

	var scene: PackedScene = load(COLLAR_PLAYER_SCENE)
	var teal = scene.instantiate()
	var blue = scene.instantiate()
	var spawn := Node3D.new()
	for n in [teal, blue, spawn]:
		get_tree().root.add_child(n)
	_quiet(teal)
	_quiet(blue)
	teal.global_position = Vector3(20, 0, 0)
	blue.global_position = Vector3(20.3, 0, 0)
	teal.customization_assigner.assign_suit_color("xc_teal")
	blue.customization_assigner.assign_suit_color("blue")
	ok("players tracked", teal.is_in_group(near.GROUP) and blue.is_in_group(near.GROUP))

	var at_teal := _spawn_legs(spawn, teal.global_position, "xc_teal")
	var at_blue := _spawn_legs(spawn, blue.global_position, "blue")
	var alone := _spawn_legs(spawn, Vector3(40, 0, 0), "xc_teal")
	await frames(2)
	var l = at_teal.get_child(0)
	var want: Texture2D = api.recolor.texture_for_pair(l.suit_texture_red, l.suit_texture_blue, "xc_teal", c.COLORS["xc_teal"])
	var got := _legs_textures(at_teal)
	ok("legs at our color take it", want != null and want != l.suit_texture_blue and got.all(func(t): return t == want), got)
	var ta = teal.customization_assigner
	ok("legs share the body's texture", want == api.recolor.texture_for(ta, "xc_teal", c.COLORS["xc_teal"]),
		[ta.use_cutoff_textures, l.suit_texture_red.resource_path, ta.suit_texture_red.resource_path])
	got = _legs_textures(at_blue)
	ok("legs at true blue stay blue", got.all(func(t): return t == at_blue.get_child(0).suit_texture_blue), got)
	got = _legs_textures(alone)
	ok("legs with nobody there stay blue", got.all(func(t): return t == alone.get_child(0).suit_texture_blue), got)
	for n in [teal, blue, spawn]:
		n.queue_free()
	await frames(1)

# By mesh, not name: a second copy would have been renamed by add_child.
func _ours_under(parent: Node, ids: Array) -> int:
	var meshes := ids.map(func(i): return api.models.mesh(i))
	var n := 0
	for child in parent.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is MeshInstance3D and meshes.has(child.get_child(0).mesh):
			n += 1
	return n

func _syncs(a) -> int:
	return a.get_children().filter(func(n): return n.get_script() != null and "recolor" in n).size()

func _no_duplicates(player) -> void:
	say("step: no duplicates")
	var parent: Node = player.get_parent()
	parent.remove_child(player)
	parent.add_child(player)
	await frames(2)
	var a = player.customization_assigner
	ok("re-enter: one of each hat", _ours_under(a.bone_attachment_hat, c.HATS) == c.HATS.size(), _ours_under(a.bone_attachment_hat, c.HATS))
	ok("re-enter: one of each glasses", _ours_under(a.bone_attachment_glasses, c.GLASSES) == c.GLASSES.size())
	ok("re-enter: one helper", _syncs(a) == 1, _syncs(a))
	ok("re-enter: one hands helper", _syncs(player) == 1, _syncs(player))

	# Overtime's online lobby copies player slots with duplicate().
	var dup = player.duplicate()
	dup.name = "XcDuplicate"
	parent.add_child(dup)
	await frames(2)
	var da = dup.customization_assigner
	ok("duplicate: one of each hat", _ours_under(da.bone_attachment_hat, c.HATS) == c.HATS.size(), _ours_under(da.bone_attachment_hat, c.HATS))
	ok("duplicate: one of each glasses", _ours_under(da.bone_attachment_glasses, c.GLASSES) == c.GLASSES.size())
	ok("duplicate: one helper", _syncs(da) == 1, _syncs(da))
	ok("duplicate: one hands helper", _syncs(dup) == 1, _syncs(dup))
	da.assign_hat(c.HATS[0])
	ok("duplicate: assign_hat works", str(da.get_assigned_hat()) == c.HATS[0], da.get_assigned_hat())
	da.assign_suit_color("xc_pink")
	await frames(2)
	ok("duplicate: helper recolors", da.character_material.albedo_texture == api.recolor.texture_for(da, "xc_pink", c.COLORS["xc_pink"]))
	dup.queue_free()

# The game's own lists, as decompiled; the live ones are asserted against these.
const VANILLA_HATS := ["none", "beer_hat", "cap_blade", "tophat", "traffic_cone", "maska_helmet", "drill_sgt_hat", "hard_hat"]
const VANILLA_COLORS := ["red", "blue", "green", "yellow", "purple"]
const OVERTIME_COLORS := ["red", "blue", "green", "yellow", "purple", "mp8_sunset", "mp8_aurora", "mp8_twilight"]

# change_hat / change_color (local_lobby_player_controls.gd:431-456), written
# out again here so game_step is checked against something it didn't produce.
func _ref_step(list: Array, cur: String, dir: int, is_hat: bool) -> String:
	var i := list.find(cur)
	if i < 0 and is_hat:
		i = 0
	return str(list[wrapi(i + dir, 0, list.size())])

func _stepper_static() -> void:
	say("step: lobby stepper, static")
	var S: GDScript = api._stepper_script
	var consts: Dictionary = load(CONTROLS_PATH).get_script_constant_map()
	var cases := [
		["vanilla hats", VANILLA_HATS, c.HATS, true],
		["live hats", consts.get("hats", []), c.HATS, true],
		["vanilla colors", VANILLA_COLORS, c.COLORS.keys(), false],
		["overtime colors", OVERTIME_COLORS, c.COLORS.keys(), false],
		["live colors", consts.get("suit_colors", []), c.COLORS.keys(), false],
	]
	for k in cases:
		var label: String = k[0]
		var list: Array = k[1]
		var ours: Array = k[2]
		var is_hat: bool = k[3]
		var unk: int = 0 if is_hat else -1
		var unknown := "rubiks_cube" if is_hat else "mp8_x"
		var ext: Array = S.extended(list, ours)
		ok("%s: extended is the list then ours" % label, ext == list + ours, ext)
		var bad := []
		for b in ext + [unknown]:
			for d in [-1, 0, 1]:
				if S.game_step(list, b, d, unk) != _ref_step(list, b, d, is_hat):
					bad.append([b, d])
		ok("%s: game_step matches the game" % label, bad.is_empty(), bad)
		bad = []
		for b in ext:
			for d in [-1, 1]:
				var want: String = ext[wrapi(ext.find(b) + d, 0, ext.size())]
				if S.remap_step(list, ours, unk, b, S.game_step(list, b, d, unk)) != want:
					bad.append([b, d])
		for d in [-1, 1]:
			var a: String = S.game_step(list, unknown, d, unk)
			if S.remap_step(list, ours, unk, unknown, a) != a:
				bad.append([unknown, d])
		ok("%s: remap_step gives the extended neighbour" % label, bad.is_empty(), bad)
		for d in [-1, 1]:
			var seen := []
			var cur: String = ext[0]
			for i in ext.size():
				cur = S.remap_step(list, ours, unk, cur, S.game_step(list, cur, d, unk))
				seen.append(cur)
			ok("%s: walk %+d visits each once and returns" % [label, d], cur == ext[0] and seen.size() == ext.size() and ext.all(func(x): return seen.has(x)), seen)
		bad = []
		for b in ext + [unknown]:
			for a in ext + [unknown]:
				var is_step: bool = a != b and (S.game_step(list, b, -1, unk) == a or S.game_step(list, b, 1, unk) == a)
				if not is_step and S.remap_step(list, ours, unk, b, a) != a:
					bad.append([b, a])
		ok("%s: anything but a step passes through" % label, bad.is_empty(), bad)
	ok("empty list passes through", S.remap_step([], c.HATS, 0, "a", "b") == "b" and S.game_step([], "a", 1, 0) == "a")
	ok("one-item list passes through", S.remap_step(["a"], c.HATS, 0, "a", "a") == "a")
	ok("two-item list (ambiguous) passes through", S.remap_step(["a", "b"], c.HATS, 0, "a", "b") == "b")
	var with_ours: Array = VANILLA_HATS + [c.HATS[0]]
	var ext2: Array = S.extended(with_ours, c.HATS)
	var seen2 := {}
	var cur2 := "none"
	for i in ext2.size():
		cur2 = S.remap_step(with_ours, c.HATS, 0, cur2, S.game_step(with_ours, cur2, 1, 0))
		seen2[cur2] = true
	ok("a list already holding one of ours: each id once", ext2.size() == VANILLA_HATS.size() + c.HATS.size() and seen2.size() == ext2.size() and cur2 == "none", [ext2.size(), seen2.size()])
	ok("StringName before", S.remap_step(VANILLA_HATS, c.HATS, 0, StringName("hard_hat"), "none") == c.HATS[0])

func _has_mod(id: String) -> bool:
	return _loader.mod_list().any(func(m): return str(m).begins_with(id + " "))

# Overtime adds its three two-tone suits; 8 Player Support, Overtime's scripts under another id, keeps the game's five.
func _overtime_suits() -> bool:
	return _has_mod("overtime")

# Presses action_1 for one frame; the keyboard path steps the active element
# in mouse_and_keyboard_direction (local_lobby_player_controls.gd:405-424).
func _key_step(seat, dir: int) -> void:
	seat.mouse_and_keyboard_direction = dir
	seat.button_cooldown_timer = 0.0
	Input.action_press("action_1")
	await frames(1)
	Input.action_release("action_1")
	await frames(1)

func _lobby() -> void:
	say("step: lobby stepper, live")
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")
	await frames(30)
	var lobby = get_tree().current_scene
	var seats: Array = lobby.local_lobby_player_controls
	var S: GDScript = api._stepper_script
	var counts: Array = seats.map(func(s): return s.get_children().filter(func(n): return n.get_script() == S).size())
	ok("one stepper on each of %d seats" % lobby.MAX_PLAYERS, seats.size() == lobby.MAX_PLAYERS and counts.all(func(n): return n == 1), counts)
	var consts: Dictionary = seats[0].get_script().get_script_constant_map()
	var hats: Array = consts.get("hats", [])
	var colors: Array = consts.get("suit_colors", [])
	var overtime := _overtime_suits()
	ok("live hats are vanilla's", hats == VANILLA_HATS, hats)
	ok("live colors: %s" % ("Overtime's 8" if overtime else "vanilla's 5"), colors == (OVERTIME_COLORS if overtime else VANILLA_COLORS), colors)

	lobby.join(-1, false)
	await frames(5)
	var seat = seats[0]
	seat._on_name_confirmed("XC")
	await frames(3)
	var a = seat.customization_assigner
	var stepper: Node = seat.get_node("XcLobbyStepper")
	ok("plain join not remapped", str(a.get_assigned_hat()) == "none" and str(a.assigned_suit_color) == colors[0], [a.get_assigned_hat(), a.assigned_suit_color])

	stepper.set_process(false)
	var bad := []
	for b in hats + c.HATS + ["rubiks_cube"]:
		for d in [-1, 1]:
			a.assign_hat(b)
			seat.change_hat(d)
			if str(a.get_assigned_hat()) != S.game_step(hats, b, d, 0):
				bad.append([b, d, str(a.get_assigned_hat())])
	for b in colors + c.COLORS.keys() + ["mp8_x"]:
		for d in [-1, 1]:
			a.assign_suit_color(b)
			seat.change_color(d)
			if str(a.assigned_suit_color) != S.game_step(colors, b, d, -1):
				bad.append([b, d, str(a.assigned_suit_color)])
	ok("game_step matches the live change_hat/change_color", bad.is_empty(), bad)
	a.assign_hat("none")
	a.assign_suit_color(colors[0])
	stepper.set_process(true)
	await frames(2)

	var ext_hats: Array = S.extended(hats, c.HATS)
	seat.active_element = seat.hat_picker_element
	for d in [1, -1]:
		var seen := []
		for i in ext_hats.size():
			await _key_step(seat, d)
			seen.append(str(a.get_assigned_hat()))
		var want: Array = []
		for i in ext_hats.size():
			want.append(ext_hats[wrapi((i + 1) * d, 0, ext_hats.size())])
		ok("keyboard: hats %+d through ours and back to none" % d, seen == want, seen)

	var ext_colors: Array = S.extended(colors, c.COLORS.keys())
	seat.active_element = seat.color_picker_element
	for d in [1, -1]:
		var seen := []
		var painted := true
		var slowest := 0
		for i in ext_colors.size():
			var t0 := Time.get_ticks_msec()
			await _key_step(seat, d)
			slowest = maxi(slowest, Time.get_ticks_msec() - t0)
			var got := str(a.assigned_suit_color)
			seen.append(got)
			if c.COLORS.has(got):
				var tex: Texture2D = api.recolor.texture_for(a, got, c.COLORS[got])
				painted = painted and a.character_material.albedo_texture == tex and tex != a.suit_texture_blue
		var want: Array = []
		for i in ext_colors.size():
			want.append(ext_colors[wrapi((i + 1) * d, 0, ext_colors.size())])
		ok("keyboard: colors %+d through ours and back" % d, seen == want, seen)
		ok("keyboard: our colors painted on landing (%+d)" % d, painted, "slowest step %d ms" % slowest)

	say("step: lobby stepper, a missing model")
	seat.active_element = seat.hat_picker_element
	var gone: Node = a.bone_attachment_hat.get_node(NodePath(c.HATS[1]))
	a.bone_attachment_hat.remove_child(gone)
	a.assign_hat(c.HATS[0])
	await frames(1)
	await _key_step(seat, 1)
	ok("a hat with no node is skipped", str(a.get_assigned_hat()) == c.HATS[2], a.get_assigned_hat())
	a.bone_attachment_hat.add_child(gone)

	say("step: lobby stepper, rejoin")
	a.assign_hat("hard_hat")
	await frames(1)
	seat.set_active(0, -1, false, {"customization": ["none", "none", colors[0]], "player_name": "XC"})
	await frames(2)
	ok("rejoin that looks like a step is not remapped", str(a.get_assigned_hat()) == "none", a.get_assigned_hat())

	say("step: lobby stepper, joystick")
	lobby.join(0, true)
	await frames(3)
	var pad = seats[1]
	pad._on_name_confirmed("PAD")
	await frames(3)
	var pa = pad.customization_assigner
	ok("pad join not remapped", str(pa.get_assigned_hat()) == "none" and str(pa.assigned_suit_color) == colors[1], [pa.get_assigned_hat(), pa.assigned_suit_color])
	# Headless has no pads; MultiplayerInput makes a device's actions when one connects.
	var right := "0right"
	var made := false
	if not InputMap.has_action(right):
		MultiplayerInput._create_actions_for_device(0)
		made = true
	if InputMap.has_action(right):
		pa.assign_hat("hard_hat")
		await frames(1)
		Input.action_press(right)
		await frames(1)
		Input.action_release(right)
		await frames(1)
		ok("pad: right from hard_hat lands on ours", str(pa.get_assigned_hat()) == c.HATS[0], pa.get_assigned_hat())
	else:
		ok("pad: %s action exists" % right, false)
	if made:
		MultiplayerInput._delete_actions_for_device(0)

	say("step: lobby stepper, presences")
	a.assign_hat(c.HATS[3])
	a.assign_suit_color("xc_brown")
	lobby.update_player_manager()
	var pres = PlayerManager.player_presences.get(-1)
	ok("presence carries our hat and color", pres != null and str(pres.customization[0]) == c.HATS[3] and str(pres.customization[2]) == "xc_brown", pres.customization if pres else null)

# The online customization screen. Its _ready loads the saved preferences into
# Globals, so they are put back afterwards; nothing here sends ui_cancel or
# action_2, which save and exit.
func _wear(sel, hat: String, glasses: String) -> void:
	var a = sel.customization_assigner
	if hat == "": a.remove_hat()
	else: a.assign_hat(hat)
	if glasses == "": a.remove_glasses()
	else: a.assign_glasses(glasses)
	Globals.active_cosmetic_hat = hat
	Globals.active_cosmetic_glasses = glasses

func _worn(sel) -> Array:
	return [Globals.active_cosmetic_hat, Globals.active_cosmetic_glasses]

func _shown(sel) -> Array:
	var a = sel.customization_assigner
	return [_visible_children(a.bone_attachment_hat), _visible_children(a.bone_attachment_glasses)]

func _online() -> void:
	say("step: online screen")
	var g := {}
	for k in ["active_cosmetic_hat", "active_cosmetic_glasses", "active_cosmetic_suit_color"]:
		g[k] = Globals.get(k)
	get_tree().change_scene_to_file(SCREEN_SCENE)
	await frames(10)
	var screen := get_tree().current_scene
	var sel: Node = null
	for n in screen.find_children("*", "Node", true, false):
		if n.get_script() != null and n.get_script().resource_path == SELECTION_PATH:
			sel = n
	ok("online screen has its selection", sel != null)
	if sel == null:
		return
	var P: GDScript = api._picker_script
	var pickers := sel.get_children().filter(func(n): return n.get_script() == P)
	ok("one picker on the selection", pickers.size() == 1, pickers.size())
	if pickers.size() != 1:
		return
	var picker: Node = pickers[0]
	var buttons := {}
	for n in sel.ui_root.find_children("*", "", true, false):
		if n.get_script() != null and n.get_script().resource_path == BRANCH_PATH and not n.is_suit_color_selection:
			buttons[str(n.assigned_cosmetic)] = n.button
	var hooked: Array = buttons.keys().filter(func(id): return buttons[id].is_pressed.get_connections().any(
		func(cn): return cn.callable.get_object() == picker))
	ok("picker follows every item tile", buttons.size() == sel.customizations.size() and hooked.size() == buttons.size(), hooked)
	var blocking: Array = picker.blocking_hats(sel)
	ok("blocking hats: the Maska and ours", blocking.has("maska_helmet") and c.NO_GLASSES_HATS.all(func(h): return blocking.has(h))
		and blocking.size() == 1 + c.NO_GLASSES_HATS.size(), blocking)

	var v_hats: Array = sel.customizations.filter(func(id): return not "glasses" in id)
	var v_glasses: Array = sel.customizations.filter(func(id): return "glasses" in id)
	var bad := []
	var count := 0
	for h in [""] + v_hats:
		for gl in [""] + v_glasses:
			for p in sel.customizations:
				_wear(sel, h, gl)
				sel.select_cosmetic(p)
				count += 1
				if _worn(sel) != P.select(h, gl, p, blocking):
					bad.append([h, gl, p, _worn(sel)])
	ok("select() matches the live select_cosmetic on %d vanilla presses" % count, bad.is_empty(), bad)

	var want := {
		"our glasses under a vanilla hat": [["tophat", "", c.GLASSES[0]], ["tophat", c.GLASSES[0]]],
		"our glasses under our hat": [[c.HATS[0], "sunglasses", c.GLASSES[1]], [c.HATS[0], c.GLASSES[1]]],
		"glasses refused under the diving helmet": [["xc_diving_helmet", "", c.GLASSES[0]], ["xc_diving_helmet", ""]],
		"the diving helmet takes glasses off": [["tophat", c.GLASSES[0], "xc_diving_helmet"], ["xc_diving_helmet", ""]],
		"our hat keeps glasses": [["", "sunglasses", c.HATS[0]], [c.HATS[0], "sunglasses"]],
		"the Maska takes our glasses off": [["", c.GLASSES[2], "maska_helmet"], ["maska_helmet", ""]],
		"pressing our worn glasses takes them off": [[c.HATS[1], c.GLASSES[3], c.GLASSES[3]], [c.HATS[1], ""]],
		"pressing our worn hat takes it off": [[c.HATS[1], c.GLASSES[3], c.HATS[1]], ["", c.GLASSES[3]]],
	}
	for label in want:
		var a: Array = want[label][0]
		ok("select(): %s" % label, P.select(a[0], a[1], a[2], blocking) == want[label][1], P.select(a[0], a[1], a[2], blocking))

	say("step: online screen, real presses")
	var presses := [
		["vanilla glasses under our hat", c.HATS[0], "", "sunglasses", [c.HATS[0], "sunglasses"]],
		["vanilla glasses off under our hat", c.HATS[0], "sunglasses", "sunglasses", [c.HATS[0], ""]],
		["vanilla glasses swapped under our hat", c.HATS[1], "sunglasses", "reading_glasses", [c.HATS[1], "reading_glasses"]],
		["vanilla glasses refused under the diving helmet", "xc_diving_helmet", "", "sunglasses", ["xc_diving_helmet", ""]],
		["vanilla hat keeps our glasses", "", c.GLASSES[0], "tophat", ["tophat", c.GLASSES[0]]],
		["the Maska takes our glasses off", "", c.GLASSES[0], "maska_helmet", ["maska_helmet", ""]],
		["vanilla hat over our hat keeps glasses", c.HATS[0], "sunglasses", "cap_blade", ["cap_blade", "sunglasses"]],
		["vanilla only, untouched", "tophat", "", "sunglasses", ["tophat", "sunglasses"]],
	]
	for t in presses:
		_wear(sel, t[1], t[2])
		await frames(1)
		# The tile Button's own signal, through ButtonClass.OnPress.
		buttons[t[3]].get_parent().pressed.emit()
		var shown := _shown(sel)
		var want_shown := [[t[4][0]] if t[4][0] != "" else [], [t[4][1]] if t[4][1] != "" else []]
		ok("press: %s" % t[0], _worn(sel) == t[4] and shown == want_shown, [_worn(sel), shown])

	say("step: online screen, layout")
	var ui: Control = sel.ui_root
	var game_rects := {}
	for n in sel.ui_root.find_children("*", "", true, false):
		if n.get_script() != null and n.get_script().resource_path == BRANCH_PATH and not n.is_suit_color_selection:
			game_rects[str(n.assigned_cosmetic)] = n.get_parent().get_parent()
	var order: Array = P.grid_order(sel.customizations, c.HATS, c.GLASSES)
	var ours: int = c.HATS.size() + c.GLASSES.size()
	var all_hats: int = sel.customizations.filter(func(id): return not "glasses" in id).size() + c.HATS.size()
	ok("grid order: hats, then glasses", order.slice(0, all_hats).all(func(id): return not "glasses" in id)
		and order.slice(all_hats).all(func(id): return "glasses" in id) and order.size() == sel.customizations.size() + ours, order)
	var tile := func(id): return game_rects[id] if game_rects.has(id) else ui.get_node_or_null("XcTile_" + id)
	var misplaced := []
	for i in order.size():
		var r: Control = tile.call(order[i])
		if r == null or r.position != P.grid_slot(i, Vector2(589, 28)) or not is_equal_approx(r.scale.x, P.TILE / P.GAME_TILE):
			misplaced.append([order[i], r.position if r else null])
	ok("%d tiles on the %dx%d grid in that order" % [order.size(), P.COLUMNS, ceili(order.size() / float(P.COLUMNS))], misplaced.is_empty(), misplaced)
	var named := func(prefix): return ui.get_children().filter(func(n): return str(n.name).begins_with(prefix)).size()
	ok("one tile and one preview per item of ours", named.call("XcTile_") == ours
		and sel.cosmetic_selection_parent.get_children().filter(func(n): return str(n.name).begins_with("XcTileView_")).size() == ours)
	var red_rect: Control = ui.get_node("suit color selection red")
	var solid_y: float = red_rect.position.y
	var game_ids: Array = sel.suit_colors.filter(func(id): return ui.has_node("suit color selection %s" % id))
	var game_n: int = game_ids.size()
	# Each column at the game's own swatch's x; the sixth one mean pitch past purple.
	var xs: Array = game_ids.map(func(id): return ui.get_node("suit color selection %s" % id).position.x)
	xs.append(xs[-1] + (xs[-1] - xs[0]) / (game_n - 1))
	var off_grid := []
	for i in c.COLORS.size():
		var j: int = game_n + i
		var slot := Vector2(xs[j % P.SWATCH_COLUMNS], solid_y + j / P.SWATCH_COLUMNS * P.ROW_GAP)
		var got: Vector2 = ui.get_node("XcSwatch_" + c.COLORS.keys()[i]).position
		if not got.is_equal_approx(slot):
			off_grid.append([c.COLORS.keys()[i], got, slot])
	ok("our %d swatches after the game's %d, %d to a row 22 apart" % [c.COLORS.size(), game_n, P.SWATCH_COLUMNS],
		named.call("XcSwatch_") == c.COLORS.size() and off_grid.is_empty(), off_grid)
	var fabric_at: int = ui.get_node("fabric overlay").get_index()
	var caret_at: int = sel.ninepatch_color_selection.get_index()
	var row2_at: int = ui.get_node("XcSwatchOverlay").get_index()
	ok("our swatches under the fabric, both fabrics under the caret",
		c.COLORS.keys().all(func(id): return ui.get_node("XcSwatch_" + id).get_index() < fabric_at) and fabric_at < caret_at and row2_at < caret_at,
		[c.COLORS.keys().map(func(id): return ui.get_node("XcSwatch_" + id).get_index()), fabric_at, row2_at, caret_at])
	var off_colour: Array = c.COLORS.keys().filter(func(id): return (ui.get_node("XcSwatch_" + id) as ColorRect).color != c.SWATCHES.get(id, c.COLORS[id]))
	ok("each swatch in its own colour (%d set apart from the cloth's)" % c.SWATCHES.size(), off_colour.is_empty() and c.SWATCHES.keys().all(func(id): return c.COLORS.has(id)), off_colour)
	var row_end: Control = ui.get_node("XcSwatch_xc_teal")
	ok("teal ends the game's row", row_end.position.y == solid_y and is_equal_approx(row_end.position.x, xs[-1]), [row_end.position, xs])
	var panel_box: Control = ui.get_node("NinePatchRect misc under outline")
	var fabric: Control = ui.get_node("fabric overlay")
	var swatch_right: float = row_end.position.x + row_end.size.x * row_end.scale.x
	ok("the panel and the fabric cover the sixth column", panel_box.position.x + panel_box.size.x > swatch_right
		and fabric.position.x + fabric.size.x * fabric.scale.x >= swatch_right
		and ui.get_node("XcSwatchOverlay").size == fabric.size, [panel_box.position.x + panel_box.size.x, fabric.size * fabric.scale.x, swatch_right])
	var ot: Array = ui.get_children().filter(func(n): return str(n.name).begins_with("OvertimeMixedSuit"))
	ok("Overtime's row %s" % ("22 under ours" if _overtime_suits() else "absent"),
		ot.all(func(b): return b.position.y == solid_y + 44) if _overtime_suits() else ot.is_empty(),
		ot.map(func(b): return b.position.y))

	say("step: online screen, our tiles and swatches")
	var btn := func(id): return ui.get_node("XcTile_" + id).find_child("Button", true, false)
	_wear(sel, "", "")
	await frames(1)
	var wrong := []
	for id in c.HATS + c.GLASSES:
		btn.call(id).pressed.emit()
		var want_on := [id, ""] if not "glasses" in id else ["", id]
		if _worn(sel) != want_on or _shown(sel) != [[want_on[0]] if want_on[0] != "" else [], [want_on[1]] if want_on[1] != "" else []]:
			wrong.append(["on", id, _worn(sel)])
		await frames(1)
		btn.call(id).pressed.emit()
		if _worn(sel) != ["", ""]:
			wrong.append(["off", id, _worn(sel)])
		await frames(1)
	ok("each tile of ours puts its item on, and off again", wrong.is_empty(), wrong)
	_wear(sel, "tophat", "")
	await frames(1)
	btn.call(c.GLASSES[1]).pressed.emit()
	ok("our glasses tile under a game hat", _worn(sel) == ["tophat", c.GLASSES[1]], _worn(sel))
	await frames(1)
	btn.call("xc_diving_helmet").pressed.emit()
	ok("our diving helmet tile takes glasses off", _worn(sel) == ["xc_diving_helmet", ""], _worn(sel))

	var caret: Control = sel.ninepatch_color_selection
	var swatch_btn := func(id): return ui.get_node("XcSwatch_" + id).find_child("Button", true, false)
	var off_caret := []
	for id in c.COLORS:
		swatch_btn.call(id).pressed.emit()
		await frames(1)
		var b: Control = swatch_btn.call(id)
		if Globals.active_cosmetic_suit_color != id or str(sel.customization_assigner.assigned_suit_color) != id \
				or caret.position != b.get_parent().position + b.position or not caret.visible:
			off_caret.append([id, Globals.active_cosmetic_suit_color, caret.position])
	ok("each swatch of ours picks its colour, caret on it", off_caret.is_empty(), off_caret)
	sel.select_suit_color("green")
	await frames(1)
	var green: Control = ui.get_node("suit color selection green").find_child("Button", true, false)
	ok("a game colour puts the caret back on the game's row", caret.position == green.get_parent().position + green.position, caret.position)
	# What _ready does with a saved colour of ours.
	Globals.active_cosmetic_suit_color = "xc_brown"
	sel.update_suit_caret_position("xc_brown")
	await frames(1)
	var brown: Control = swatch_btn.call("xc_brown")
	ok("a saved colour of ours: caret on our swatch", caret.position == brown.get_parent().position + brown.position, caret.position)

	say("step: online screen, labels and focus")
	_wear(sel, c.HATS[3], c.GLASSES[2])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var labels := [sel.info_label_color.text, sel.info_label_hat.text, sel.info_label_glasses.text]
	# Ours are numbered in catalog order after Overtime's last code.
	var our_code := func(id): return "%07d" % (P.FIRST_CODE + _all_ids().find(id))
	ok("labels read our codes", labels == ["KL_R[0]: " + our_code.call("xc_brown"), "KL_R[1]: " + our_code.call(c.HATS[3]),
		"KL_R[2]: " + our_code.call(c.GLASSES[2])], labels)
	_wear(sel, "tophat", "sunglasses")
	sel.select_suit_color("purple")
	await get_tree().physics_frame
	await get_tree().physics_frame
	labels = [sel.info_label_color.text, sel.info_label_hat.text, sel.info_label_glasses.text]
	ok("labels keep the game's codes for its items", labels == ["KL_R[0]: 0010057", "KL_R[1]: 0010048", "KL_R[2]: 0010046"], labels)
	var dangling := []
	var focusable: Array = c.COLORS.keys().map(func(id): return swatch_btn.call(id)) + ot
	for color in ["red", "blue", "green", "yellow", "purple"]:
		focusable.append(ui.get_node("suit color selection %s" % color).find_child("Button", true, false))
	for b in focusable:
		for side in ["focus_neighbor_top", "focus_neighbor_bottom", "focus_neighbor_left", "focus_neighbor_right"]:
			var path: NodePath = b.get(side)
			if not path.is_empty() and b.get_node_or_null(path) == null:
				dangling.append([b.name, side, path])
	ok("every focus neighbour resolves", dangling.is_empty(), dangling)
	var red_btn: Control = ui.get_node("suit color selection red").find_child("Button", true, false)
	var purple_btn: Control = ui.get_node("suit color selection purple").find_child("Button", true, false)
	var hop := func(b: Control, side: String): return b.get_node_or_null(b.get(side))
	var walks := [
		["down from red", hop.call(red_btn, "focus_neighbor_bottom"), swatch_btn.call("xc_pink")],
		["up from pink", hop.call(swatch_btn.call("xc_pink"), "focus_neighbor_top"), red_btn],
		["right from purple", hop.call(purple_btn, "focus_neighbor_right"), swatch_btn.call("xc_teal")],
		["left from teal", hop.call(swatch_btn.call("xc_teal"), "focus_neighbor_left"), purple_btn],
		["down from teal", hop.call(swatch_btn.call("xc_teal"), "focus_neighbor_bottom"), swatch_btn.call("xc_charcoal")],
		["up from charcoal", hop.call(swatch_btn.call("xc_charcoal"), "focus_neighbor_top"), swatch_btn.call("xc_teal")],
		["right from brown", hop.call(swatch_btn.call("xc_brown"), "focus_neighbor_right"), swatch_btn.call("xc_lime")],
		["left from lime", hop.call(swatch_btn.call("xc_lime"), "focus_neighbor_left"), swatch_btn.call("xc_brown")],
		["down from purple", hop.call(purple_btn, "focus_neighbor_bottom"), swatch_btn.call("xc_white")],
	]
	ok("pad focus walks the two colour rows", walks.all(func(w): return w[1] == w[2]),
		walks.filter(func(w): return w[1] != w[2]).map(func(w): return [w[0], w[1].name if w[1] else null]))

	say("step: online screen, tile previews")
	var views := {}
	for inst in sel.cosmetic_selection_parent.get_children():
		if not "cosmetic_holder_parent" in inst:
			continue
		for item in inst.cosmetic_holder_parent.get_children():
			if item is Node3D and item.visible:
				views[str(item.name)] = [inst, item]
	ok("a preview for each of the %d items" % order.size(), order.all(func(id): return views.has(id)), views.keys())
	# The tile turns its holder: a hat shares the top hat's place on the turntable,
	# and its surface centre, averaged over a turn, sits level with the view's centre. The
	# turntable also wobbles, which the average doesn't remove: 2 px of 128.
	var off_centre := []
	for id in c.HATS:
		var holder: Node3D = views[id][0].cosmetic_holder_parent
		var cam: Camera3D = P._camera_of(views[id][0])
		var spot: Vector3 = P.centre(holder.get_node("tophat")) - P.centre(views[id][1])
		var level: float = P.level_offset(cam, views[id][1])
		if absf(spot.x) > 0.001 or absf(spot.z) > 0.001 or absf(level) > 2.0:
			off_centre.append([id, spot, level])
	ok("our hats on the top hat's turntable spot, level in view", off_centre.is_empty(), off_centre)
	# All glasses at one size, the game's own (owner): ours as large as its
	# sunglasses, and its two as a fresh tile scene draws them.
	var fresh = load(TILE_SCENE).instantiate()
	var sizes := []
	for id in c.GLASSES:
		var anchor_scale: Vector3 = views[id][0].cosmetic_holder_parent.get_node("sunglasses").basis.get_scale()
		if not views[id][1].basis.get_scale().is_equal_approx(anchor_scale):
			sizes.append([id, views[id][1].basis.get_scale()])
	for id in sel.customizations.filter(func(n): return "glasses" in n):
		if not views[id][1].basis.get_scale().is_equal_approx(fresh.cosmetic_holder_parent.get_node(id).basis.get_scale()):
			sizes.append([id, views[id][1].basis.get_scale()])
	fresh.free()
	ok("every glasses tile at the game's own size", sizes.is_empty(), sizes)
	var lit := []
	for id in c.HATS + c.GLASSES:
		var mat := (P._mesh_of(views[id][1]).get_surface_override_material(0)) as StandardMaterial3D
		var lift: float = P.TILE_LIFT.get(id, 0.0)
		var got: float = mat.emission_energy_multiplier if mat.emission_enabled else 0.0
		if not is_equal_approx(got, lift):
			lit.append([id, got])
	ok("only %s lifted, and only in their tiles" % str(P.TILE_LIFT.keys()), lit.is_empty()
		and not (sel.customization_assigner.bone_attachment_glasses.get_node("xc_eyepatch_glasses").get_child(0)
			.get_surface_override_material(0) as StandardMaterial3D).emission_enabled, lit)

	say("step: online screen, re-enter")
	var root := get_tree().current_scene
	var before_pos: Array = order.map(func(id): return tile.call(id).position)
	var parent := root.get_parent()
	parent.remove_child(root)
	parent.add_child(root)
	await frames(2)
	ok("re-enter: no second tile, nothing moved twice", named.call("XcTile_") == ours and named.call("XcSwatch_") == c.COLORS.size()
		and order.map(func(id): return tile.call(id).position) == before_pos
		and sel.get_children().filter(func(n): return n.get_script() == P).size() == 1)

	for k in g:
		Globals.set(k, g[k])
