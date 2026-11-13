extends Node

# Dev-only: the saved-names list prototyped on the live local lobby for the
# owner's picks, and the main menu's Options alternative; the picked variant moves
# into couch_lobby's name_panel.gd. Headless it logs each seat's name box and its gap
# to the next seat; windowed it also saves shots to
# %TEMP%/machine-party-tests/cl_names_render/<setup>_<lang>/. CL_NAMES_LOCALE=ZHS|ZHT
# sets the game's language and shoots a subset; CL_NAMES_RENDER=menu shoots only the Options; =page the shipped Saved names page restyled into each candidate size; =built the shipped list and Options page;
# =pencil every seat on the shipped list, half on the pencil; =layout the shipped outfit view
# (cards clear of each other and of LEAVE, icons at least their own size), the list and the letters.
# =built also shoots LEAVE unlit and lit in an empty lobby.

const LOBBY := "res://scenes/local_lobby/local_lobby.tscn"
const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const FONT := "res://fonts/Terminal F4.ttf"
const ARROW_UP := "res://textures/ui/arrow_up_32_shadow.png"
const ARROW_DOWN := "res://textures/ui/arrow_down_32_shadow.png"
const SAVED := ["JERM", "WWWWWWW", "ALEX", "SAM", "MAYA", "LEO", "ZOEY", "KAI", "TT", "CEK", "KLEB", "LOKY"]
const SEVEN := ["WWWWWWW", "JEREMIA", "ALEXAND", "SAMANTH", "MAYAKOV", "LEONARD", "ZOEYBEL", "KAIROSS"]
const LISTS := [
	{"id": "list_a_rows5_f21_fade_label", "rows": 5, "font": 21, "cursor": false, "label": true},
	{"id": "list_b_rows3_f24_fade_label", "rows": 3, "font": 24, "cursor": false, "label": true},
	{"id": "list_c_rows5_f16_cursor_label", "rows": 5, "font": 16, "cursor": true, "label": true},
	{"id": "list_d_rows5_f21_fade_icon", "rows": 5, "font": 21, "cursor": false, "label": false},
]
# Per seat, the highlighted item (0 is the pencil), so one shot shows several scroll states.
const HIGHLIGHT := [0, 2, 7, 1, 4, 0, 10, 3]
const KEYBOARD_SEAT := 3
const DELETE_SEATS := [1, 5]
const SPINNERS := [
	{"id": "spin_a_sep13_game", "sep": -13, "font": 24},
	{"id": "spin_b_sep16", "sep": -16, "font": 24},
	{"id": "spin_c_sep21_letters18", "sep": -21, "font": 18},
	{"id": "spin_d_sep21_letters18_one_arrow", "sep": -21, "font": 18, "one_arrow": true},
]
const RED := Color(1.0, 0.36, 0.3)
# The outfit icons are 26 px drawings.
const ICON_ART := 26.0

var fails := 0
var out: FileAccess
var _loader
var lang := "EN"
var setup := ""
var windowed := false
var lobby: Node
var controls: Array = []
var font: Font
var up_tex: Texture2D
var down_tex: Texture2D
var pencil_tex: Texture2D
var _seps: Array = []

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/cl_names_render/result.txt"), FileAccess.WRITE)
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
	_run.call_deferred()

static func lang_of(raw: String) -> String:
	var v := raw.to_upper()
	return v if v == "ZHS" or v == "ZHT" else "EN"

