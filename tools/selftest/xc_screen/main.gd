extends Node

# Dev-only: the online customization screen as More Cosmetics lays it out.
# Headless, it dumps the screen's Controls (rects, focus neighbours) and checks
# that no box overlaps; windowed, it also shoots the screen into
# %TEMP%/machine-party-tests/xc_screen/. It never calls save_and_exit, and
# never sends ui_cancel or action_2, which call it.

const SCREEN := "res://scenes/character_customization.tscn"
const BRANCH_SCRIPT := "res://scripts/components/character customization/customization_selection_branch.gd"

var fails := 0
var out: FileAccess
var out_dir: String
var api
var windowed := false

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/xc_screen/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func _mod_ready(loader) -> void:
	out_dir = OS.get_environment("TEMP").path_join("machine-party-tests/xc_screen")
	# Shots hold game art: a relative path would land them in the game folder or the repo.
	if not out_dir.is_absolute_path():
		ok("TEMP is set", false, out_dir)
		finish()
		return
	api = loader.registry("more_cosmetics").get("api")
	_run.call_deferred()

func _run() -> void:
	ok("more_cosmetics api", api != null)
	if api == null:
		finish()
		return
	windowed = DisplayServer.get_name() != "headless"
	var g := {}
	for k in ["active_cosmetic_hat", "active_cosmetic_glasses", "active_cosmetic_suit_color"]:
		g[k] = Globals.get(k)
	if windowed:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("shots"))
		for f in DirAccess.get_files_at(out_dir.path_join("shots")):
			DirAccess.remove_absolute(out_dir.path_join("shots").path_join(f))
	await get_tree().create_timer(1.0).timeout
	var sel: Node = await _screen()
	ok("screen loaded", sel != null)
	if sel == null:
		finish()
		return
	_dump(get_tree().current_scene)
	await _shoot("saved")
	_wear(sel, WORN)
	await _shoot("built_ours")
	if windowed:
		_tile_light(sel)
	_wear(sel, WORN_GAME)
	await _shoot("built_game")
	for k in g:
		Globals.set(k, g[k])
	finish()

# A fresh copy of the screen; returns its CustomizationSelection.
func _screen() -> Node:
	get_tree().change_scene_to_file(SCREEN)
	await frames(10)
	for n in get_tree().current_scene.find_children("*", "Node", true, false):
		if n.get_script() != null and "select_cosmetic" in n and "ui_root" in n:
			return n
	return null

func _shoot(name: String) -> void:
	_overlaps(name)
	if not windowed:
		await frames(3)
		return
	# The screen fades in over 1 s after a 1 s timer; tile viewports need a few frames.
	await get_tree().create_timer(2.6).timeout
	_save(get_viewport(), name)

func _dump(screen: Node) -> void:
	var win := get_window()
	say("window size=%s content_scale_size=%s mode=%d aspect=%d factor=%.2f visible_rect=%s" % [
		win.size, win.content_scale_size, win.content_scale_mode, win.content_scale_aspect,
		win.content_scale_factor, get_viewport().get_visible_rect()])
	var sel: Node = null
	for n in screen.find_children("*", "Node", true, false):
		if n.get_script() != null and "select_cosmetic" in n and "ui_root" in n:
			sel = n
			break
	ok("selection node", sel != null, screen.get_path_to(sel) if sel else "")
	if sel == null:
		return
	say("selection %s script=%s ui_root=%s caret=%s" % [screen.get_path_to(sel), sel.get_script().resource_path,
		screen.get_path_to(sel.ui_root), screen.get_path_to(sel.ninepatch_color_selection)])
	say("customizations %s" % [sel.customizations])
	say("suit_colors %s" % [sel.suit_colors])
	for i in sel.selection_rect_array.size():
		var r: TextureRect = sel.selection_rect_array[i]
		say("rect %d %s %s" % [i, screen.get_path_to(r), _box(r)])
	for n in screen.find_children("*", "Node", true, false):
		if n.get_script() != null and n.get_script().resource_path == BRANCH_SCRIPT:
			var b = n.get("button")
			say("branch %s cosmetic=%s suit=%s parent=%s button=%s" % [screen.get_path_to(n), n.assigned_cosmetic,
				n.is_suit_color_selection, screen.get_path_to(n.get_parent()), screen.get_path_to(b) if b is Node else b])
	for c in screen.find_children("*", "Control", true, false):
		var line := "ctl %s [%s] %s vis=%s" % [screen.get_path_to(c), c.get_class(), _box(c), c.is_visible_in_tree()]
		if c.get_script() != null:
			line += " script=%s" % c.get_script().resource_path.get_file()
		if c is Button or c is Label:
			line += " text=%s" % JSON.stringify(c.text)
		if c.focus_mode != Control.FOCUS_NONE:
			line += " focus=%d L=%s R=%s T=%s B=%s" % [c.focus_mode, c.focus_neighbor_left, c.focus_neighbor_right,
				c.focus_neighbor_top, c.focus_neighbor_bottom]
		say(line)

