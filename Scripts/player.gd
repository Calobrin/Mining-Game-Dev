extends CharacterBody3D

const SPEED = 8.0
const JUMP_VELOCITY = 4.0

@export var sensitivity = 0.5
@export var min_camera_distance = 2.0
@export var max_camera_distance = 8.0
@export var camera_scroll_speed = 1.0

@onready var camera_pivot: Node3D = $"Camera Origin"  # Pivot for vertical camera rotation
@onready var spring_arm: SpringArm3D = $"Camera Origin/SpringArm3D" # The spring arm

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Rotate the player horizontally with the mouse
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))

		# Calculate the potential new vertical rotation
		var new_rotation_x = camera_pivot.rotation.x + deg_to_rad(event.relative.y * sensitivity)
		
		# Clamp the new rotation before applying it
		camera_pivot.rotation.x = clamp(new_rotation_x, deg_to_rad(-45), deg_to_rad(80))

	# Exit the game
	if Input.is_action_just_pressed("Exit"):
		get_tree().quit()

	# Handle camera zoom with mouse wheel
	if event.is_action_pressed("Wheel Up"):
		spring_arm.spring_length = max(spring_arm.spring_length - camera_scroll_speed, min_camera_distance)
	if event.is_action_pressed("Wheel Down"):
		spring_arm.spring_length = min(spring_arm.spring_length + camera_scroll_speed, max_camera_distance)

	# Toggle mouse mode
	if Input.is_action_just_pressed("Tab"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get movement input
	var input_dir = Input.get_vector("Left", "Right", "Forwards", "Backwards")
	if input_dir != Vector2.ZERO:
		# Move in the direction the player is facing
		var forward = transform.basis.z
		var right = transform.basis.x
		var move_dir = (forward * input_dir.y + right * input_dir.x).normalized()
		
		velocity.x = move_dir.x * SPEED
		velocity.z = move_dir.z * SPEED
	else:
		# Gradually stop movement when no input
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Move the player
	move_and_slide()
