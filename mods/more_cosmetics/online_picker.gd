extends Node

# Child of the online screen's CustomizationSelection. The game's
# select_cosmetic asks is_compatible_with_glasses(), which returns null for any
# name it doesn't know, so under one of our hats it refuses every pair of
# glasses. After the game handles a tile press, this redoes it with select().
# It also lays the screen out as one 7-column grid with our colour row (as
# picked from renders) and names our items on the info labels.

const BRANCH_PATH := "res://scripts/components/character customization/customization_selection_branch.gd"
const GAME_TILE := 89.0
const TILE := 46.0
const PITCH := 52.0
const COLUMNS := 7
# Our swatch row sits this far under the game's solid row, above Overtime's.
const ROW_GAP := 22.0
# Codes after Overtime's last (0010060), in catalog order: hats, glasses, colours.
const FIRST_CODE := 10061
# Tile-only emission for ours that render too dark to read in their tiles;
# xc_screen measures each tile's lit pixels. The amounts were picked from renders;
# emission scales the item's own texture.
const TILE_LIFT := {"xc_eyepatch_glasses": 0.08, "xc_head_mirror": 0.10, "xc_kippah": 0.06, "xc_cowboy_hat": 0.06}
const LAID_OUT := &"xc_online_layout"

# Set by main.gd on every hook call.
var hats: Array = []
var glasses: Array = []
var no_glasses_hats: Array = []
var colors: Dictionary = {}
var note: Callable

var _hat := ""
var _glasses := ""
# Our swatch Buttons by colour id, and the y the game's caret sits at.
var _swatches := {}
var _caret_y := 0.0

func _ready() -> void:
	# The labels are rewritten in the screen's _physics_process; ours go after.
	process_physics_priority = 1000
	# Deferred: every branch in the scene has connected its button by then, so
	# our handler runs after the game's, and Overtime's row exists.
	_attach.call_deferred()

func _attach() -> void:
	var sel := get_parent()
	var branches := {}
	var solids := {}
	for n in sel.ui_root.find_children("*", "", true, false):
		if n.get_script() == null or n.get_script().resource_path != BRANCH_PATH:
			continue
		if n.customization_selection != sel or n.button == null:
			continue
		if n.is_suit_color_selection:
			solids[str(n.assigned_cosmetic)] = n
			continue
		branches[str(n.assigned_cosmetic)] = n
		var press := _after_press.bind(str(n.assigned_cosmetic))
		if not n.button.is_pressed.is_connected(press):
			n.button.is_pressed.connect(press)
	_remember()
	if not sel.ui_root.has_meta(LAID_OUT):
		sel.ui_root.set_meta(LAID_OUT, true)
		_lay_out(sel, branches, solids)

# A press arrives during input handling, before any _process, so this is the
# state from before it.
func _process(_delta: float) -> void:
	_remember()
	_place_caret()

func _physics_process(_delta: float) -> void:
	var sel := get_parent()
	for row in [[sel.info_label_color, "KL_R[0]: ", Globals.active_cosmetic_suit_color],
			[sel.info_label_hat, "KL_R[1]: ", Globals.active_cosmetic_hat],
			[sel.info_label_glasses, "KL_R[2]: ", Globals.active_cosmetic_glasses]]:
		var c := code(row[2])
		if c != "" and row[0] != null:
			row[0].text = row[1] + c

func _remember() -> void:
	_hat = Globals.active_cosmetic_hat
	_glasses = Globals.active_cosmetic_glasses

func _after_press(pressed: String) -> void:
	var sel := get_parent()
	var known: Array = sel.customizations + hats + glasses + [""]
	if not (known.has(_hat) and known.has(_glasses) and known.has(pressed)):
		return
	if not (hats.has(_hat) or glasses.has(_glasses)):
		return
	press(pressed)

