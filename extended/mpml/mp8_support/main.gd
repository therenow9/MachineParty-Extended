extends Node

# MD5 checks bind to the original game build;
# overlay SHA256 detects damage/mixed files, not a trusted publisher identity.
const MOD_ID := "mp8_support"
const PACK := "mp8_support_overlay.zip"
const MANIFEST := "vanilla_md5.json"
# The online tag's prefix (network_manager's MP8_VERSION_TAG); the build writes it into the manifest too.
const TAG_PREFIX := "mp-extended-"
const SENTINELS := [
	"res://modules/multiplayer/network_manager.gd",
	"res://scripts/scenes/game/game.gd",
	"res://scenes/lobby/scripts/lobby_scene.gd",
]
const MESSAGES := {
	"LOADER_API": "Update MachinePartyModLoader; API 2 required.",
	"MOD_DIRECTORY": "Cannot locate the mp8_support mod folder.",
	"OVERTIME_PRESENT": "Overtime is installed too; remove one of the two. Machine Party: Extended stays off.",
	"INSTALLED_TWICE": "Machine Party: Extended is installed in two folders; delete one. This copy stays off.",
	"LOAD_ORDER": "Game scripts loaded too early; use priority -1000.",
	"MANIFEST_MISSING": "Missing package manifest. Download the complete package.",
	"MANIFEST_INVALID": "Invalid package manifest. Download the complete package.",
	"VANILLA_MISMATCH": "Game scripts differ. Restore vanilla before MPML or use a matching Machine Party: Extended release.",
	"OVERLAY_MISSING": "Missing overlay ZIP. Download the complete package.",
	"OVERLAY_SIZE": "Overlay size mismatch. Keep all files from the same package.",
	"OVERLAY_HASH": "Overlay SHA256 mismatch. Download the complete package.",
	"OVERLAY_LOAD": "Verified overlay could not be mounted.",
	"RELAY": "mp8_net.gd failed to load. Download the complete package.",
	"VERSION_MISMATCH": "Loaded version differs from mod.json. Replace the whole package.",
	"MOUNTED": "Overlay mounted; original scripts and package digest verified.",
	"READY": "Machine Party: Extended ready.",
}
const MAIN_MENU := "res://scenes/main_menu/scripts/main_menu.gd"
const TITLE_ART := "title_extended.png"
const RELAY := "mp8_net.gd"
# The word's centre from the logo's top left, in the menu's 960x540 pixels (tools/make_title.py).
const TITLE_CENTRE := Vector2(283.0, 91.5)
var _mounted: bool = false
var _title: Texture2D = null
var _relay_script: Script = null
var _hosted: Array[Node] = []

func _text(code: String) -> String:
	return str(MESSAGES.get(code, code))

func _valid_manifest(parsed) -> bool:
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("schema") != 1:
		return false
	if typeof(parsed.get("files")) != TYPE_DICTIONARY or parsed["files"].is_empty():
		return false
	if typeof(parsed.get("game_version")) != TYPE_STRING or not parsed["game_version"].begins_with(TAG_PREFIX):
		return false
	if typeof(parsed.get("overlay_sha256")) != TYPE_STRING:
		return false
	var digest: String = parsed["overlay_sha256"]
	if digest.length() != 64 or not digest.is_valid_hex_number(false):
		return false
	var size = parsed.get("overlay_size")
	if typeof(size) != TYPE_INT and typeof(size) != TYPE_FLOAT:
		return false
	if not is_finite(float(size)) or size <= 0 or size != floor(size):
		return false
	for path in parsed["files"]:
		if typeof(path) != TYPE_STRING or not path.begins_with("res://") or not path.ends_with(".gdc") or path.contains("..") or path.contains("\\"):
			return false
		var md5 = parsed["files"][path]
		if typeof(md5) != TYPE_STRING or md5.length() != 32 or not md5.is_valid_hex_number(false):
			return false
	return true

