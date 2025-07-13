extends Node3D

@export var sensitivity = 0.5
@export var min_camera_distance = 2.0
@export var max_camera_distance = 8.0
@export var camera_scroll_speed = 1.0

@onready var camera_pivot: Node3D = self        # Camera pivot node (parent of SpringArm)
@onready var spring_arm: SpringArm3D = $SpringArm3D  # Spring arm for camera zoom
@onready var camera: Camera3D = $SpringArm3D/Camera3D  # Actual camera
@onready var player: Node3D = get_parent()      # Player character node

# Input tracking
var is_right_click_held: bool = false
var is_left_click_held: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var needs_alignment: bool = false     # Track if character needs alignment with camera

# Limits for camera pitch (up/down)
var min_pitch: float = deg_to_rad(-45)  # Looking down
var max_pitch: float = deg_to_rad(80)   # Looking up

# Debug
var debug_mode: bool = false

func _ready() -> void:
	# Initialize the camera system
	# Make sure camera starts behind player
	camera_pivot.rotation.y = 0
	spring_arm.rotation.y = 0

# Main input handling for mouse movement and wheel
func _input(event: InputEvent) -> void:
	# Camera rotation (mouse movement)
	if event is InputEventMouseMotion:
		if is_right_click_held:
			# RIGHT-CLICK MODE: Character rotates with camera
			_handle_right_click_rotation(event.relative)
		elif is_left_click_held:
			# LEFT-CLICK MODE: Camera orbits around character
			_handle_left_click_rotation(event.relative)

	# Camera zoom with mouse wheel
	if event.is_action_pressed("Wheel Up"):
		spring_arm.spring_length = max(spring_arm.spring_length - camera_scroll_speed, min_camera_distance)
	if event.is_action_pressed("Wheel Down"):
		spring_arm.spring_length = min(spring_arm.spring_length + camera_scroll_speed, max_camera_distance)

# Handle right-click camera rotation (player and camera move together)
func _handle_right_click_rotation(relative: Vector2) -> void:
	# Horizontal rotation: Rotate player around Y-axis
	player.rotate_y(deg_to_rad(-relative.x * sensitivity))
	
	# Keep camera directly behind player in right-click mode
	camera_pivot.rotation.y = 0
	spring_arm.rotation.y = 0
	
	# Vertical rotation: Tilt camera up/down
	var new_rotation_x = camera_pivot.rotation.x - deg_to_rad(relative.y * sensitivity)
	camera_pivot.rotation.x = clamp(new_rotation_x, min_pitch, max_pitch)

# Handle left-click camera rotation (only camera moves, not player)
func _handle_left_click_rotation(relative: Vector2) -> void:
	# Horizontal rotation: Camera orbits around player
	camera_pivot.rotation.y -= deg_to_rad(relative.x * sensitivity)
	
	# Vertical rotation: Tilt camera up/down
	var new_rotation_x = camera_pivot.rotation.x - deg_to_rad(relative.y * sensitivity)
	camera_pivot.rotation.x = clamp(new_rotation_x, min_pitch, max_pitch)

# Handle mouse button presses and releases
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# RIGHT CLICK HANDLING
		if Input.is_action_just_pressed("Right Click"):
			# Release left-click if it was held
			if is_left_click_held:
				is_left_click_held = false
				
			# Switch to right-click mode
			is_right_click_held = true
			
			# Set flag to align player when movement begins
			needs_alignment = true
			
			# Capture mouse and save position
			last_mouse_position = get_viewport().get_mouse_position()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		elif Input.is_action_just_released("Right Click"):
			# Right-click released
			is_right_click_held = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().warp_mouse(last_mouse_position)
		
		# LEFT CLICK HANDLING
		if Input.is_action_just_pressed("Left Click") and not is_right_click_held:
			# Switch to left-click mode
			is_left_click_held = true
			last_mouse_position = get_viewport().get_mouse_position()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		elif Input.is_action_just_released("Left Click"):
			# Left-click released
			is_left_click_held = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().warp_mouse(last_mouse_position)

# Check for movement input and align character when needed
func _physics_process(_delta: float) -> void:
	# Only check for alignment if right-click is held and alignment is needed
	if is_right_click_held and needs_alignment:
		# Check for movement input
		var input_dir = Input.get_vector("Left", "Right", "Forwards", "Backwards")
		
		# If player is giving movement input, align character to camera
		if input_dir != Vector2.ZERO:
			_align_player_to_camera()
			needs_alignment = false  # Reset flag after alignment

# Align the player to the camera direction when switching from left-click to right-click
func _align_player_to_camera() -> void:
	# Get camera's forward vector in world space
	var camera_forward = -camera.global_transform.basis.z.normalized()
	# Project onto XZ plane (ignore vertical component)
	camera_forward.y = 0
	
	if camera_forward.length() > 0.001:
		camera_forward = camera_forward.normalized()
		
		# The critical step: Set player rotation to match camera direction
		# In right-click mode, player should face AWAY from camera
		var target_direction = -camera_forward
		player.rotation.y = atan2(target_direction.x, target_direction.z)
	
	# Reset camera_pivot rotation around Y axis to be directly behind player
	camera_pivot.rotation.y = 0
	spring_arm.rotation.y = 0
