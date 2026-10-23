extends Node3D
## Cat behaviour on top of cat.glb. Sits, grooms and strolls near home; when a
## bike comes close and fast it bolts to whichever nearby spot is farthest from
## the player and NOT on a road, so it never darts into the rider's path.

enum State { SIT, STROLL, FLEE, CALM }

@export var flee_range := 7.0
@export var flee_speed := 4.5
@export var stroll_radius := 4.0

var state := State.SIT
var home := Vector3.ZERO
var city: Node
var speed := 0.0
var target := Vector3.ZERO
var _t := 0.0
var _state_t := 0.0
var _next_t := 3.0
var _parts := {}
var _ground_t := 0.0


func _ready() -> void:
	add_to_group("animals")
	add_to_group("cats")
	home = global_position
	for n in ["Head", "LegFL", "LegFR", "LegRL", "LegRR", "Tail"]:
		_parts[n] = find_child(n, true, false)


func _player():
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if ps.size() > 0 else null


func _physics_process(delta: float) -> void:
	_t += delta
	_state_t += delta
	var p = _player()
	var d := INF
	if p:
		d = (p.global_position - global_position).length()
	if state != State.FLEE and p and d < flee_range and absf(p.speed) > 1.5:
		target = _flee_target(p.global_position)
		_enter(State.FLEE)
		var a := get_tree().get_first_node_in_group("audio")
		if a and randf() < 0.7:
			a.play_at("meow", global_position, -4.0, randf_range(0.95, 1.2), 30.0)
	match state:
		State.SIT:
			speed = move_toward(speed, 0.0, 4.0 * delta)
			if _state_t > _next_t:
				target = _safe_point(home + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, stroll_radius))
				_enter(State.STROLL)
		State.STROLL:
			if _move_to(target, 0.9, delta):
				_next_t = randf_range(4.0, 9.0)
				_enter(State.SIT)
		State.FLEE:
			if _move_to(target, flee_speed, delta) or _state_t > 4.0:
				_next_t = 5.0
				_enter(State.CALM)
		State.CALM:
			speed = move_toward(speed, 0.0, 6.0 * delta)
			if _state_t > _next_t and (not p or d > flee_range + 2.0):
				target = home
				_enter(State.STROLL)
	_animate(delta)


func _enter(s: State) -> void:
	state = s
	_state_t = 0.0


func _move_to(pos: Vector3, max_speed: float, delta: float) -> bool:
	var to := pos - global_position
	to.y = 0.0
	if to.length() < 0.3:
		return true
	var yaw := atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(10.0 * delta, 0.0, 1.0))
	speed = move_toward(speed, max_speed, 10.0 * delta)
	global_position += to.normalized() * minf(speed * delta, to.length())
	_ground_t -= delta
	if _ground_t <= 0.0:
		_ground_t = 0.15
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, global_position + Vector3.DOWN * 3.0, 1))
		if hit:
			global_position.y = hit.position.y
	return false


## Of 12 candidate spots around the cat, pick the one farthest from the
## player that isn't on a road.
func _flee_target(player_pos: Vector3) -> Vector3:
	var best := global_position
	var best_score := -INF
	for i in 12:
		var a := TAU * i / 12.0
		var c := global_position + Vector3(cos(a), 0, sin(a)) * 6.0
		if city and city.has_method("is_on_road") and city.is_on_road(c):
			continue
		if city and city.has_method("is_on_road") and city.is_on_road(global_position.lerp(c, 0.5)):
			continue
		var score := c.distance_to(player_pos)
		if score > best_score:
			best_score = score
			best = c
	return best


func _safe_point(c: Vector3) -> Vector3:
	if city and city.has_method("is_on_road") and city.is_on_road(c):
		return home
	return c


func _animate(delta: float) -> void:
	var gait := clampf(speed / 2.0, 0.0, 1.0)
	var ph := _t * (5.0 + speed * 3.0)
	if _parts.LegFL:
		_parts.LegFL.rotation.x = sin(ph) * 0.7 * gait
		_parts.LegRR.rotation.x = sin(ph) * 0.7 * gait
		_parts.LegFR.rotation.x = sin(ph + PI) * 0.7 * gait
		_parts.LegRL.rotation.x = sin(ph + PI) * 0.7 * gait
	if _parts.Tail:
		_parts.Tail.rotation.z = sin(_t * 1.7) * 0.25
		_parts.Tail.rotation.x = lerpf(_parts.Tail.rotation.x, -0.6 if state == State.FLEE else 0.0, clampf(6.0 * delta, 0.0, 1.0))
	if _parts.Head:
		var look := sin(_t * 0.8) * 0.5 if state == State.SIT or state == State.CALM else 0.0
		_parts.Head.rotation.y = lerpf(_parts.Head.rotation.y, look, clampf(3.0 * delta, 0.0, 1.0))
