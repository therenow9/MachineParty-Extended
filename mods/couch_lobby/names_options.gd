extends Node

# Child of the main menu (main_menu.gd's node). Adds "Saved names" under Options' Language and a
# page that lists the saved names, where Y and Y again (a pad), Delete and Delete again (keys), or
# the row's mark clicked twice delete one (Y, not X: the menu reads X as Back).
# A page left open when the menu leaves the tree goes with it, the Back button's connections too.

const RED := Color(1.0, 0.36, 0.3)
const ROW_NAME := "CouchLobbySavedNamesButton"
const PAGE_NAME := "CouchLobbySavedNamesPage"
# In the page's units: the gap kept above the menu's Back, and between the delete marks and the scrollbar.
const GAP_ABOVE_BACK := 16.0
const BAR_GAP := 6.0

var store
var menu: Control
var row: Button
var _language: Button
var _page: VBoxContainer = null
var _back: Button = null
var _parked: Array = []      # the game's own connections on its Back button while the page is open
var _back_neighbours: Array = []   # and its own up and down neighbours
var _hidden: Array = []
var _column := 0.0           # Options' rows' width, before they hide
var _armed := ""

func _ready() -> void:
	menu = get_parent()
	_attach.call_deferred()

static func lang_of(raw: String) -> String:
	var value := raw.to_upper().replace("-", "_")
	if value == "ZHT" or value == "ZH_TW" or value == "ZH_HK" or value == "ZH_MO" or value.begins_with("ZH_HANT"):
		return "ZHT"
	if value == "ZHS" or value == "ZH" or value == "ZH_CN" or value == "ZH_SG" or value.begins_with("ZH_HANS"):
		return "ZHS"
	return "EN"

static func pick(en: String, zhs: String, zht: String) -> String:
	var lang := lang_of(TranslationServer.get_locale())
	return zhs if lang == "ZHS" else (zht if lang == "ZHT" else en)

func _attach() -> void:
	_language = menu.get("options_language_button")
	if not (is_instance_valid(_language) and _language is Button) or _language.get_parent().has_node(ROW_NAME):
		return
	row = copy_button(_language, pick("Saved names", "已保存的名字", "已儲存的名字"))
	row.name = ROW_NAME
	_language.add_sibling(row)
	# Explicit neighbours would step over the new row.
	var below := _language.focus_neighbor_bottom
	if not below.is_empty():
		var next := _language.get_node_or_null(below)
		_language.focus_neighbor_bottom = _language.get_path_to(row)
		row.focus_neighbor_top = row.get_path_to(_language)
		if next is Control:
			row.focus_neighbor_bottom = row.get_path_to(next)
			next.focus_neighbor_top = next.get_path_to(row)
	row.pressed.connect(_open)
	Globals.locale_changed.connect(func(): row.text = pick("Saved names", "已保存的名字", "已儲存的名字"))

# A copy of the menu's own row, so it has its font, sounds and focus look; not its signals.
static func copy_button(like: Button, text: String) -> Button:
	var b: Button = like.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	b.text = text
	b.visible = true
	b.disabled = false
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_neighbor_top = NodePath()
	b.focus_neighbor_bottom = NodePath()
	return b

func _open() -> void:
	if _page != null or store == null:
		return
	var rows := _language.get_parent()
	_column = rows.size.x
	_hidden = []
	for ch in rows.get_children():
		if ch is CanvasItem and ch.visible:
			ch.visible = false
			_hidden.append(ch)
	# The menu's Back stays on screen (its prompt names each pad's own back button) and the menu presses it
	# on Back from any pad; while the page is open it only closes the page.
	_back = menu.get("options_back_button")
	_parked = []
	if _back is Button:
		for c in _back.pressed.get_connections():
			_parked.append(c)
			_back.pressed.disconnect(c["callable"])
		_back.pressed.connect(_close)
		_back_neighbours = [_back.focus_neighbor_top, _back.focus_neighbor_bottom]
		menu.set("current_back_button", _back)
	var options = menu.get("options_handler")
	if options:
		options.active = false
	_page = VBoxContainer.new()
	_page.name = PAGE_NAME
	rows.add_child(_page)
	_build("")

func _close() -> void:
	if _page == null:
		return
	_page.get_parent().remove_child(_page)
	_page.queue_free()
	_page = null
	_armed = ""
	if is_instance_valid(_back):
		_back.pressed.disconnect(_close)
		for c in _parked:
			_back.pressed.connect(c["callable"], c["flags"])
		if _back_neighbours.size() == 2:
			_back.focus_neighbor_top = _back_neighbours[0]
			_back.focus_neighbor_bottom = _back_neighbours[1]
	_parked = []
	_back_neighbours = []
	_back = null
	for ch in _hidden:
		if is_instance_valid(ch):
			ch.visible = true
	_hidden = []
	menu.set("current_back_button", menu.get("options_back_button"))
	var options = menu.get("options_handler")
	if options:
		options.active = true
	if GameManager.is_using_controller():
		row.grab_focus()

