extends Node

# Child of a LocalLobbyPlayerControls panel. Adds a glasses row (a copy of the
# hat row) between the hat and suit color rows, and drives it with the same
# input rules, cooldowns and sounds as the vanilla hat picker.

const GLASSES = ["none", "sunglasses", "reading_glasses"]
# Matches is_compatible_with_glasses() in the online customization screen.
const NO_GLASSES_HATS = ["maska_helmet", "rubiks_cube"]
const BLOCKED_ROW_ALPHA := 0.55
# Highest panel position vanilla uses (seat 0). Anything above this runs the
# host crown into the "press any button to join" banner.
const MIN_PANEL_Y := 71.0

var icon_path: String
# Shared with main.gd: input device -> chosen glasses, for players in a seat.
var glasses_by_device: Dictionary
# Set by main.gd: the vanilla lists plus another mod's (More Cosmetics').
var glasses: Array = GLASSES
var no_glasses_hats: Array = NO_GLASSES_HATS

var controls: Control
var glasses_row: Control
var glasses_picker_element: Control
var glasses_prev: Control
var glasses_next: Control

var _cooldown := 0.0
var _recorded_device = null
var _shifted_position = null
var _tween: Tween

func _ready() -> void:
	controls = get_parent()
	_build_row()
	_connect_mouse()

func _build_row() -> void:
	var hat_row: Control = controls.hbox_selection_hat
	# No DUPLICATE_SIGNALS: the hat arrows' mouse handlers must not come along.
	glasses_row = hat_row.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	glasses_row.name = "HBoxContainerGlasses"
	hat_row.add_sibling(glasses_row)

	glasses_picker_element = glasses_row.get_node(hat_row.get_path_to(controls.hat_picker_element))
	glasses_prev = glasses_row.get_node(hat_row.get_path_to(controls.hat_prev))
	glasses_next = glasses_row.get_node(hat_row.get_path_to(controls.hat_next))

	if glasses_picker_element is TextureRect and FileAccess.file_exists(icon_path):
		var image := Image.load_from_file(icon_path)
		if image:
			glasses_picker_element.texture = ImageTexture.create_from_image(image)

	var elements: Array = controls.active_elements
	elements.insert(elements.find(controls.hat_picker_element) + 1, glasses_picker_element)

func _connect_mouse() -> void:
	glasses_prev.mouse_entered.connect(func():
		controls.set_active_element_from_mouse(glasses_picker_element, -1)
		controls.set_keyboard_control_self_modulate(glasses_prev, 1.0, true)
	)
	glasses_prev.mouse_exited.connect(func():
		controls.set_active_element_from_mouse(null)
		controls.set_keyboard_control_self_modulate(glasses_prev, 0.5)
	)
	glasses_next.mouse_entered.connect(func():
		controls.set_active_element_from_mouse(glasses_picker_element, 1)
		controls.set_keyboard_control_self_modulate(glasses_next, 1.0, true)
	)
	glasses_next.mouse_exited.connect(func():
		controls.set_active_element_from_mouse(null)
		controls.set_keyboard_control_self_modulate(glasses_next, 0.5)
	)

# Runs after the parent's _process each frame, so the vanilla hat/color/ready
# handling and up/down navigation have already happened.
func _process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)

	if _glasses_blocked() and get_assigned_glasses() != "none":
		controls.customization_assigner.assign_glasses("none")

	_sync_layout()
	_record_choice()

	if not controls.active or not controls.can_control or controls.on_main_input or controls.is_ready:
		return
	if controls.active_element != glasses_picker_element:
		return

	var direction := _read_direction()
	if direction != 0:
		change_glasses(direction)
		controls.press_speaker.play()

func _read_direction() -> int:
	var device: int = controls.device
	if controls.is_joystick:
		for step in [[-1, "left"], [1, "right"]]:
			if MultiplayerInput.is_action_pressed(device, step[1]):
				if MultiplayerInput.is_action_just_pressed(device, step[1]):
					_cooldown = controls.button_press_cooldown_duration
					return step[0]
				if _cooldown <= 0.0:
					_cooldown = controls.button_cooldown_duration
					return step[0]
				return 0
		return 0

	var pressed = MultiplayerInput.is_action_pressed(device, "action_1")
	var just_pressed = MultiplayerInput.is_action_just_pressed(device, "action_1")
	if pressed and (just_pressed or _cooldown <= 0.0):
		_cooldown = controls.button_press_cooldown_duration if just_pressed else controls.button_cooldown_duration
		return controls.mouse_and_keyboard_direction
	return 0

func _sync_layout() -> void:
	glasses_row.visible = controls.hbox_selection_hat.visible
	glasses_row.modulate.a = BLOCKED_ROW_ALPHA if _glasses_blocked() else 1.0

	# The extra row makes the panel taller. Whenever vanilla places the panel
	# with the pickers showing, shift it up one row (as far as the banner
	# allows) so it ends where it used to.
	if glasses_row.visible and controls.position != _shifted_position:
		var row_height: float = glasses_row.get_combined_minimum_size().y + controls.get_theme_constant("separation")
		controls.position.y = max(controls.position.y - row_height, min(controls.position.y, MIN_PANEL_Y))
		_shifted_position = controls.position

# Keep the registry entry for whoever is in this seat current; drop it when the
# seat empties so a stale choice can't follow the device into the next game.
func _record_choice() -> void:
	var seated: bool = controls.assigned_player_id >= 0
	if _recorded_device != null and (not seated or controls.device != _recorded_device):
		glasses_by_device.erase(_recorded_device)
		_recorded_device = null
	if seated:
		glasses_by_device[controls.device] = get_assigned_glasses()
		_recorded_device = controls.device

func change_glasses(direction: int) -> void:
	if _glasses_blocked():
		return

	# Glasses whose model failed to load have no node and would read back as "none".
	var attach: Node = controls.customization_assigner.bone_attachment_glasses
	var shown := glasses.filter(func(g): return g == "none" or attach.has_node(NodePath(g)))
	var index = shown.find(get_assigned_glasses())
	controls.customization_assigner.assign_glasses(shown[wrapi(index + direction, 0, shown.size())])

	var arrow: Control = glasses_prev if direction < 0 else glasses_next
	arrow.self_modulate.a = 1
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(arrow, "self_modulate", controls.tween_color_end, 0.1)

func get_assigned_glasses() -> String:
	for child in controls.customization_assigner.bone_attachment_glasses.get_children():
		if child.visible and glasses.has(str(child.name)):
			return str(child.name)
	return "none"

func _glasses_blocked() -> bool:
	return str(controls.customization_assigner.get_assigned_hat()) in no_glasses_hats

# `base` plus the usable names in `extra`: non-empty Strings, not "none", not
# already listed. Returns a new array; ok is false if anything was dropped.
static func merged(base: Array, extra) -> Dictionary:
	var out := base.duplicate()
	var ok := true
	if extra == null:
		return {"list": out, "ok": true}
	if not extra is Array:
		return {"list": out, "ok": false}
	for item in extra:
		if (item is String or item is StringName) and str(item) != "" and str(item) != "none" and not out.has(str(item)):
			out.append(str(item))
		else:
			ok = false
	return {"list": out, "ok": ok}
