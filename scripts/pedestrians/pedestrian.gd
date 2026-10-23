extends AnimatableBody3D
## A townsperson built from pedestrian.glb segments with a procedural walk.
## mode "loop": walks a sidewalk loop. mode "crossing": waits at the kerb for
## a gap in traffic, crosses on the zebra, pauses, and crosses back.
## Stops for the player in its way and flinches when a bike whizzes past.

const Geo = preload("res://scripts/systems/geo.gd")
const SB = preload("res://scripts/systems/segment_body.gd")

enum State { WALK, WAIT, STARTLED }

@export var walk_speed := 1.3
var mode := "loop"
var points: PackedVector3Array
var idx := 0
var state := State.WALK
var speed := 0.0
var _phase := 0.0
var _wait_t := 0.0
var _startle_t := 0.0
var _seg := {}
var _model: Node3D
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _think_t := 0.0
var _player_block := false
var _side := 0.0          # sidestep offset (m) after hearing a bell
var _side_t := 0.0


func setup(model_scene: PackedScene, pts: PackedVector3Array, start_idx: int, walk_mode: String, colors: Dictionary) -> void:
	points = pts
	idx = start_idx % pts.size()
	mode = walk_mode
	add_to_group("pedestrians")
	collision_layer = Geo.LAYER_NPCS
	collision_mask = 0
	# Moved incrementally from script, so don't defer transforms to the physics
	# step (sync_to_physics would discard the per-frame steps).
	sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	if model_scene:
		_model = model_scene.instantiate()
		add_child(_model)
		_seg = SB.collect(_model)
		for mat_name in colors:
			SB.recolor(_model, mat_name, colors[mat_name])
	walk_speed *= randf_range(0.85, 1.15)
	_think_t = randf() * 0.2
	global_position = points[idx]
	_last_pos = global_position
	if mode == "crossing":
		state = State.WAIT
		_wait_t = randf_range(1.0, 4.0)
	_pose(0.0)


func _physics_process(delta: float) -> void:
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.2
		_think()
	var target_speed := 0.0
	match state:
		State.WALK:
			target_speed = 0.0 if _player_block else walk_speed
		State.WAIT:
			_wait_t -= delta
			if _wait_t <= 0.0 and (mode != "crossing" or _road_clear()):
				state = State.WALK
		State.STARTLED:
			_startle_t -= delta
			if _startle_t <= 0.0:
				state = State.WALK
	speed = move_toward(speed, target_speed, 3.0 * delta)
	if speed > 0.01:
		var to := points[(idx + 1) % points.size()] - global_position
		to.y = 0.0
		var step := speed * delta
		if to.length() <= step:
			global_position = points[(idx + 1) % points.size()]
			idx = (idx + 1) % points.size()
			if mode == "crossing":
				# Each crossing path has two ends; pause at each kerb.
				state = State.WAIT
				_wait_t = randf_range(3.0, 7.0)
				speed = 0.0
		else:
			var dir := to.normalized()
			global_position += dir * step
			var want := Basis.looking_at(dir, Vector3.UP)
			global_basis = global_basis.slerp(want, clampf(8.0 * delta, 0.0, 1.0)).orthonormalized()
	# Sidestep: shift sideways (to our right) while the bell's effect lasts.
	_side_t = maxf(0.0, _side_t - delta)
	var want_side := 0.8 if _side_t > 0.0 else 0.0
	var ds := move_toward(_side, want_side, 1.5 * delta) - _side
	_side += ds
	global_position += global_basis.x * ds
	_phase += speed * delta * 3.6
	_pose(delta)


