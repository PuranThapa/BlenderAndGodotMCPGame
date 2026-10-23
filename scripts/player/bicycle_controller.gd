extends CharacterBody3D
## Arcade bicycle controller. Speed is a scalar along the heading; steering uses
## a kinematic bicycle model with a low-speed "walk it round" assist so the
## player can turn around. Camera switching only changes which camera is
## current, so velocity and route state are never reset.

signal crashed(impact_speed: float)
signal camera_mode_changed(first_person: bool)
signal landed(air_time: float, hard: bool)
signal hit_by_car
signal dog_nipped

@export var max_speed := 11.0
@export var pedal_accel := 3.6
@export var brake_decel := 9.0
@export var reverse_max := 2.0
@export var rolling_drag := 0.35
@export var air_drag := 0.012
@export var wheelbase := 1.05
@export var max_steer_deg := 34.0
@export var high_speed_steer_deg := 8.0
@export var hop_velocity := 3.6
@export var gravity := 14.0
@export var crash_speed := 7.0
@export var recover_time := 1.6
@export var reverse_delay := 0.6
@export var launch_memory_decay := 4.0
@export var step_height := 0.2      # obstacles lower than this (curbs) are ridden over

var speed := 0.0
var steer := 0.0
var lean := 0.0
var air_time := 0.0
var crash_timer := 0.0          # > 0 while controls are locked by a crash
var crashing := false            # GTA-style crash sequence running (see crash_sequence.gd)
var _slide_v := Vector3.ZERO     # bike sliding after a crash
var _slide_spin := 0.0
var _fp_before_crash := false
var controls_enabled := true
var first_person := false
var nearby_target: Node = null
var nearby_depot: Node = null
var _last_safe := Transform3D.IDENTITY
var _safe_timer := 0.0
var _vertical := 0.0
var _stopped_time := 0.0
var _launch_vy := 0.0

@onready var visual: Node3D = $Visual
@onready var tp_rig: Node3D = $ThirdPersonRig
@onready var tp_camera: Camera3D = $ThirdPersonRig/SpringArm3D/Camera3D
@onready var fp_camera: Camera3D = $FirstPersonCamera


func _ready() -> void:
	add_to_group("player")
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	_last_safe = global_transform
	tp_rig.setup(self)
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		toggle_camera()
	elif event.is_action_pressed("respawn"):
		respawn()
	elif event.is_action_pressed("bell"):
		ring_bell()


## Ring-ring: pedestrians ahead step aside.
func ring_bell() -> void:
	_sfx("bell", -6.0, randf_range(0.98, 1.02))
	get_tree().call_group("pedestrians", "hear_bell", global_position, -global_transform.basis.z)


func _sfx(key: String, db := 0.0, pitch := 1.0) -> void:
	var a := get_tree().get_first_node_in_group("audio")
	if a:
		a.play(key, db, pitch)


func toggle_camera() -> void:
	first_person = not first_person
	_apply_camera()
	camera_mode_changed.emit(first_person)


func _apply_camera() -> void:
	fp_camera.current = first_person
	tp_camera.current = not first_person
	# Hide the head in first person so it doesn't block the view.
	visual.set_head_visible(not first_person)


