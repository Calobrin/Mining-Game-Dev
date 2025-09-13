extends Node
class_name MiningSessionManager

# In-memory, scene-scoped manager that tracks Mining Minigame snapshots per node
# Scope: valid only while you remain in the Mines scene (this node should exist in that scene)

var _states: Dictionary = {}        # node_id:int -> Dictionary snapshot
var _completed: Dictionary = {}     # node_id:int -> bool

func _ready() -> void:
	# Add to a known group so other nodes can find it easily
	add_to_group("mining_session")

# --- Query APIs ---
func has_state(node_id: int) -> bool:
	return _states.has(node_id)

func get_state(node_id: int) -> Dictionary:
	if _states.has(node_id):
		return _states[node_id]
	return {}

func is_completed(node_id: int) -> bool:
	return _completed.get(node_id, false)

# --- Mutating APIs ---
func save_state(node_id: int, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_states[node_id] = snapshot
	# When saving a snapshot mid-run, ensure completed is false
	_completed[node_id] = false
	# Debug
	#print("[MiningSession] Saved state for node ", node_id)

func mark_completed(node_id: int) -> void:
	_completed[node_id] = true
	# Optionally remove the snapshot to free memory; keeping it is fine too.
	# _states.erase(node_id)
	#print("[MiningSession] Marked node completed ", node_id)

func clear_all() -> void:
	_states.clear()
	_completed.clear()
