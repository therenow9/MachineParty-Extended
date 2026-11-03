extends SceneTree

# [MP8] Runtime parse check of the patched scripts, run through tools\parsecheck.ps1. gdre's compile
# does not resolve base-class identifiers, so `self.global_transform` in a Minigame (a Node) compiles
# and packs clean but fails to load in game. This mounts the patched PCK, so global class names
# resolve, and feeds each .gd under patch\ to GDScript.reload(); a non-zero exit means a failure.


# The game's 18 autoloads, from its project.binary. The parser knows these names only from the
# "autoload/*" project settings; unregistered, GameManager, PauseMenu and the rest read as undeclared.
const AUTOLOADS := {
	"AchievementManager": "*res://autoloads/achievement_manager.gd",
	"CursorManager": "*res://autoloads/cursor_manager.tscn",
	"DebugTools": "*res://autoloads/debug_tools.tscn",
	"DecalManager": "*res://autoloads/decal_manager.tscn",
	"EffectManager": "*res://autoloads/effect_manager.tscn",
	"GameManager": "*res://autoloads/game_manager.gd",
	"GlobalOverlay": "*res://modules/global_overlay/global_overlay.tscn",
	"Globals": "*res://autoloads/globals.gd",
	"LocalizationDebugMenu": "*res://scenes/localization_debug_menu.tscn",
	"MultiplayerInput": "*res://addons/multiplayer_input/multiplayer_input.gd",
	"MusicManager": "*res://autoloads/music_manager.tscn",
	"NetworkManager": "*res://modules/multiplayer/network_manager.gd",
	"PauseMenu": "*res://modules/pause_menu/pause_menu.tscn",
	"PlayerManager": "*res://autoloads/player_manager.tscn",
	"PropManager": "*res://autoloads/prop_manager.tscn",
	"Shaker": "*res://addons/shaker/src/Shaker.gd",
	"SoundManager": "*res://autoloads/sound_manager.tscn",
	"Steamworks": "*res://modules/steamworks/steamworks.gd",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		printerr("Use tools/parsecheck.ps1 -Pck <path> to provide the PCK and patch directory")
		quit(2)
		return
	if not ProjectSettings.load_resource_pack(args[0], true):
		printerr("Failed to mount the PCK: ", args[0])
		quit(2)
		return

	if args.size() == 3 and not ProjectSettings.load_resource_pack(args[2], true):
		printerr("Failed to mount the candidate overlay: ", args[2])
		quit(2)
		return

	# Registered after mounting the PCK: the paths are inside it.
	for k in AUTOLOADS:
		ProjectSettings.set_setting("autoload/" + k, AUTOLOADS[k])

	# MP8_CHECK_DIR=src\ runs the unpatched scripts as a baseline: only errors the patched run reports
	# and the baseline does not are ours.
	var scan_dir := OS.get_environment("MP8_CHECK_DIR")
	if scan_dir.is_empty():
		scan_dir = args[1]

	var files: Array[String] = []
	_collect(scan_dir, files)
	files.sort()
	print("Scanning:", scan_dir)

	print("== Parse self-check: %d patched scripts ==" % files.size())
	var bad: Array[String] = []

	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src.is_empty():
			print("  ?? cannot read  %s" % f)
			bad.append(f)
			continue

		# The separator goes to stderr too, so each engine Parse Error can be tied to its file.
		printerr("---- ", f.get_file())

		var gd := GDScript.new()
		# class_name is blanked, since the PCK already registers the global class ("Class X hides a
		# global script class"); the line stays, so stderr's line numbers match the file.
		gd.source_code = _blank_class_name(src)
		# reload() prints parse errors to stderr; anything but OK is a failure.
		var err: int = gd.reload()
		if err != OK:
			print("  ❌ parse failed(err=%d)  %s" % [err, f.get_file()])
			bad.append(f)
		else:
			print("  ✓  %s" % f.get_file())

	print("")
	if bad.is_empty():
		print("All passed: %d scripts parse" % files.size())
		quit(0)
	else:
		print("%d scripts failed to parse; do not run this PCK:" % bad.size())
		for f in bad:
			print("   - %s" % f.get_file())
		quit(1)


func _blank_class_name(src: String) -> String:
	var lines := src.split("\n")
	var inline_base := RegEx.new()
	inline_base.compile("^\\s*class_name\\s+\\w+\\s+extends\\s+(.+)$")
	for i in lines.size():
		if lines[i].strip_edges().begins_with("class_name "):
			# Keep an inline base class; removing the whole line silently changes
			# Node-derived scripts into RefCounted and hides real scope errors.
			var declaration := inline_base.search(lines[i])
			lines[i] = "extends " + declaration.get_string(1) if declaration != null else ""
	return "\n".join(lines)


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_collect(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
