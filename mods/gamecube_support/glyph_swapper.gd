extends RefCounted

# Takes over the game's controller prompt textures with live-swappable proxies.
#
# Each vanilla path under res://textures/ui/control/ is replaced in the
# resource cache by an AtlasTexture whose atlas starts as the vanilla texture.
# Scenes loaded afterwards (by path or uid://) get the proxy, so switching the
# proxy's atlas between vanilla and a GameCube glyph redraws every prompt that
# uses it, with no game scripts touched. AtlasTexture also avoids reading back
# the VRAM-compressed vanilla textures.

const BASE := "res://textures/ui/control/"

var proxies := {}     # rel path -> AtlasTexture (owns the res:// path)
var vanilla := {}     # rel path -> original Texture2D
var glyphs := {}      # art -> {glyph key -> ImageTexture}
var precached := PackedStringArray()
var problems := PackedStringArray()

func install(rel_paths: Array) -> void:
	for rel in rel_paths:
		var path: String = BASE + rel
		if ResourceLoader.has_cached(path):
			precached.append(rel)
		var tex = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
		if not (tex is Texture2D):
			problems.append("no vanilla texture at " + path)
			continue
		var proxy := AtlasTexture.new()
		proxy.atlas = tex
		proxy.region = Rect2(Vector2.ZERO, tex.get_size())
		proxy.take_over_path(path)
		proxies[rel] = proxy
		vanilla[rel] = tex

# Loads every <glyph_root>/<art>/<key>.png it finds. Missing files are fine:
# that slot just keeps the vanilla look in that art set.
func load_glyphs(glyph_root: String, arts: Array) -> void:
	for art in arts:
		var by_key := {}
		var dir := glyph_root.path_join(art)
		var d := DirAccess.open(dir)
		if d == null:
			problems.append("no glyph folder " + dir)
			glyphs[art] = by_key
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() != "png":
				continue
			var img := Image.load_from_file(dir.path_join(f))
			if img == null or img.is_empty():
				problems.append("unreadable glyph " + dir.path_join(f))
				continue
			img.generate_mipmaps()
			by_key[f.get_basename()] = ImageTexture.create_from_image(img)
		glyphs[art] = by_key

# Points every proxy at the GameCube glyph for its slot, or back at vanilla.
# slot_keys maps rel path -> glyph key. Returns how many proxies changed.
func apply(gamecube: bool, art: String, slot_keys: Dictionary) -> int:
	var changed := 0
	var by_key: Dictionary = glyphs.get(art, {})
	for rel in proxies:
		var target: Texture2D = vanilla[rel]
		if gamecube:
			var g = by_key.get(str(slot_keys.get(rel, "")))
			if g is Texture2D and Vector2i(g.get_size()) == Vector2i(target.get_size()):
				target = g
		var proxy: AtlasTexture = proxies[rel]
		if proxy.atlas != target:
			proxy.atlas = target
			proxy.region = Rect2(Vector2.ZERO, target.get_size())
			changed += 1
	return changed

# Glyphs whose size doesn't match the vanilla slot they'd replace.
func size_mismatches(slot_keys: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for art in glyphs:
		for rel in proxies:
			var g = glyphs[art].get(str(slot_keys.get(rel, "")))
			if g is Texture2D and Vector2i(g.get_size()) != Vector2i(vanilla[rel].get_size()):
				out.append("%s/%s for %s: %s vs %s" % [art, slot_keys[rel], rel, g.get_size(), vanilla[rel].get_size()])
	return out

# Paths where the resource cache no longer hands out our proxy
# (another mod or an early load took the path back).
func lost_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for rel in proxies:
		if ResourceLoader.load(BASE + rel) != proxies[rel]:
			out.append(rel)
	return out
