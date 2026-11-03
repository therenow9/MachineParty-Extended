extends Node

# Extended's calls between peers, at /root/MP8Net on Extended peers only (main.gd adds it). Godot sends
# an RPC as its index in the node's sorted RPC table, so an @rpc added to a game script would shift the
# game's ids and land on the wrong method in a vanilla peer. The game's scripts keep exactly the game's
# @rpc methods; Extended's go through these two, to peers whose join data carries our tag.

enum Mode { AUTHORITY_LOCAL, AUTHORITY_REMOTE, ANY_PEER_LOCAL }

# The only methods a relay call can reach, by script and name, each with the @rpc mode it stands for.
# A call naming a method missing here is dropped with an error on the sender. mp8_selftest checks the
# other way: every name here exists in its script, since a stale one would fail on every receiver.
const TARGETS := {
	"res://minigames/burn_recycle/scripts/burn_recycle.gd": {
		"_mp8_layout_rpc": Mode.AUTHORITY_LOCAL,
		"_mp8_pause_rpc": Mode.AUTHORITY_LOCAL,
		"_mp8_score_board_rpc": Mode.AUTHORITY_LOCAL,
		"_mp8_sync_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/burn_recycle/components/player/burn_recycle_player.gd": {
		"mp8_setup_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet.gd": {
		"mp8_shot_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/duck_hunt/scripts/duck_hunt.gd": {
		"set_hunter_names_rpc": Mode.AUTHORITY_LOCAL,
		"set_hunters_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_set_ducks_ambient_light_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/duck_hunt/components/hunter_player/scripts/hunter_player.gd": {
		"mp8_setup_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/escalator_pit/scripts/escalator_pit.gd": {
		"mp8_shot_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/exploding_collar_race/scripts/exploding_collar_race.gd": {
		"mp8_move_spawn_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/forklift_certified/components/delivery_area/forklift_certified_delivery_area.gd": {
		"mp8_set_score_mult_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/forklift_certified/scripts/forklift_certified.gd": {
		"zz_mp8v_add_delivery_areas_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/green_pea/components/coach_handler/coach_handler.gd": {
		"mp8_shoot_players_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/junk_platform/scripts/junk_platform.gd": {
		"mp8_adjust_camera_rpc": Mode.AUTHORITY_REMOTE,
		"mp8_set_junk_speed_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_set_platform_labels_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_shot_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/manufacture_gun/scripts/manufacture_gun.gd": {
		"zz_mp8v_bench_room_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_spawned_workstation_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_receive_item_sequence_rpc": Mode.AUTHORITY_REMOTE,
		"mp8_remove_empty_workstation_rpc": Mode.AUTHORITY_LOCAL,
	},
	"res://minigames/smoke_break/scripts/smoke_break.gd": {
		"mp8_move_crate_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_move_seat_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_set_pause_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_toggle_crate_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/smoke_break/components/player/scripts/smoke_break_player.gd": {
		"mp8_setup_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/spine_breaker/components/device/spine_breaker_device.gd": {
		"mp8_bind_rpc": Mode.ANY_PEER_LOCAL,
		"mp8_retire_quiet_rpc": Mode.ANY_PEER_LOCAL,
	},
	"res://minigames/spine_breaker/scripts/spine_breaker.gd": {
		"mp8_device_place_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_device_reset_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_ensure_devices_rpc": Mode.AUTHORITY_LOCAL,
		"mp8_spine_tryout_rpc": Mode.AUTHORITY_LOCAL,
	},
}


# peer 0 sends to every Extended peer, as rpc() does. Remote sends go first, then the local call, as in
# Godot's rpcp; a local call here keeps the current sender: 0 outside an RPC, the RPC's sender inside one (PD19).
func send(peer: int, node: Node, method: StringName, args: Array) -> void:
	var mode := mode_of(node, method)
	if mode < 0:
		push_error("[MP8] relay: %s is not a relay target of %s" % [method, _script_path(node)])
		return
	var path := String(get_tree().root.get_path_to(node))
	var me := multiplayer.get_unique_id()
	var nm := get_tree().root.get_node("NetworkManager")
	var ids: Array = Array(multiplayer.get_peers()) if peer == 0 else [peer]
	for id in ids:
		if id == me or not nm.mp8_peer_extended(id):
			continue
		if mode == Mode.ANY_PEER_LOCAL:
			_any_peer_call.rpc_id(id, path, method, args)
		else:
			_authority_call.rpc_id(id, path, method, args)
	if mode != Mode.AUTHORITY_REMOTE and (peer == 0 or peer == me):
		node.callv(method, args)


@rpc("authority", "call_remote", "reliable")
func _authority_call(path: String, method: StringName, args: Array) -> void:
	_receive(false, path, method, args)


@rpc("any_peer", "call_remote", "reliable")
func _any_peer_call(path: String, method: StringName, args: Array) -> void:
	_receive(true, path, method, args)


func _receive(any_peer: bool, path: String, method: StringName, args: Array) -> void:
	var node := get_tree().root.get_node_or_null(NodePath(path))
	if node == null:
		push_error("[MP8] relay: no node %s for %s" % [path, method])
		return
	var mode := mode_of(node, method)
	if mode < 0 or (mode == Mode.ANY_PEER_LOCAL) != any_peer:
		push_error("[MP8] relay: refused %s on %s from %d" % [method, path, multiplayer.get_remote_sender_id()])
		return
	node.callv(method, args)


# The method's Mode, or -1 when the relay may not call it.
static func mode_of(node: Node, method: StringName) -> int:
	return int(TARGETS.get(_script_path(node), {}).get(String(method), -1))


# An exported game's scripts load from .gdc files; the list names their source paths.
static func _script_path(node: Node) -> String:
	var script = node.get_script() if node != null else null
	if script == null:
		return ""
	var path: String = script.resource_path
	return path.trim_suffix("c") if path.ends_with(".gdc") else path
