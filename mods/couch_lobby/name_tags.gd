extends RefCounted

# The couch's saved names, most recently used first; the order is the only state kept.
# The file is written when the list changes, never on load: entries that fail the
# checks are dropped in memory only, and a first launch leaves the saves folder alone.

const MAX_LETTERS := 7
const CAP := 50
const KEY := "saved_names"

signal changed

var names: Array = []
var persist := true
var path := ""
var _keep_original := false

# The spinners make only A-Z; anything else (the game's "P1", vanilla's "P-1") is a default.
static func is_saveable(n) -> bool:
	if not (n is String) or n.length() < 1 or n.length() > MAX_LETTERS:
		return false
	for i in n.length():
		var c: int = n.unicode_at(i)
		if c < 65 or c > 90:
			return false
	return true

static func validated(data) -> Dictionary:
	var out := []
	if not (data is Dictionary) or not (data.get(KEY) is Array):
		return {"names": out, "ok": false}
	var ok := true
	for n in data[KEY]:
		if not is_saveable(n) or out.has(n):
			ok = false
		elif out.size() == CAP:
			return {"names": out, "ok": false}
		else:
			out.append(n)
	return {"names": out, "ok": ok}

static func remembered(list: Array, n: String, cap := CAP) -> Array:
	var out := forgotten(list, n)
	out.push_front(n)
	return out.slice(0, cap)

static func forgotten(list: Array, n: String) -> Array:
	return list.filter(func(x): return x != n)

# False when the file was there but some or all of it was unusable.
func load_from(p: String) -> bool:
	path = p
	names = []
	_keep_original = false
	if not FileAccess.file_exists(p):
		return true
	var json := JSON.new()
	var parsed := json.parse(FileAccess.get_file_as_string(p)) == OK
	var v := validated(json.data if parsed else null)
	names = v["names"]
	_keep_original = not v["ok"]
	return v["ok"]

func remember(n: String) -> void:
	if not is_saveable(n):
		return
	var next := remembered(names, n)
	if next == names:
		return
	names = next
	changed.emit()
	_save()

func forget(n: String) -> void:
	if not names.has(n):
		return
	names = forgotten(names, n)
	changed.emit()
	_save()

# Through a temporary file, so a crash mid-write never leaves half a list.
func _save() -> void:
	if not persist or path.is_empty():
		return
	# A hand edit that failed the checks survives the first save beside the file, to be fixed.
	if _keep_original:
		DirAccess.copy_absolute(path, path + ".bad")
		_keep_original = false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({KEY: names}, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(tmp, path)
