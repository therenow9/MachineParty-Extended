extends Node

# Dev-only and windowed, beside a launch (run_playtest.sh launch <M> --extra tools/selftest/perf_probe): where a
# minigame's frame goes. Never ships, and changes nothing the game keeps: every ablation is put back.
#   PERF_PROBE=inventory   at each minigame load + 12 s: every SubViewport (size, update mode, measured CPU/GPU ms,
#                          visible and shadow draw calls), every shadowed light, the environments' effects
#   PERF_PROBE=ablate      the inventory, then in play: a 4 s baseline, then 4 s with one cost switched off, in turn
#                          (PERF_ABLATE=a,b,... picks them; default all of ABLATIONS), each against the baselines
#                          either side. The game's frame time is the measure; the windows' first 0.75 s are dropped.
#                          Also: root3d (the window draws no 3D; on 8 Player Support 0.8.0+ the build already does
#                          so under a tile cover, and the inventory notes it), svp=<text> (the SubViewports whose path holds it).
#                          PERF_REPEAT=N runs the whole list N times, for minigames whose frame time drifts.
#   PERF_PROBE=shots       the inventory, then with the tree paused: window shots as is, the next frame, and with
#                          root3d, omni_paraboloid and omni_shadows each applied alone
# PERF_START_S=<s> starts any mode that many seconds after the load instead of 12.
# Results go to %TEMP%/machine-party-tests/perf_probe/<started>_<minigame>.txt.

const ABLATIONS := ["tiles_but_p1", "omni_shadows", "dir_shadows", "all_lights", "env_effects", "other_subviewports",
	"omni_paraboloid", "tile_atlas_1024", "bots", "mods_process"]
const WINDOW_S := 4.0
const SETTLE_S := 0.75
const START_AFTER_S := 12.0

var _mode := ""
var _ablations: Array = []
var _dir := ""
var _out: FileAccess = null
var _mg: Node = null
var _mg_t := 0.0
var _inventoried := false
var _measured: Dictionary = {}
var _queue: Array = []
var _step := ""
var _step_t := 0.0
var _frames: Array = []
var _draws: Array = []
var _gpu: Array = []
var _cpu: Array = []
var _states: Dictionary = {}
var _undo: Array = []
var _vps: Array = []

func _mod_ready(_loader) -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mode = OS.get_environment("PERF_PROBE")
	if _mode == "":
		_mode = "inventory"
	var picked := OS.get_environment("PERF_ABLATE")
	_ablations = ABLATIONS.duplicate() if picked == "" else Array(picked.split(","))
	_dir = OS.get_environment("TEMP").path_join("machine-party-tests/perf_probe")
	DirAccess.make_dir_recursive_absolute(_dir)
	get_tree().node_added.connect(_on_node_added)

func say(msg: String) -> void:
	if _out != null:
		_out.store_line(msg)
		_out.flush()

func _on_node_added(node: Node) -> void:
	if node is SubViewport:
		_measure(node)
	if node is Minigame and node != _mg:
		_mg = node
		_mg_t = 0.0
		_inventoried = false
		_queue.clear()
		_step = ""
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
		_out = FileAccess.open(_dir.path_join("%s_%s.txt" % [stamp, node.name]), FileAccess.WRITE)
		say("# perf_probe %s, minigame %s, window %s, renderer %s" % [_mode, node.name,
			get_window().size, RenderingServer.get_video_adapter_name()])

func _measure(v: Viewport) -> void:
	if not _measured.has(v.get_instance_id()):
		_measured[v.get_instance_id()] = true
		RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)

func _process(delta: float) -> void:
	if not is_instance_valid(_mg) or not _mg.is_inside_tree():
		if _step != "":
			_restore()
			_step = ""
		return
	_mg_t += delta
	if _mg_t < (float(OS.get_environment("PERF_START_S")) if OS.get_environment("PERF_START_S") != "" else START_AFTER_S):
		return
	if not _inventoried:
		_inventoried = true
		_inventory()
		if _mode == "shots":
			_shots()
		if _mode == "ablate":
			for r in maxi(int(OS.get_environment("PERF_REPEAT")), 1):
				for a in _ablations:
					_queue.append("base")
					_queue.append(a)
			_queue.append("base")
		return
	if _step == "" and _queue.is_empty():
		return
	if _step == "":
		_begin(_queue.pop_front())
		return
	_step_t += delta
	if _step_t >= SETTLE_S:
		_sample(delta)
	if _step_t >= WINDOW_S:
		_report()
		_restore()
		_step = ""

