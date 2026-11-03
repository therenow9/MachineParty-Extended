extends Node

# Dev only (PC6): on every seat's tile, each cube's index and an arrow per stick direction to the
# cube a press picks (8 Player Support 0.10's screen pick, else InteractionHandler.segment_matrix);
# an arrow more than 60 degrees off its stick direction on screen is thick and reported. README, "chisel_map".
# CHISEL_MAP=play: no round time limit, small labels beside the cubes, arrows (diagonals white) only from the
# chisel's cube, no shots.

const HANDLER := "res://minigames/chisel_gauntlet_multiplayer/components/player/components/interaction_handler/interaction_handler.gd"
const GAUNTLET := "res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet.gd"
const PLAY := "play"
const SHOTS_SEC := [6, 10, 14, 18, 24]
const DIRS := {Vector2.UP: Color(1.0, 0.25, 0.25), Vector2.DOWN: Color(0.3, 0.55, 1.0), Vector2.LEFT: Color(0.3, 0.9, 0.35), Vector2.RIGHT: Color(1.0, 0.85, 0.2)}
const NAMES := {Vector2.UP: "up", Vector2.DOWN: "down", Vector2.LEFT: "left", Vector2.RIGHT: "right"}
# 8 Player Support 0.11's stick diagonals, drawn in play mode only.
const DIAGONALS := [Vector2(0.70710677, -0.70710677), Vector2(-0.70710677, -0.70710677), Vector2(0.70710677, 0.70710677), Vector2(-0.70710677, 0.70710677)]
const OFF_DEG := 60.0
const CROP_MARGIN := 24.0

var dir := OS.get_environment("TEMP").path_join("machine-party-tests/chisel_map")
var _overlays: Array = []
var _start := -1
var _shot := 0
var _busy := false
var _play := OS.get_environment("CHISEL_MAP") == PLAY
var _gauntlet: Node

