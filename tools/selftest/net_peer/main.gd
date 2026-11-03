extends Node

# Dev-only driver for tools/run_online.sh: one online peer on this PC, over the game's own ENet debug lobby
# (res://scenes/debug_lobby/debug_lobby.tscn, multiplayer_menu.gd), which every build ships but no menu opens.
# It adds no @rpc and no node under a game node, so a peer running only this mod is the game's own wire.
# MP_NET (set by the runner, one per process): role=host|join;name=P1;seats=N;minigames=A,B|all;
#   spoof_tag=<tag> (send game_version+<tag>, as Extended before 0.22 did);hold=<s> (host: wait after seating, for a joiner
#   meant to be refused);cap=<s> (end the run that long into a minigame that hasn't ended);limit=<s>;
#   idle (no presses);diag (the picker's and briefing's state in each STATE line). Results go to
#   mods/net_peer/result.txt, one event a line.
# A trailer peer (run_online.sh --cast/--window/--record) adds: outfit=<hat>,<glasses>,<suit> (sent in the join
#   data, enet_backend.gd save_player_info); window=<x>,<y> (borderless, on top, 960x540 there; its lines carry
#   the frame and the Unix time); mute_music; audio_rec=<file.wav> (Master recorded, saved at the end).

const DEBUG_LOBBY := "res://scenes/debug_lobby/debug_lobby.tscn"
# The online players' gameplay actions (project.godot); pause, debug and menu actions are left out.
const PLAY_ACTIONS := ["confirm", "cancel", "space", "action_1", "action_2", "action_3", "action_4",
	"left_shoulder", "right_shoulder", "left_trigger", "right_trigger"]
const MOVE_ACTIONS := ["up", "down", "left", "right"]

var cfg := {}
var out: FileAccess
var _t0 := 0
var _last_minigame := -1
var _last_load := ""
var _ended := false
var _last_state := ""
var _last_scene := ""
var _load_ms := 0
var _loader
var _playing := false
var _mash_left := 0.0
var _move_left := 0.0
var _rng := RandomNumberGenerator.new()
var _rec: AudioEffectRecord
var _finishing := false
# When this load's host-side probe runs (ms), 0 once done.
var _probe_at := 0
# Long enough for the host's initialize and every client's sequence to land, even with 8 peers.
const PROBE_MS := 8000

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/net_peer/result.txt"), FileAccess.WRITE)
	# Before the event, so the runner's ' LOAD .*' and ' SCORES .*' comparisons with headless peers still match.
	var stamp := " f=%d u=%.3f" % [Engine.get_frames_drawn(), Time.get_unix_time_from_system()] if cfg.has("window") else ""
	var line := "%7.1f%s %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, stamp, msg]
	out.store_line(line)
	out.flush()
	print("[NETPEER] ", line)

func finish(why: String) -> void:
	if _finishing:
		return
	_finishing = true
	if _rec != null and _rec.is_recording_active():
		say("AUDIO_REC stop")
		_rec.set_recording_active(false)
		var wav := _rec.get_recording()
		var err := wav.save_to_wav(cfg["audio_rec"]) if wav != null else ERR_UNAVAILABLE
		say("AUDIO_REC saved=%s %s" % [err == OK, cfg["audio_rec"]])
	say("END %s" % why)
	# The runner stops ddagrab on this END line; the window stays up meanwhile, so the crop never shows the desktop.
	if cfg.has("window"):
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _mod_ready(loader) -> void:
	_loader = loader
	_t0 = Time.get_ticks_msec()
	for part in OS.get_environment("MP_NET").split(";", false):
		var kv := part.split("=", true, 1)
		cfg[kv[0]] = kv[1] if kv.size() > 1 else ""
	_rng.seed = hash(cfg.get("name", "P"))
	if cfg.has("mute_music"):
		var bus := AudioServer.get_bus_index("MUSIC")
		if bus >= 0:
			AudioServer.set_bus_mute(bus, true)
	if cfg.has("audio_rec"):
		_rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _rec)
		say("AUDIO_REC start")  # the WAV's first sample, on the u= clock
		_rec.set_recording_active(true)
	if cfg.has("window"):
		# The game stops taking presses on focus-out (game_manager.gd _on_window_focus_out), so a windowed
		# peer keeps it set while the owner uses the desktop.
		get_viewport().focus_exited.connect(func(): GameManager.game_focused = true, CONNECT_DEFERRED)
		GameManager.game_focused = true
	_run.call_deferred()

# The main menu applies the saved display settings on its _ready (options_handler.apply_settings), after
# _mod_ready, so the window is placed once the menu is up and again in the lobby. Position is in the
# primary screen's pixels, the ones ddagrab's output 0 crops.
func _place_window() -> void:
	var xy := String(cfg["window"]).split(",")
	var screen := DisplayServer.get_primary_screen()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	# Once the owner clicks away it can't take focus back, and _process keeps the mouse visible, so it never
	# holds the cursor the game captures in play (Chisel, Duck Hunt, cursor_manager.gd). It does take focus
	# once at startup: the game activates its window before any mod runs.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + Vector2i(int(xy[0]), int(xy[1])))
	await get_tree().process_frame
	say("WINDOW screen=%d at %s pos=%s size=%s" % [screen, DisplayServer.screen_get_position(screen), DisplayServer.window_get_position(), DisplayServer.window_get_size()])

