extends RefCounted

# Stands in for Offline Bots' bot_identity.gd, whose brain calls only roll_outfit and assign_names
# (bot_manager.gd:343-346). Each slot takes its least-used value among the other bots and seated humans,
# so every value is used once before any repeats; a hat that blocks glasses gets "none".
# With a trailer cast (tools/trailer_cast), bots take seats 2-8 of it in order instead: the brain rolls each
# bot's outfit in seat order with the earlier bots' outfits as taken_outfits.

static var base: GDScript
static var cast: Array = []
static var hats: Array = []
static var glasses: Array = []
static var colors: Array = []
static var no_glasses_hats: Array = []

# The local lobby's name entry: 4 letters from A to Z (local_lobby_player_name_character_selector.gd).
static func assign_names(bots: Array, total: int) -> Array:
	var out: Array = []
	if not cast.is_empty():
		for i in bots.size():
			out.append(str(cast[mini(i + 1, cast.size() - 1)]["short"]).to_upper())
		return out
	for full in base.assign_names(bots, total):
		var short := _short(full)
		for i in 40:
			if not out.has(short):
				break
			short = _short(base.roll_name([]))
		out.append(short)
	return out

static func _short(full: String) -> String:
	var letters := ""
	for c in full.to_upper():
		if c >= "A" and c <= "Z":
			letters += c
	return letters.left(4)

static func roll_outfit(taken_outfits: Array = []) -> Array:
	if not cast.is_empty():
		var c: Dictionary = cast[mini(taken_outfits.size() + 1, cast.size() - 1)]
		return [str(c["hat"]), str(c["glasses"]), str(c["suit"])]
	var taken := _humans()
	for o in taken_outfits:
		if o is Array and o.size() == 3:
			taken["hats"].append(str(o[0]))
			taken["glasses"].append(str(o[1]))
			taken["colors"].append(str(o[2]))
	var h: String = _pick(hats, taken["hats"])
	var g: String = "none" if no_glasses_hats.has(h) else _pick(glasses, taken["glasses"])
	return [h, g, _pick(colors, taken["colors"])]

static func _pick(pool: Array, taken: Array) -> String:
	var least: int = pool.map(func(x): return taken.count(x)).min()
	return str(pool.filter(func(x): return taken.count(x) == least).pick_random())

# The local lobby's human seats, read from their models as Better Couch Lobby reads glasses.
static func _humans() -> Dictionary:
	var out := {"hats": [], "glasses": [], "colors": []}
	var lobby = (Engine.get_main_loop() as SceneTree).current_scene
	if lobby == null or not ("player_data" in lobby):
		return out
	for seat in lobby.player_data:
		var d = lobby.player_data[seat]
		if d is Dictionary and d.get("is_bot", false):
			continue
		var a = lobby.local_lobby_player_controls[seat].customization_assigner
		out["hats"].append(str(a.get_assigned_hat()))
		out["colors"].append(str(a.assigned_suit_color))
		var worn := "none"
		for c in a.bone_attachment_glasses.get_children():
			if c.visible and glasses.has(str(c.name)):
				worn = str(c.name)
		out["glasses"].append(worn)
	return out
