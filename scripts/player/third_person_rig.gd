extends Node3D
## Smooth chase camera. Top-level so it can lag slightly behind the bike's yaw
## while the SpringArm3D keeps it out of walls. Mouse drag orbits temporarily.

@export var height := 1.7
@export var follow_rate := 14.0
@export var yaw_rate := 5.0
@export var orbit_return_rate := 1.5

var target: Node3D
var focus = null        # Vector3 to look at instead of the target (crash), or null
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0

@onready var arm: SpringArm3D = $SpringArm3D


func setup(t: Node3D) -> void:
	target = t
	top_level = true
	arm.add_excluded_object(t.get_rid())
	snap()


func snap() -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3.UP * height
	rotation = Vector3(0, target.global_rotation.y, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.003, -0.5, 0.35)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var base: Vector3 = target.global_position if focus == null else focus
	var goal := base + Vector3.UP * height
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_rate * delta))
	var yaw_goal: float = target.global_rotation.y
	# When reversing, keep looking forward instead of swinging around.
	rotation.y = lerp_angle(rotation.y, yaw_goal, 1.0 - exp(-yaw_rate * delta))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw = lerpf(_orbit_yaw, 0.0, 1.0 - exp(-orbit_return_rate * delta))
		_orbit_pitch = lerpf(_orbit_pitch, 0.0, 1.0 - exp(-orbit_return_rate * delta))
	arm.rotation = Vector3(deg_to_rad(-14.0) + _orbit_pitch, _orbit_yaw, 0)
	# Pull back a little during a crash so rider and bike both stay in frame.
	arm.spring_length = lerpf(arm.spring_length, 6.5 if focus != null else 4.6, 1.0 - exp(-3.0 * delta))
