extends Node

# Child of a local lobby panel (the panels are the hook: Offline Bots replaces the
# lobby's script with a subclass). The game drops a player out with Start
# (local_leave); a GameCube pad also drops out with B on its name screen, where
# the game gives B nothing to do, so from the outfit panel it is B, then B.

var api  # gamecube_support's main.gd: detector, config

var _was_naming := false

func _process(_delta: float) -> void:
	var controls = get_parent()
	var naming: bool = controls.assigned_player_id >= 0 and controls.name_entry_selector.active
	var was := _was_naming
	_was_naming = naming
	if api == null or api.detector == null:
		return
	var device: int = controls.device
	var pressed: bool = naming and controls.is_joystick and MultiplayerInput.is_action_just_pressed(device, b_action(api.config["button_layout"]))
	if not drops_out(was, naming, controls.is_joystick and api.detector.is_gamecube(device), pressed):
		return
	var lobby = lobby_of(controls)
	if lobby == null or lobby.game_started or not lobby.active or not lobby.can_control:
		return
	var seat: int = controls.assigned_player_id
	# What the lobby's handle_leave_input does for Start.
	lobby.leave(seat)
	lobby._on_player_ready_changed(seat, false)

# Last frame's state too, so the B that opens the name screen from the outfit
# panel doesn't also drop the player out, whichever node runs first.
static func drops_out(was_naming: bool, naming: bool, gamecube: bool, b_pressed: bool) -> bool:
	return was_naming and naming and gamecube and b_pressed

# The game's back is action_2 (east); under "positional" GameCube B is west.
static func b_action(layout: String) -> StringName:
	return &"action_2" if layout == "nintendo" else &"action_3"

static func lobby_of(controls: Node) -> Node:
	var lobby := controls.get_parent()
	while lobby != null and not ("local_lobby_player_controls" in lobby and "player_data" in lobby):
		lobby = lobby.get_parent()
	return lobby