# Applies select() from the state before the press to the assigner and Globals.
func press(pressed: String) -> void:
	var sel := get_parent()
	var want := select(_hat, _glasses, pressed, blocking_hats(sel))
	var a = sel.customization_assigner
	if Globals.active_cosmetic_hat != want[0]:
		if want[0] == "":
			a.remove_hat()
		else:
			a.assign_hat(want[0])
		Globals.active_cosmetic_hat = want[0]
	if Globals.active_cosmetic_glasses != want[1]:
		if want[1] == "":
			a.remove_glasses()
		else:
			a.assign_glasses(want[1])
		Globals.active_cosmetic_glasses = want[1]
	_remember()

# The hats the live screen says block glasses, plus ours.
func blocking_hats(sel: Node) -> Array:
	var out: Array = no_glasses_hats.duplicate()
	for id in sel.customizations:
		if not "glasses" in id and sel.is_compatible_with_glasses(id) is bool and not sel.is_compatible_with_glasses(id):
			out.append(id)
	return out

# The game's select_cosmetic, with blocking read from a list: pressing what is
# worn takes it off, glasses are refused under a blocking hat, and a blocking
# hat takes glasses off. Returns [hat, glasses].
static func select(hat: String, worn_glasses: String, pressed: String, blocking: Array) -> Array:
	if "glasses" in pressed:
		if pressed == worn_glasses:
			return [hat, ""]
		if blocking.has(hat):
			return [hat, worn_glasses]
		return [hat, pressed]
	if pressed == hat:
		return ["", worn_glasses]
	return [pressed, "" if blocking.has(pressed) else worn_glasses]

# The label code for one of our ids, or "" for any other name.
func code(id: String) -> String:
	var i := (hats + glasses + colors.keys()).find(id)
	return "" if i < 0 else "%07d" % (FIRST_CODE + i)

# All hats, then all glasses: the game's in its own order, then ours.
static func grid_order(game: Array, our_hats: Array, our_glasses: Array) -> Array:
	var game_hats := game.filter(func(id): return not "glasses" in id)
	var game_glasses := game.filter(func(id): return "glasses" in id)
	return game_hats + our_hats + game_glasses + our_glasses

static func grid_slot(index: int, origin: Vector2) -> Vector2:
	return origin + Vector2(index % COLUMNS, index / COLUMNS) * PITCH

func _lay_out(sel: Node, branches: Dictionary, solids: Dictionary) -> void:
	var ui: Control = sel.ui_root
	var game_rects := {}
	for id in sel.customizations:
		if branches.has(id):
			game_rects[id] = branches[id].get_parent().get_parent()
	var panel := ui.get_node_or_null("NinePatchRect misc under outline") as Control
	var overlay := ui.get_node_or_null("fabric overlay") as Control
	if game_rects.size() != sel.customizations.size() or not solids.has("red") or panel == null:
		if note.is_valid():
			note.call("more_cosmetics: the online screen isn't laid out as expected; our items aren't on it")
		return
	var first: Control = game_rects[sel.customizations[0]]
	var origin := first.position
	var old_bottom := 0.0
	for id in game_rects:
		old_bottom = maxf(old_bottom, game_rects[id].position.y + GAME_TILE)

	var ours := {}
	var made := 0
	for id in hats + glasses:
		var tile := _our_tile(sel, first, branches[sel.customizations[0]], id, made)
		if tile != null:
			ours[id] = tile
			made += 1
	var order := grid_order(sel.customizations, hats.filter(func(id): return ours.has(id)),
		glasses.filter(func(id): return ours.has(id)))
	for i in order.size():
		var rect: Control = game_rects[order[i]] if game_rects.has(order[i]) else ours[order[i]]
		rect.position = grid_slot(i, origin)
		rect.scale = Vector2.ONE * (TILE / GAME_TILE)
	var bottom := grid_slot(order.size() - 1, origin).y + TILE
	var dy := bottom - old_bottom

	# The colour panel moves up into the freed space, and our row goes under the
	# game's solid swatches; Overtime's two-tone row moves below ours.
	var overtime: Array = ui.get_children().filter(func(n): return str(n.name).begins_with("OvertimeMixedSuit"))
	for n in [panel, overlay, sel.ninepatch_color_selection] + solids.values().map(func(b): return b.get_parent()):
		if n != null:
			n.position.y += dy
	for n in overtime:
		n.position.y += dy + ROW_GAP
	panel.size.y += ROW_GAP
	_caret_y = sel.ninepatch_color_selection.position.y
	if overlay != null:
		var o: Control = overlay.duplicate()
		o.name = "XcSwatchOverlay"
		ui.add_child(o)
		o.position.y += ROW_GAP

	# The screen's own colour order; Overtime's two-tone suits have no solid swatch.
	var game_order: Array = sel.suit_colors.filter(func(id): return solids.has(id))
	var ids: Array = colors.keys()
	for i in ids.size():
		var src = solids.get(game_order[i]) if i < game_order.size() else null
		if src == null:
			continue
		var b := _our_swatch(sel, src, ids[i])
		_swatches[ids[i]] = b
		var above: Control = src.button.get_parent()
		above.focus_neighbor_bottom = above.get_path_to(b)
		b.focus_neighbor_top = b.get_path_to(above)
		if overtime.size() == 3:
			b.focus_neighbor_bottom = b.get_path_to(overtime[mini(i / 2, 2)])
	for i in overtime.size():
		if _swatches.size() == 5:
			overtime[i].focus_neighbor_top = overtime[i].get_path_to(_swatches[ids[i * 2]])
	_place_caret()