func _box(c: Control) -> String:
	return "pos=(%d,%d) size=(%d,%d)" % [c.global_position.x, c.global_position.y, c.size.x, c.size.y]

func _save(vp: Viewport, name: String) -> void:
	var path := out_dir.path_join("shots").path_join(name + ".webp")
	var err := vp.get_texture().get_image().save_webp(path, true, 0.9)
	ok("shot %s" % name, err == OK, path)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

# --- The built screen, wearing ours and then the game's.

const WORN := ["xc_chef_hat", "xc_monocle_glasses", "xc_teal"]
const WORN_GAME := ["tophat", "sunglasses", "purple"]

func _wear(sel: Node, worn: Array) -> void:
	var a = sel.customization_assigner
	a.assign_hat(worn[0])
	a.assign_glasses(worn[1])
	sel.select_suit_color(worn[2])
	Globals.active_cosmetic_hat = worn[0]
	Globals.active_cosmetic_glasses = worn[1]

# Every tile, swatch and Overtime button stays on the 960x540 canvas, clear of
# the game's fixed controls and of each other; the panel is their backdrop.
func _overlaps(name: String) -> void:
	var ui: Control = get_tree().current_scene.get_node("ui")
	var boxes := []
	for n in ui.get_children():
		var nm := str(n.name)
		if nm.begins_with("rect") or nm.begins_with("XcTile_"):
			boxes.append([nm, Rect2(n.position, Vector2.ONE * 89.0 * n.scale.x)])
		elif nm.begins_with("suit color selection") or nm.begins_with("XcSwatch_") or nm.begins_with("OvertimeMixedSuit"):
			boxes.append([nm, Rect2(n.position, n.size)])
	var panel: Control = ui.get_node("NinePatchRect misc under outline")
	var fixed := {}
	for path in ["NinePatchRect character preview", "NinePatchRect save and exit", "NinePatchRect reset button"]:
		var c: Control = ui.get_node(path)
		fixed[path] = Rect2(c.global_position, c.size)
	for path in ["info label selection", "info label color", "info label hat", "info label glasses"]:
		var l: Label = ui.get_node(path)
		fixed[path] = Rect2(l.global_position, l.get_minimum_size())
	var screen := Rect2(0, 0, 960, 540)
	var bad := []
	var panel_rect := Rect2(panel.position, panel.size)
	if not screen.encloses(panel_rect):
		bad.append(["panel", "off screen"])
	for f in fixed:
		if panel_rect.intersects(fixed[f]):
			bad.append(["panel", f])
	for i in boxes.size():
		var r: Rect2 = boxes[i][1]
		if not screen.encloses(r):
			bad.append([boxes[i][0], "off screen"])
		for f in fixed:
			if r.intersects(fixed[f]):
				bad.append([boxes[i][0], f])
		for j in range(i + 1, boxes.size()):
			if r.intersects(boxes[j][1]):
				bad.append([boxes[i][0], boxes[j][0]])
		say("box %s %s" % [name, boxes[i]])
	say("box %s panel %s" % [name, panel_rect])
	ok("%s: %d boxes, no overlaps" % [name, boxes.size()], boxes.size() >= 25 and bad.is_empty(), bad)

# Each tile's own preview, read back: how much of it the item covers, the
# item's mean brightness, and how far its middle sits from the tile's centre
# (fractions of the tile). Pixels count as the item above LIT luma.
const LIT := 0.06

func _tile_light(sel: Node) -> void:
	for inst in sel.cosmetic_selection_parent.get_children():
		if not "cosmetic_holder_parent" in inst:
			continue
		var id := ""
		for item in inst.cosmetic_holder_parent.get_children():
			if item is Node3D and item.visible:
				id = str(item.name)
		var img: Image = inst.assigned_viewport.get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		var n := 0
		var sum := 0.0
		var cx := 0.0
		var cy := 0.0
		for y in h:
			for x in w:
				var l := img.get_pixel(x, y).get_luminance()
				if l > LIT:
					n += 1
					sum += l
					cx += x
					cy += y
		var cover := float(n) / (w * h)
		say("tile %s size=%dx%d cover=%.3f luma=%.3f offset=(%+.3f,%+.3f)" % [id, w, h, cover,
			sum / maxi(n, 1), (cx / maxi(n, 1)) / w - 0.5 if n else 0.0, (cy / maxi(n, 1)) / h - 0.5 if n else 0.0])
		img.save_webp(out_dir.path_join("shots").path_join("tile_%s.webp" % id), true, 0.9)
