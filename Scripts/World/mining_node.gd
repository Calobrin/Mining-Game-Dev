extends Area3D
const MiningSessionManagerScript = preload("res://Scripts/Mining Minigame/MiningSessionManager.gd")

# You can customize properties for different mining nodes
@export var difficulty: int = 1 # Difficulty level affecting mining game
@export var rewards_multiplier: float = 1.0 # Multiplier for rewards

@onready var interact_label = $"../Label3D"
@onready var sprite_3d = $".."

var player_nearby = false
var mining_active = false # To prevent multiple mining sessions
var is_active = false # Whether this mining node is currently active in the mine
var node_id: int = -1

func _ready() -> void:
	# Add to mining_nodes group so the manager can find it
	add_to_group("mining_nodes")
	# Capture a stable ID for this Mines visit
	node_id = get_instance_id()
	
	interact_label.visible = false
	sprite_3d.visible = false # Start invisible until activated
	
	connect("body_entered", _on_body_entered)
	connect("body_exited", _on_body_exited)
	
	# The manager will call activate() if this node should be active
	
func _on_body_entered(body):
	if body.is_in_group("player") and is_active:
		player_nearby = true
		interact_label.visible = true
		
func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = false
		interact_label.visible = false

func _input(event):
	if player_nearby and is_active and event.is_action_pressed("Interact") and not mining_active:
		start_mining_game()

# Store reference to current minigame instance
var current_minigame = null

# This function will start the mining minigame
func start_mining_game():
	if mining_active:
		return
			
	mining_active = true
	interact_label.visible = false  # Hide the prompt while mining
	
	# Pause the game tree (pauses all nodes except those with 'process_mode = PROCESS_MODE_ALWAYS')
	get_tree().paused = true
	
	# Load and instance the mining minigame scene
	current_minigame = preload("res://Scenes/MiningMinigame.tscn").instantiate()
	current_minigame.process_mode = Node.PROCESS_MODE_ALWAYS  # Make sure it runs while tree is paused
	# Pass along this node's ID so the minigame can include it in signals
	current_minigame.node_id = node_id
	# Avoid auto-starting in _ready(); we will explicitly start or restore
	current_minigame.auto_start = false
	
	# Set difficulty and rewards before adding to scene
	current_minigame.difficulty = difficulty
	current_minigame.rewards_multiplier = rewards_multiplier
	
	# Add it to the scene tree
	get_tree().root.add_child(current_minigame)
	
	# Connect to the minigame's closed signals (new enriched first, then legacy as fallback)
	if current_minigame.has_signal("minigame_closed_with_state"):
		if current_minigame.minigame_closed_with_state.is_connected(_on_minigame_closed_with_state):
			current_minigame.minigame_closed_with_state.disconnect(_on_minigame_closed_with_state)
		current_minigame.minigame_closed_with_state.connect(_on_minigame_closed_with_state)

	# Legacy signal connection remains for compatibility
	if current_minigame.has_signal("minigame_closed"):
		# Disconnect first to prevent duplicate connections
		if current_minigame.minigame_closed.is_connected(_on_minigame_closed):
			current_minigame.minigame_closed.disconnect(_on_minigame_closed)
		current_minigame.minigame_closed.connect(_on_minigame_closed)
	
	# Acquire or create the session manager (scene-scoped)
	var session = get_tree().get_first_node_in_group("mining_session")
	if session == null:
		# Fallback: create one if missing so feature works without scene tweaks
		var mgr = MiningSessionManagerScript.new()
		get_tree().root.add_child(mgr)
		session = mgr

	# If this node was already completed, ignore interaction
	if session.is_completed(node_id):
		print("Mining node already completed; ignoring.")
		# Clean up the minigame instance immediately
		if current_minigame and is_instance_valid(current_minigame):
			current_minigame.queue_free()
			current_minigame = null
		# Unpause and restore input
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mining_active = false
		return

	# Start or resume the minigame based on saved state
	if session.has_state(node_id) and current_minigame.has_method("init_from_state"):
		var state: Dictionary = session.get_state(node_id)
		current_minigame.init_from_state(state)
	else:
		# Start fresh then immediately snapshot for deterministic resume
		current_minigame.start_game()
		if current_minigame.has_method("create_state_snapshot"):
			var snap: Dictionary = current_minigame.create_state_snapshot()
			session.save_state(node_id, snap)
	
	# Capture the mouse for the minigame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_minigame_closed(revealed_count: int = 0, total_value: int = 0):
	# Clean up the minigame instance
	if current_minigame and is_instance_valid(current_minigame):
		current_minigame.queue_free()
		current_minigame = null
	
	# Unpause the game
	get_tree().paused = false
	
	# Restore mouse mode for 3D game
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Allow mining again
	mining_active = false
	interact_label.visible = player_nearby  # Show label again if player is still nearby
	
	# Here you can use revealed_count and total_value as needed
	print("Mining complete! Found ", revealed_count, " treasures worth ", total_value, " total")

# New enriched close handler with persistence support
func _on_minigame_closed_with_state(revealed_count: int, total_value: int, was_completed: bool, _closing_node_id: int, snapshot: Dictionary):
	# Clean up the minigame instance
	if current_minigame and is_instance_valid(current_minigame):
		current_minigame.queue_free()
		current_minigame = null

	# Unpause the game
	get_tree().paused = false
	# Restore mouse mode for 3D game
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Allow mining again
	mining_active = false
	interact_label.visible = false

	# Session manager
	var session = get_tree().get_first_node_in_group("mining_session")
	if session == null:
		var mgr = MiningSessionManagerScript.new()
		get_tree().root.add_child(mgr)
		session = mgr

	if was_completed:
		# Mark complete and remove node from scene
		session.mark_completed(node_id)
		deactivate()
		queue_free()
	else:
		# Save progress snapshot to resume later
		session.save_state(node_id, snapshot)

	print("Mining session closed. Found ", revealed_count, ", value ", total_value, ", completed=", was_completed)
	
# Called by the mining node manager to activate this node
func activate():
	is_active = true
	sprite_3d.visible = true
	# Only show label if player is already nearby
	interact_label.visible = player_nearby
	print("Mining node activated")

# Called by the mining node manager to deactivate this node
func deactivate():
	is_active = false
	player_nearby = false
	sprite_3d.visible = false
	interact_label.visible = false
	print("Mining node deactivated")
	

			
	# Update label text based on ore type
	interact_label.text = "[E]: Mine "

# Helper function to choose a random element from an array
func choose(array):
	if array.size() == 0:
		return null
	return array[randi() % array.size()]
