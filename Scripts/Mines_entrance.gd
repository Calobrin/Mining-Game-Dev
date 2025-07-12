extends Area3D
@export var current_scene = ""
@onready var interact_label = $"../Label3D"
@onready var sprite_3d = $".."

var player_nearby = false

func _ready() -> void:
	interact_label.visible = false
	connect("body_entered", _on_body_entered)
	connect("body_exited", _on_body_exited)
	
func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = true
		interact_label.visible = true
		
func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = false
		interact_label.visible = false

func _input(event):
	if player_nearby and event.is_action_pressed("Interact"):
		if current_scene == "Town":
			#Global.source_scene == "Town"  # This may be needed later.
			get_tree().change_scene_to_file("res://Scenes/mg_mines_level_1.tscn")
			print("You entered the Mines Level 1")
		elif current_scene == "Mines":
			Global.source_scene = "Mines"
			get_tree().change_scene_to_file("res://Scenes/mg_town.tscn")
			print("You returned to Town from the Mines Level 1")