func pick(en: String, zhs: String, zht: String) -> String:
	return zhs if lang == "ZHS" else (zht if lang == "ZHT" else en)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	lang = lang_of(OS.get_environment("CL_NAMES_LOCALE"))
	if lang != "EN":
		TranslationServer.set_locale(lang)
		# The game applies its saved language after the mods start; ours is kept over it.
		get_tree().node_added.connect(func(_n): if TranslationServer.get_locale() != lang: TranslationServer.set_locale(lang))
	windowed = DisplayServer.get_name() != "headless"
	font = load(FONT)
	up_tex = load(ARROW_UP)
	down_tex = load(ARROW_DOWN)
	pencil_tex = _pencil()
	ok("the game's font and arrows load", font != null and up_tex != null and down_tex != null)
	ok("the pencil icon loads from couch_lobby", pencil_tex != null)

	if OS.get_environment("CL_NAMES_RENDER") == "page":
		await _page_variants()
		finish()
		return
	get_tree().change_scene_to_file(LOBBY)
	await frames(30)
	await get_tree().create_timer(1.5).timeout
	lobby = get_tree().current_scene
	controls = lobby.local_lobby_player_controls
	setup = "extended" if controls.size() == 8 else "vanilla"
	say("setup %s, %d seats, language %s, windowed %s" % [setup, controls.size(), lang, windowed])
	for i in controls.size():
		if i == KEYBOARD_SEAT:
			lobby.join(-1, false)
		else:
			lobby.join(20 + i, true)
	await frames(10)
	for c in controls:
		_seps.append(c.name_entry_selector.get_theme_constant("separation"))
	var full := lang == "EN"
	if OS.get_environment("CL_NAMES_RENDER") == "built":
		await _built()
		finish()
		return
	if OS.get_environment("CL_NAMES_RENDER") == "menu":
		await _menu()
		finish()
		return
	if OS.get_environment("CL_NAMES_RENDER") == "pencil":
		await _pencil_shot()
		finish()
		return
	if OS.get_environment("CL_NAMES_RENDER") == "layout":
		await _layout_shots()
		finish()
		return

	for v in (LISTS if full else [LISTS[0]]):
		for i in controls.size():
			_show_list(i, v, HIGHLIGHT[i], "", false)
		await _measure_and_shot(v.id)
	for mode in (["text", "tint"] if full else ["text"]):
		for i in controls.size():
			_show_list(i, LISTS[0], HIGHLIGHT[i], mode if DELETE_SEATS.has(i) else "", false)
		await _measure_and_shot("delete_" + mode)
	if full:
		for i in controls.size():
			_show_list(i, LISTS[0], 0, "", true)
		await _measure_and_shot("empty_pencil_only")
		for s in SPINNERS:
			for i in controls.size():
				_show_spinners(i, s)
			await _measure_and_shot(s.id)
		for i in controls.size():
			_clear(i)
			controls[i]._on_name_confirmed(SEVEN[i])
		await frames(90)
		_label_report()
		await _shot("named_seven_letters")
	for i in controls.size():
		_clear(i)
	await _menu()
	finish()

# The shipped list and Options page, not the prototypes: every seat on its list,
# seat 1 confirmed so the others show its name dimmed, then the Options page with one name marked.
func _built() -> void:
	var store = _loader.registry("couch_lobby").get("names")
	ok("the names store is up", store != null)
	if store == null:
		return
	var kept: Array = store.names.duplicate()
	var persist: bool = store.persist
	store.persist = false
	store.names = SAVED.duplicate()
	for i in controls.size():
		lobby.leave(i)
	await frames(5)
	for i in controls.size():
		if i == KEYBOARD_SEAT:
			lobby.join(-1, false)
		else:
			lobby.join(20 + i, true)
	await frames(10)
	controls[0]._on_name_confirmed("JERM")
	await frames(3)
	for i in range(1, controls.size()):
		var panel = controls[i].get_node_or_null("CouchLobbyNamePanel")
		if panel and panel._list != null:
			panel._lit = mini(HIGHLIGHT[i], panel._items.size() - 1)
			panel._build()
	ok("the lists are open", range(1, controls.size()).all(func(i): return controls[i].name_entry_selector.get_node_or_null("CouchLobbyNameList") != null))
	await _shot("built_join")
	await _leave_shots()
	Globals.splash_screen_viewed = true
	get_tree().change_scene_to_file(MAIN_MENU)
	await frames(30)
	await get_tree().create_timer(6.0).timeout
	var root := get_tree().current_scene
	var menu: Node = root if root.has_method("set_current_active_container") else root.get_node_or_null("MainMenuScene")
	var helper: Node = menu.get_node_or_null("CouchLobbySavedNames") if menu else null
	ok("the Options helper is up", helper != null)
	if helper != null:
		menu.set_current_active_container(&"Options")
		await get_tree().create_timer(1.0).timeout
		helper.row.grab_focus()
		await _shot("built_options_row")
		helper.row.pressed.emit()
		await frames(3)
		var b: Button = helper._name_button("ALEX")
		if b:
			b.grab_focus()
			helper._delete_step("ALEX", true)
		await _shot("built_options_page")
		menu.current_back_button.pressed.emit()
	store.names = kept
	store.persist = persist

