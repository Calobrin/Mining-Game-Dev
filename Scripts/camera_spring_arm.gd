extends SpringArm3D

@export var mouse_sensibility: float = 0.005
@export_range(-90.0, 0.0, 0.1, "radians_as_degrees") var min_verticle_angle: float = -PI/2
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var max_vertical_angle: float = PI/4

const MIN_SPRING_LENGTH = 2
const MAX_SPRING_LENGTH = 8

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensibility
		rotation.y = wrapf(rotation.y, 0.0, TAU)
		
		rotation.x -= event.relative.y * mouse_sensibility
		rotation.x = clamp(rotation.x, min_verticle_angle, max_vertical_angle)
	if event.is_action_pressed("Wheel Up"):
		spring_length = max(spring_length - 1, MIN_SPRING_LENGTH)
	if event.is_action_pressed("Wheel Down"):
		spring_length = min(spring_length + 1, MAX_SPRING_LENGTH)
		
		#spring_length = clamp(spring_length, MIN_SPRING_LENGTH, MAX_SPRING_LENGTH)
		
	if event.is_action_pressed("Tab"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
