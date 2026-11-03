extends Node

# Dev-only and windowed: Duck Hunt's look-speed prompt as the game draws it,
# with the vanilla glyphs, the GameCube L click / Z, and the D-pad a GameCube
# hunter sees, in every art set; then The Filter's briefing controls page.
# Saved to %TEMP%/machine-party-tests/gcs_render/.

const HUNTER := "res://minigames/duck_hunt/components/hunter_player/hunter_player.tscn"
const LB := "hires/controller_left_shoulder_button_wide_2x.png"
const RB := "hires/controller_right_shoulder_button_wide_2x.png"
const ARTS := ["classic", "outline", "authentic", "letters"]
const INTERMISSION := "res://minigames/intermission_new/intermission_new.tscn"

var fails := 0
var out: FileAccess
var _loader
var dir := OS.get_environment("TEMP").path_join("machine-party-tests/gcs_render")

func say(msg: String) -> void:
	if out == null:
		out = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("mods/gcs_render/result.txt"), FileAccess.WRITE)
	out.store_line(msg)
	out.flush()

func ok(label: String, cond, extra = "") -> void:
	if not cond: fails += 1
	say("%s %s  %s" % ["PASS" if cond else "FAIL", label, str(extra)])

func finish() -> void:
	say("DONE fails=%d" % fails)
	get_tree().quit()

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _mod_ready(loader) -> void:
	_loader = loader
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var api = _loader.registry("gamecube_support").get("api")
	ok("gamecube_support registered", api != null)
	if api == null:
		finish(); return
	ok("windowed", DisplayServer.get_name() != "headless", DisplayServer.get_name())
	DirAccess.make_dir_recursive_absolute(dir)
	var style0: String = api.config["style"]
	var art0: String = api.config["art"]

	get_tree().change_scene_to_packed(load(HUNTER))
	await frames(10)
	var hunter: Node = get_tree().current_scene
	hunter.camera.current = true
	hunter.hud.visible = true
	hunter.keyboard_sensitivity_prompt.visible = false
	hunter.controller_sensitivity_prompt.visible = true
	hunter.anim_sensitivity_prompt.play("show")
	await get_tree().create_timer(1.5).timeout
	var left: TextureRect = null
	var right: TextureRect = null
	for r in hunter.controller_sensitivity_prompt.find_children("*", "TextureRect", true, false):
		if r.texture == api.swapper.proxies[LB]: left = r
		if r.texture == api.swapper.proxies[RB]: right = r
	ok("found both shoulder slots", left != null and right != null)
	if left == null or right == null:
		finish(); return
	say("slots: %s and %s, window %s" % [left.size, right.size, get_viewport().get_visible_rect().size])

	api.set_style("xbox", false)
	await _shot("vanilla")
	api.set_style("gamecube", false)
	for art in ARTS:
		api.set_art(art, false)
		await _shot("now_" + art)
		var g: Dictionary = api.swapper.glyphs.get(art, {})
		ok("D-pad glyphs in %s" % art, g.has("Dpad_left_wide") and g.has("Dpad_right_wide"))
		if not g.has("Dpad_left_wide") or not g.has("Dpad_right_wide"):
			continue
		left.texture = g["Dpad_left_wide"]
		right.texture = g["Dpad_right_wide"]
		await _shot("dpad_" + art)
		left.texture = api.swapper.proxies[LB]
		right.texture = api.swapper.proxies[RB]
	await _briefing(api)
	api.set_style(style0, false)
	api.set_art(art0, false)
	finish()

# The Filter's briefing controls page, drawn by the game into the intermission
# screen's SubViewport, in every art set.
func _briefing(api) -> void:
	get_tree().change_scene_to_packed(load(INTERMISSION))
	await get_tree().create_timer(2.0).timeout
	var inter: Node = get_tree().current_scene
	var brief = inter.get("screen_briefing")
	ok("briefing screen found", brief != null)
	if brief == null:
		return
	GameManager.current_input_device = GameManager.InputDevice.Controller
	await brief.set_briefing_screen_info(Globals.MinigameIdentifier.BurnRecycle)
	var anim: AnimationPlayer = brief.anim_brief_screen
	anim.play("setup brief screen")
	anim.seek(anim.current_animation_length, true)
	brief.update_page_content()
	var n: Node = brief.brief_controls_container
	while n != null and not (n is SubViewport):
		if n is CanvasItem:
			n.visible = true
			n.modulate.a = 1.0
		n = n.get_parent()
	ok("briefing drawn in a SubViewport", n is SubViewport)
	if not (n is SubViewport):
		return
	var vp: SubViewport = n
	var rows: Array = brief.brief_controls_container.get_children()
	ok("briefing rows have the helper", rows.any(func(r): return r.get_node_or_null("GcBriefingGlyphs") != null), rows.size())
	await get_tree().create_timer(1.0).timeout
	api.set_style("xbox", false)
	await _vp_shot(vp, "brief_vanilla")
	api.set_style("gamecube", false)
	for art in ARTS:
		api.set_art(art, false)
		await _vp_shot(vp, "brief_" + art)

func _vp_shot(vp: SubViewport, name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	say("shot " + name)

func _shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	say("shot " + name)