# Every seat on the shipped list, even seats on the pencil (lit), odd ones on a name (the pencil dimmed).
func _pencil_shot() -> void:
	var store = _loader.registry("couch_lobby").get("names")
	ok("the names store is up", store != null)
	if store == null:
		return
	var kept: Array = store.names.duplicate()
	var persist: bool = store.persist
	store.persist = false
	store.names = SAVED.duplicate()
	for i in controls.size():
		lobby.leave(i)
	await frames(5)
	for i in controls.size():
		if i == KEYBOARD_SEAT:
			lobby.join(-1, false)
		else:
			lobby.join(20 + i, true)
	await frames(10)
	for i in controls.size():
		var panel = controls[i].get_node_or_null("CouchLobbyNamePanel")
		if panel and panel._list != null:
			panel._lit = 0 if i % 2 == 0 else mini(1 + i, panel._items.size() - 1)
			panel._first = 0
			panel._build()
	await _measure_and_shot("pencil")
	# The bar's pencil: drawn 1:1 on screen at a whole multiple of the art, so no pixel row drops.
	var l0 = controls[0].name_entry_selector.get_node_or_null("CouchLobbyNameList")
	var bars: Array = l0.find_children("*", "TextureRect", true, false).filter(func(t): return t.get_parent() is CenterContainer) if l0 else []
	ok("the pencil bar has its pencil", not bars.is_empty())
	if not bars.is_empty():
		var t: TextureRect = bars[0]
		var shown: Vector2 = t.get_global_rect().size
		var tex: Vector2 = t.texture.get_size()
		var k: float = tex.y / pencil_tex.get_size().y
		say("PENCIL %s: art %s, drawn %s (%.0fx), on screen %s, list %.0f wide on screen" % [setup, pencil_tex.get_size(), tex, k, shown, l0.get_global_rect().size.x])
		ok("the pencil is drawn 1:1 on screen at a whole scale of its art", absf(shown.y - tex.y) < 0.05 and absf(shown.x - tex.x) < 0.05 and absf(k - roundf(k)) < 0.001 and k >= 1.0, [shown, tex, k])
	store.names = kept
	store.persist = persist

# LEAVE in an empty lobby, unlit and as the name screen's back lights it.
func _leave_shots() -> void:
	for i in controls.size():
		lobby.leave(i)
	await frames(10)
	var b: Node = lobby.get_node_or_null("CouchLobbyButtons")
	ok("the buttons helper is up", b != null and b.has_method("_light"))
	await _shot("leave_unlit")
	if b != null and b.has_method("_light"):
		b._light(true)
		await _shot("leave_lit")
		ok("LEAVE lit has the focus", lobby.leave_button.has_focus())
		b._light(false)

func _card_rect(c: Control) -> Rect2:
	var r := Rect2()
	for ch in c.get_children():
		if ch is Control and ch.visible:
			var cr: Rect2 = ch.get_global_rect()
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
	return r

func _card_report(id: String) -> void:
	await frames(3)
	var rects: Array = controls.map(func(c): return _card_rect(c))
	var gap := INF
	for i in rects.size() - 1:
		gap = minf(gap, rects[i + 1].position.x - rects[i].end.x)
	var bottom: float = rects.map(func(r): return r.end.y).max()
	var leave: Rect2 = lobby.leave_button.get_global_rect()
	var hits_leave: bool = rects.any(func(r): return r.intersects(leave))
	var polaroid_top := INF
	var ups: Node = lobby.get_node_or_null("CouchLobbyCloseUps")
	if ups:
		for n in ups.find_children("*", "Control", true, false):
			if n.is_visible_in_tree() and n.get_global_rect().size.x > 40:
				polaroid_top = minf(polaroid_top, n.get_global_rect().position.y)
	say("CARD %s %s: smallest gap %.0f, lowest edge %.0f, Polaroids from %.0f, LEAVE %s (%s)" % [setup, id, gap, bottom, polaroid_top, leave, "overlapped" if hits_leave else "clear"])
	# Vanilla's own card boxes overlap; only Extended's are laid out side by side.
	if setup == "extended":
		ok("%s: the cards stay clear of each other and of LEAVE" % id, gap >= 0.0 and not hits_leave, [gap, hits_leave])

