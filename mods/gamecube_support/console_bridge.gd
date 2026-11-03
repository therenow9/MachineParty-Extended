extends Node

# Adds `gc ...` commands to the Debug Console mod (~).
#
# The console has no command registry (its commands are a fixed match), so
# this swaps its LineEdit's text_submitted handler for a wrapper: lines that
# start with "gc" are ours, everything else goes to the console unchanged.
# Every console member used is checked first; if anything is missing the
# console is left untouched and the config file / hotkey still work.

var api            # main.gd node
var _con: Node
var _line: LineEdit
var _orig: Callable

func attach(console: Node) -> bool:
	if console == null or not console.has_method("_on_submit") or not console.has_method("_print"):
		return false
	var line = console.get("_input")
	if not (line is LineEdit):
		return false
	var orig := Callable(console, "_on_submit")
	if not line.text_submitted.is_connected(orig):
		return false
	line.text_submitted.disconnect(orig)
	line.text_submitted.connect(_on_submitted)
	_con = console
	_line = line
	_orig = orig
	return true

func detach() -> void:
	if _line != null and is_instance_valid(_line) and _line.text_submitted.is_connected(_on_submitted):
		_line.text_submitted.disconnect(_on_submitted)
		_line.text_submitted.connect(_orig)
	_line = null

func _exit_tree() -> void:
	detach()

func _on_submitted(text: String) -> void:
	var t := text.strip_edges()
	var head := t.get_slice(" ", 0).to_lower()
	if head != "gc":
		_orig.call(text)
		if head == "help":
			_con.call("_print", "gc: GameCube controller support (type 'gc help')")
		return
	_line.text = ""
	_con.call("_print", "> " + t)
	for out in api.run_command(t.split(" ", false).slice(1)):
		_con.call("_print", out)
	_line.grab_focus()