func _mod_init(loader) -> void:
	_mounted = false
	if loader.has_method("has_api") and not loader.call("has_api", 2):
		_fail(loader, "LOADER_API")
		return
	var directory: String = loader.dir_of(MOD_ID)
	if directory.is_empty():
		_fail(loader, "MOD_DIRECTORY")
		return
	var overtime := _installed_folder(directory.get_base_dir(), "overtime")
	if not overtime.is_empty():
		_fail(loader, "OVERTIME_PRESENT", "mods/" + overtime)
		return
	# The bundle's folder is named machine_party_extended, a build's mp8_support; the loader starts both
	# copies of one id, and two overlays would mount. An older copy without this check mounts alone.
	var twin := _installed_folder(directory.get_base_dir(), MOD_ID, directory.get_file())
	if not twin.is_empty():
		_fail(loader, "INSTALLED_TWICE", "mods/" + twin)
		return
	for path in SENTINELS:
		if ResourceLoader.has_cached(path):
			_fail(loader, "LOAD_ORDER", path)
			return
	var manifest_path := directory.path_join(MANIFEST)
	if not FileAccess.file_exists(manifest_path):
		_fail(loader, "MANIFEST_MISSING")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not _valid_manifest(parsed):
		_fail(loader, "MANIFEST_INVALID")
		return
	var mod_path := directory.path_join("mod.json")
	var mod_data = JSON.parse_string(FileAccess.get_file_as_string(mod_path)) if FileAccess.file_exists(mod_path) else null
	if typeof(mod_data) != TYPE_DICTIONARY or mod_data.get("id") != MOD_ID or typeof(mod_data.get("version")) != TYPE_STRING:
		_fail(loader, "VERSION_MISMATCH")
		return
	if _normalized_version(mod_data["version"]) != _normalized_version(parsed["game_version"]):
		_fail(loader, "VERSION_MISMATCH", str(mod_data["version"]) + " / " + str(parsed["game_version"]))
		return
	var pack := directory.path_join(PACK)
	if not FileAccess.file_exists(pack):
		_fail(loader, "OVERLAY_MISSING")
		return
	var file := FileAccess.open(pack, FileAccess.READ)
	if file == null:
		_fail(loader, "OVERLAY_MISSING")
		return
	var size := file.get_length()
	file.close()
	if size != int(parsed["overlay_size"]):
		_fail(loader, "OVERLAY_SIZE")
		return
	if FileAccess.get_sha256(pack).to_lower() != str(parsed["overlay_sha256"]).to_lower():
		_fail(loader, "OVERLAY_HASH")
		return
	# Each replaced game script must still match its vanilla MD5 before mounting; up to 3 mismatches are reported.
	var bad := PackedStringArray()
	for path in parsed["files"]:
		if not FileAccess.file_exists(path) or FileAccess.get_md5(path).to_lower() != str(parsed["files"][path]).to_lower():
			bad.append(path)
		if bad.size() == 3:
			break
	if not bad.is_empty():
		_fail(loader, "VANILLA_MISMATCH", ", ".join(bad))
		return
	# Every Extended call between peers goes through the relay, so without it Extended stays off.
	_relay_script = loader.compile(directory.path_join(RELAY))
	if _relay_script == null:
		_fail(loader, "RELAY")
		return
	if not ProjectSettings.load_resource_pack(pack, true):
		_fail(loader, "OVERLAY_LOAD")
		return
	_mounted = true
	loader.note("mp8_support: [MOUNTED] " + _text("MOUNTED") + " " + str(parsed["game_version"]))
	_hook_title(loader, directory)
	_host_init(loader, directory)

# A bundle carries its other mods in subfolders, whose mod.json the loader never reads (one level
# only), so they start here, in the loader's order, and only with the overlay mounted.
# Each finds its folder in the "mpml_dir" meta, since dir_of() knows only top-level mods.
func _host_init(loader, directory: String) -> void:
	var found: Array = []
	for sub in DirAccess.get_directories_at(directory):
		if sub.begins_with("."):
			continue
		var manifest := directory.path_join(sub).path_join("mod.json")
		if not FileAccess.file_exists(manifest):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if typeof(data) != TYPE_DICTIONARY:
			loader.note("mp8_support: skip %s: mod.json is not valid JSON" % sub)
			continue
		found.append({
			"id": str(data.get("id", sub)),
			"version": str(data.get("version", "0.0.0")),
			"entry": str(data.get("entry", "main.gd")),
			"priority": int(data.get("priority", 0)),
			"dir": directory.path_join(sub),
		})
	found.sort_custom(func(a, b):
		if a["priority"] == b["priority"]:
			return str(a["id"]) < str(b["id"])
		return a["priority"] < b["priority"])
	for m in found:
		# The loader starts a separate copy whatever happens here, so the bundle's stands down.
		var separate := _installed_folder(directory.get_base_dir(), m["id"])
		if not separate.is_empty():
			loader.note("mp8_support: mods/%s runs instead of this bundle's %s" % [separate, m["id"]])
			continue
		var script = loader.compile(str(m["dir"]).path_join(m["entry"]))
		if script == null:
			loader.note("mp8_support: skip %s: entry script failed" % m["id"])
			continue
		var node := Node.new()
		node.set_script(script)
		node.name = m["id"]
		node.set_meta("mpml_dir", m["dir"])
		_hosted.append(node)
		loader.note("mp8_support: hosting %s v%s" % [m["id"], m["version"]])
		if node.has_method("_mod_init"):
			node.call("_mod_init", loader)