func _begin(step: String) -> void:
	_step = step
	_step_t = 0.0
	_frames.clear()
	_draws.clear()
	_gpu.clear()
	_cpu.clear()
	_states.clear()
	_undo.clear()
	if step != "base":
		_apply(step)
	_vps = _viewports()

func _sample(delta: float) -> void:
	_frames.append(delta * 1000.0)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var gpu := 0.0
	var cpu := 0.0
	for v in _vps:
		if not is_instance_valid(v):
			continue
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(v.get_viewport_rid())
	_gpu.append(gpu)
	_cpu.append(cpu)
	var st := _mg_state()
	_states[st] = int(_states.get(st, 0)) + 1

func _report() -> void:
	say("window %-18s changed %3d frames %4d  median %6.2f ms  p90 %6.2f  mean %6.2f  draws %6.0f  vp_cpu %6.2f  vp_gpu %6.2f  states %s" % [
		_step, _undo.size(), _frames.size(), _pct(_frames, 0.5), _pct(_frames, 0.9), _mean(_frames), _mean(_draws),
		_mean(_cpu), _mean(_gpu), _states])

func _mg_state() -> String:
	var m = _mg.get("state_machine")
	if not is_instance_valid(m) or not (m is Node):
		return ""
	var c = m.get("current_state")
	return str(c.name) if is_instance_valid(c) and c is Node else ""

static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(int(q * s.size()), s.size() - 1)])

static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += float(x)
	return t / a.size()

func _all(cls: String) -> Array:
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children(true):
			stack.append(c)
	return out

# The rendering ones: the window and every SubViewport whose update mode can draw this frame.
func _viewports() -> Array:
	var out: Array = [get_tree().root]
	for v in _all("SubViewport"):
		if v.render_target_update_mode == SubViewport.UPDATE_ALWAYS \
				or v.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE \
				or v.render_target_update_mode == SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
			_measure(v)
			out.append(v)
	return out

func _tiles() -> Array:
	var out: Array = []
	for n in _all("Node"):
		if n == _mg or _mg.is_ancestor_of(n):
			var v = n.get("local_viewport")
			if is_instance_valid(v) and v is SubViewport and not out.has(v):
				out.append(v)
	return out

func _info(v: Viewport, what: int, kind: int) -> int:
	return RenderingServer.viewport_get_render_info(v.get_viewport_rid(), what, kind)

