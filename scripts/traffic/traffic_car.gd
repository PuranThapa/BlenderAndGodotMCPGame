extends AnimatableBody3D
## A car that drives a closed lane loop. Looks ahead for the player,
## pedestrians, animals and other cars and brakes to keep a gap; slows for
## corners; takes turns at junctions through the TrafficManager's reservations.
## If blocked by something other than the player for too long it creeps past
## (stuck recovery) so traffic never deadlocks.

const Geo = preload("res://scripts/systems/geo.gd")

@export var cruise_speed := 9.0
@export var accel := 2.5
@export var brake := 7.0
@export var gap := 4.5            # metres kept to the obstacle ahead
@export var stuck_timeout := 10.0

var manager: Node
var path: PackedVector3Array
var cum: PackedFloat32Array        # cumulative distance at each point
var total := 0.0
var dist := 0.0
var speed := 0.0
var blocked_by := ""               # "", "player", "car", "pedestrian", "animal", "junction"
var _obstacle_dist := INF
var _scan_t := 0.0
var _stuck_t := 0.0
var _ghost_t := 0.0
var _wheels: Array = []
var _junction := -1
var _engine: AudioStreamPlayer3D
var _wait_player_t := 0.0
var _horn_cool := 0.0


func setup(mgr: Node, points: PackedVector3Array, start_dist: float, color: Color, model: PackedScene) -> void:
	manager = mgr
	path = points
	cum.resize(path.size() + 1)
	cum[0] = 0.0
	for i in path.size():
		cum[i + 1] = cum[i] + path[i].distance_to(path[(i + 1) % path.size()])
	total = cum[path.size()]
	dist = fposmod(start_dist, total)
	add_to_group("traffic")
	collision_layer = Geo.LAYER_VEHICLES
	collision_mask = 0
	sync_to_physics = true
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.4, 4.1)
	cs.shape = shape
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)
	if model != null:
		var car := model.instantiate()
		add_child(car)
		for mi in car.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(si)
				if m != null and m.resource_name == "Car_Paint":
					var c := m.duplicate() as StandardMaterial3D
					c.albedo_color = color
					mi.set_surface_override_material(si, c)
		for wn in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
			var w := car.find_child(wn, true, false)
			if w:
				_wheels.append(w)
	_scan_t = randf() * 0.1      # stagger scans between cars
	var audio := mgr.get_tree().get_first_node_in_group("audio")
	if audio:
		_engine = audio.attach_loop(self, "engine", -12.0, 45.0)
	global_transform = _xform_at(dist)


func sample(d: float) -> Vector3:
	d = fposmod(d, total)
	var lo := 0
	var hi := path.size()
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg_len := cum[lo + 1] - cum[lo]
	var t := (d - cum[lo]) / seg_len if seg_len > 0.0 else 0.0
	return path[lo].lerp(path[(lo + 1) % path.size()], t)


func _xform_at(d: float) -> Transform3D:
	var p := sample(d)
	var ahead := sample(d + 2.0)
	var dir := (ahead - sample(d - 1.0))
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


func forward() -> Vector3:
	return -global_transform.basis.z


func _physics_process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.1
		_scan()
	var target := cruise_speed
	# Slow for corners: heading change over the next 12 m.
	var d0 := (sample(dist + 1.0) - sample(dist)).normalized()
	var d1 := (sample(dist + 13.0) - sample(dist + 12.0)).normalized()
	if d0.dot(d1) < 0.9:
		target = minf(target, 5.0)
	if _ghost_t > 0.0:
		_ghost_t -= delta
		target = minf(target, 3.0)
	elif _obstacle_dist < INF:
		target = minf(target, clampf((_obstacle_dist - gap) * 1.1, 0.0, cruise_speed))
	if target < speed:
		speed = move_toward(speed, target, brake * delta)
	else:
		speed = move_toward(speed, target, accel * delta)
	# Stuck recovery: blocked by a non-player obstacle for too long.
	if speed < 0.2 and blocked_by != "" and blocked_by != "player":
		_stuck_t += delta
		if _stuck_t > stuck_timeout:
			_stuck_t = 0.0
			_ghost_t = 3.0
	else:
		_stuck_t = 0.0
	dist = fposmod(dist + speed * delta, total)
	global_transform = _xform_at(dist)
	for w in _wheels:
		w.rotation.x -= speed / 0.32 * delta
	if _engine:
		_engine.pitch_scale = 0.75 + speed / cruise_speed * 0.6
	# A short polite toot if the player keeps blocking the lane.
	_horn_cool = maxf(0.0, _horn_cool - delta)
	if blocked_by == "player" and speed < 0.5:
		_wait_player_t += delta
		if _wait_player_t > 2.0 and _horn_cool <= 0.0:
			_horn_cool = 7.0
			var audio := get_tree().get_first_node_in_group("audio")
			if audio:
				audio.play_at("horn", global_position, -4.0, randf_range(0.95, 1.05))
	else:
		_wait_player_t = 0.0


func _scan() -> void:
	var pos := global_position
	var fwd := forward()
	var look := maxf(12.0, speed * speed / (2.0 * brake) + gap + 6.0)
	_obstacle_dist = INF
	blocked_by = ""
	for group in ["player", "pedestrians", "animals", "traffic", "obstacles"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == self or not (n is Node3D):
				continue
			var rel: Vector3 = n.global_position - pos
			rel.y = 0.0
			var along := rel.dot(fwd)
			if along <= 0.5 or along > look:
				continue
			var lateral := (rel - fwd * along).length()
			# Wider lateral margin for people so cars stop before crossings.
			var half := 1.7 if group == "traffic" else 2.0
			if lateral < half:
				var d := along - (2.2 if group == "traffic" else 0.0)
				if d < _obstacle_dist:
					_obstacle_dist = d
					blocked_by = {"player": "player", "pedestrians": "pedestrian", "animals": "animal", "traffic": "car", "obstacles": "rider"}[group]
	# Junction reservation: wait if another car holds the junction ahead.
	var j: int = manager.junction_ahead(self, pos, fwd, 14.0)
	if j != _junction and _junction >= 0:
		manager.release_junction(_junction, self)
	_junction = j
	if j >= 0 and not manager.request_junction(j, self):
		var jd: float = manager.junction_distance(j, pos) - 7.0
		if jd < _obstacle_dist:
			_obstacle_dist = maxf(jd + gap, 0.0)
			blocked_by = "junction"
	# A car that can't stop in time still mustn't run anyone over: if the
	# player is right in front of a moving car, knock them down (fair penalty).
	if blocked_by == "player" and _obstacle_dist < 3.2 and speed > 3.0:
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("hit_by_vehicle"):
				p.hit_by_vehicle(fwd * speed)
		speed = 0.0
