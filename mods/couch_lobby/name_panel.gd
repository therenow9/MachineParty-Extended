extends Node

# Child of a LocalLobbyPlayerControls panel. Gives its name screen NAME_LETTERS
# spinners, saves each name confirmed there, and opens it on a list of the saved
# names: the pencil (the letters), then the names. A plain Node: the panel's own
# show and hide loops over its children never reach it.

const NAME_LETTERS := 7
const SELECTOR_SCENE := "res://scenes/local_lobby/components/local_lobby_player_name_character_selector.tscn"
# The text sizes here are on screen; a scaled card (Extended's) gets them larger on its canvas.
# The owner's pick: the game's 24 px letters at its -13 make 7 letters 146 px wide,
# past the 101 px between vanilla's seats 2 and 3; 18 px at -21 (11 px apart in the selector's
# 32 px cell) leave them 3 px apart, so an unscaled card keeps them at 18. A scaled card's
# letters match the names. A container resets its children's scale: the letters shrink, not the box.
const LETTER_SIZE := 18
const LETTER_PITCH := 11
# The list as picked: 5 rows, the game's fade, no wrap; 23 px. The
# list as wide as the 7 letters, the names centred, the pencil row a filled bar with the pencil end to end.
const ROWS := 5
const ROW_FONT := 23
const BAR_HEIGHT := 40       # on the card's canvas
const BAR_FILL := Color(1, 1, 1, 0.22)
const BAR_PAD := 4           # on screen, around the pencil
# The pencil grows by whole screen pixels only (below 1x, nearest filtering drops pixel rows), and
# lengthens by repeating its shaft: name_new.png's columns 10-26 are identical (make_icon.py).
const SHAFT_FROM := 10
const PENCIL_ENDS := 20      # its point's and its end's columns, never repeated
const MAX_SCALE := 3
const LIT := 1.0
const UNLIT := 0.5
const IN_USE := 0.2
const FONT := "res://fonts/Terminal F4.ttf"
const ARROW_UP := "res://textures/ui/arrow_up_32_shadow.png"
const ARROW_DOWN := "res://textures/ui/arrow_down_32_shadow.png"
const LIST_NAME := "CouchLobbyNameList"
# Set on the controls while this panel owns back on the name screen; GameCube Controller Support's
# drop-out stands aside for it. Its registry key gives a GameCube pad's B under its layout.
const BACK_META := &"couch_lobby_name_back"
const GCS_ID := "gamecube_support"

var store
var pencil: Texture2D
var note := Callable()
var registry := Callable()   # id -> the loader's registry for that mod
var controls: Control
var entry: Control
var _extended := false
var _lit_letter = null
var _list: VBoxContainer = null
var _items: Array = []       # "" is the pencil, then the saved names
var _lit := 0
var _first := 0              # the top visible row
var _armed := false
var _pending := -1           # the row A went down on, picked when it comes up
var _repeat := 0.0
var _start_name := ""        # what the letters showed when the name screen opened
var _chose_letters := false  # on the letters by the pencil, not because nothing was saved
var _back_armed := false
var _confirming := false
var row_font := ROW_FONT
var letter_font := LETTER_SIZE
var _width := 0.0            # the list's, on the card's canvas: the letters' row
var _bare: Image = null      # the pencil as drawn
var _pencils := {}           # Vector2i(length, scale) -> its texture

func _ready() -> void:
	controls = get_parent()
	entry = controls.name_entry_selector
	if pencil != null:
		_bare = pencil.get_image()
		if _bare != null:
			_bare.convert(Image.FORMAT_RGBA8)
	_extended = _extend()
	set_letters(LETTER_SIZE, LETTER_PITCH)
	# Only the game's own confirm (spinners, accept button, this list) passes through here, so
	# the names that tests, rejoins and Offline Bots set directly are never saved.
	entry.name_confirmed.connect(_on_name_confirmed)
	entry.visibility_changed.connect(_on_entry_visibility)
	if store != null:
		store.changed.connect(_on_store_changed)
	controls.set_meta(BACK_META, true)