class Overlay extends Control:
	var handler: Node
	var vp: SubViewport
	var seat := ""
	var play := false
	var off_edges := PackedStringArray()
	var links := {}  # cube -> {direction name: cube} as a pad press goes now

	func _process(_d: float) -> void:
		size = Vector2(vp.size)
		queue_redraw()

	func points() -> Dictionary:
		var cam: Camera3D = vp.get_camera_3d()
		var segs: Dictionary = handler.segments_by_id
		var at := {}
		if cam == null:
			return at
		for i in segs:
			if is_instance_valid(segs[i]) and not cam.is_position_behind(segs[i].global_position):
				at[i] = cam.unproject_position(segs[i].global_position)
		return at

	func _draw() -> void:
		var at := points()
		if at.is_empty():
			return
		var segs: Dictionary = handler.segments_by_id
		var matrix: Dictionary = handler.get_script().get_script_constant_map()["segment_matrix"]
		var font := ThemeDB.fallback_font
		off_edges.clear()
		links.clear()
		var screen := handler.has_method("_mp8_screen_target")
		var cur = handler.highlighted_segment
		var cur_id: int = cur.index if is_instance_valid(cur) and cur.get("index") != null else -100
		for i in at:
			if play and i != cur_id:
				continue
			links[i] = {}
			for d in DIRS.keys() + (DIAGONALS if play else []):
				# The build's own pick; -3 (its MP8_NO_TARGET) or no build pick means the table decides.
				var to = handler._mp8_screen_target(segs[i], d) if screen else -3
				if typeof(to) != TYPE_INT or to == -3:
					to = matrix.get(i, {}).get(d)
				if typeof(to) != TYPE_INT or not at.has(to):
					continue
				links[i][NAMES.get(d, str(d))] = to
				var v: Vector2 = at[to] - at[i]
				var off := rad_to_deg(absf(v.angle_to(d)))
				var bad := off > OFF_DEG
				if bad:
					off_edges.append("%d %s -> %d (%.0f deg off)" % [i, NAMES.get(d, str(d)), to, off])
				if play:
					if i == cur_id:
						var tip2: Vector2 = v.normalized()
						var end: Vector2 = at[to] - tip2 * 3.0
						var col: Color = DIRS.get(d, Color.WHITE)
						draw_line(at[i] + tip2 * 3.0, end, col, 2.0, true)
						draw_line(end, end - tip2.rotated(0.5) * 6.0, col, 2.0, true)
						draw_line(end, end - tip2.rotated(-0.5) * 6.0, col, 2.0, true)
					continue
				var a: Vector2 = at[i] + v.normalized() * 9.0 + d.orthogonal() * 3.0
				var b: Vector2 = at[i] + v * 0.45 + d.orthogonal() * 3.0
				draw_line(a, b, DIRS[d], 4.0 if bad else 1.5, true)
				var tip := (b - a).normalized()
				draw_line(b, b - tip.rotated(0.5) * 6.0, DIRS[d], 2.0, true)
				draw_line(b, b - tip.rotated(-0.5) * 6.0, DIRS[d], 2.0, true)
		if play:
			for i in at:
				var active: bool = i < 0 or segs[i].get("active") != false
				var label := "S" if i == -1 else "R" if i == -2 else str(i)
				var col := Color(1, 1, 0.3) if i == cur_id else Color(1, 1, 1, 0.75) if active else Color(1, 0.4, 0.4, 0.6)
				draw_string_outline(font, at[i] + Vector2(5, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.8))
				draw_string(font, at[i] + Vector2(5, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
			return
		for i in at:
			var active: bool = i < 0 or segs[i].get("active") != false
			draw_circle(at[i], 8.0, Color(0, 0, 0, 0.7))
			var label := "S" if i == -1 else "R" if i == -2 else str(i)
			draw_string(font, at[i] + Vector2(-7, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 14, 12, Color.WHITE if active else Color(1, 0.4, 0.4))
		draw_string(font, Vector2(6, 16), "%s  up red, down blue, left green, right yellow; thick = >%d deg off" % [seat, int(OFF_DEG)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

func _mod_init(loader) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	loader.on_scene_script(HANDLER, _on_handler)
	if _play:
		loader.on_scene_script(GAUNTLET, func(n: Node) -> void: _gauntlet = n)

func _on_handler(handler: Node) -> void:
	_attach.call_deferred(handler)

# set_local_data gives the handler its tile a moment after it enters the tree.
func _attach(handler: Node) -> void:
	for i in 300:
		if not is_instance_valid(handler):
			return
		if handler.local_viewport != null and not handler.segments_by_id.is_empty():
			break
		await get_tree().process_frame
	if not is_instance_valid(handler) or handler.local_viewport == null:
		return
	var o := Overlay.new()
	o.handler = handler
	o.vp = handler.local_viewport
	o.seat = "device %d" % handler.device_id
	o.play = _play
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.vp.add_child(o)
	_overlays.append(o)
	if _start < 0:
		_start = Time.get_ticks_msec()

# _on_round_timer_tick ends the round when round_time_remaining reaches 0 (server only, as a local game is).
func _process(_d: float) -> void:
	if _play:
		if is_instance_valid(_gauntlet):
			_gauntlet.round_time_remaining = 999
		return
	if _start < 0 or _busy or _shot >= SHOTS_SEC.size():
		return
	if Time.get_ticks_msec() - _start >= SHOTS_SEC[_shot] * 1000:
		_shoot()

# Per seat: the tile with the arrows, then without them cropped round the block, with
# each cube's position in that crop (_chisel_map.json) for the decision page to draw on.
func _shoot() -> void:
	_busy = true
	var live: Array = _overlays.filter(func(o): return is_instance_valid(o))
	var tag := "%dseats_%02ds" % [live.size(), SHOTS_SEC[_shot]]
	get_viewport().get_texture().get_image().save_png(dir.path_join(tag + ".png"))
	var lines := PackedStringArray()
	var seats := {}
	for o in live:
		var name: String = o.seat.replace(" ", "")
		o.vp.get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [tag, name]))
		lines.append("%s: %d arrows off" % [o.seat, o.off_edges.size()])
		for e in o.off_edges:
			lines.append("  " + e)
		var at: Dictionary = o.points()
		if at.is_empty():
			continue
		o.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = o.vp.get_texture().get_image()
		o.visible = true
		var box := Rect2(at.values()[0], Vector2.ZERO)
		for v in at.values():
			box = box.expand(v)
		var r := Rect2i(box.grow(CROP_MARGIN).intersection(Rect2(Vector2.ZERO, Vector2(img.get_size()))))
		img.get_region(r).save_png(dir.path_join("%s_%s_clean.png" % [tag, name]))
		var pts := {}
		var act := {}
		for i in at:
			pts[str(i)] = [at[i].x - r.position.x, at[i].y - r.position.y]
			act[str(i)] = i < 0 or o.handler.segments_by_id[i].get("active") != false
		var links := {}
		for i in o.links:
			links[str(i)] = o.links[i]
		seats[name] = {"crop": [r.position.x, r.position.y, r.size.x, r.size.y], "tile": [img.get_width(), img.get_height()], "points": pts, "active": act, "off": Array(o.off_edges), "links": links, "screen": o.handler.has_method("_mp8_screen_target")}
	var f := FileAccess.open(dir.path_join(tag + "_report.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	var matrix := {}
	if not live.is_empty():
		var m: Dictionary = live[0].handler.get_script().get_script_constant_map()["segment_matrix"]
		for i in m:
			var row := {}
			for d in m[i]:
				row[NAMES[d]] = m[i][d]
			matrix[str(i)] = row
	var j := FileAccess.open(dir.path_join(tag + "_chisel_map.json"), FileAccess.WRITE)
	j.store_string(JSON.stringify({"seats": seats, "matrix": matrix}, " "))
	j.close()
	_shot += 1
	_busy = false