# While a minigame plays, presses like a player who mashes: a held direction that changes about once
# a second and one or two other actions at a time, so idle-proof minigames end and the players' RPCs fire.
# Events, not Input.action_press: some players read presses in _unhandled_input (Table Manners).
func _process(delta: float) -> void:
	if cfg.has("window") and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _playing or cfg.has("idle"):
		return
	_move_left -= delta
	if _move_left <= 0.0:
		_move_left = _rng.randf_range(0.4, 1.4)
		_release(MOVE_ACTIONS)
		_press(MOVE_ACTIONS[_rng.randi() % MOVE_ACTIONS.size()])
	_mash_left -= delta
	if _mash_left <= 0.0:
		_mash_left = _rng.randf_range(0.08, 0.3)
		_release(PLAY_ACTIONS)
		for i in _rng.randi_range(0, 2):
			_press(PLAY_ACTIONS[_rng.randi() % PLAY_ACTIONS.size()])

func _press(action: String) -> void:
	if Input.is_action_pressed(action):
		return
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	e.strength = 1.0
	Input.parse_input_event(e)

func _release(actions: Array) -> void:
	for a in actions:
		if Input.is_action_pressed(a):
			var e := InputEventAction.new()
			e.action = a
			e.pressed = false
			Input.parse_input_event(e)

func _release_all() -> void:
	_release(PLAY_ACTIONS + MOVE_ACTIONS)

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	say("START role=%s name=%s version=%s mods=%s" % [cfg.get("role", "?"), cfg.get("name", "?"), Globals.game_version, ",".join(PackedStringArray(_loader.mod_list()))])
	if cfg.has("window"):
		say("WINDOW_FLAGS no_focus=%s borderless=%s on_top=%s mode=%d" % [DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS),
			DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP), DisplayServer.window_get_mode()])
	if cfg.has("mute_music"):
		var bus := AudioServer.get_bus_index("MUSIC")
		say("MUSIC %s" % ("muted" if bus >= 0 and AudioServer.is_bus_mute(bus) else "NOT muted (no MUSIC bus)" if bus < 0 else "NOT muted"))
	if cfg.has("spoof_tag"):
		Globals.game_version += "+" + cfg["spoof_tag"]
		say("VERSION sent as %s" % Globals.game_version)
	# The host's playlist only: a joiner gets it from the host (update_playlist_state_rpc), as in the game.
	if cfg.get("role") == "host":
		_set_playlist()
	Globals.skipping_intro_cutscene = true
	# Headless gets no window focus event, and the game gates players and the briefing's cooldown on it.
	GameManager.game_focused = true
	get_tree().create_timer(float(cfg.get("limit", "300"))).timeout.connect(func(): finish("TIMEOUT"))
	NetworkManager.join_allowed.connect(func(reconnect, in_progress, debug_only):
		say("JOINED%s reconnect=%s in_progress=%s" % [" SPECTATOR" if debug_only else "", reconnect, in_progress]))
	# A vanilla peer has 4 reasons and an Extended host can send a 5th (MP8RoomFull), so a value past this
	# peer's list prints as reason_<n>.
	NetworkManager.join_refused.connect(func(_id, reason):
		var names: Array = NetworkManager.RefuseReason.keys()
		say("REFUSED %s" % (names[reason] if reason is int and reason >= 0 and reason < names.size() else "reason_%s" % reason))
		get_tree().create_timer(1.0).timeout.connect(func(): finish("refused")))
	NetworkManager.on_peer_connected.connect(func(id): say("PEER+ %d" % id))
	NetworkManager.on_peer_disconnected.connect(func(id): say("PEER- %d" % id))
	NetworkManager.on_host_disconnected.connect(func(): say("HOST_GONE"); get_tree().create_timer(1.0).timeout.connect(func(): finish("host gone")))
	if cfg.has("window"):
		await _place_window()
	get_tree().change_scene_to_file(DEBUG_LOBBY)
	await get_tree().create_timer(1.5).timeout
	if cfg.has("window"):
		await _place_window()
	var lobby := get_tree().current_scene
	lobby.debug_lobby_handler.name_entry.text = cfg.get("name", "P")
	# A release build makes the Steam backend at startup (NetworkManager._ready). The game's create_backend
	# frees it on the first host or join, but Extended's debug lobby won't host while one exists.
	if NetworkManager.active_backend:
		NetworkManager.active_backend.free()
		NetworkManager.active_backend = null
	if cfg.has("outfit"):
		var o := String(cfg["outfit"]).split(",")
		Globals.active_cosmetic_hat = o[0]
		Globals.active_cosmetic_glasses = o[1]
		Globals.active_cosmetic_suit_color = o[2]
		say("OUTFIT %s" % ",".join(o))
	if cfg.get("role") == "host":
		lobby._on_host_button_pressed()
		say("HOSTING")
		var seats := int(cfg.get("seats", "2"))
		while _seated(lobby) < seats:
			await get_tree().create_timer(0.5).timeout
			if not is_instance_valid(lobby):
				return
		await get_tree().create_timer(2.0 + float(cfg.get("hold", "0"))).timeout
		if _seated(lobby) < 2:
			finish("alone")
			return
		say("STARTING seated=%d" % _seated(lobby))
		lobby._on_lobby_start_button_pressed()
	else:
		await get_tree().create_timer(float(cfg.get("delay", "3"))).timeout
		lobby._on_join_button_pressed()
		say("JOINING")
	while not _ended:
		await get_tree().create_timer(0.5).timeout
		_watch()