func _exit_tree() -> void:
	if is_instance_valid(controls):
		controls.remove_meta(BACK_META)

func _extend() -> bool:
	var selectors: Array = entry.character_selectors
	if selectors.is_empty() or selectors.size() >= NAME_LETTERS:
		return false
	var path: String = selectors[0].scene_file_path
	var scene: PackedScene = load(path if not path.is_empty() else SELECTOR_SCENE)
	var added := []
	for k in NAME_LETTERS - selectors.size():
		var s: Node = scene.instantiate() if scene else null
		if s == null:
			break
		entry.add_child(s)
		added.append(s)
		selectors.append(s)
	# A typed array refuses a node of another class with only an error print.
	if selectors.size() != NAME_LETTERS or not added.all(func(x): return selectors.has(x)):
		for s in added:
			selectors.erase(s)
			s.queue_free()
		if note.is_valid():
			note.call("couch_lobby: could not add name letters; names stay at %d" % selectors.size())
		return false
	for s in added:
		s.hover_speaker = entry.hover_speaker
		s.press_speaker = entry.press_speaker
	return true

# The list's and the letters' sizes for this card, so they show at these sizes on screen.
# letter_screen < 0: as large as the names on a scaled card, LETTER_SIZE on an unscaled one.
func fit_text(row_screen := ROW_FONT, letter_screen := -1) -> void:
	var shrink: float = controls.get_global_transform().get_scale().y
	if shrink <= 0.0:
		shrink = 1.0
	if letter_screen < 0:
		letter_screen = row_screen if shrink < 1.0 else LETTER_SIZE
	row_font = roundi(row_screen / shrink)
	set_letters(roundi(letter_screen / shrink), letter_pitch(letter_screen, shrink))

func set_letters(size: int, pitch: int) -> void:
	letter_font = size
	if not _extended:
		return
	var cell := 0.0
	for s in entry.character_selectors:
		s.character_label.add_theme_font_size_override("font_size", size)
		cell = maxf(cell, s.character_label.custom_minimum_size.x)
	entry.add_theme_constant_override("separation", roundi(pitch - cell))

# The canvas distance between letters: the owner's 11 px at 18 grown with the letters, made a whole
# number of screen pixels where one is near (never tighter), so every gap on a scaled card is the same.
static func letter_pitch(screen_size: int, shrink: float) -> int:
	var t := LETTER_PITCH * screen_size / float(LETTER_SIZE) / shrink
	var best := -1
	for p in range(ceili(t * 0.97), roundi(t) + 5):
		if absf(p * shrink - roundf(p * shrink)) < 0.01 and (best < 0 or absf(p - t) < absf(best - t)):
			best = p
	return best if best > 0 else roundi(t)

func _process(delta: float) -> void:
	if not (entry.visible and entry.active):
		_back_armed = false
		_lit_letter = null
		return
	if _drive_back():
		return
	if _list != null:
		_drive_list(delta)
	elif _extended:
		_one_arrow()

# At 18 px every letter's arrows run together into one strip, so a pad shows only the
# edited letter's. A keyboard player keeps them all: the mouse edits by hovering them.
func _one_arrow() -> void:
	if not (entry.active and entry.is_joystick):
		_lit_letter = null
		return
	if entry.active_element == _lit_letter:
		return
	_lit_letter = entry.active_element
	for s in entry.character_selectors:
		var a: float = s.inactive_modulate_value if s == _lit_letter else 0.0
		s.cycle_previous_element.self_modulate.a = a
		s.cycle_next_element.self_modulate.a = a

func _on_name_confirmed(player_name) -> void:
	if store != null:
		_confirming = true
		store.remember(str(player_name))
		_confirming = false

# The game's letters take no key: a keyboard player's Enter confirms them (unless a focused button took it).
func _unhandled_input(event: InputEvent) -> void:
	if controls.is_joystick or _list != null or not (entry.visible and entry.active):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		entry.press_speaker.play()
		entry.accept_name()

# --- back: the letters to the list, the list to dropped out ---------------------

