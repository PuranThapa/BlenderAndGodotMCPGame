extends Node3D
## Bicycle + rider visual. Forward is -Z, ground at y = 0.
## Uses the Blender bicycle (assets/models/bicycle.glb) when present, else a
## primitive graybox with the same pivot names: RearWheel, Crank/PedalL/PedalR,
## SteerPivot/FrontWheel, SteerPivot/GripL/GripR. The rider is procedural and
## IK-posed onto the pedals and grips every frame.
## Exposes update_motion() so the controller can drive wheel spin, steering,
## pedalling and lean.

const Geo = preload("res://scripts/systems/geo.gd")
const CrashSequence = preload("res://scripts/player/crash_sequence.gd")
const BIKE_MODEL := "res://assets/models/bicycle.glb"
const RIDER_MODEL := "res://assets/models/rider.glb"
# Segment lengths baked into rider.glb (see assets/blender/build_rider.py).
const R_TORSO := 0.50
const R_UPPER_ARM := 0.30
const R_FOREARM := 0.30
const R_THIGH := 0.46
const R_SHIN := 0.44
const RIDER_SEGMENTS := ["Torso", "Head", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "ThighL", "ThighR", "ShinL", "ShinR", "FootL", "FootR"]

const WHEEL_R := 0.34
const REAR_AXLE := Vector3(0, WHEEL_R, 0.525)
const BB := Vector3(0, 0.30, 0.05)
const SEAT := Vector3(0, 0.86, 0.16)
const HEAD_TOP := Vector3(0, 0.92, -0.40)
const HEAD_BOT := Vector3(0, 0.74, -0.44)
const STEER_Z := -0.42
const CRANK_LEN := 0.17
const THIGH := 0.46
const SHIN := 0.46

var bike_root: Node3D
var rear_wheel: Node3D
var front_wheel: Node3D
var steer_pivot: Node3D
var crank: Node3D
var rider: Node3D
var _pedal_l: Node3D
var _pedal_r: Node3D
var _legs := {}
var _arms := {}
var _head_parts: Array = []
var _seg := {}          # rider.glb segment name -> Node3D (empty when using the graybox rider)
var _rest := 0.0        # 0 riding .. 1 stopped with the left foot on the ground
var _throw_t := -1.0    # throwing-arm animation progress (0..1), <0 when idle
var look_target = null  # world point the rider glances at (next house), or null
const PEDAL_READY := 2.4   # crank angle with the right pedal up and forward
const THROW_TIME := 0.45
var _grip_l: Node3D
var _grip_r: Node3D
var _crank_angle := 0.0
var _crash_tilt := 0.0
var crash := CrashSequence.new()
var _rider_marker: Node3D

var m_frame: Material
var m_dark: Material
var m_metal: Material
var m_skin: Material
var m_shirt: Material
var m_pants: Material
var m_shoe: Material


func _ready() -> void:
	m_frame = Geo.mat("bike_frame", Color(0.62, 0.08, 0.07), 0.35, 0.0, 0.3)
	m_dark = Geo.mat("rubber", Color(0.05, 0.05, 0.05), 0.9)
	m_metal = Geo.mat("chrome", Color(0.75, 0.75, 0.78), 0.25, 0.0, 0.9)
	m_skin = Geo.mat("skin", Color(0.78, 0.57, 0.42), 0.7)
	m_shirt = Geo.mat("shirt", Color(0.20, 0.36, 0.62), 0.85)
	m_pants = Geo.mat("pants", Color(0.55, 0.47, 0.33), 0.9)
	m_shoe = Geo.mat("shoe", Color(0.15, 0.12, 0.10), 0.8)
	if not _load_bike_model():
		_build_bike()
	_build_rider()
	update_motion(0.0, 0.0, 0.0, false)


