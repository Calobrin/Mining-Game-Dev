extends Node3D

@onready var player = $Player  # Assuming the player node is in the scene
@onready var mines_to_town_spawn = $Spawnpoint  # Spawn point when coming from the Mines

func _ready() -> void:
	match Global.source_scene:
		"Mines":
			player.global_transform.origin = mines_to_town_spawn.global_transform.origin
			player.global_transform.basis = mines_to_town_spawn.global_transform.basis
			