# focus_name: the row to focus after a rebuild ("" the first).
func _build(focus_name: String) -> void:
	for ch in _page.get_children():
		_page.remove_child(ch)
		ch.queue_free()
	var title := copy_button(_language, pick("Saved names", "已保存的名字", "已儲存的名字"))
	title.disabled = true
	title.focus_mode = Control.FOCUS_NONE
	_page.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var languages = menu.get("language_select_handler")
	if languages and languages.get("scroll_container") is ScrollContainer:
		scroll.theme = languages.scroll_container.theme
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_page.add_child(scroll)
	var first: Button = null
	var focus: Button = null
	var chain: Array[Button] = []
	var spacing := 0.0
	for n in store.names:
		var line := HBoxContainer.new()
		var b := copy_button(_language, "  " + n)
		b.name = "Name_" + n
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_exited.connect(func(): _disarm(n))
		var mark := copy_button(_language, "x")
		mark.name = "Delete_" + n
		mark.focus_mode = Control.FOCUS_NONE
		mark.pressed.connect(func(): _delete_step(n, false))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(BAR_GAP, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(b)
		line.add_child(mark)
		line.add_child(gap)
		list.add_child(line)
		spacing = float(line.get_theme_constant("separation"))
		chain.append(b)
		first = first if first else b
		if n == focus_name:
			focus = b
	if store.names.is_empty():
		var none := copy_button(_language, "  " + pick("No saved names", "没有已保存的名字", "沒有已儲存的名字"))
		none.disabled = true
		list.add_child(none)
	var hint := copy_button(_language, pick("Y: delete", "Y 删除", "Y 刪除"))
	hint.disabled = true
	hint.focus_mode = Control.FOCUS_NONE
	_page.add_child(hint)
	# Wider by the spacer and its separation, so the marks stay at the column's edge and only the bar moves.
	scroll.custom_minimum_size = Vector2(_column + BAR_GAP + spacing, _list_height(list, title, hint))
	_link(chain)
	var target: Button = focus if focus else first
	if target and GameManager.is_using_controller():
		target.grab_focus()

# As many whole rows as fit between the title and a gap above the menu's Back, so no row shows cut
# and the hint never runs under Back (the menu sits lower in Chinese, its font is taller).
# The page is laid out at the top of Options' rows, so its height comes from minimum sizes.
func _list_height(list: VBoxContainer, title: Control, hint: Control) -> float:
	var sep := float(list.get_theme_constant("separation"))
	var page_sep := float(_page.get_theme_constant("separation"))
	# A row's own height, not Language's: a row with CJK text (Language's, in Chinese) is taller than a name's.
	var pitch: float = (list.get_child(0) as Control).get_combined_minimum_size().y + sep
	var shown := maxi(list.get_child_count(), 1)
	var rows := _page.get_parent() as Control
	if _back is Button and _back.is_visible_in_tree():
		var back_top: float = (rows.get_global_transform().affine_inverse() * _back.get_global_transform().origin).y
		var room: float = back_top - title.get_combined_minimum_size().y - hint.get_combined_minimum_size().y - 2.0 * page_sep - GAP_ABOVE_BACK
		shown = clampi(int(floor((room + sep) / pitch)), 1, shown)
	return shown * pitch - sep

# Back's scene neighbours are Options' rows, hidden while the page shows, and the automatic search
# inside a ScrollContainer finds nothing above Back. So the names chain explicitly and wrap through
# Back, as Options' own first row and Back do.
func _link(chain: Array[Button]) -> void:
	if not (_back is Button):
		return
	if chain.is_empty():
		_back.focus_neighbor_top = NodePath(".")
		_back.focus_neighbor_bottom = NodePath(".")
		return
	for i in chain.size():
		var b := chain[i]
		b.focus_neighbor_top = b.get_path_to(chain[i - 1] if i > 0 else _back)
		b.focus_neighbor_bottom = b.get_path_to(chain[i + 1] if i + 1 < chain.size() else _back)
	_back.focus_neighbor_top = _back.get_path_to(chain[-1])
	_back.focus_neighbor_bottom = _back.get_path_to(chain[0])

func _input(event: InputEvent) -> void:
	if _page == null:
		return
	var y: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE
	if not (y or key):
		return
	var f := get_viewport().gui_get_focus_owner()
	if f is Button and String(f.name).begins_with("Name_") and _page.is_ancestor_of(f):
		get_viewport().set_input_as_handled()
		_delete_step(String(f.name).trim_prefix("Name_"), true)

# The first step marks the row red; the same row's second step deletes it.
func _delete_step(n: String, from_pad: bool) -> void:
	if _armed != n:
		_disarm(_armed)
		_armed = n
		var b := _name_button(n)
		if b:
			b.text = "  %s  %s" % [n, pick("Y again: delete", "再按 Y 删除", "再按 Y 刪除") if from_pad else pick("Again: delete", "再按一次删除", "再按一次刪除")]
			for c in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
				b.add_theme_color_override(c, RED)
		return
	var names: Array = store.names
	var at := names.find(n)
	var after: String = names[at + 1] if at + 1 < names.size() else (names[at - 1] if at > 0 else "")
	_armed = ""
	store.forget(n)
	_build(after)

func _disarm(n: String) -> void:
	if n.is_empty() or n != _armed:
		return
	_armed = ""
	var b := _name_button(n)
	if b:
		b.text = "  " + n
		for c in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			b.remove_theme_color_override(c)

func _name_button(n: String) -> Button:
	return _page.find_child("Name_" + n, true, false) as Button if _page else null