# A tile built like the game's: a copy of its first tile's frame and button,
# showing our item through a preview placed the way the game places its own.
func _our_tile(sel: Node, src: Control, src_branch: Node, id: String, index: int) -> Control:
	var view_name := "XcTileView_" + id
	var inst = sel.cosmetic_selection_parent.get_node_or_null(view_name)
	if inst == null:
		inst = sel.cosmetic_selection_instance.instantiate()
		inst.name = view_name
		sel.cosmetic_selection_parent.add_child(inst)
		var off: int = 3 + 3 * (sel.customizations.size() + index + 1)
		var o: Vector3 = inst.camera_parent.transform.origin
		inst.camera_parent.transform.origin = Vector3(o.x - off, o.y, o.z - 10)
		inst.setup_cosmetic(id)
		var item := inst.cosmetic_holder_parent.get_node_or_null(NodePath(id)) as Node3D
		if item == null:
			inst.queue_free()
			return null
		# Our hats borrow the top hat's spot, so a larger one sits off the tile's
		# centre. Glasses stay where and as large as the game draws its own (owner).
		var cam := _camera_of(inst)
		if not "glasses" in id and cam != null:
			centre_on_turntable(cam, inst.cosmetic_holder_parent.get_node_or_null("tophat"), item)
		if TILE_LIFT.has(id):
			_lift(item, TILE_LIFT[id])
	var tile_name := "XcTile_" + id
	var tile := sel.ui_root.get_node_or_null(tile_name) as Control
	if tile != null:
		return tile
	var feed_path := src.get_path_to(sel.selection_rect_array[0])
	var button_path := src.get_path_to(src_branch.button)
	tile = src.duplicate()
	tile.name = tile_name
	var branch := tile.get_node(src.get_path_to(src_branch))
	branch.get_parent().remove_child(branch)
	branch.free()
	sel.ui_root.add_child(tile)
	(tile.get_node(feed_path) as TextureRect).texture = inst.assigned_viewport.get_texture()
	var bc = tile.get_node(button_path)
	bc.is_pressed.connect(_press_ours.bind(id))
	bc.is_hovered.connect(_hover.bind(id))
	bc.is_focused.connect(_hover.bind(id))
	bc.is_exited.connect(_hover.bind("--"))
	return tile

static func _mesh_of(item: Node3D) -> MeshInstance3D:
	for child in item.get_children():
		if child is MeshInstance3D and child.mesh != null:
			return child
	return null

static func _camera_of(inst: Node) -> Camera3D:
	for n in inst.camera_parent.find_children("*", "Camera3D", true, false):
		return n
	return null

# The area-weighted centre of an item's surface, in its parent's space: where
# its mass reads to the eye, so thin straps and chains barely move it.
static func centre(item: Node3D) -> Vector3:
	var mi := _mesh_of(item)
	var faces := mi.mesh.get_faces()
	var sum := Vector3.ZERO
	var area := 0.0
	for t in range(0, faces.size(), 3):
		var a := (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).length()
		sum += (faces[t] + faces[t + 1] + faces[t + 2]) / 3.0 * a
		area += a
	return item.transform * (mi.transform * (sum / maxf(area, 1e-9)))

