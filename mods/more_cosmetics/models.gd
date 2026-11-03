extends RefCounted

# Puts our hats and glasses beside the vanilla ones wherever the game keeps
# them by name: the assigner on each character, the hat gib, and the online
# screen's preview tile. Each item is modelled in the local space of an anchor
# item's mesh (tophat for hats, sunglasses for glasses) and copies the anchor's
# transforms and material, so it sits and shades the way the anchor would.

const HAT_ANCHOR := "tophat"
const GLASSES_ANCHOR := "sunglasses"

var catalog
var items_dir: String
var note: Callable
var _meshes := {}
var _materials := {}

# Runs while the assigner enters the tree, before its _ready assigns the saved
# cosmetics by node name.
func inject_assigner(assigner: Node) -> void:
	_inject_all(assigner.bone_attachment_hat, HAT_ANCHOR, catalog.HATS, assigner)
	_inject_all(assigner.bone_attachment_glasses, GLASSES_ANCHOR, catalog.GLASSES, assigner)

# PropManager adds a gib and, in the same call, shows hat_meshes[name]; adding
# later would leave the first flight of every pooled gib empty.
func inject_gib(gib: Node) -> void:
	var anchor = gib.hat_meshes.get(StringName(HAT_ANCHOR))
	if not anchor is Node3D:
		_note("hat gib has no %s to copy, our hats won't fly off" % HAT_ANCHOR)
		return
	# Our own copy, so instances can never share the dictionary we write to.
	var meshes: Dictionary = gib.hat_meshes.duplicate()
	for id in catalog.HATS:
		var node := inject(anchor.get_parent(), anchor, id)
		if node != null:
			meshes[StringName(id)] = node
	gib.hat_meshes = meshes

func inject_tile(tile: Node) -> void:
	var holder: Node = tile.cosmetic_holder_parent
	_inject_all(holder, HAT_ANCHOR, catalog.HATS, tile)
	_inject_all(holder, GLASSES_ANCHOR, catalog.GLASSES, tile)

func _inject_all(parent: Node, anchor_name: String, ids: Array, owner_node: Node) -> void:
	if parent == null or not owner_node.is_ancestor_of(parent):
		_note("%s: no item parent to add to" % owner_node.name)
		return
	var anchor := parent.get_node_or_null(anchor_name) as Node3D
	if anchor == null:
		_note("%s: no %s to copy" % [owner_node.name, anchor_name])
		return
	for id in ids:
		inject(parent, anchor, id)

# Hidden, like every vanilla item until the game shows one by name. An existing
# node is kept: hooks fire again on re-entry, and Overtime's online lobby
# duplicate()s player slots along with what we added.
func inject(parent: Node, anchor: Node3D, id: String) -> Node3D:
	var existing := parent.get_node_or_null(NodePath(id)) as Node3D
	if existing != null:
		return existing
	var anchor_mesh: MeshInstance3D = null
	for child in anchor.get_children():
		if child is MeshInstance3D:
			anchor_mesh = child
			break
	var item_mesh := mesh(id)
	if anchor_mesh == null or item_mesh == null:
		return null
	var holder := Node3D.new()
	holder.name = id
	holder.transform = anchor.transform
	holder.visible = false
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	mi.mesh = item_mesh
	mi.transform = anchor_mesh.transform
	mi.layers = anchor_mesh.layers
	var mat := material(id, anchor_mesh)
	for s in item_mesh.get_surface_count():
		mi.set_surface_override_material(s, mat)
	holder.add_child(mi)
	parent.add_child(holder)
	return holder

func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		_meshes[id] = _load_mesh(items_dir.path_join(id + ".glb"))
	return _meshes[id]

# One per item, shared by every copy of it.
func material(id: String, anchor_mesh: MeshInstance3D) -> Material:
	if not _materials.has(id):
		var base := anchor_mesh.get_active_material(0)
		var mat: BaseMaterial3D = base.duplicate() if base is BaseMaterial3D else StandardMaterial3D.new()
		mat.albedo_texture = texture(id)
		_materials[id] = mat
	return _materials[id]

func texture(id: String) -> Texture2D:
	var path := items_dir.path_join(id + ".png")
	if not FileAccess.file_exists(path):
		_note("missing " + path)
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_note("unreadable " + path)
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _load_mesh(path: String) -> Mesh:
	if not FileAccess.file_exists(path):
		_note("missing " + path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		_note("unreadable " + path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		_note("no scene in " + path)
		return null
	var found: Mesh = null
	for node in [root] + root.find_children("*", "", true, false):
		if node is MeshInstance3D and node.mesh != null:
			found = node.mesh
		elif node is ImporterMeshInstance3D and node.mesh != null:
			found = node.mesh.get_mesh()
		if found != null:
			break
	root.free()
	if found == null:
		_note("no mesh in " + path)
	return found

func _note(msg: String) -> void:
	if note.is_valid():
		note.call("more_cosmetics: " + msg)
