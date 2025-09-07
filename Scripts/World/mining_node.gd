extends Area3D

# You can customize properties for different mining nodes
@export var difficulty: int = 1 # Difficulty level affecting mining game
@export var rewards_multiplier: float = 1.0 # Multiplier for rewards

@onready var interact_label = $"../Label3D"
@onready var sprite_3d = $".."

var player_nearby = false
var mining_active = false # To prevent multiple mining sessions
var is_active = false # Whether this mining node is currently active in the mine

func _ready() -> void:
	# Add to mining_nodes group so the manager can find it
	add_to_group("mining_nodes")
	
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
	
	# Set difficulty and rewards before adding to scene
	current_minigame.difficulty = difficulty
	current_minigame.rewards_multiplier = rewards_multiplier
	
	# Add it to the scene tree
	get_tree().root.add_child(current_minigame)
	
	# Connect to the minigame's closed signal
	if current_minigame.has_signal("minigame_closed"):
		# Disconnect first to prevent duplicate connections
		if current_minigame.minigame_closed.is_connected(_on_minigame_closed):
			current_minigame.minigame_closed.disconnect(_on_minigame_closed)
		current_minigame.minigame_closed.connect(_on_minigame_closed)
	
	# Start the minigame
	current_minigame.start_game()
	
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
