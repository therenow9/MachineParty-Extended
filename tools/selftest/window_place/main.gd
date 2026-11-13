extends Node
# Dev-only, installed by the runners for every windowed run: keeps the game's window on the nearest screen
# starting left of the primary, at its height, found on each run, so it stays off the owner's main screen.
#   MP_WINDOW_SCREEN=primary  stay on the primary screen
#   MP_WINDOW_KEEP_SIZE=1     the runner was given --resolution: the window keeps its size
#   MP_WINDOW_FOCUS=none      unattended: the window can't take focus back, and the game keeps reading input
#                             while the owner works in another window (the runners set it; keep otherwise)

const CHECK_S := 0.5
const MAX_SIZE := Vector2i(1920, 1080)

var _target := -1
var _no_focus := false
var _left := 0.0

func say(msg: String) -> void:
	print("[window_place] ", msg)

func _mod_ready(_loader) -> void:
	_no_focus = OS.get_environment("MP_WINDOW_FOCUS") == "none"
	_target = _find_target()
	if _no_focus:
		# The game activates its window once at startup, before any mod runs; from here it can't take focus
		# again. A focus-out turns GameManager.game_focused off and every minigame then drops input
		# (game_manager.gd _on_window_focus_out), so it is set back once that handler has run.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		get_viewport().focus_exited.connect(_keep_focused, CONNECT_DEFERRED)
		_keep_focused()
	_place()

func _find_target() -> int:
	var primary := DisplayServer.get_primary_screen()
	if OS.get_environment("MP_WINDOW_SCREEN") == "primary":
		return primary
	# Positions are physical pixels but a scaled screen's size is not (a 4K at 160% reads 2400x1350), so
	# edges can't be matched: the nearest screen starting left of the primary, at its height, is the one.
	var p := Rect2i(DisplayServer.screen_get_position(primary), DisplayServer.screen_get_size(primary))
	var best := -1
	var rects := []
	for s in DisplayServer.get_screen_count():
		var at := DisplayServer.screen_get_position(s)
		rects.append("%d:%s" % [s, at])
		if s != primary and at.x < p.position.x and at.y < p.end.y \
				and (best < 0 or at.x > DisplayServer.screen_get_position(best).x):
			best = s
	if best < 0:
		say("WARN no screen left of the primary; staying on it (screen %d of %s)" % [primary, ", ".join(rects)])
		return primary
	return best

func _keep_focused() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.game_focused = true

# The main menu applies the saved display settings after _mod_ready (globals.gd set_fullscreen resizes the
# window on its current screen), so the screen is checked again for as long as the game runs.
func _place() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(_target)
	# A windowed game takes the size of the screen it started on, larger than some targets.
	var size := DisplayServer.window_get_size()
	if OS.get_environment("MP_WINDOW_KEEP_SIZE") != "1" and size != size.min(MAX_SIZE):
		say("NOTE window %s capped to %s (--resolution keeps a size)" % [size, size.min(MAX_SIZE)])
		size = size.min(MAX_SIZE)
		DisplayServer.window_set_size(size)
	var origin := DisplayServer.screen_get_position(_target)
	DisplayServer.window_set_position(origin + (DisplayServer.screen_get_size(_target) - size) / 2)
	await get_tree().process_frame
	say("WINDOW screen=%d at %s pos=%s size=%s no_focus=%s" % [_target, origin, DisplayServer.window_get_position(), DisplayServer.window_get_size(), _no_focus])

func _process(delta: float) -> void:
	# Captured or confined, the cursor would be held by a window the owner can't click back into.
	if _no_focus and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_left -= delta
	if _left > 0.0:
		return
	_left = CHECK_S
	if DisplayServer.window_get_current_screen() != _target:
		_place()
