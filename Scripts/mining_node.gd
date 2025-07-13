extends Area3D

# You can customize properties for different mining nodes
@export var ore_type: String = "Iron" # Type of ore this node contains
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

# This function will start the mining minigame
func start_mining_game():
	mining_active = true
	
	# You can uncomment and modify this code once you have a mining minigame scene
	# var mining_scene = load("res://Scenes/mining_minigame.tscn").instantiate()
	# mining_scene.setup(ore_type, difficulty, rewards_multiplier)
	# get_tree().get_root().add_child(mining_scene)
	
	# For now, just print debug info
	print("Starting mining game with: " + ore_type + ", difficulty: " + str(difficulty))
	
	# This would be called when the mining game ends
	# In reality, you would connect to a signal from your mining game scene
	await get_tree().create_timer(0.5).timeout
	mining_active = false
	
# Called by the mining node manager to activate this node
func activate():
	is_active = true
	sprite_3d.visible = true
	# Only show label if player is already nearby
	interact_label.visible = player_nearby
	print("Mining node activated: " + ore_type)

# Called by the mining node manager to deactivate this node
func deactivate():
	is_active = false
	player_nearby = false
	sprite_3d.visible = false
	interact_label.visible = false
	print("Mining node deactivated")
	
# Set ore type based on rarity group
func set_ore_group(group: String):
	match group:
		"common":
			ore_type = choose(["Iron", "Copper", "Tin"])
			difficulty = 1
			rewards_multiplier = 1.0
		"uncommon":
			ore_type = choose(["Silver", "Gold", "Mithril"])
			difficulty = 2
			rewards_multiplier = 2.0
		"rare":
			ore_type = choose(["Adamantite", "Dragonite", "Starstone"])
			difficulty = 3
			rewards_multiplier = 3.5
		_:
			ore_type = "Iron"
			difficulty = 1
			rewards_multiplier = 1.0
			
	# Update label text based on ore type
	interact_label.text = "[E]: Mine " + ore_type

# Helper function to choose a random element from an array
func choose(array):
	if array.size() == 0:
		return null
	return array[randi() % array.size()]