func _load_bike_model() -> bool:
	if not ResourceLoader.exists(BIKE_MODEL):
		return false
	var scene := load(BIKE_MODEL) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.name = "BikeModel"
	add_child(model)
	bike_root = model
	rear_wheel = model.find_child("RearWheel", true, false)
	crank = model.find_child("Crank", true, false)
	steer_pivot = model.find_child("SteerPivot", true, false)
	front_wheel = model.find_child("FrontWheel", true, false)
	_pedal_l = model.find_child("PedalL", true, false)
	_pedal_r = model.find_child("PedalR", true, false)
	_grip_l = model.find_child("GripL", true, false)
	_grip_r = model.find_child("GripR", true, false)
	for n in [rear_wheel, crank, steer_pivot, front_wheel, _pedal_l, _pedal_r, _grip_l, _grip_r]:
		if n == null:
			push_warning("bicycle.glb is missing a pivot node; using graybox bike")
			model.queue_free()
			return false
	return true


func _build_bike() -> void:
	bike_root = Node3D.new()
	bike_root.name = "Bike"
	add_child(bike_root)

	rear_wheel = _make_wheel("RearWheel")
	rear_wheel.position = REAR_AXLE
	bike_root.add_child(rear_wheel)

	# Frame tubes.
	Geo.tube(bike_root, BB, SEAT, 0.022, m_frame)
	Geo.tube(bike_root, SEAT + Vector3(0, -0.05, -0.02), HEAD_TOP, 0.02, m_frame)
	Geo.tube(bike_root, BB, HEAD_BOT, 0.026, m_frame)
	Geo.tube(bike_root, HEAD_BOT, HEAD_TOP, 0.028, m_frame)
	for side in [-0.06, 0.06]:
		Geo.tube(bike_root, REAR_AXLE + Vector3(side, 0, 0), BB + Vector3(side * 0.4, 0, 0), 0.012, m_frame)
		Geo.tube(bike_root, REAR_AXLE + Vector3(side, 0, 0), SEAT + Vector3(side * 0.3, -0.07, 0), 0.011, m_frame)
	# Seat post + saddle.
	Geo.tube(bike_root, SEAT, SEAT + Vector3(0, 0.06, 0.01), 0.014, m_metal)
	Geo.box(bike_root, SEAT + Vector3(0, 0.08, 0.02), Vector3(0.14, 0.05, 0.26), m_dark)
	# Rear carrier with a newspaper bundle.
	Geo.box(bike_root, Vector3(0, 0.66, 0.50), Vector3(0.16, 0.02, 0.36), m_metal)
	Geo.tube(bike_root, Vector3(0.07, 0.66, 0.66), REAR_AXLE + Vector3(0.07, 0, 0), 0.008, m_metal)
	Geo.tube(bike_root, Vector3(-0.07, 0.66, 0.66), REAR_AXLE + Vector3(-0.07, 0, 0), 0.008, m_metal)
	Geo.box(bike_root, Vector3(0, 0.73, 0.50), Vector3(0.22, 0.12, 0.30), Geo.mat("newsprint", Color(0.86, 0.84, 0.78), 0.95))

	# Crank, chainring, pedals.
	crank = Node3D.new()
	crank.name = "Crank"
	crank.position = BB
	bike_root.add_child(crank)
	var ring := Geo.cylinder(crank, Vector3(0.07, 0, 0), 0.10, 0.008, m_metal)
	ring.rotation.z = PI / 2
	Geo.tube(crank, Vector3(0.08, 0, 0), Vector3(0.08, -CRANK_LEN, 0), 0.012, m_metal)
	Geo.tube(crank, Vector3(-0.08, 0, 0), Vector3(-0.08, CRANK_LEN, 0), 0.012, m_metal)
	_pedal_r = Geo.box(crank, Vector3(0.13, -CRANK_LEN, 0), Vector3(0.09, 0.02, 0.06), m_dark)
	_pedal_l = Geo.box(crank, Vector3(-0.13, CRANK_LEN, 0), Vector3(0.09, 0.02, 0.06), m_dark)
	# Chain (static loop approximation).
	Geo.tube(bike_root, BB + Vector3(0.07, 0.10, 0), REAR_AXLE + Vector3(0.07, 0.04, 0), 0.006, m_dark)
	Geo.tube(bike_root, BB + Vector3(0.07, -0.10, 0), REAR_AXLE + Vector3(0.07, -0.04, 0), 0.006, m_dark)

	# Steering assembly: fork, front wheel, stem, bars, brake levers, basket.
	steer_pivot = Node3D.new()
	steer_pivot.name = "SteerPivot"
	steer_pivot.position = Vector3(0, 0, STEER_Z)
	bike_root.add_child(steer_pivot)
	var fwd_axle := Vector3(0, WHEEL_R, -0.525 - STEER_Z)
	front_wheel = _make_wheel("FrontWheel")
	front_wheel.position = fwd_axle
	steer_pivot.add_child(front_wheel)
	for side in [-0.055, 0.055]:
		Geo.tube(steer_pivot, Vector3(side * 0.5, HEAD_BOT.y, HEAD_BOT.z - STEER_Z), fwd_axle + Vector3(side, 0, 0), 0.013, m_metal)
	var stem_top := Vector3(0, 1.0, 0.03)
	Geo.tube(steer_pivot, Vector3(0, HEAD_TOP.y, HEAD_TOP.z - STEER_Z), stem_top, 0.016, m_metal)
	Geo.tube(steer_pivot, stem_top + Vector3(-0.29, 0, 0.03), stem_top + Vector3(0.29, 0, 0.03), 0.012, m_metal)
	_grip_l = Node3D.new()
	_grip_l.position = stem_top + Vector3(-0.25, 0, 0.03)
	steer_pivot.add_child(_grip_l)
	_grip_r = Node3D.new()
	_grip_r.position = stem_top + Vector3(0.25, 0, 0.03)
	steer_pivot.add_child(_grip_r)
	for g in [_grip_l, _grip_r]:
		var grip := Geo.cylinder(g, Vector3.ZERO, 0.017, 0.11, m_dark)
		grip.rotation.z = PI / 2
		Geo.tube(g, Vector3(0, 0.0, -0.02), Vector3(0, -0.02, -0.11), 0.006, m_metal)
	# Front basket.
	Geo.box(steer_pivot, Vector3(0, 0.74, -0.20), Vector3(0.30, 0.16, 0.22), Geo.mat("basket", Color(0.45, 0.33, 0.18), 0.9))
	Geo.box(steer_pivot, Vector3(0, 0.83, -0.20), Vector3(0.24, 0.04, 0.18), Geo.mat("newsprint", Color(0.86, 0.84, 0.78), 0.95))


