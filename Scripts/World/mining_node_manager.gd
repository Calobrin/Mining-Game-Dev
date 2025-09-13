extends Node

# Configure what fraction of mining nodes should be active this run
@export_range(0.0, 1.0, 0.05) var min_active_ratio: float = 0.5
@export_range(0.0, 1.0, 0.05) var max_active_ratio: float = 0.8
@export var min_active_count_floor: int = 1

# Dictionary to track active nodes by ID
var active_nodes = {}

func _ready():
	# Wait a frame to ensure all mining nodes are registered
	await get_tree().process_frame
	randomize()
	randomize_active_nodes()

# Call this when entering the mine to select random active nodes
func randomize_active_nodes():
	# Reset active nodes
	active_nodes.clear()
	
	# Get all mining nodes in the scene
	var all_nodes = get_tree().get_nodes_in_group("mining_nodes")
	
	# No nodes found or invalid configuration
	if all_nodes.size() == 0:
		print("No mining nodes found in the scene!")
		return
		
	# Decide how many to activate this run based on total count and configured ratio range
	var total: int = all_nodes.size()
	var lo: float = float(min(min_active_ratio, max_active_ratio))
	var hi: float = float(max(min_active_ratio, max_active_ratio))
	var chosen_ratio: float = randf_range(lo, hi)
	var nodes_to_activate: int = clamp(int(round(total * chosen_ratio)), min_active_count_floor, total)
	
	# Shuffle the array to randomize selection
	all_nodes.shuffle()
	
	# Select random nodes to activate
	var activated = 0
	for node in all_nodes:
		if activated >= nodes_to_activate:
			break
			
		# Generate node ID if needed
		var node_id = node.get_instance_id()
		
		# Activate this node
		active_nodes[node_id] = true
		node.activate()
			
		activated += 1
		
	# Deactivate the rest
	for node in all_nodes:
		var node_id = node.get_instance_id()
		if not active_nodes.has(node_id):
			node.deactivate()
	
	print("Activated " + str(activated) + " mining nodes (" + str(total) + " total, ratio= " + str(chosen_ratio).substr(0,4) + ")")

# Helper function to select index based on weights
func weighted_random_index(weights: Array[float]) -> int:
	var sum = 0.0
	for weight in weights:
		sum += weight
		
	var value = randf() * sum
	var running_sum = 0.0
	
	for i in range(weights.size()):
		running_sum += weights[i]
		if value <= running_sum:
			return i
			
	return 0  # Fallback to first index
	
# Check if a specific node should be active
func is_node_active(node) -> bool:
	var node_id = node.get_instance_id()
	return active_nodes.has(node_id)