# How far below the view's centre an item's centre sits, averaged over a full
# turn of its holder (8 angles), since the tile spins the holder.
static func level_offset(cam: Camera3D, item: Node3D) -> float:
	var holder := item.get_parent() as Node3D
	var kept := holder.transform
	var mid := centre(item)
	var sum := 0.0
	for i in 8:
		holder.transform = kept * Transform3D(Basis(Vector3.UP, TAU * i / 8.0), Vector3.ZERO)
		sum += cam.unproject_position(holder.global_transform * mid).y
	holder.transform = kept
	return sum / 8.0 - cam.get_viewport().get_visible_rect().size.y / 2.0

# The tile turns its holder, so a hat is put on the turntable where the game's
# top hat sits, then moved along the holder's up axis until it sits level with
# the view's centre over a turn; perspective makes each step inexact, so it repeats.
static func centre_on_turntable(cam: Camera3D, anchor: Node3D, item: Node3D) -> void:
	if anchor == null or _mesh_of(item) == null or _mesh_of(anchor) == null:
		return
	item.position += centre(anchor) - centre(item)
	var size := cam.get_viewport().get_visible_rect().size
	var axes := cam.global_basis.orthonormalized()
	var up: Vector3 = item.get_parent().global_basis.y.normalized()
	var facing := axes.y.dot(up)
	if absf(facing) < 0.2:
		return
	for step in 6:
		var off := -level_offset(cam, item)
		if absf(off) < 0.25:
			return
		var depth := (-axes.z).dot(item.get_parent().global_transform * centre(item) - cam.global_position)
		var per_px := 2.0 * depth * tan(deg_to_rad(cam.fov) / 2.0) / size.y
		if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			per_px = cam.size / size.y
		item.global_position -= up * (off * per_px / facing)

# A tile's own copy of the item's material, lit from within by its texture.
static func _lift(item: Node3D, energy: float) -> void:
	var mi := _mesh_of(item)
	var mat := mi.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat = mat.duplicate()
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_texture = mat.albedo_texture
	mat.emission_energy_multiplier = energy
	for s in mi.mesh.get_surface_count():
		mi.set_surface_override_material(s, mat)

func _our_swatch(sel: Node, src_branch: Node, id: String) -> Control:
	var src: ColorRect = src_branch.get_parent()
	var button_path := src.get_path_to(src_branch.button)
	var s := sel.ui_root.get_node_or_null("XcSwatch_" + id) as ColorRect
	if s == null:
		s = src.duplicate()
		s.name = "XcSwatch_" + id
		var branch := s.get_node(src.get_path_to(src_branch))
		branch.get_parent().remove_child(branch)
		branch.free()
		s.color = colors[id]
		s.position.y += ROW_GAP
		sel.ui_root.add_child(s)
		var bc = s.get_node(button_path)
		bc.is_pressed.connect(func(): get_parent().select_suit_color(id))
		bc.is_hovered.connect(_hover.bind(id))
		bc.is_focused.connect(_hover.bind(id))
		bc.is_exited.connect(_hover.bind("--"))
	return s.get_node(button_path).get_parent()

func _press_ours(id: String) -> void:
	_remember()
	press(id)

func _hover(id: String) -> void:
	var sel := get_parent()
	var c := code(id)
	if c == "":
		sel.customization_hovered(id)
	else:
		sel.info_label_selection.text = "KL_RUID: " + c

# The game moves its caret along the solid row by name and sends any other
# name to x 0; for ours it goes on our swatch, and back to its own row after.
func _place_caret() -> void:
	if _swatches.is_empty():
		return
	var caret: Control = get_parent().ninepatch_color_selection
	var b: Control = _swatches.get(Globals.active_cosmetic_suit_color)
	if b != null:
		caret.visible = true
		caret.position = b.get_parent().position + b.position
	else:
		caret.position.y = _caret_y
