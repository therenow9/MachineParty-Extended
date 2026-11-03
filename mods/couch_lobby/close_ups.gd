extends Node

# Child of the local lobby. Each seat's Polaroid films a portrait double (the character-select
# character, upright) in a copy of the room far outside the room camera's view, through that
# screen's own camera pose, so the seated model keeps its slouch. The double is dressed through
# the game's assigner calls, which More Cosmetics also hooks, so its items and recolour show.

const CUSTOMIZATION := "res://scenes/character_customization.tscn"
const ROOM_COPY := Vector3(400, 0, 0)
const ROW_Z := 2.0
# Close enough that the outer seats' doubles and cameras stay well inside the room copy's walls.
const ROW_GAP := 1.2
# Render layers 11-18, one per seat: a seat's camera sees the room copy (layer 1) and its own double.
const SEAT_LAYER_BIT := 10
# The character-select screen's camera, under a SubViewport, so its 3D chain starts there.
const MENU_CAMERA := "viewport_character preview/character preview camera parent/camera_character preview feed"
# The strip on the game's 960x540 canvas: at the very bottom, over the seated players' feet.
const STRIP_TOP := 430.0
const CARD_H := 104.0
const CARD_MAX_W := 112.0
const GAP := 8.0
const MARGIN := 24.0
const TILTS := [-2.5, 1.8, -1.2, 2.6, -2.0, 1.2, -2.8, 2.2]
# LEAVE; START, PLAYLIST, SKIP INTRO. Raised above the strip only while one overlaps it.
const BUTTON_ROWS := ["Control/Lobby/Control/HFlowContainer", "Control/Lobby/Control/HFlowContainer2", "Control/Lobby/Control/HFlowContainer3"]
# Brown stains: a noise threshold, so the card reads handled rather than printed.
const GRIME := """shader_type canvas_item;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float n = noise(UV * 6.0) * 0.6 + noise(UV * 19.0) * 0.4;
	COLOR = vec4(0.32, 0.24, 0.14, smoothstep(0.55, 0.85, n) * 0.35);
}
"""

var note: Callable
var lobby: Node
var _packed: PackedScene
var _world: World3D
var _room: Node3D
var _strip: Control
var _rows: Array = []
var _lift := 0.0
var _seats := {}
var _font: Font
var _grime: Shader
var _pose: Transform3D
var _fov := 0.0

func _ready() -> void:
	lobby = get_parent()
	var room_vp := lobby.get_node_or_null("LobbyPreviewViewport") as SubViewport
	var screen := lobby.get_node_or_null("Control/TextureRect") as Control
	_room = lobby.players_node.get_parent() if lobby.players_node else null
	_packed = load(CUSTOMIZATION)
	if room_vp == null or screen == null or _room == null or _room.get_node_or_null("lobby environment1") == null or _packed == null:
		note.call("couch_lobby: the local lobby isn't laid out as expected; close-ups off")
		set_process(false)
		return
	if not _read_menu_camera():
		note.call("couch_lobby: the character-select screen has no camera where expected; close-ups off")
		set_process(false)
		return
	_world = room_vp.find_world_3d()
	_build_room_copy()
	# Inserted right after the room's picture, so the room's own posterize and vignette pass covers it too.
	_strip = Control.new()
	_strip.name = "CouchLobbyStrip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_sibling(_strip)
	for path in BUTTON_ROWS:
		var row := lobby.get_node_or_null(path) as Control
		if row:
			_rows.append(row)
	_grime = Shader.new()
	_grime.code = GRIME

# The menu camera's pose relative to its character, as the scene file holds it: the first key
# of its sway, the view the screen opens on. Read from an instance that never enters the tree.
func _read_menu_camera() -> bool:
	var scene: Node = _packed.instantiate()
	var cam := scene.get_node_or_null(MENU_CAMERA) as Camera3D
	var character := scene.get_node_or_null("main character2") as Node3D
	if cam and character:
		_pose = chain(character).affine_inverse() * chain(cam)
		_fov = cam.fov
	scene.free()
	return _fov > 0.0

