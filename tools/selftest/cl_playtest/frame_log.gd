extends Node

# The launch lane's frame log: one CSV row per wall-clock second, with every frame's time in the last column,
# so tools/perf_summary.py computes exact percentiles. A frame's time is its _process delta (the time
# between frames as the game sees it). Lines starting with # are the setup and match notes.
# Runs while the game is paused (the pause menu) and after every other node of the frame (priority).
# render_cpu_ms and gpu_ms sum every measured viewport's render time (the window's and each SubViewport's, so a
# split screen's tiles count); the server reports a frame a few frames late, and headless reports 0.

const COLUMNS := ["t", "scene", "state", "mg_state", "round", "frames", "fps", "avg_ms", "p99_ms", "max_ms",
	"process_ms", "physics_ms", "render_cpu_ms", "gpu_ms", "draw_calls", "objects", "nodes", "video_mem_mb",
	"subviewports", "subviewport_mpx", "frame_ms"]

var path := ""
var rows := 0
var _file: FileAccess
var _start_usec := 0
var _window_usec := 0
var _frames: Array = []
var _process_sum := 0.0
var _physics_sum := 0.0
var _render_cpu_sum := 0.0
var _gpu_sum := 0.0
var _viewports: Array = []

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000

func open(file_path: String, header: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		return false
	path = file_path
	for line in header:
		_file.store_line("# " + str(line))
	_file.store_line(",".join(COLUMNS))
	_file.flush()
	_start_usec = Time.get_ticks_usec()
	_window_usec = _start_usec
	_measure(get_tree().root)
	for v in get_tree().root.find_children("*", "SubViewport", true, false):
		_measure(v)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	return true

func comment(line: String) -> void:
	if _file != null:
		_file.store_line("# " + line)
		_file.flush()

func _on_node_added(node: Node) -> void:
	if node is SubViewport and _file != null:
		_measure(node)

func _measure(v: Viewport) -> void:
	RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
	_viewports.append(v)

func close() -> void:
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _file == null:
		return
	if not _frames.is_empty():
		_write_row()
	_file.close()
	_file = null

func _process(delta: float) -> void:
	if _file == null:
		return
	_frames.append(delta * 1000.0)
	_process_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	for v in _viewports:
		if not is_instance_valid(v):
			continue
		var rid: RID = v.get_viewport_rid()
		_render_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if Time.get_ticks_usec() - _window_usec >= 1000000:
		_write_row()

func _write_row() -> void:
	var now := Time.get_ticks_usec()
	var s: Dictionary = stats(_frames)
	var n: int = _frames.size()
	var where: Dictionary = _where()
	_viewports = _viewports.filter(func(v): return is_instance_valid(v))
	var subs: Array = _rendering_subviewports()
	var fields: Array = [
		"%.2f" % ((now - _start_usec) / 1000000.0), where["scene"], where["state"], where["mg_state"], where["round"],
		n, "%.1f" % s["fps"], "%.2f" % s["avg_ms"], "%.2f" % s["p99_ms"], "%.2f" % s["max_ms"],
		"%.2f" % (_process_sum / n), "%.2f" % (_physics_sum / n), "%.2f" % (_render_cpu_sum / n), "%.2f" % (_gpu_sum / n),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"%.1f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		subs.size(), "%.2f" % (subs.reduce(func(a, v): return a + v.size.x * v.size.y, 0) / 1000000.0),
		" ".join(_frames.map(func(ms): return "%.2f" % ms)),
	]
	_file.store_line(row(fields))
	_file.flush()
	rows += 1
	_frames.clear()
	_process_sum = 0.0
	_physics_sum = 0.0
	_render_cpu_sum = 0.0
	_gpu_sum = 0.0
	_window_usec = now

# The SubViewports whose update mode lets them render (a split-screen tile, a monitor in the world), counted once a
# second; a when-visible one counts even while nothing shows it, so gpu_ms, not this count, is the measured cost.
func _rendering_subviewports() -> Array:
	var out: Array = []
	for v in _viewports:
		if v is SubViewport and v.is_inside_tree() and v.render_target_update_mode != SubViewport.UPDATE_DISABLED \
				and v.render_target_update_mode != SubViewport.UPDATE_ONCE:
			out.append(v)
	return out

# The current scene's file name; in the local game its state machine's state, the minigame's own state and round.
func _where() -> Dictionary:
	var out := {"scene": "", "state": "", "mg_state": "", "round": ""}
	# close() also runs from the mod's _exit_tree, when this node has already left the tree.
	if not is_inside_tree():
		return out
	var scene: Node = get_tree().current_scene
	if scene == null:
		return out
	out["scene"] = scene.scene_file_path.get_file().get_basename()
	out["state"] = _state_of(scene.get("state_machine"))
	# is_instance_valid before `is`: a repeat frees the old minigame a second before the new one is set, `is` on a
	# freed instance stops this function, and _write_row's typed Dictionary then crashes the release build.
	var mg = scene.get("minigame")
	if is_instance_valid(mg) and mg is Node:
		out["mg_state"] = _state_of(mg.get("state_machine"))
	var r = scene.get("session_current_minigame_round")
	if r != null:
		out["round"] = str(r)
	return out

static func _state_of(machine) -> String:
	if not is_instance_valid(machine) or not (machine is Node):
		return ""
	var current = machine.get("current_state")
	return str(current.name) if is_instance_valid(current) and current is Node else ""

# frames, fps (frames over the frames' own total time), mean, nearest-rank 99th percentile and max, in ms.
static func stats(frame_ms: Array) -> Dictionary:
	var n: int = frame_ms.size()
	if n == 0:
		return {"frames": 0, "fps": 0.0, "avg_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0}
	var sorted: Array = frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += float(ms)
	var rank: int = int(ceil(0.99 * n)) - 1
	return {
		"frames": n,
		"fps": n * 1000.0 / total if total > 0.0 else 0.0,
		"avg_ms": total / n,
		"p99_ms": float(sorted[clampi(rank, 0, n - 1)]),
		"max_ms": float(sorted[n - 1]),
	}

static func row(fields: Array) -> String:
	var out: Array = []
	for f in fields:
		var s: String = str(f)
		if s.contains(",") or s.contains("\"") or s.contains("\n"):
			s = "\"" + s.replace("\"", "\"\"") + "\""
		out.append(s)
	return ",".join(out)