## Every 0.2 s: player in the way? bike rushing past? stuck?
func _think() -> void:
	_player_block = false
	for p in get_tree().get_nodes_in_group("player"):
		var rel: Vector3 = p.global_position - global_position
		rel.y = 0.0
		var fwd := -global_basis.z
		var along := rel.dot(fwd)
		if along > 0.0 and along < 2.6 and (rel - fwd * along).length() < 0.9:
			_player_block = true
		if rel.length() < 2.2 and absf(p.speed) > 5.0 and state != State.STARTLED:
			state = State.STARTLED
			_startle_t = 0.9
	# Follow the ground (kerbs, road surface on crossings).
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 2.0, Geo.LAYER_WORLD))
	if hit:
		global_position.y = hit.position.y
	# Stuck recovery: no progress while trying to walk -> skip to the next point.
	if state == State.WALK and not _player_block:
		if global_position.distance_to(_last_pos) < 0.05:
			_stuck_t += 0.2
			if _stuck_t > 5.0:
				idx = (idx + 1) % points.size()
				global_position = points[idx]
				_stuck_t = 0.0
		else:
			_stuck_t = 0.0
	_last_pos = global_position


## Bell rung behind/near us: step aside for a few seconds.
func hear_bell(from: Vector3, bike_fwd: Vector3) -> void:
	var rel := global_position - from
	rel.y = 0.0
	if rel.length() > 9.0 or rel.dot(bike_fwd) < 0.0:
		return
	_side_t = 3.0


func _road_clear() -> bool:
	for car in get_tree().get_nodes_in_group("traffic"):
		var rel: Vector3 = global_position - car.global_position
		var along: float = rel.dot(car.forward())
		if along > -3.0 and along < 28.0 and absf((rel - car.forward() * along).length()) < 12.0 and car.speed > 1.0:
			return false
	return true


func _pose(_delta: float) -> void:
	if _seg.is_empty():
		return
	var fwd := Vector3(0, 0, -1)
	var walk := clampf(speed / maxf(walk_speed, 0.1), 0.0, 1.0)
	var bob := absf(sin(_phase)) * 0.025 * walk
	var hip := Vector3(0, 0.93 + bob, 0)
	var lean := 0.05 * walk
	var up := Vector3(0, 1, -lean).normalized()
	var torso := Transform3D(SB.seg_basis(up, fwd), hip)
	_seg["Torso"].transform = torso
	_seg["Head"].transform = Transform3D(SB.seg_basis(Vector3.UP, fwd), torso * Vector3(0, SB.TORSO, 0))
	var startled := state == State.STARTLED
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var ph := _phase + (0.0 if side == "L" else PI)
		var a := sin(ph) * 0.42 * walk
		var knee_bend := maxf(0.0, sin(ph + 1.2)) * 0.75 * walk
		var h := torso * Vector3(sx * 0.09, 0, 0)
		var knee := h + Vector3(0, -cos(a), -sin(a)) * SB.THIGH
		var ankle := knee + Vector3(0, -cos(a - knee_bend), -sin(a - knee_bend)) * SB.SHIN
		SB.place(_seg["Thigh" + side], h, knee, fwd)
		SB.place(_seg["Shin" + side], knee, ankle, fwd)
		_seg["Foot" + side].transform = Transform3D(SB.seg_basis(Vector3.UP, fwd), ankle)
		var sh := torso * Vector3(sx * 0.19, 0.46, 0)
		var elbow: Vector3
		var hand: Vector3
		if startled:
			# Arms up in surprise.
			elbow = sh + Vector3(sx * 0.2, 0.15, -0.15).normalized() * SB.UPPER_ARM
			hand = elbow + Vector3(sx * 0.05, 0.3, -0.05).normalized() * SB.FOREARM
		else:
			var arm_a := -sin(ph) * 0.35 * walk
			elbow = sh + Vector3(sx * 0.05, -cos(arm_a), -sin(arm_a)).normalized() * SB.UPPER_ARM
			hand = elbow + Vector3(sx * 0.03, -cos(arm_a + 0.35), -sin(arm_a + 0.35)).normalized() * SB.FOREARM
		SB.place(_seg["UpperArm" + side], sh, elbow, fwd)
		SB.place(_seg["Forearm" + side], elbow, hand, fwd)