static func chain(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

func _build_room_copy() -> void:
	var copy: Node3D = _room.get_node("lobby environment1").duplicate()
	copy.name = "CouchLobbyRoomCopy"
	_room.add_child(copy)
	copy.position = ROOM_COPY
	var lamp_src := _room.get_node_or_null("OmniLight3D") as OmniLight3D
	if lamp_src:
		var lamp: OmniLight3D = lamp_src.duplicate()
		lamp.name = "CouchLobbyLampCopy"
		_room.add_child(lamp)
		lamp.position = ROOM_COPY + lamp_src.position

func _process(_delta: float) -> void:
	var controls: Array = lobby.local_lobby_player_controls
	var shown: Array = []
	for i in controls.size():
		var c = controls[i]
		var seated: bool = is_instance_valid(c) and c.assigned_player_id >= 0
		if seated and not _seats.has(i):
			_seats[i] = _make_seat(i, controls.size(), c)
		if not _seats.has(i):
			continue
		var s: Dictionary = _seats[i]
		if seated:
			_sync(s, c)
			# The double's idle frame is applied on its first frame in the tree, so the head is read after it.
			if not s.posed and Engine.get_process_frames() > s.born + 1:
				_aim(s)
		# Until it is posed, the camera sits at the world origin and would film the real lobby.
		# On the name screen the seat still holds the last occupant's name; the room hides its label there too.
		var on: bool = seated and s.posed and not c.name_entry_selector.active
		s.card.visible = on
		s.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if on:
			shown.append(i)
	_layout(shown)
	_raise_buttons(shown)

func _make_seat(i: int, seat_count: int, controls) -> Dictionary:
	var scene: Node = _packed.instantiate()
	var character: Node3D = scene.get_node("main character2")
	_unown(character)
	character.get_parent().remove_child(character)
	# Taken from a scene that never enters the tree, so the menu's own scripts never run.
	scene.free()
	var mesh: MeshInstance3D = character.get_node("Armature/Skeleton3D/character mesh")
	# The double never blinks. Other blinks swap the eye texture on a material every instance
	# shares, so the double keeps its own copy, set open in case it was copied mid-blink.
	var blink = character.get_node_or_null("character blink")
	var eyes: Material = mesh.get_active_material(2).duplicate()
	if blink:
		eyes.set("albedo_texture", blink.texture_eye_open)
		blink.free()
	mesh.set_surface_override_material(2, eyes)
	var holder := Node3D.new()
	holder.name = "CouchLobbyDouble%d" % (i + 1)
	_room.add_child(holder)
	holder.position = ROOM_COPY + Vector3(row_x(i, seat_count), 0.0, ROW_Z)
	holder.rotation.y = PI
	holder.add_child(character)
	var vp := SubViewport.new()
	vp.name = "CouchLobbyPhoto%d" % (i + 1)
	vp.world_3d = _world
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = _fov
	cam.near = 0.05
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.cull_mask = 1 | (1 << (SEAT_LAYER_BIT + i))
	vp.add_child(cam)
	cam.current = true
	var s := {"i": i, "double": character, "assigner": character.get_node("Armature/Skeleton3D/customization assigner"),
		"vp": vp, "cam": cam, "look": [], "born": Engine.get_process_frames(), "posed": false}
	_build_card(s, controls)
	return s

# One pose for good: the zoom never follows the hat.
func _aim(s: Dictionary) -> void:
	var character: Node3D = s.double
	var menu := (character.global_transform * _pose).orthonormalized()
	s.cam.global_transform = front_pose(menu, s.assigner.bone_attachment_glasses.global_position, -character.global_basis.z)
	s.posed = true

# Head-on: the menu camera swung round the vertical line through the head onto the way the
# body faces, keeping its distance, height above the head and downward tilt, and not its lean.
static func front_pose(menu: Transform3D, head: Vector3, face: Vector3) -> Transform3D:
	face.y = 0.0
	face = face.normalized()
	var off := menu.origin - head
	return Transform3D(Basis.from_euler(Vector3(menu.basis.get_euler().x, atan2(face.x, face.z), 0.0)),
		head + face * Vector2(off.x, off.z).length() + Vector3.UP * off.y)

func _unown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_unown(c)

# The seat's look, each value set on the double through the game's own assigner calls.
func _sync(s: Dictionary, controls) -> void:
	var want := look_of(controls.customization_assigner)
	if want != s.look:
		var d = s.assigner
		var have := look_of(d)
		if want[0] != have[0]:
			if want[0] == "none": d.remove_hat()
			else: d.assign_hat(want[0])
		if want[1] != have[1]:
			if want[1] == "none": d.remove_glasses()
			else: d.assign_glasses(want[1])
		if want[2] != have[2]:
			d.assign_suit_color(want[2])
		s.look = want
		_set_layers(s)
	if s.label.text != controls.player_name:
		s.label.text = controls.player_name

static func look_of(assigner) -> Array:
	var glasses := "none"
	for c in assigner.bone_attachment_glasses.get_children():
		if c is Node3D and c.visible:
			glasses = str(c.name)
			break
	return [str(assigner.get_assigned_hat()), glasses, str(assigner.assigned_suit_color)]

func _set_layers(s: Dictionary) -> void:
	for g in (s.double as Node).find_children("*", "GeometryInstance3D", true, false):
		g.layers = 1 << (SEAT_LAYER_BIT + s.i)

static func row_x(i: int, seat_count: int) -> float:
	return (i - (seat_count - 1) * 0.5) * ROW_GAP

func _build_card(s: Dictionary, controls) -> void:
	var size := Vector2(CARD_MAX_W, CARD_H)
	var card := Control.new()
	card.name = "CouchLobbyCard%d" % (s.i + 1)
	card.size = size
	card.pivot_offset = size * 0.5
	card.rotation = deg_to_rad(TILTS[s.i % TILTS.size()])
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(card)
	var paper := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.84, 0.77)
	sb.border_color = Color(0.7, 0.67, 0.6)
	sb.set_border_width_all(1)
	paper.add_theme_stylebox_override("panel", sb)
	paper.size = size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	var photo := TextureRect.new()
	photo.texture = (s.vp as SubViewport).get_texture()
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(photo)
	var grime := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _grime
	m.set_shader_parameter("seed", float(s.i) * 3.7)
	grime.material = m
	grime.size = size
	grime.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(grime)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	var font: Font = controls.name_label.get_theme_font("font")
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.18, 0.16, 0.14))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	var tape := ColorRect.new()
	tape.color = Color(0.83, 0.78, 0.58, 0.8)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tape.rotation = deg_to_rad(-4.0 if s.i % 2 == 0 else 3.0)
	card.add_child(tape)
	s.card = card
	s.paper = paper
	s.photo = photo
	s.grime = grime
	s.label = label
	s.tape = tape