func _seated(lobby) -> int:
	return lobby.player_order_by_seat.values().filter(func(v): return v > 0).size()

func _set_playlist() -> void:
	var wanted: Array = []
	var names := String(cfg.get("minigames", "all"))
	if names == "all":
		wanted = Array(Globals.CustomMinigamesWhitelist)
	else:
		for n in names.split(",", false):
			if Globals.MinigameIdentifier.has(n):
				wanted.append(Globals.MinigameIdentifier[n])
			else:
				say("BAD minigame %s" % n)
	Globals.session_playlist.clear()
	for id in wanted:
		Globals.session_playlist.append(MinigameListResource.create(id, 1))

func _watch() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var sname := "%s pause=%s" % [scene.name, PauseMenu.active]
	if sname != _last_scene:
		_last_scene = sname
		say("SCENE %s" % sname)
	if scene.name == "MainMenu" and _last_minigame != -1:
		_ended = true
		finish("session over")
		return
	var sm = scene.get("state_machine")
	if sm != null and sm.get("current_state") != null:
		var im = scene.get("intermission_manager")
		var st := "%s paused=%s" % [sm.current_state.name, get_tree().paused]
		if im != null and cfg.has("diag"):
			var b = im.screen_briefing
			st += " icons=%d next=%s brief=%s/%s/%s/%s" % [im.picker.active_icons.size(), im.next_minigame_identifier, b.active, b.ready_button_press_allowed, b.is_ready, b.ready_button_on_cooldown]
		if st != _last_state:
			_last_state = st
			say("STATE %s" % st)
		var playing: bool = sm.current_state.name == "MinigamePlaying"
		if _playing and not playing:
			_release_all()
		_playing = playing
		if im != null and im.screen_briefing.active and not im.screen_briefing.is_ready and im.screen_briefing.ready_button_press_allowed and not im.screen_briefing.ready_button_on_cooldown:
			# The host syncs the scores just before each briefing (start_minigame_pick), so peers compare here.
			var scores: Dictionary = scene.total_score_by_network_id
			var ids := scores.keys()
			ids.sort()
			say("SCORES %s" % ",".join(PackedStringArray(ids.map(func(i): return "%d:%d" % [i, scores[i]]))))
			im.screen_briefing._on_ready_button_pressed()
			say("READY")
	var mg = scene.get("minigame")
	if mg != null and is_instance_valid(mg):
		var key := "%s r%d" % [Globals.MinigameIdentifier.keys()[Globals.current_minigame_identifier], Globals.current_minigame_round]
		if mg.get_instance_id() != _last_minigame or key != _last_load:
			_last_minigame = mg.get_instance_id()
			_last_load = key
			_load_ms = Time.get_ticks_msec()
			say("LOAD %s" % key)
			# What Extended's call sites choose by: a wrong answer silently sends the other path's calls.
			if NetworkManager.has_method("mp8_room_extended"):
				say("ROOM extended=%s peers=%d" % [NetworkManager.call("mp8_room_extended"), multiplayer.get_peers().size()])
			_probe_at = Time.get_ticks_msec() + PROBE_MS
		elif _probe_at > 0 and Time.get_ticks_msec() >= _probe_at:
			_probe_at = 0
			_probe(mg)
		elif _playing and cfg.has("cap") and Time.get_ticks_msec() - _load_ms > int(cfg["cap"]) * 1000:
			_ended = true
			finish("capped %s" % key)

# What each peer's own copy of an Extended minigame holds after its start, for the runner to compare with the
# host's: relay calls the host sends from initialize() run inside the last client's player_loaded RPC (PD19).
func _probe(mg) -> void:
	match Globals.MinigameIdentifier.keys()[Globals.current_minigame_identifier]:
		"ManufactureGun":
			var empties: int = mg.empty_desk_array.filter(func(d): return d != null and is_instance_valid(d) and not d.is_queued_for_deletion()).size()
			say("PROBE ManufactureGun own_bench=%s sequence=%d empty_desks=%d" % [mg.workstation != null, mg.item_sequence.size(), empties])
		"SpineBreaker":
			var devs = mg.get("_mp8_devices")
			if devs is Array:
				var at := PackedStringArray()
				for d in devs:
					if is_instance_valid(d):
						at.append("(%.2f, %.2f)%s" % [d.global_position.x, d.global_position.z, "" if d.visible else " hidden"])
				say("PROBE SpineBreaker devices=%d at %s" % [at.size(), " ".join(at)])