func _physics_process(delta: float) -> void:
	if crashing:
		_crash_physics(delta)
		return
	var throttle := 0.0
	var brake := 0.0
	var steer_in := 0.0
	if controls_enabled and crash_timer <= 0.0:
		throttle = Input.get_action_strength("pedal")
		brake = Input.get_action_strength("brake")
		steer_in = Input.get_axis("steer_right", "steer_left")

	var on_floor := is_on_floor()

	# Longitudinal.
	if on_floor:
		if throttle > 0.0 and speed >= -0.1:
			var headroom := clampf(1.0 - speed / max_speed, 0.0, 1.0)
			speed += pedal_accel * throttle * (0.35 + 0.65 * headroom) * delta
		if brake > 0.0:
			if speed > 0.25:
				speed = move_toward(speed, 0.0, brake_decel * brake * delta)
				_stopped_time = 0.0
			elif throttle <= 0.0:
				# Brief hold at a standstill before rolling backwards.
				_stopped_time += delta
				if _stopped_time > reverse_delay:
					speed = move_toward(speed, -reverse_max, 2.5 * brake * delta)
				else:
					speed = move_toward(speed, 0.0, brake_decel * delta)
		else:
			_stopped_time = 0.0
			if throttle > 0.0 and speed < 0.0:
				speed = move_toward(speed, 0.0, brake_decel * delta)
		speed = move_toward(speed, 0.0, (rolling_drag + air_drag * speed * speed) * delta)
	else:
		speed = move_toward(speed, 0.0, air_drag * speed * speed * delta)

	# Steering: available lock shrinks with speed for stability.
	var t := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var lock := deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, sqrt(t)))
	steer = move_toward(steer, steer_in * lock, 3.0 * delta)
	var yaw_rate := 0.0
	if on_floor or air_time < 0.15:
		yaw_rate = speed * tan(steer) / wheelbase
		if absf(speed) < 1.5:
			# Low-speed assist: shuffle the bike around even when nearly stopped.
			yaw_rate += steer_in * 1.1 * (1.0 - absf(speed) / 1.5)
	rotate_y(yaw_rate * delta)

	# Vertical.
	if on_floor:
		if air_time > 0.35:
			var hard := _vertical < -7.5
			landed.emit(air_time, hard)
			_sfx("thud", -4.0 if hard else -14.0, 1.2 if not hard else 0.9)
			if hard:
				speed *= 0.6
		air_time = 0.0
		_vertical = -0.5
		# Remember how fast we were climbing so a ramp lip launches us even
		# though the body levels out for a few frames while crossing the edge.
		var n := get_floor_normal()
		var fwd_now := -global_transform.basis.z
		var climb := -speed * fwd_now.dot(n) / maxf(n.y, 0.5)
		_launch_vy = maxf(climb, _launch_vy - launch_memory_decay * delta)
		if controls_enabled and crash_timer <= 0.0 and Input.is_action_just_pressed("jump"):
			_vertical = hop_velocity
			on_floor = false
	else:
		if air_time == 0.0:
			# Leaving the ground (ramp lip): keep the upward momentum we had.
			_vertical = maxf(_vertical, _launch_vy)
			_launch_vy = 0.0
		air_time += delta
		_vertical -= gravity * delta

	var fwd := -global_transform.basis.z
	var pre_velocity := fwd * speed
	velocity = Vector3(pre_velocity.x, _vertical, pre_velocity.z)
	move_and_slide()

	# Walls (not curbs or slopes) cost speed and can cause a crash.
	var hit_wall := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y < 0.3 and c.get_position().y - global_position.y > step_height:
			hit_wall = true
			var impact := -pre_velocity.dot(n)
			if impact > crash_speed and crash_timer <= 0.0:
				_crash(impact, pre_velocity)
				break
	if hit_wall and crash_timer <= 0.0:
		var real := get_real_velocity()
		var along := fwd.dot(Vector3(real.x, 0, real.z))
		if absf(along) < absf(speed):
			speed = along
	if is_on_ceiling() and _vertical > 0.0:
		_vertical = 0.0

	_update_visual(delta, yaw_rate, throttle > 0.0 and on_floor)
	_update_safety(delta)


## Called by a traffic car that couldn't stop in time. Knocks the rider over
## and nudges them out of the lane.
func hit_by_vehicle(push: Vector3) -> void:
	if crash_timer > 0.0:
		return
	global_position += Vector3(push.z, 0, -push.x).normalized() * 0.8 * signf(randf() - 0.5) + push.normalized() * 0.4
	hit_by_car.emit()
	_crash(push.length(), push)