# Cards for the seated players, in seat order, centred on the canvas.
static func card_rects(count: int, canvas_w: float) -> Array:
	var w := minf(CARD_MAX_W, (canvas_w - MARGIN * 2.0 - GAP * (count - 1)) / maxf(count, 1))
	var x0 := (canvas_w - (w * count + GAP * (count - 1))) * 0.5
	var out := []
	for k in count:
		out.append(Rect2(x0 + k * (w + GAP), STRIP_TOP, w, CARD_H))
	return out

func _layout(shown: Array) -> void:
	var rects := card_rects(shown.size(), lobby.get_viewport().get_visible_rect().size.x)
	for k in shown.size():
		var s: Dictionary = _seats[shown[k]]
		var r: Rect2 = rects[k]
		if s.card.position == r.position and s.card.size == r.size:
			continue
		var size := r.size
		s.card.position = r.position
		s.card.size = size
		s.card.pivot_offset = size * 0.5
		s.paper.size = size
		s.grime.size = size
		var pr := Rect2(6, 6, size.x - 12, size.y - 30)
		s.photo.position = pr.position
		s.photo.size = pr.size
		# The camera renders at the window's own shape; KEEP_HEIGHT holds the menu's height of view.
		s.vp.size = Vector2i(roundi(pr.size.x * 2.0), roundi(pr.size.y * 2.0))
		s.label.position = Vector2(0, size.y - 23)
		s.label.size = Vector2(size.x, 18)
		s.tape.size = Vector2(size.x * 0.42, 11)
		s.tape.position = Vector2(size.x * 0.29, -5)
		s.tape.pivot_offset = s.tape.size * 0.5

# How far to lift the button rows: to end just above the strip, while a shown button,
# where it sits unlifted, overlaps the strip (with slack for the cards' tilt).
static func lift_for(buttons: Array, cards: Array) -> float:
	if cards.is_empty():
		return 0.0
	var band: Rect2 = cards[0]
	for r in cards:
		band = band.merge(r)
	band = band.grow(6.0)
	var bottom := 0.0
	var covered := false
	for b in buttons:
		bottom = maxf(bottom, (b as Rect2).end.y)
		covered = covered or (b as Rect2).intersects(band)
	return maxf(bottom - (band.position.y + 2.0), 0.0) if covered else 0.0

func _raise_buttons(shown: Array) -> void:
	var buttons := []
	for row in _rows:
		for b in row.get_children():
			if b is Control and b.is_visible_in_tree():
				var r: Rect2 = b.get_global_rect()
				r.position.y += _lift
				buttons.append(r)
	var lift := lift_for(buttons, card_rects(shown.size(), lobby.get_viewport().get_visible_rect().size.x))
	if is_equal_approx(lift, _lift):
		return
	for row in _rows:
		row.position.y += _lift - lift
	_lift = lift
