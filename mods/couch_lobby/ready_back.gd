extends Node

# Child of a LocalLobbyPlayerControls panel. The game's back (action_2) on the outfit opens the name
# screen even when the player is ready; here back from ready only unreadies, and back again goes on
# to the name screen. Runs before the panel's _process, which reads the same press this frame.

var controls: Control

func _ready() -> void:
	controls = get_parent()
	process_priority = controls.process_priority - 1

static func unreadies(active: bool, can_control: bool, on_main_input: bool, is_ready: bool, back: bool) -> bool:
	return active and can_control and not on_main_input and is_ready and back

func _process(_delta: float) -> void:
	if controls.assigned_player_id < 0:
		return
	var back := MultiplayerInput.is_action_just_pressed(controls.device, &"action_2")
	if not unreadies(controls.active, controls.can_control, controls.on_main_input, controls.is_ready, back):
		return
	controls.set_player_ready(false)
	controls.press_speaker.play()
	# A pad host can walk from the checkmark to the lobby's buttons while ready; its next A would press
	# the focused one, so the game's own set_ready_focus takes it back (the game calls it for pads only).
	if controls.is_joystick and controls.main_player and controls.main_button_focused:
		controls.set_ready_focus()
	# The panel's _process skips this frame while can_control is off, so the same press can't also
	# open the name screen (Input.action_release can't undo a pad's own press).
	controls.can_control = false
	_resume.call_deferred()

func _resume() -> void:
	if is_instance_valid(controls) and controls.active and not controls.can_control:
		controls.can_control = true