func _inventory() -> void:
	var tiles := _tiles()
	for c in RenderingServer.frame_pre_draw.get_connections():
		if c["callable"].get_method() == &"_mp8_skip_covered_3d":
			say("NOTE 8 Player Support 0.8.0+ skips the window's 3D under a tile cover itself: root3d measures nothing here")
	say("## viewports (tiles: %d)" % tiles.size())
	var mpx := 0.0
	for v in _viewports():
		var rid: RID = v.get_viewport_rid()
		var size: Vector2i = v.size
		var line := "%s%s size %s" % ["TILE " if tiles.has(v) else "", v.get_path(), size]
		if v is SubViewport:
			mpx += size.x * size.y / 1000000.0
			line += " update %d own_world %s msaa %d taa %s ssaa %d scale %.2f atlas %d lod %.1f occl %s" % [
				v.render_target_update_mode, v.own_world_3d, v.msaa_3d, v.use_taa, v.screen_space_aa,
				v.scaling_3d_scale, v.positional_shadow_atlas_size, v.mesh_lod_threshold, v.use_occlusion_culling]
			var cam: Camera3D = v.get_camera_3d()
			line += " cam %s" % ("none" if cam == null else "%s mask %d" % [cam.name, cam.cull_mask])
			var parent: Node = v.get_parent()
			line += " parent %s" % (parent.get_class() if parent != null else "-")
			if parent is CanvasItem:
				line += " parent_visible %s" % parent.is_visible_in_tree()
		line += " | cpu %.2f gpu %.2f | draws vis %d shadow %d | objs vis %d shadow %d | prims vis %d shadow %d" % [
			RenderingServer.viewport_get_measured_render_time_cpu(rid), RenderingServer.viewport_get_measured_render_time_gpu(rid),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			_info(v, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)]
		say(line)
	say("subviewport mpx %.2f, total draws %d" % [mpx, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	say("## shadowed lights")
	for l in _all("Light3D"):
		if not l.shadow_enabled:
			continue
		var line := "%s %s visible %s energy %.2f layers %d cull %d" % [l.get_class(), l.get_path(), l.is_visible_in_tree(),
			l.light_energy, l.layers, l.light_cull_mask]
		if l is OmniLight3D:
			line += " range %.1f mode %d" % [l.omni_range, l.omni_shadow_mode]
		elif l is SpotLight3D:
			line += " range %.1f angle %.0f" % [l.spot_range, l.spot_angle]
		elif l is DirectionalLight3D:
			line += " mode %d max_dist %.0f" % [l.directional_shadow_mode, l.directional_shadow_max_distance]
		say(line)
	var unshadowed := 0
	for l in _all("Light3D"):
		if not l.shadow_enabled and l.is_visible_in_tree():
			unshadowed += 1
	say("unshadowed visible lights %d" % unshadowed)
	say("## environments")
	for e in _environments():
		say("%s ssao %s ssil %s ssr %s sdfgi %s glow %s fog %s vfog %s" % [e.resource_path if e.resource_path != "" else str(e),
			e.ssao_enabled, e.ssil_enabled, e.ssr_enabled, e.sdfgi_enabled, e.glow_enabled, e.fog_enabled, e.volumetric_fog_enabled])
	var meshes := 0
	var casters := 0
	for m in _all("GeometryInstance3D"):
		if m.is_visible_in_tree():
			meshes += 1
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
	say("visible geometry %d, shadow casters %d, particles %d, reflection probes %d, decals %d" % [meshes, casters,
		_all("GPUParticles3D").size() + _all("CPUParticles3D").size(), _all("ReflectionProbe").size(), _all("Decal").size()])
	_casters()
	_timestamps()

# Shadow casters grouped by their path with digits dropped (one line per kind of thing), heaviest first.
func _casters() -> void:
	var groups: Dictionary = {}
	var digits := RegEx.create_from_string("[0-9]+")
	for g in _all("GeometryInstance3D"):
		if not g.is_visible_in_tree() or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var parts: Array = Array(str(g.get_path()).split("/")).slice(3, 9)
		var key := digits.sub("/".join(parts), "#", true)
		var tris := 0
		var mesh: Mesh = null
		var copies := 1
		if g is MeshInstance3D:
			mesh = g.mesh
		elif g is MultiMeshInstance3D and g.multimesh != null:
			mesh = g.multimesh.mesh
			copies = g.multimesh.visible_instance_count if g.multimesh.visible_instance_count >= 0 else g.multimesh.instance_count
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				var n: int = mesh.surface_get_array_index_len(s)
				tris += (n if n > 0 else mesh.surface_get_array_len(s)) / 3
		var e: Array = groups.get(key, [0, 0, g.cast_shadow])
		e[0] += 1
		e[1] += tris * copies
		groups[key] = e
	var keys: Array = groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	say("## shadow casters by kind (count, triangles, cast mode), %d kinds" % keys.size())
	for i in mini(keys.size(), 30):
		say("%5d %9d %d  %s" % [groups[keys[i]][0], groups[keys[i]][1], groups[keys[i]][2], keys[i]])

# The tree paused, so only shaders' TIME moves: the window as it is, the next frame (the noise floor), then one
# variant at a time, each put back. PNGs beside the result; tools compare them.
func _shots() -> void:
	get_tree().paused = true
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var dir := _dir.path_join("shots_%s_%s" % [stamp, _mg.name])
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames_drawn(4)
	_shot(dir, "a_as_is")
	await _frames_drawn(1)
	_shot(dir, "b_as_is_next_frame")
	for step in ["root3d", "omni_paraboloid", "omni_shadows"]:
		_undo.clear()
		_apply(step)
		await _frames_drawn(3)
		_shot(dir, "c_" + step)
		_restore()
		await _frames_drawn(3)
	_shot(dir, "d_as_is_after")
	get_tree().paused = false
	say("shots in %s" % dir)

func _frames_drawn(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw

func _shot(dir: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))

func _environments() -> Array:
	var out: Array = []
	for w in _all("WorldEnvironment"):
		if w.environment != null and not out.has(w.environment):
			out.append(w.environment)
	for c in _all("Camera3D"):
		if c.environment != null and not out.has(c.environment):
			out.append(c.environment)
	return out

func _timestamps() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		say("timestamps: no RenderingDevice")
		return
	var n := rd.get_captured_timestamps_count()
	say("## timestamps: %d captured (frame %d)" % [n, rd.get_captured_timestamps_frame()])
	var prev := 0
	for i in n:
		var t := rd.get_captured_timestamp_gpu_time(i)
		say("%12d gpu delta (raw units)  %s" % [t - prev if i > 0 else 0, rd.get_captured_timestamp_name(i)])
		prev = t

func _change(obj: Object, prop: String, value) -> void:
	_undo.append([obj, prop, obj.get(prop)])
	obj.set(prop, value)

func _restore() -> void:
	for i in range(_undo.size() - 1, -1, -1):
		var u: Array = _undo[i]
		if is_instance_valid(u[0]):
			u[0].set(u[1], u[2])
	_undo.clear()

func _apply(step: String) -> void:
	match step:
		"tiles_but_p1":
			var tiles := _tiles()
			for i in range(1, tiles.size()):
				_change(tiles[i], "render_target_update_mode", SubViewport.UPDATE_DISABLED)
		"omni_shadows":
			for l in _all("Light3D"):
				if not (l is DirectionalLight3D) and l.shadow_enabled:
					_change(l, "shadow_enabled", false)
		"dir_shadows":
			for l in _all("DirectionalLight3D"):
				if l.shadow_enabled:
					_change(l, "shadow_enabled", false)
		"all_lights":
			for l in _all("Light3D"):
				if l.visible:
					_change(l, "visible", false)
		"env_effects":
			for e in _environments():
				for p in ["ssao_enabled", "ssil_enabled", "ssr_enabled", "sdfgi_enabled", "glow_enabled", "volumetric_fog_enabled"]:
					if e.get(p):
						_change(e, p, false)
		"other_subviewports":
			var tiles := _tiles()
			for v in _viewports():
				if v is SubViewport and not tiles.has(v):
					_change(v, "render_target_update_mode", SubViewport.UPDATE_DISABLED)
		"omni_paraboloid":
			for l in _all("OmniLight3D"):
				if l.shadow_enabled:
					_change(l, "omni_shadow_mode", OmniLight3D.SHADOW_DUAL_PARABOLOID)
		"tile_atlas_1024":
			for v in _tiles():
				_change(v, "positional_shadow_atlas_size", 1024)
		"bots":
			for n in _all("Node"):
				var s = n.get_script()
				if s != null and str(s.resource_path).ends_with("bot_manager.gd"):
					_change(n, "process_mode", Node.PROCESS_MODE_DISABLED)
		"mods_process":
			for n in _all("Node"):
				var s = n.get_script()
				if n != self and s != null and str(s.resource_path).contains("/mods/") \
						and not str(s.resource_path).contains("bot_") and not str(s.resource_path).contains("cl_playtest"):
					_change(n, "process_mode", Node.PROCESS_MODE_DISABLED)
		"root3d":
			_change(get_tree().root, "disable_3d", true)
		_:
			if step.begins_with("svp="):
				for v in _all("SubViewport"):
					if str(v.get_path()).contains(step.substr(4)):
						_change(v, "render_target_update_mode", SubViewport.UPDATE_DISABLED)
			else:
				say("unknown ablation %s" % step)
