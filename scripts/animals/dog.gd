extends Node3D
## Dog behaviour on top of dog.glb (Head, LegFL/FR/RL/RR, Tail pivots).
## Yard dogs stay home and bark at the passing bike. A "chaser" dog
## telegraphs (growl + crouch) before a short, escapable chase, then trots home.
## Non-solid on purpose: a dog can nip (small penalty) but never knock you over.

enum State { IDLE, ALERT, TELEGRAPH, CHASE, RETURN }

@export var chaser := false
@export var notice_range := 13.0
@export var chase_speed := 6.5          # bike tops out at 11 m/s, so it's escapable
@export var chase_time := 6.0
@export var leash := 25.0               # max distance from home during a chase
@export var cooldown := 15.0

signal nipped

var state := State.IDLE
var home := Vector3.ZERO
var home_yaw := 0.0
var speed := 0.0
var _t := 0.0
var _state_t := 0.0
var _cool_t := 0.0
var _bark_t := 0.0
var _has_nipped := false
var _parts := {}
var _bubble: Label3D
var _ground_t := 0.0


func _ready() -> void:
	add_to_group("animals")
	add_to_group("dogs")
	home = global_position
	home_yaw = global_rotation.y
	for n in ["Head", "LegFL", "LegFR", "LegRL", "LegRR", "Tail"]:
		_parts[n] = find_child(n, true, false)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 48
	_bubble.pixel_size = 0.006
	_bubble.outline_size = 10
	_bubble.position = Vector3(0, 1.1, 0)
	_bubble.visible = false
	add_child(_bubble)


func _player():
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if ps.size() > 0 else null


func _physics_process(delta: float) -> void:
	_t += delta
	_state_t += delta
	_cool_t = maxf(0.0, _cool_t - delta)
	var p = _player()
	var to_p := Vector3.ZERO
	var d := INF
	if p:
		to_p = p.global_position - global_position
		to_p.y = 0.0
		d = to_p.length()
	match state:
		State.IDLE:
			speed = 0.0
			if d < notice_range:
				if chaser and _cool_t <= 0.0 and absf(p.speed) > 1.0:
					_enter(State.TELEGRAPH)
				else:
					_enter(State.ALERT)
		State.ALERT:
			speed = 0.0
			_face(to_p, delta, 6.0)
			_bark(delta, "Woof!")
			if d > notice_range + 4.0:
				_enter(State.IDLE)
			elif chaser and _cool_t <= 0.0 and absf(p.speed) > 1.0:
				_enter(State.TELEGRAPH)
		State.TELEGRAPH:
			# Clear warning before anything happens: growl, crouch, face the bike.
			speed = 0.0
			_face(to_p, delta, 8.0)
			_say("Grrr... WOOF!", Color(1, 0.6, 0.3))
			if _state_t > 1.3:
				_has_nipped = false
				_enter(State.CHASE)
		State.CHASE:
			_face(to_p, delta, 10.0)
			speed = move_toward(speed, chase_speed, 8.0 * delta)
			_bark(delta, "WOOF!")
			if d < 1.1 and not _has_nipped and p:
				_has_nipped = true
				nipped.emit()
				if p.has_method("dog_nip"):
					p.dog_nip()
			var far_from_home := global_position.distance_to(home) > leash
			if _state_t > chase_time or far_from_home or d > 16.0 or _has_nipped and _state_t > 1.0:
				_cool_t = cooldown
				_enter(State.RETURN)
		State.RETURN:
			var to_home := home - global_position
			to_home.y = 0.0
			if to_home.length() < 0.4:
				speed = 0.0
				rotation.y = lerp_angle(rotation.y, home_yaw, 4.0 * delta)
				if _state_t > 1.0:
					_enter(State.IDLE)
			else:
				_face(to_home, delta, 6.0)
				speed = move_toward(speed, 2.2, 4.0 * delta)
	if speed > 0.01:
		global_position += -global_basis.z * speed * delta
		_ground_t -= delta
		if _ground_t <= 0.0:
			_ground_t = 0.15
			_snap_to_ground()
	_animate(delta)


func _enter(s: State) -> void:
	state = s
	_state_t = 0.0
	if s == State.TELEGRAPH:
		_sound("growl", 0.0, 1.0)     # warning growl before a chase
	if s == State.IDLE or s == State.RETURN:
		_bubble.visible = false


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rate * delta, 0.0, 1.0))


func _bark(delta: float, text: String) -> void:
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = randf_range(0.7, 1.3)
		_say(text, Color(1, 1, 1))
		_sound("bark", -2.0, randf_range(0.9, 1.15))
	elif _bark_t < 0.4:
		_bubble.visible = false


func _sound(key: String, db: float, pitch: float) -> void:
	var a := get_tree().get_first_node_in_group("audio")
	if a:
		a.play_at(key, global_position + Vector3.UP * 0.5, db, pitch, 40.0)


func _say(text: String, color: Color) -> void:
	_bubble.text = text
	_bubble.modulate = color
	_bubble.visible = true


func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	if hit:
		global_position.y = hit.position.y


func _animate(delta: float) -> void:
	var gait := clampf(speed / 3.0, 0.0, 1.0)
	var rate := 4.0 + speed * 2.2
	var ph := _t * rate
	if _parts.LegFL:
		_parts.LegFL.rotation.x = sin(ph) * 0.6 * gait
		_parts.LegRR.rotation.x = sin(ph) * 0.6 * gait
		_parts.LegFR.rotation.x = sin(ph + PI) * 0.6 * gait
		_parts.LegRL.rotation.x = sin(ph + PI) * 0.6 * gait
	if _parts.Tail:
		var wag := 1.0 if state == State.IDLE or state == State.RETURN else 2.5
		_parts.Tail.rotation.y = sin(_t * 9.0 * wag) * 0.5
	if _parts.Head:
		var target_x := 0.0
		if state == State.IDLE:
			target_x = -0.35 + sin(_t * 1.3) * 0.15          # sniffing
		elif _bubble.visible:
			target_x = 0.25 + sin(_t * 18.0) * 0.08           # barking
		_parts.Head.rotation.x = lerpf(_parts.Head.rotation.x, target_x, clampf(8.0 * delta, 0.0, 1.0))
	# Crouch while telegraphing.
	var crouch := -0.08 if state == State.TELEGRAPH else 0.0
	var model := get_child(0) as Node3D
	if model and model != _bubble:
		model.position.y = lerpf(model.position.y, crouch, clampf(10.0 * delta, 0.0, 1.0))