# The back button for this seat: a GameCube pad's B under its layout, else a pad's X (the menu's
# Back) or the keyboard's X key (the lobby's own back, action_2).
static func back_action(is_joystick: bool, gamecube_b: StringName) -> StringName:
	if not is_joystick:
		return &"action_2"
	return gamecube_b if gamecube_b != &"" else &"action_3"

# What back does: "list" (the letters back to the list), "leave", or "" (nothing).
static func back_does(on_list: bool, has_names: bool, is_joystick: bool) -> String:
	if not on_list and has_names:
		return "list"
	return "leave" if is_joystick else ""

static func gamecube_b(reg: Callable, device: int) -> StringName:
	if not reg.is_valid():
		return &""
	var f = reg.call(GCS_ID).get("name_back")
	return f.call(device) if f is Callable and f.is_valid() else &""

func _gamecube_b(device: int) -> StringName:
	return gamecube_b(registry, device)

# True when back acted this frame. The press that opened this screen (B from the outfit, or the
# back that left the letters) is still down: nothing counts until it has been seen up.
func _drive_back() -> bool:
	var dev: int = controls.device
	var action := back_action(controls.is_joystick, _gamecube_b(dev) if controls.is_joystick else &"")
	var down := MultiplayerInput.is_action_pressed(dev, action)
	if not _back_armed:
		_back_armed = not down
		return false
	if not MultiplayerInput.is_action_just_pressed(dev, action):
		return false
	match back_does(_list != null, store != null and not store.names.is_empty(), controls.is_joystick):
		"list":
			_back_armed = false
			entry.set_player_name(_start_name)
			_first_letter()
			entry.press_speaker.play()
			_open()
			return true
		"leave":
			return _drop_out()
	return false

func _first_letter() -> void:
	var selectors: Array = entry.character_selectors
	if selectors.is_empty():
		return
	if entry.active_element:
		entry.active_element.set_focused(false)
	entry.active_selector_index = 0
	entry.active_element = selectors[0]
	entry.active_element.set_focused(true)

# What the lobby's handle_leave_input does for Start.
func _drop_out() -> bool:
	var lobby := _lobby()
	if lobby == null or not "player_data" in lobby or lobby.get("game_started") or not lobby.active or not lobby.can_control:
		return false
	var seat: int = controls.assigned_player_id
	lobby.leave(seat)
	lobby._on_player_ready_changed(seat, false)
	return true

func _lobby() -> Node:
	var lobby := controls.get_parent()
	while lobby != null and not "local_lobby_player_controls" in lobby:
		lobby = lobby.get_parent()
	return lobby

# --- the list ------------------------------------------------------------------------

# set_active() shows the entry before it sets active and the name, so the list opens a frame later.
func _on_entry_visibility() -> void:
	if entry.visible:
		_opened.call_deferred()
	else:
		_close(false)

func _opened() -> void:
	fit_text()
	_start_name = shown_name(entry)
	_chose_letters = false
	_open()

func _open() -> void:
	if _list != null or not entry.visible or not entry.active or store == null or store.names.is_empty():
		return
	# A join shows P<n> in the letters, a return with B the name already confirmed.
	var shown: String = shown_name(entry)
	_items = [""] + store.names
	_lit = maxi(_items.find(shown), 0) if shown in store.names else 0
	_first = first_row(_items.size(), _lit)
	_armed = false
	_back_armed = false
	_pending = -1
	entry.is_joystick = false
	_width = letters_width(entry)
	for s in entry.character_selectors:
		s.visible = false
	controls.name_accept_button.visible = false
	_list = VBoxContainer.new()
	_list.name = LIST_NAME
	_list.custom_minimum_size.x = _width
	_list.add_theme_constant_override("separation", -2)
	entry.add_child(_list)
	_build()

# to_letters: the pencil was picked, so the panel goes on to the spinners.
func _close(to_letters: bool) -> void:
	if _list == null:
		return
	entry.remove_child(_list)
	_list.queue_free()
	_list = null
	for s in entry.character_selectors:
		s.visible = true
	entry.is_joystick = controls.is_joystick
	_lit_letter = null
	_back_armed = false
	_chose_letters = to_letters
	if to_letters:
		controls.name_accept_button.visible = not controls.is_joystick