func _make_wheel(wheel_name: String) -> Node3D:
	var w := Node3D.new()
	w.name = wheel_name
	var tyre := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = WHEEL_R - 0.04
	torus.outer_radius = WHEEL_R
	torus.rings = 32
	torus.ring_segments = 8
	tyre.mesh = torus
	tyre.material_override = m_dark
	tyre.rotation.z = PI / 2
	w.add_child(tyre)
	var hub := Geo.cylinder(w, Vector3.ZERO, 0.03, 0.10, m_metal)
	hub.rotation.z = PI / 2
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(0, cos(a), sin(a)) * (WHEEL_R - 0.04)
		Geo.tube(w, Vector3.ZERO, p, 0.003, m_metal)
	return w


func _build_rider() -> void:
	if _load_rider_model():
		return
	rider = Node3D.new()
	rider.name = "Rider"
	add_child(rider)
	var hip := SEAT + Vector3(0, 0.13, 0.04)
	var shoulder := Vector3(0, 1.43, -0.10)
	Geo.tube(rider, hip, shoulder, 0.15, m_shirt)
	Geo.sphere(rider, hip, Vector3(0.32, 0.18, 0.24), m_pants)
	# Head, neck and cap.
	var head := shoulder + Vector3(0, 0.22, -0.06)
	var m_cap := Geo.mat("cap", Color(0.72, 0.12, 0.10), 0.8)
	_head_parts = [
		Geo.tube(rider, shoulder, shoulder + Vector3(0, 0.1, -0.03), 0.05, m_skin),
		Geo.sphere(rider, head, Vector3(0.21, 0.24, 0.22), m_skin),
		Geo.sphere(rider, head + Vector3(0, 0.07, 0.01), Vector3(0.23, 0.13, 0.23), m_cap),
		Geo.box(rider, head + Vector3(0, 0.05, -0.14), Vector3(0.2, 0.02, 0.12), m_cap),
	]
	# Newspaper satchel slung on the right hip with a strap.
	var m_bag := Geo.mat("satchel", Color(0.82, 0.62, 0.20), 0.9)
	Geo.box(rider, hip + Vector3(0.22, 0.08, 0.02), Vector3(0.10, 0.30, 0.36), m_bag)
	Geo.box(rider, hip + Vector3(0.22, 0.24, 0.02), Vector3(0.11, 0.06, 0.26), Geo.mat("newsprint", Color(0.86, 0.84, 0.78), 0.95))
	Geo.tube(rider, hip + Vector3(0.2, 0.2, 0.02), shoulder + Vector3(-0.14, 0.02, 0), 0.025, m_bag)
	# Limbs are re-posed every frame.
	for side in ["l", "r"]:
		_legs[side] = [Geo.tube(rider, Vector3.ZERO, Vector3.UP, 0.065, m_pants), Geo.tube(rider, Vector3.ZERO, Vector3.UP, 0.05, m_skin), Geo.box(rider, Vector3.ZERO, Vector3(0.1, 0.07, 0.24), m_shoe)]
		_arms[side] = [Geo.tube(rider, Vector3.ZERO, Vector3.UP, 0.048, m_shirt), Geo.tube(rider, Vector3.ZERO, Vector3.UP, 0.038, m_skin)]
	rider.set_meta("hip", hip)
	rider.set_meta("shoulder", shoulder)


