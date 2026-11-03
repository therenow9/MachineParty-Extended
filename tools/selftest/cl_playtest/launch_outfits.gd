extends RefCounted

# The launch lane's outfits for every seat, humans and bots: hats all differ, glasses are random
# ("none" included, and always "none" under a hat that blocks them), suit colours differ while they last.
# "none" counts as a hat only once the real hats run out. Pure, so the headless check calls it directly.

static func roll(n: int, hats: Array, glasses: Array, colors: Array, no_glasses_hats: Array, rng: RandomNumberGenerator) -> Array:
	var hat_pool: Array = real_hats(hats)
	var first: Array = _shuffled(hat_pool, rng)
	if n > first.size() and hats.has("none"):
		first.append("none")
	var hat_seq: Array = _cycled(first if not first.is_empty() else ["none"], n, rng)
	var color_seq: Array = _cycled(_distinct(colors), n, rng)
	var glasses_pool: Array = _distinct(glasses)
	if not glasses_pool.has("none"):
		glasses_pool.append("none")
	var out: Array = []
	for i in n:
		var hat: String = str(hat_seq[i])
		var worn: String = "none"
		if not no_glasses_hats.has(hat):
			worn = str(glasses_pool[rng.randi_range(0, glasses_pool.size() - 1)])
		var color = color_seq[i] if i < color_seq.size() else ""
		out.append([hat, worn, color])
	return out

static func real_hats(hats: Array) -> Array:
	return _distinct(hats).filter(func(h): return str(h) != "none")

static func _distinct(list: Array) -> Array:
	var out: Array = []
	for x in list:
		if not out.has(x):
			out.append(x)
	return out

# The pool once in a random order, then again reshuffled, until n values: each value is used once before any repeats.
static func _cycled(pool: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if pool.is_empty():
		return out
	while out.size() < n:
		out.append_array(_shuffled(pool, rng))
	out.resize(n)
	return out

static func _shuffled(list: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = list.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out
