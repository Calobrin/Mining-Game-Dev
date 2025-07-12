extends CharacterBody3D

const SPEED = 8.0
const JUMP_VELOCITY = 4.0

@onready var camera_script: Node = $"Camera Origin"  # Reference to the camera script

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # Set the mouse mode to visible by default

func _input(event: InputEvent) -> void:
	# Pass input events to the camera
	camera_script._input(event)

	# Exit the game
	if Input.is_action_just_pressed("Exit"):
		get_tree().quit()

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get movement input (WASD)
	var input_dir = Input.get_vector("Left", "Right", "Forwards", "Backwards")
	if input_dir != Vector2.ZERO:
		# Move the player in the direction they're facing (camera's orientation)
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