# The letters' row as the game lays it out, hidden or not: the list's width.
static func letters_width(e: Control) -> float:
	var sels: Array = e.character_selectors
	var cell := 0.0
	for s in sels:
		cell = maxf(cell, s.get_combined_minimum_size().x)
	return sels.size() * cell + (sels.size() - 1) * e.get_theme_constant("separation")

# The largest whole scale at which the pencil (art_h tall, at least PENCIL_ENDS + 1 long) fits
# inside the bar's height and the room beside it, both in screen pixels; 0 when none does.
static func pencil_scale(art_h: int, inner_h: float, room: float) -> int:
	for k in range(MAX_SCALE, 0, -1):
		if art_h * k <= inner_h and (PENCIL_ENDS + 1) * k <= room:
			return k
	return 0

# The pencil `length` pixels long as drawn: its point and end as they are, its shaft's column repeated.
static func pencil_of_length(bare: Image, length: int) -> Image:
	var n := maxi(length - PENCIL_ENDS, 1)
	var h := bare.get_height()
	var tail := PENCIL_ENDS - SHAFT_FROM
	var img := Image.create(SHAFT_FROM + n + tail, h, false, bare.get_format())
	img.blit_rect(bare, Rect2i(0, 0, SHAFT_FROM, h), Vector2i.ZERO)
	for k in n:
		img.blit_rect(bare, Rect2i(SHAFT_FROM, 0, 1, h), Vector2i(SHAFT_FROM + k, 0))
	img.blit_rect(bare, Rect2i(bare.get_width() - tail, 0, tail, h), Vector2i(SHAFT_FROM + n, 0))
	return img

# The bar's pencil, end to end on screen pixels; null when there's no art or no room.
func _bar_pencil(shrink: float) -> TextureRect:
	if _bare == null or shrink <= 0.0:
		return null
	var room := _width * shrink - 2 * BAR_PAD
	var k := pencil_scale(_bare.get_height(), BAR_HEIGHT * shrink - 2 * BAR_PAD, room)
	if k == 0:
		return null
	var length := floori(room / k)
	var key := Vector2i(length, k)
	if not _pencils.has(key):
		var img := pencil_of_length(_bare, length)
		img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
		_pencils[key] = ImageTexture.create_from_image(img)
	var tex: Texture2D = _pencils[key]
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(tex.get_width(), tex.get_height()) / shrink
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func shown_name(e: Node) -> String:
	var n := ""
	for s in e.character_selectors:
		var ch: String = s.character_label.text
		if ch != "-":
			n += ch
	return n

func in_use() -> Array:
	var lobby := _lobby()
	var out := []
	if lobby == null:
		return out
	for c in lobby.local_lobby_player_controls:
		if c != controls and c.active and c.assigned_player_id >= 0:
			out.append(str(c.player_name))
	return out

# The next row from `from` in `step`'s direction that nobody else is using, or `from` itself.
static func next_row(items: Array, used: Array, from: int, step: int) -> int:
	var k := from + step
	while k >= 0 and k < items.size():
		if k == 0 or not used.has(items[k]):
			return k
		k += step
	return from

static func first_row(count: int, lit: int, rows: int = ROWS) -> int:
	return clampi(lit - rows / 2, 0, maxi(count - rows, 0))

# The list scrolls only when the highlight would leave it, so a hovered row never moves under the mouse.
static func kept_in_view(first: int, lit: int, count: int, rows: int = ROWS) -> int:
	if lit < first:
		first = lit
	elif lit >= first + rows:
		first = lit - rows + 1
	return clampi(first, 0, maxi(count - rows, 0))

# A seat that opened on its letters with nothing saved gets the list once a name is, if its
# player hasn't changed a letter yet.
func _on_store_changed() -> void:
	if _list == null:
		if not (_confirming or _chose_letters) and entry.visible and entry.active and shown_name(entry) == _start_name:
			_open()
		return
	var was: String = _items[_lit]
	_items = [""] + store.names
	_lit = maxi(_items.find(was), 0)
	_build()