# EXTENDED beside the main menu's logo, and our tag in its corner. The loader calls it on node_added,
# while the menu's children are still entering the tree; deferred, it runs after the menu's _ready has
# written the corner.
func _hook_title(loader, directory: String) -> void:
	if not loader.has_method("has_api") or not loader.has_api("on_scene_script"):
		loader.note("mp8_support: title word and version corner off")
		return
	var path := directory.path_join(TITLE_ART)
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if image == null:
		loader.note("mp8_support: title word off")
	else:
		_title = ImageTexture.create_from_image(image)
	loader.on_scene_script(MAIN_MENU, func(menu: Node): _add_title.call_deferred(menu))

func _add_title(menu: Node) -> void:
	if not is_instance_valid(menu) or not menu.is_inside_tree():
		return
	# Globals.game_version stays vanilla's for mixed rooms, so the corner gets the tag from here.
	var corner = menu.get("version_label")
	var nm := get_tree().root.get_node_or_null("NetworkManager")
	if corner is Label and nm != null and nm.has_method("mp8_full_version"):
		corner.text = nm.mp8_full_version()
	if _title == null:
		return
	var logo := menu.find_child("logo", true, false) as Control
	if logo == null or logo.get_parent().has_node("mp8_extended"):
		return
	var word := TextureRect.new()
	word.name = "mp8_extended"
	word.texture = _title
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word.scale = logo.scale
	word.position = logo.position + TITLE_CENTRE - _title.get_size() * logo.scale / 2
	logo.add_sibling(word)

# A folder scan, not has_mod(): the loader starts mp8_support before every other mod. Overtime
# must never mount beside it (both overlays replace the same scripts), and a hosted mod never
# starts beside its own separate copy. Never `skip`, the asking mod's own folder.
static func _installed_folder(mods_dir: String, id: String, skip: String = "") -> String:
	for sub in DirAccess.get_directories_at(mods_dir):
		if sub.begins_with(".") or sub == skip:
			continue
		var path := mods_dir.path_join(sub).path_join("mod.json")
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY and str(data.get("id", sub)) == id:
			return sub
	return ""

func _normalized_version(value: String) -> String:
	value = value.trim_prefix(TAG_PREFIX)
	var pieces := value.split("-", true, 1)
	var numbers := pieces[0].split(".")
	if numbers.size() == 3 and numbers[2] == "0":
		numbers.remove_at(2)
	return ".".join(numbers) + ("-" + pieces[1] if pieces.size() > 1 else "")

func _mod_ready(loader) -> void:
	if not _mounted:
		return
	var declared: String = "?"
	var data = JSON.parse_string(FileAccess.get_file_as_string(loader.dir_of(MOD_ID).path_join("mod.json")))
	if typeof(data) == TYPE_DICTIONARY:
		declared = str(data.get("version", "?"))
	# Each peer finds the relay by this path, so the name is fixed.
	var relay := Node.new()
	relay.set_script(_relay_script)
	relay.name = "MP8Net"
	get_tree().root.add_child.call_deferred(relay)
	var nm = get_tree().root.get_node_or_null("NetworkManager")
	var actual: String = str(nm.get("MP8_VERSION_TAG")) if nm != null else "?"
	if not actual.begins_with(TAG_PREFIX) or declared == "?" or _normalized_version(actual) != _normalized_version(declared):
		_fail(loader, "VERSION_MISMATCH", declared + " / " + actual)
	else:
		loader.note("mp8_support: [READY] " + _text("READY") + " " + actual)
	# As the loader does for its entry nodes: under it, named by id, then _mod_ready.
	for node in _hosted:
		loader.add_child(node)
		if node.has_method("_mod_ready"):
			node.call("_mod_ready", loader)

func _fail(loader, code: String, detail: String = "") -> void:
	var message := "[MP8:" + code + "] " + _text(code)
	if not detail.is_empty():
		message += " " + detail
	loader.note("mp8_support: " + message)
	printerr(message)