# Seats on their lists, then on their letters (seven Ws), at the panel's own sizes for the card.
func _name_screens(id: String) -> void:
	var panels: Array = controls.map(func(c): return c.get_node_or_null("CouchLobbyNamePanel"))
	for c in controls:
		c.show_name_entry()
	await frames(4)
	for i in panels.size():
		var p = panels[i]
		if p and p._list != null:
			p._lit = 0 if i % 2 == 0 else mini(1 + i, p._items.size() - 1)
			p._first = 0
			p._build()
	await frames(2)
	var p0 = panels[0]
	var pitch: float = (p0.entry.get_theme_constant("separation") + p0.entry.character_selectors[0].character_label.custom_minimum_size.x) * controls[0].get_global_transform().get_scale().x
	say("TEXT %s: names %d px, letters %d px on the card's canvas; letters %.2f screen px apart" % [setup, p0.row_font, p0.letter_font, pitch])
	ok("the letters sit a whole number of screen pixels apart", absf(pitch - roundf(pitch)) < 0.01, pitch)
	await _measure_and_shot("%s_list" % id)
	for p in panels:
		if p and p._list != null:
			p._pick(0)
	for c in controls:
		c.name_entry_selector.set_player_name("WWWWWWW")
	await _measure_and_shot("%s_letters" % id)

# The outfit view as it ships (every seat on a 7-letter name), then the name screens.
func _layout_shots() -> void:
	var store = _loader.registry("couch_lobby").get("names")
	ok("the names store is up", store != null)
	if store == null:
		return
	var kept: Array = store.names.duplicate()
	var persist: bool = store.persist
	store.persist = false
	store.names = SAVED.duplicate()
	for i in controls.size():
		lobby.leave(i)
	await frames(5)
	for i in controls.size():
		if i == KEYBOARD_SEAT:
			lobby.join(-1, false)
		else:
			lobby.join(20 + i, true)
	await frames(10)
	for i in controls.size():
		controls[i]._on_name_confirmed(SEVEN[i])
	await frames(90)
	var icon: Rect2 = controls[0].hat_picker_element.get_global_rect()
	say("OUTFIT %s: hat icon %.1f px on screen (its drawing %d)" % [setup, icon.size.y, ICON_ART])
	ok("the outfit icons show at least their own size", icon.size.y >= ICON_ART - 0.05, icon.size)
	await _card_report("layout")
	await _shot("layout_outfit")
	await _name_screens("layout")
	store.names = kept
	store.persist = persist

func _pencil() -> Texture2D:
	var node: Node = _loader.get_node_or_null("couch_lobby")
	var dir: String = node.get_meta("mpml_dir") if node != null and node.has_meta("mpml_dir") else _loader.dir_of("couch_lobby")
	var image := Image.load_from_file(dir.path_join("name_new.png"))
	return ImageTexture.create_from_image(image) if image else null

# --- the list ------------------------------------------------------------------

func _show_list(i: int, v: Dictionary, lit: int, delete_mode: String, empty: bool) -> void:
	_clear(i)
	var c = controls[i]
	var e: Control = c.name_entry_selector
	for s in e.character_selectors:
		s.visible = false
	c.name_accept_button.visible = false
	var box := VBoxContainer.new()
	box.name = "ProtoList"
	box.add_theme_constant_override("separation", -2)
	var items: Array = ["+"] + ([] if empty else SAVED)
	var rows: int = mini(v["rows"], items.size())
	var start: int = clampi(lit - rows / 2, 0, items.size() - rows)
	box.add_child(_arrow(up_tex, start > 0))
	for k in range(start, start + rows):
		box.add_child(_row(v, items[k], k == 0, k == lit, i == KEYBOARD_SEAT, delete_mode if k == lit and k > 0 else ""))
	box.add_child(_arrow(down_tex, start + rows < items.size()))
	e.add_child(box)