## A chasing dog caught up: lose some speed (no crash, nothing graphic).
func dog_nip() -> void:
	speed *= 0.7
	dog_nipped.emit()


## Start the crash sequence: the bike drops and slides, the rider is thrown
## along `direction` as far as the impact allows, then gets up, walks back,
## lifts the bike and remounts. Controls return when the visual says so.
func _crash(impact: float, direction := Vector3.ZERO) -> void:
	var d := Vector3(direction.x, 0, direction.z)
	if d.length_squared() < 1e-4:
		d = -global_transform.basis.z * signf(speed if absf(speed) > 0.1 else 1.0)
	d = d.normalized()
	crash_timer = recover_time
	crashing = true
	speed = 0.0
	lean = 0.0
	var sev := clampf((impact - 6.0) / 6.0, 0.0, 1.0)
	_slide_v = d * (0.6 + 2.2 * sev)
	_slide_spin = randf_range(-1.0, 1.0) * (0.4 + 1.2 * sev)
	_fp_before_crash = first_person
	if first_person:
		# Watch the fall from outside, like GTA.
		first_person = false
		_apply_camera()
	_sfx("crash", -3.0)
	visual.start_crash(impact, d)
	crashed.emit(impact)


func _crash_physics(delta: float) -> void:
	# The bike skids to a stop and spins a little; gravity still applies.
	_vertical = -0.5 if is_on_floor() else _vertical - gravity * delta
	velocity = Vector3(_slide_v.x, _vertical, _slide_v.z)
	move_and_slide()
	_slide_v = _slide_v.move_toward(Vector3.ZERO, 4.0 * delta)
	rotate_y(_slide_spin * delta)
	_slide_spin = move_toward(_slide_spin, 0.0, 3.0 * delta)
	var hurry := Input.is_action_pressed("pedal") or Input.is_action_pressed("brake") or Input.is_action_pressed("interact")
	tp_rig.focus = visual.crash_focus()
	if visual.update_crash(delta, hurry):
		_end_crash()


func _end_crash() -> void:
	crashing = false
	crash_timer = 0.0
	speed = 0.0
	lean = 0.12          # matches the stopped, foot-down lean the rider mounts into
	_slide_v = Vector3.ZERO
	tp_rig.focus = null
	visual.set_rest_immediate()
	if _fp_before_crash:
		first_person = true
		_apply_camera()


func _cancel_crash() -> void:
	if crashing:
		visual.cancel_crash()
	crashing = false
	crash_timer = 0.0
	tp_rig.focus = null


func _update_visual(delta: float, yaw_rate: float, pedalling: bool) -> void:
	var target_lean := 0.0
	# Stopped on the ground with no pedalling: put a foot down and lean onto it.
	var stopped := is_on_floor() and absf(speed) < 0.35 and not pedalling and crash_timer <= 0.0
	visual.set_rest(stopped, delta)
	if is_on_floor():
		target_lean = clampf(atan(speed * yaw_rate / 9.8), -0.42, 0.42)
		target_lean = lerpf(target_lean, 0.12, visual.rest_amount())
	lean = lerpf(lean, target_lean, 1.0 - exp(-6.0 * delta))
	visual.update_motion(speed, steer, lean, pedalling, delta)


func _update_safety(delta: float) -> void:
	_safe_timer += delta
	if is_on_floor() and crash_timer <= 0.0 and _safe_timer > 1.5:
		_safe_timer = 0.0
		_last_safe = global_transform
	if global_position.y < -20.0:
		respawn()


func respawn() -> void:
	global_transform = _last_safe
	speed = 0.0
	_vertical = 0.0
	velocity = Vector3.ZERO
	_cancel_crash()
	visual.set_crash_tilt(0.0)


func teleport(xform: Transform3D) -> void:
	_cancel_crash()
	global_transform = xform
	_last_safe = xform
	speed = 0.0
	velocity = Vector3.ZERO
	tp_rig.snap()


func get_speed_kmh() -> float:
	return absf(speed) * 3.6
