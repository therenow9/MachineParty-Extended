extends Node

# Child of a LocalLobbyPlayerControls panel. A pad (or the keyboard) that drops out and joins again
# in the same lobby gets back the outfit it last wore there; the game's join starts it on no hat, no
# glasses and the seat's colour. Kept on the lobby node, so a new lobby (after a match, or a new
# session) starts fresh, and the game's own rejoin after a match is left to the game.

const OUTFITS_META := &"couch_lobby_outfits"

var controls: Control
var _seated = null   # the device seated here, null while the seat is empty

func _ready() -> void:
	controls = get_parent()

func _process(_delta: float) -> void:
	if controls.assigned_player_id < 0:
		_seated = null
		return
	var outfits = _outfits()
	if outfits == null:
		return
	var device: int = controls.device
	var assigner = controls.customization_assigner
	if _seated != device:
		_seated = device
		if outfits.has(device):
			var o: Array = outfits[device]
			assigner.assign_hat(o[0])
			assigner.assign_glasses(o[1])
			assigner.assign_suit_color(o[2])
	outfits[device] = [str(assigner.get_assigned_hat()), glasses_of(assigner.bone_attachment_glasses), assigner.assigned_suit_color]

static func glasses_of(attachment: Node) -> String:
	for child in attachment.get_children():
		if child.visible:
			return str(child.name)
	return "none"

# device -> [hat, glasses, suit colour], shared by every panel of this lobby.
func _outfits():
	var lobby := controls.get_parent()
	while lobby != null and not "local_lobby_player_controls" in lobby:
		lobby = lobby.get_parent()
	if lobby == null:
		return null
	if not lobby.has_meta(OUTFITS_META):
		lobby.set_meta(OUTFITS_META, {})
	return lobby.get_meta(OUTFITS_META)