func _build() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	var used := in_use()
	if _lit > 0 and used.has(_items[_lit]):
		_lit = next_row(_items, used, _lit, -1)
	var rows := mini(ROWS, _items.size())
	_first = kept_in_view(_first, _lit, _items.size())
	var start := _first
	_list.add_child(_arrow(load(ARROW_UP), start > 0))
	for k in range(start, start + rows):
		_list.add_child(_row(k, used.has(_items[k]) and k > 0))
	_list.add_child(_arrow(load(ARROW_DOWN), start + rows < _items.size()))

func _row(k: int, taken: bool) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", load(FONT))
	b.add_theme_font_size_override("font_size", row_font)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_shadow_color", Color.BLACK)
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 1)
	var alpha := IN_USE if taken else (LIT if k == _lit else UNLIT)
	if k == 0:
		# A flat Button draws no stylebox: the bar is the button's own.
		b.flat = false
		b.custom_minimum_size = Vector2(_width, BAR_HEIGHT)
		var bar := StyleBoxFlat.new()
		bar.bg_color = BAR_FILL
		bar.set_content_margin_all(0)
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(st, bar)
		var t := _bar_pencil(controls.get_global_transform().get_scale().y)
		if t != null:
			# self_modulate fades only the bar; the pencil, a child, takes the same alpha.
			var c := CenterContainer.new()
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.modulate.a = alpha
			c.add_child(t)
			b.add_child(c)
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		b.text = _items[k]
	b.self_modulate.a = alpha
	b.disabled = taken
	# A pad player's panel takes no mouse; a keyboard player's rows follow the pointer and pick on release.
	if controls.is_joystick:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		b.mouse_entered.connect(func(): _hover(k))
		b.pressed.connect(func(): _mouse_pick(k))
	return b

func _arrow(tex: Texture2D, shown: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(16, 16)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.self_modulate.a = 1.0 if shown else 0.0
	return t

func _hover(k: int) -> void:
	if _list != null and k != _lit:
		_lit = k
		_build()
		entry.hover_speaker.play()

func _mouse_pick(k: int) -> void:
	if _list != null and _armed:
		_pick(k)

# The A or click that joined the seat, or B'd back to it, is still down when the list opens:
# nothing counts until it has been seen up.
func _drive_list(delta: float) -> void:
	var dev: int = controls.device
	if controls.is_joystick:
		var down := MultiplayerInput.is_action_pressed(dev, "action_1")
		if not _armed:
			_armed = not down
			return
		if MultiplayerInput.is_action_just_pressed(dev, "action_1"):
			_pending = _lit
		elif not down and _pending >= 0:
			var k := _pending
			_pending = -1
			if k == _lit:
				_pick(k)
				return
		_move(dev, delta)
	elif not _armed:
		_armed = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _move(dev: int, delta: float) -> void:
	_repeat = maxf(_repeat - delta, 0.0)
	var step := 0
	for d in [["up", -1], ["down", 1]]:
		if MultiplayerInput.is_action_just_pressed(dev, d[0]):
			step = d[1]
			_repeat = entry.button_press_cooldown_duration
		elif MultiplayerInput.is_action_pressed(dev, d[0]) and _repeat <= 0.0:
			step = d[1]
			_repeat = entry.button_cooldown_duration
	if step == 0:
		return
	var k := next_row(_items, in_use(), _lit, step)
	if k != _lit:
		_lit = k
		_pending = -1
		_build()
		entry.hover_speaker.play()

func _pick(k: int) -> void:
	# The pencil starts a new name: blank letters, not the name the seat had.
	if k == 0:
		entry.press_speaker.play()
		entry.set_player_name("")
		_first_letter()
		_close(true)
		return
	var n: String = _items[k]
	if in_use().has(n):
		return
	_close(false)
	entry.set_player_name(n)
	entry.name_confirmed.emit(n)
