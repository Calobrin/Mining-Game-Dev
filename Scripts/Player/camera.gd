extends Node3D

@export var sensitivity = 0.12
@export var min_camera_distance = 2.0
@export var max_camera_distance = 8.0
@export var camera_scroll_speed = 0.5
@export var zoom_in_speed := 14.0    # speed when moving camera closer (on obstruction)
@export var zoom_out_speed := 6.0    # speed when moving camera back out (when clear)
@export var collision_padding := 0.15 # extra space from hit point to avoid near-plane clipping
@export var camera_collision_mask: int = 0xFFFFF # layers the camera should collide with
@export var ray_origin_offset := 0.4  # raise ray start to avoid hitting ground/self when pitching up
@export var min_obstruction_distance := 0.35 # ignore hits that are unrealistically close to the pivot
@export var ignore_floor_hits := true  # if true, ignore floor-like surfaces for camera collision

@onready var camera_pivot: Node3D = self        # Camera pivot node (parent of SpringArm)
@onready var spring_arm: SpringArm3D = $SpringArm3D  # Spring arm for camera zoom
@onready var camera: Camera3D = $SpringArm3D/Camera3D  # Actual camera
@onready var player: Node3D = get_parent()      # Player character node

# Input tracking
var is_right_click_held: bool = false
var is_left_click_held: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO

# Limits for camera pitch (up/down)
var min_pitch: float = deg_to_rad(-70)  # Looking down
var max_pitch: float = deg_to_rad(80)   # Looking up

# Debug
var debug_mode: bool = false

# Smoothed camera distance handling
var desired_length: float
var current_length: float

func _enter_tree() -> void:
	# Capture as early as possible on scene load to prevent cursor flash
	if Input.is_action_pressed("Right Click"):
		is_right_click_held = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Input.is_action_pressed("Left Click"):
		is_left_click_held = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	# Initialize the camera system
	# Make sure camera starts behind player
	camera_pivot.rotation.y = 0
	spring_arm.rotation.y = 0

	# Prefer per-event mouse motion (no frame accumulation) for 1:1 feel in Godot 4.3
	# This avoids large spikes when many small mouse moves get combined in a single frame.
	Input.use_accumulated_input = false

	# We'll do custom collision + smoothing, so disable built-in SpringArm collision shape
	spring_arm.shape = null

	# Reduce near-clip to avoid walls disappearing when the camera gets very close
	camera.near = 0.05

	# Initialize smoothed distances
	desired_length = clamp(spring_arm.spring_length, min_camera_distance, max_camera_distance)
	current_length = desired_length

	# If a mouse button is still physically held during a scene change, re-enter that mode and capture.
	# This keeps camera control fluid across scene transitions.
	if Input.is_action_pressed("Right Click"):
		is_right_click_held = true
		last_mouse_position = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		call_deferred("_ensure_mouse_captured")
	elif Input.is_action_pressed("Left Click"):
		is_left_click_held = true
		last_mouse_position = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		call_deferred("_ensure_mouse_captured")

func _ensure_mouse_captured() -> void:
	# Reinforce capture after the scene is fully ready to avoid any late resets
	if is_right_click_held or is_left_click_held:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

	# Camera zoom with mouse wheel (affects desired length; smoothing happens in _physics_process)
	if event.is_action_pressed("Wheel Up"):
		desired_length = max(desired_length - camera_scroll_speed, min_camera_distance)
	if event.is_action_pressed("Wheel Down"):
		desired_length = min(desired_length + camera_scroll_speed, max_camera_distance)

func _physics_process(delta: float) -> void:
	# Compute target camera length using a raycast with padding, then smooth toward it
	var from: Vector3 = spring_arm.global_transform.origin + Vector3.UP * ray_origin_offset
	# Spring arm extends along its -Z (camera looks along -Z), so target point is along -Z
	var back_dir: Vector3 = -spring_arm.global_transform.basis.z.normalized()
	var to: Vector3 = from + back_dir * desired_length

	var hit_distance := INF
	var space := get_world_3d().direct_space_state
	if space:
		var p := PhysicsRayQueryParameters3D.create(from, to)
		p.collision_mask = camera_collision_mask
		# Exclude the player so we don't immediately hit our own body
		p.exclude = [player.get_rid()]
		var hit := space.intersect_ray(p)
		if hit and hit.has("position"):
			var dist := from.distance_to(hit["position"]) - collision_padding
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			var is_floor := normal.y > 0.6       # hit looks like a floor/ground
			# Ignore extremely close hits, and optionally ignore floor hits entirely to avoid overhead caps
			if dist >= min_obstruction_distance:
				if ignore_floor_hits and is_floor:
					pass
				else:
					hit_distance = dist

	var target_length := desired_length
	if hit_distance != INF:
		target_length = clamp(hit_distance, min_camera_distance, desired_length)

	# Smooth: move in fast, move out slower to avoid popping
	var speed := zoom_in_speed if target_length < current_length else zoom_out_speed
	current_length = move_toward(current_length, target_length, speed * delta)
	spring_arm.spring_length = current_length

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
			
			# CRITICAL STEP: Align player to face in the direction the camera is looking
			_align_player_to_camera()
			
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
