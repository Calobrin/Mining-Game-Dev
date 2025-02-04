extends Node3D

@export var sensitivity = 0.5
@export var min_camera_distance = 2.0
@export var max_camera_distance = 8.0
@export var camera_scroll_speed = 1.0

@onready var camera_pivot: Node3D = self  # Camera pivot node (likely this node)
@onready var spring_arm: SpringArm3D = $"SpringArm3D"  # The spring arm node
@onready var player: Node3D = get_parent()  # Reference to the player node (parent of camera)

var is_right_click_held: bool = false  # Track right-click status
var last_mouse_position: Vector2 = Vector2.ZERO  # Store mouse position before right-click

func _input(event: InputEvent) -> void:
	# Handle camera rotation only when right-click is held
	if event is InputEventMouseMotion:
		if is_right_click_held:  # Camera rotation happens only if right-click is held
			# Rotate the player horizontally with the mouse (around Y-axis)
			player.rotate_y(deg_to_rad(-event.relative.x * sensitivity))

			# Calculate the vertical camera angle
			var new_rotation_x = camera_pivot.rotation.x - deg_to_rad(event.relative.y * sensitivity)
			camera_pivot.rotation.x = clamp(new_rotation_x, deg_to_rad(-45), deg_to_rad(80))

	# Handle camera zoom with mouse wheel
	if event.is_action_pressed("Wheel Up"):
		spring_arm.spring_length = max(spring_arm.spring_length - camera_scroll_speed, min_camera_distance)
	if event.is_action_pressed("Wheel Down"):
		spring_arm.spring_length = min(spring_arm.spring_length + camera_scroll_speed, max_camera_distance)

func _unhandled_input(event: InputEvent) -> void:
	# Handle right-click press and release using the input map action
	if event is InputEventMouseButton:
		if Input.is_action_pressed("Right Click"):
			if not is_right_click_held:
				# Right-click pressed: lock the mouse and enable camera control
				is_right_click_held = true
				# Save the current mouse position before capturing
				last_mouse_position = get_viewport().get_mouse_position()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif Input.is_action_just_released("Right Click"):
			# Right-click released: stop camera control and unlock the mouse
			is_right_click_held = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Return the mouse to the position it was at before right-click
			get_viewport().warp_mouse(last_mouse_position)