func _load_rider_model() -> bool:
	if not ResourceLoader.exists(RIDER_MODEL):
		return false
	var model := (load(RIDER_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Rider"
	for n in RIDER_SEGMENTS:
		var node := model.find_child(n, true, false) as Node3D
		if node == null:
			push_warning("rider.glb is missing segment %s; using graybox rider" % n)
			model.free()
			_seg.clear()
			return false
		_seg[n] = node
	add_child(model)
	rider = model
	rider.set_meta("hip", SEAT + Vector3(0, 0.13, 0.04))
	rider.set_meta("shoulder", Vector3(0, 1.43, -0.10))
	_head_parts = [_seg["Head"]]
	return true


## speed in m/s (negative = reversing), steer angle in radians, lean in radians.
func update_motion(speed: float, steer: float, lean: float, pedalling: bool, delta := 0.0) -> void:
	var spin := speed / WHEEL_R * delta
	rear_wheel.rotation.x -= spin
	front_wheel.rotation.x -= spin
	steer_pivot.rotation.y = steer
	if pedalling:
		_crank_angle -= abs(speed) / WHEEL_R * 0.45 * delta + 2.0 * delta
	elif _rest > 0.0:
		# Stopped: bring the right pedal up and forward, ready to push off.
		var target := PEDAL_READY + TAU * roundf((_crank_angle - PEDAL_READY) / TAU)
		_crank_angle = move_toward(_crank_angle, target, 4.0 * delta)
	crank.rotation.x = _crank_angle
	if _throw_t >= 0.0:
		_throw_t += delta / THROW_TIME
		if _throw_t >= 1.0:
			_throw_t = -1.0
	rotation.z = lean + _crash_tilt
	_pose_limbs()
	if crash.phase == CrashSequence.Phase.BLEND:
		crash.blend_out(delta)


## Blend toward the "stopped, foot down" pose (called every physics frame).
func set_rest(stopped: bool, delta: float) -> void:
	_rest = move_toward(_rest, 1.0 if stopped else 0.0, delta * (3.0 if stopped else 6.0))


func rest_amount() -> float:
	return _rest


func play_throw() -> void:
	_throw_t = 0.0


## World position of the rider's right hand (where a thrown paper starts).
func right_hand_position() -> Vector3:
	if _seg.has("ForearmR"):
		var f: Node3D = _seg["ForearmR"]
		return f.global_transform * Vector3(0, -R_FOREARM, 0)
	return global_position + Vector3.UP * 1.2


func set_head_visible(v: bool) -> void:
	for p in _head_parts:
		p.visible = v


# ------------------------------------------------------------------ crash
func start_crash(impact: float, direction: Vector3) -> void:
	crash.start(self, impact, direction)
	# The thrown rider is an obstacle for traffic until he's back on the bike.
	if _rider_marker == null:
		_rider_marker = Node3D.new()
		_rider_marker.name = "FallenRider"
		_rider_marker.top_level = true
		add_child(_rider_marker)
	_rider_marker.add_to_group("obstacles")


## Runs the crash animation instead of update_motion. True when finished.
func update_crash(delta: float, hurry: bool) -> bool:
	var done := crash.update(delta, hurry)
	if _rider_marker and _seg.has("Torso"):
		_rider_marker.global_position = _seg["Torso"].global_position
		if done:
			_rider_marker.remove_from_group("obstacles")
	rotation.z = crash.roll
	steer_pivot.rotation.y = crash.steer
	rear_wheel.rotation.x -= crash.wheel_spin * delta
	front_wheel.rotation.x -= crash.wheel_spin * delta
	crank.rotation.x = _crank_angle
	return done


func is_crashing() -> bool:
	return crash.is_active()


func crash_focus() -> Vector3:
	return crash.focus()


func cancel_crash() -> void:
	crash.cancel()
	if _rider_marker:
		_rider_marker.remove_from_group("obstacles")
	rotation.z = 0.0


func set_rest_immediate() -> void:
	_rest = 1.0
	_crash_tilt = 0.0


func set_crash_tilt(t: float) -> void:
	_crash_tilt = t
	rotation.z = _crash_tilt


func _pose_limbs() -> void:
	if not _seg.is_empty():
		_pose_rider_model()
		return
	var hip: Vector3 = rider.get_meta("hip")
	var shoulder: Vector3 = rider.get_meta("shoulder")
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var pedal: Node3D = _pedal_l if side == "l" else _pedal_r
		var foot := rider.to_local(pedal.global_position) + Vector3(0, 0.05, 0)
		var h := hip + Vector3(sx * 0.1, -0.02, 0)
		var knee := _two_bone(h, foot, THIGH, SHIN, Vector3(0, 0, -1))
		var parts: Array = _legs[side]
		Geo.set_tube(parts[0], h, knee, 0.065)
		Geo.set_tube(parts[1], knee, foot, 0.05)
		parts[2].position = foot + Vector3(0, -0.02, -0.03)
		var grip: Node3D = _grip_l if side == "l" else _grip_r
		var hand := rider.to_local(grip.global_position)
		var sh := shoulder + Vector3(sx * 0.19, -0.04, 0)
		var elbow := _two_bone(sh, hand, 0.3, 0.3, Vector3(sx * 0.6, -0.2, 0.6).normalized())
		var arm: Array = _arms[side]
		Geo.set_tube(arm[0], sh, elbow, 0.048)
		Geo.set_tube(arm[1], elbow, hand, 0.038)


## Places each rigid segment of rider.glb between its joints (rider-local space).
func _pose_rider_model() -> void:
	var rest := smoothstep(0.0, 1.0, _rest)
	# Stopped: slide forward off the saddle and sit up straighter.
	var hip: Vector3 = rider.get_meta("hip") + Vector3(0, -0.05, -0.07) * rest
	var shoulder_c: Vector3 = rider.get_meta("shoulder") + Vector3(0, 0.03, 0.08) * rest
	var fwd := Vector3(0, 0, -1)
	var torso_up := (shoulder_c - hip).normalized()
	var torso := Transform3D(_seg_basis(torso_up, fwd), hip)
	_seg["Torso"].transform = torso
	# Head sits on the torso but looks more upright, toward the road ahead,
	# glancing at the next house when it's close.
	var head_up := torso_up.lerp(Vector3.UP, 0.65).normalized()
	var head_fwd := fwd
	if look_target != null:
		var to: Vector3 = rider.to_local(look_target) - torso * Vector3(0, R_TORSO, 0)
		to.y = 0.0
		if to.length() > 0.5:
			var yaw := clampf(atan2(-to.x, -to.z), -1.2, 1.2)
			head_fwd = Vector3(-sin(yaw), 0, -cos(yaw))
	_seg["Head"].transform = Transform3D(_seg_basis(head_up, head_fwd), torso * Vector3(0, R_TORSO, 0))
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		# Legs: ankle above the pedal, knee bends forward.
		var pedal: Node3D = _pedal_l if side == "L" else _pedal_r
		var ankle := rider.to_local(pedal.global_position) + Vector3(0, 0.08, 0.04)
		var foot_up := Vector3.UP
		if side == "L" and rest > 0.0:
			# Left foot planted on the ground beside the bike.
			var bike := get_parent() as Node3D
			var ground := bike.global_position - bike.global_transform.basis.x * 0.42 - bike.global_transform.basis.z * 0.08 + Vector3.UP * 0.085
			ankle = ankle.lerp(rider.to_local(ground), rest)
			foot_up = Vector3.UP.lerp(rider.global_basis.inverse() * Vector3.UP, rest).normalized()
		var h := torso * Vector3(sx * 0.09, 0.0, 0.0)
		var knee := _two_bone(h, ankle, R_THIGH, R_SHIN, (fwd + Vector3(sx * 0.25 * rest, 0, 0)).normalized())
		_place_segment("Thigh" + side, h, knee, fwd)
		_place_segment("Shin" + side, knee, ankle, fwd)
		_seg["Foot" + side].transform = Transform3D(_seg_basis(foot_up, fwd), ankle)
		# Arms: hand centre on the grip, elbows out and back.
		var grip: Node3D = _grip_l if side == "L" else _grip_r
		var hand := rider.to_local(grip.global_position)
		var sh := torso * Vector3(sx * 0.19, 0.46, 0.0)
		if side == "R" and _throw_t >= 0.0:
			# Throw: swing the right hand back, out and up, then release forward-right.
			var t := _throw_t
			var wind := sh + Vector3(0.35, 0.05, 0.25)
			var release := sh + Vector3(0.45, 0.1, -0.35)
			var arc := wind.lerp(release, smoothstep(0.2, 0.8, t))
			hand = hand.lerp(arc, sin(t * PI))
		var elbow := _two_bone(sh, hand, R_UPPER_ARM, R_FOREARM, Vector3(sx * 0.6, -0.2, 0.6).normalized())
		_place_segment("UpperArm" + side, sh, elbow, fwd)
		_place_segment("Forearm" + side, elbow, hand, fwd)


## Segment authored along local -Y from its pivot: put the pivot at `a`, point -Y at `b`.
func _place_segment(seg_name: String, a: Vector3, b: Vector3, fwd: Vector3) -> void:
	_seg[seg_name].transform = Transform3D(_seg_basis((a - b).normalized(), fwd), a)


## Basis whose +Y is `up` and whose -Z is as close to `fwd` as possible.
func _seg_basis(up: Vector3, fwd: Vector3) -> Basis:
	var f := fwd - up * fwd.dot(up)
	if f.length_squared() < 1e-6:
		f = Vector3(0, 0, -1).cross(up).cross(up)
	var z := -f.normalized()
	var x := up.cross(z)
	return Basis(x, up, z)


## Simple analytic two-bone IK; `bend` is the preferred joint direction.
func _two_bone(root: Vector3, target: Vector3, l1: float, l2: float, bend: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.001)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := (bend - dir * bend.dot(dir)).normalized()
	return root + dir * a + perp * h
