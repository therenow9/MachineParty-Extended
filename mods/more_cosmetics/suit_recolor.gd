extends RefCounted

# Paints our suit colors from an assigner's own red and blue suit textures, so
# any character whose textures differ gets its own. Texels that differ between
# red and blue are cloth; the rest (skin, belt, the "100") is copied from red.
# Cloth keeps red's painted shading: its value, max(r, g, b), relative to the
# cloth's mean value, scales the new color's mid-tone.

const MASK_DELTA := 24

var _cache := {}

# The cutoff pair when the assigner uses it, since vanilla falls back to the
# full blue there too. Null when the assigner has no textures to start from.
func texture_for(assigner: Object, color_id: String, mid_tone: Color) -> Texture2D:
	var cutoff: bool = assigner.use_cutoff_textures
	var red = assigner.suit_texture_cutoff_red if cutoff else assigner.suit_texture_red
	var blue = assigner.suit_texture_cutoff_blue if cutoff else assigner.suit_texture_blue
	return texture_for_pair(red, blue, color_id, mid_tone)

# Keyed by the source textures, so the collar race's legs, which load the
# body's own full red and blue, share the body's result.
func texture_for_pair(red, blue, color_id: String, mid_tone: Color) -> Texture2D:
	if not (red is Texture2D and blue is Texture2D):
		return null
	var key := "%d:%d:%s" % [red.get_instance_id(), blue.get_instance_id(), color_id]
	if not _cache.has(key):
		var img := recolor(red.get_image(), blue.get_image(), mid_tone)
		_cache[key] = ImageTexture.create_from_image(img) if img != null else null
	return _cache[key]

# RGB8, the same size as red and without mipmaps, like the game's suit textures.
static func recolor(red: Image, blue: Image, mid_tone: Color) -> Image:
	if red == null or blue == null or red.is_empty() or red.get_size() != blue.get_size():
		return null
	var a := _rgb8(red)
	var b := _rgb8(blue)
	if a == null or b == null:
		return null
	var da := a.get_data()
	var mask := cloth_mask(da, b.get_data())
	var total := 0
	var count := 0
	for i in mask.size():
		if mask[i] != 0:
			var o := i * 3
			total += maxi(da[o], maxi(da[o + 1], da[o + 2]))
			count += 1
	if count == 0:
		return a
	var lut := shade_table(mid_tone, float(total) / count)
	for i in mask.size():
		if mask[i] != 0:
			var o := i * 3
			var v := maxi(da[o], maxi(da[o + 1], da[o + 2])) * 3
			da[o] = lut[v]
			da[o + 1] = lut[v + 1]
			da[o + 2] = lut[v + 2]
	return Image.create_from_data(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8, da)

# One byte per texel, 1 where red and blue differ by more than MASK_DELTA.
static func cloth_mask(red_rgb: PackedByteArray, blue_rgb: PackedByteArray) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(red_rgb.size() / 3)
	for i in mask.size():
		var o := i * 3
		if absi(red_rgb[o] - blue_rgb[o]) + absi(red_rgb[o + 1] - blue_rgb[o + 1]) + absi(red_rgb[o + 2] - blue_rgb[o + 2]) > MASK_DELTA:
			mask[i] = 1
	return mask

# RGB for each value 0..255: the mid-tone at the cloth's mean value, scaled.
static func shade_table(mid_tone: Color, mean_value: float) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(768)
	var mean := maxf(mean_value, 1.0)
	for v in 256:
		var k := v / mean
		lut[v * 3] = clampi(roundi(mid_tone.r8 * k), 0, 255)
		lut[v * 3 + 1] = clampi(roundi(mid_tone.g8 * k), 0, 255)
		lut[v * 3 + 2] = clampi(roundi(mid_tone.b8 * k), 0, 255)
	return lut

static func _rgb8(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return null
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	return img