func _row(v: Dictionary, item: String, is_pencil: bool, lit: bool, keyboard: bool, delete_mode: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var a := 1.0 if lit or v["cursor"] else 0.5
	if v["cursor"]:
		row.add_child(_label(">" if lit else " ", v["font"], 1.0, Color.WHITE))
	if is_pencil:
		var icon := TextureRect.new()
		icon.texture = pencil_tex
		icon.custom_minimum_size = Vector2(v["font"], v["font"])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.self_modulate.a = a
		row.add_child(icon)
		if v["label"]:
			row.add_child(_label(pick("NEW NAME", "新名字", "新名字"), v["font"], a, Color.WHITE))
		return row
	var text := item
	var color := Color.WHITE
	if delete_mode == "text":
		text = pick("DELETE?", "删除？", "刪除？")
		color = RED
	elif delete_mode == "tint":
		color = RED
	row.add_child(_label(text, v["font"], a, color))
	if keyboard:
		row.add_child(_label("x", v["font"], 1.0 if lit else 0.5, RED if lit else Color.WHITE))
	return row

func _label(text: String, size: int, alpha: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.self_modulate.a = alpha
	return l

func _arrow(tex: Texture2D, shown: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(16, 16)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.self_modulate.a = 1.0 if shown else 0.0
	return t

func _show_spinners(i: int, s: Dictionary) -> void:
	_clear(i)
	var e: Control = controls[i].name_entry_selector
	# A container resets its children's scale, so a smaller box means smaller letters.
	e.add_theme_constant_override("separation", s["sep"])
	for sel in e.character_selectors:
		sel.character_label.add_theme_font_size_override("font_size", s["font"])
		if s.get("one_arrow", false) and sel != e.active_element:
			sel.cycle_previous_element.self_modulate.a = 0.0
			sel.cycle_next_element.self_modulate.a = 0.0
	e.set_player_name("WWWWWWW")

func _clear(i: int) -> void:
	var c = controls[i]
	var e: Control = c.name_entry_selector
	var old := e.get_node_or_null("ProtoList")
	if old:
		e.remove_child(old)
		old.queue_free()
	for s in e.character_selectors:
		s.visible = true
		s.character_label.add_theme_font_size_override("font_size", 24)
		s.cycle_previous_element.self_modulate.a = 0.5
		s.cycle_next_element.self_modulate.a = 0.5
	if i < _seps.size():
		e.add_theme_constant_override("separation", _seps[i])
	c.name_accept_button.visible = c.name_entry_selector.active and not c.is_joystick

# --- measuring and shooting -------------------------------------------------------

# The union of a seat's visible content in canvas pixels: the list, or the shown letters.
func _content(i: int) -> Rect2:
	var e: Control = controls[i].name_entry_selector
	var r := Rect2()
	for ch in e.get_children():
		if ch is Control and ch.visible:
			var cr: Rect2 = ch.get_global_rect()
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
	return r

func _measure_and_shot(id: String) -> void:
	await frames(3)
	var rects: Array = range(controls.size()).map(func(i): return _content(i))
	var parts := []
	for i in rects.size():
		parts.append("P%d x %.0f..%.0f y %.0f..%.0f" % [i + 1, rects[i].position.x, rects[i].end.x, rects[i].position.y, rects[i].end.y])
	say("MEASURE %s %s: %s" % [setup, id, ", ".join(parts)])
	var worst := INF
	var pairs := []
	for i in rects.size() - 1:
		var gap: float = rects[i + 1].position.x - rects[i].end.x
		pairs.append("%d-%d %.0f" % [i + 1, i + 2, gap])
		worst = minf(worst, gap)
	say("GAPS %s %s (negative overlaps): %s; smallest %.0f" % [setup, id, ", ".join(pairs), worst])
	await _shot(id)

func _label_report() -> void:
	var parts := []
	for i in controls.size():
		var l: Label = controls[i].name_label
		var r := l.get_global_rect()
		parts.append("P%d x %.0f..%.0f" % [i + 1, r.position.x, r.end.x])
	say("LABELS %s: %s" % [setup, ", ".join(parts)])

func _shot(id: String) -> void:
	if not windowed:
		return
	var dir := OS.get_environment("TEMP").path_join("machine-party-tests/cl_names_render/%s_%s" % [setup, lang.to_lower()])
	if not dir.is_absolute_path():
		ok("TEMP is set", false, dir)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(20)
	await RenderingServer.frame_post_draw
	var file := dir.path_join("%s.png" % id)
	ok("shot %s" % id, get_viewport().get_texture().get_image().save_png(file) == OK, file)

# --- the shipped Options page, restyled into each candidate size ----------------------

const MORE := ["NOVA", "BLAZ", "ROBE", "ALEN", "JOE", "HGWD", "MIKA", "RUBY"]
# rows: whole rows shown (0: as many whole rows as fit above Back). width: 0 fits the longest name,
# -1 is the Options rows' own column (the sliders), else the page's units.
const PAGE_VARIANTS := [
	{"id": "shipped", "shipped": true},
	{"id": "a_rows7_narrow", "rows": 7, "width": 0},
	{"id": "b_rows7_column", "rows": 7, "width": -1},
	{"id": "c_rows7_wide", "rows": 7, "width": 560},
	{"id": "d_fit_column", "rows": 0, "width": -1},
]

func _page_variants() -> void:
	setup = "menu"
	var store = _loader.registry("couch_lobby").get("names")
	ok("the names store is up", store != null)
	if store == null:
		return
	var kept: Array = store.names.duplicate()
	var persist: bool = store.persist
	store.persist = false
	Globals.splash_screen_viewed = true
	get_tree().change_scene_to_file(MAIN_MENU)
	await frames(30)
	await get_tree().create_timer(6.0).timeout
	var root := get_tree().current_scene
	var menu: Node = root if root.has_method("set_current_active_container") else root.get_node_or_null("MainMenuScene")
	var helper: Node = menu.get_node_or_null("CouchLobbySavedNames") if menu else null
	ok("the Options helper is up", helper != null)
	if helper == null:
		store.names = kept
		store.persist = persist
		return
	menu.set_current_active_container(&"Options")
	await get_tree().create_timer(1.0).timeout
	var lang_scroll: ScrollContainer = menu.language_select_handler.scroll_container
	var back: Button = menu.options_back_button
	say("PAGE viewport %s, Language list %s (local size %s), Back %s, Options rows %s" % [get_viewport().get_visible_rect().size, _drawn(lang_scroll), lang_scroll.size, _drawn(back), _drawn(helper._language.get_parent())])
	var column: float = helper._language.get_parent().size.x
	var all: Array = SAVED + MORE
	for count in [5, 7, 20]:
		store.names = all.slice(0, count)
		for v in PAGE_VARIANTS:
			if v.get("rows", -1) == 0 and count < 20:
				continue
			# Entering straight from boot, the menu's intro can put it back on Main after the first switch.
			if menu.get("current_active_container") != &"Options" or not helper.row.is_visible_in_tree():
				menu.set_current_active_container(&"Options")
				await get_tree().create_timer(1.5).timeout
			helper.row.pressed.emit()
			await frames(3)
			var page: Control = helper._page
			var scroll: ScrollContainer = page.find_children("*", "ScrollContainer", true, false)[0]
			var list: VBoxContainer = scroll.get_child(0)
			var line: Control = list.get_child(0)
			var pitch: float = line.size.y + list.get_theme_constant("separation")
			if v.has("shipped"):
				var bar := scroll.get_v_scroll_bar()
				say("PAGE shipped_n%d: list %s, scroll %s, bar %s shown %s, first mark %s, hint %s, Back %s" % [count, list.size, _drawn(scroll), _drawn(bar), bar.is_visible_in_tree(), _drawn(list.get_child(0).get_child(1)) if list.get_child(0).get_child_count() > 1 else "-", _drawn(page.get_child(page.get_child_count() - 1)), _drawn(back)])
				var hint: Control = page.get_child(page.get_child_count() - 1)
				ok("shipped, %d names: the hint ends above Back" % count, _drawn(hint).end.y <= _drawn(back).position.y, [_drawn(hint).end.y, _drawn(back).position.y])
				ok("shipped, %d names: a scrollbar only when they don't all fit" % count, bar.is_visible_in_tree() == (list.size.y > scroll.size.y + 0.5), [list.size.y, scroll.size.y])
				helper._name_button(store.names[0]).grab_focus()
				await frames(6)
				ok("shipped, %d names, at the top: no row cut" % count, _cut_rows(scroll).is_empty(), _cut_rows(scroll))
				await _shot("page_shipped_n%d_top" % count)
				helper._name_button(store.names[-1]).grab_focus()
				await frames(6)
				ok("shipped, %d names, at the end: no row cut" % count, _cut_rows(scroll).is_empty(), _cut_rows(scroll))
				await _shot("page_shipped_n%d_end" % count)
				back.pressed.emit()
				await frames(3)
				continue
			var k: int = v["rows"]
			if k == 0:
				# Whole rows from the list's top down to a gap above Back's top, in the page's own units.
				var inv := scroll.get_global_transform().affine_inverse()
				var room: float = (inv * Vector2(0, _drawn(back).position.y)).y - 16.0 - _hint_height(page)
				k = maxi(int(floor((room + list.get_theme_constant("separation")) / pitch)), 1)
			k = mini(k, count)
			var w: float = column if v["width"] == -1 else float(v["width"])
			scroll.custom_minimum_size = Vector2(w, k * pitch - list.get_theme_constant("separation"))
			scroll.theme = lang_scroll.theme
			await frames(3)
			var first: Button = helper._name_button(store.names[0])
			first.grab_focus()
			var id := "page_%s_n%d" % [v["id"], count]
			say("PAGE on %s, page shown %s" % [menu.get("current_active_container"), page.is_visible_in_tree()])
			say("PAGE %s: width %.0f, %d whole rows, row %.0f, pitch %.0f, list %s, scroll %s, Back %s" % [id, w, k, line.size.y, pitch, list.size, _drawn(scroll), _drawn(back)])
			await _shot(id + "_top")
			if count > k:
				helper._name_button(store.names[-1]).grab_focus()
				await frames(6)
				await _shot(id + "_end")
			back.pressed.emit()
			await frames(3)
	store.names = kept
	store.persist = persist

func _cut_rows(scroll: ScrollContainer) -> Array:
	var sr := _drawn(scroll)
	var out: Array = []
	for line in scroll.get_child(0).get_children():
		var r := _drawn(line)
		var shown := minf(r.end.y, sr.end.y) - maxf(r.position.y, sr.position.y)
		if shown > 1.0 and shown < r.size.y - 1.0:
			out.append("%s %.0f/%.0f" % [line.get_child(0).name, shown, r.size.y])
	return out

func _hint_height(page: Control) -> float:
	var hint: Control = page.get_child(page.get_child_count() - 1)
	return hint.size.y + page.get_theme_constant("separation")

func _drawn(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)

# --- the Options alternative -------------------------------------------------------

func _menu() -> void:
	Globals.splash_screen_viewed = true
	get_tree().change_scene_to_file(MAIN_MENU)
	await frames(30)
	await get_tree().create_timer(6.0).timeout
	var root := get_tree().current_scene
	var menu: Node = root if root.has_method("set_current_active_container") else root.get_node_or_null("MainMenuScene")
	ok("the main menu is up", menu != null and menu.has_method("set_current_active_container"))
	if menu == null:
		return
	menu.set_current_active_container(&"Options")
	await get_tree().create_timer(1.0).timeout
	var language: Button = menu.find_child("LanguageButton", true, false)
	ok("the Options language row is found", language != null)
	if language == null:
		return
	var saved := _menu_button(language, pick("Saved names", "已保存的名字", "已儲存的名字"))
	language.add_sibling(saved)
	saved.name = "SavedNamesButton"
	await frames(3)
	saved.grab_focus()
	await _shot("menu_options_row")

	var rows: Control = language.get_parent()
	var hidden := []
	for ch in rows.get_children():
		if ch is CanvasItem and ch.visible:
			ch.visible = false
			hidden.append(ch)
	var list := VBoxContainer.new()
	list.name = "ProtoSavedNames"
	rows.add_child(list)
	var title := _menu_button(language, pick("Saved names", "已保存的名字", "已儲存的名字"))
	title.disabled = true
	list.add_child(title)
	var buttons := []
	for n in SAVED.slice(0, 7):
		var b := _menu_button(language, "  " + n)
		list.add_child(b)
		buttons.append(b)
	list.add_child(_menu_button(language, pick("X Delete   B Back", "X 删除   B 返回", "X 刪除   B 返回")))
	await frames(3)
	buttons[1].grab_focus()
	await _shot("menu_saved_names")
	buttons[1].text = "  " + SAVED[1] + "  " + pick("X again: delete", "再按 X 删除", "再按 X 刪除")
	buttons[1].add_theme_color_override("font_focus_color", RED)
	buttons[1].add_theme_color_override("font_color", RED)
	await _shot("menu_saved_names_confirm")
	say("MENU rows at x %.0f, list width %.0f" % [list.get_global_rect().position.x, list.get_global_rect().size.x])

func _menu_button(like: Button, text: String) -> Button:
	var b: Button = like.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	b.text = text
	b.visible = true
	b.focus_neighbor_top = NodePath()
	b.focus_neighbor_bottom = NodePath()
	return b
