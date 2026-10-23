extends RefCounted
## GTA-style crash for the rider.glb segment body, driven by bike_visual.gd.
##
##   FALL   rider thrown along the impact direction (distance/height scale
##          with impact speed; blocked by walls -> deflects sideways), tumbles
##   SLIDE  skids to rest face down
##   LIE    lies still (longer after harder hits), then lifts his head
##   GETUP  push-up -> one knee -> standing
##   WALK   turns and walks back to the fallen bike
##   LIFT   crouches, grabs bar + saddle, hauls the bike upright
##   MOUNT  steps round, swings the right leg over the rear wheel, sits
##   BLEND  hands back to the normal riding pose (0.3 s cross-fade)
##
## Poses are dictionaries of joint targets (hip, feet, hands) and directions
## (torso up/forward, head) expressed in a local frame facing -Z; limbs are
## solved with two-bone IK. Everything is procedural, so it adapts to wherever
## the rider and bike actually end up.

const SB = preload("res://scripts/systems/segment_body.gd")

enum Phase { FALL, SLIDE, LIE, GETUP, WALK, LIFT, MOUNT, BLEND, DONE }

const BIKE_DOWN_ROLL := 1.32      # radians: bike lying on its left side
const BIKE_HELD_ROLL := 0.3       # leaning toward the rider while held
const REST_ROLL := 0.12           # stopped, rider's left foot down
const PEDAL_READY := 2.4

var v                              # bike_visual.gd node
var phase := Phase.DONE
var t := 0.0
var since := 0.0                   # time since impact
var sev := 0.0                     # 0 light .. 1 hard
var dir := Vector3.FORWARD
var fly_start := Vector3.ZERO
var land := Vector3.ZERO
var rest_pt := Vector3.ZERO
var arc := 0.5
var yaw_spin := 0.0
var dur := {}
var roll := 0.0
var steer := 0.0
var wheel_spin := 0.0
var _lie_frame := Transform3D.IDENTITY
var _walk := {}
var _ph := 0.0
var _snap := {}
var _snap_t := 0.0
var _snap_len := 0.15
var _body_only := false
var _base_y := 0.0                 # ground height where the crash began


# ------------------------------------------------------------------ lifecycle
func start(visual, impact: float, direction: Vector3) -> void:
	v = visual
	sev = clampf((impact - 6.0) / 6.0, 0.0, 1.0)
	dir = Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 1e-4:
		dir = -v.get_parent().global_transform.basis.z
	dir = dir.normalized()
	since = 0.0
	t = 0.0
	roll = 0.0
	steer = randf_range(-0.6, 0.6)
	wheel_spin = impact / 0.34
	_body_only = v._seg.is_empty()
	dur = {
		"fall": 0.42 + 0.3 * sev, "slide": 0.25 + 0.3 * sev, "lie": 0.5 + 1.3 * sev,
		"getup": 1.6, "lift": 1.2, "mount": 1.4,
	}
	phase = Phase.FALL
	if _body_only:
		return
	var hip0: Vector3 = v._seg["Torso"].global_position
	_snapshot(0.15)
	v.rider.top_level = true
	v.rider.global_transform = Transform3D(Basis.IDENTITY, v.get_parent().global_position)
	_base_y = v.get_parent().global_position.y
	fly_start = _ground(hip0)
	# Throw distance from impact, cut short by anything solid in the way.
	var d := 0.9 + 3.2 * sev
	var free := _clear_distance(fly_start, dir, d + 0.6)
	if free - 0.5 < 0.7:
		# Hit a wall/car head on: bounce off sideways-back instead.
		dir = dir.rotated(Vector3.UP, deg_to_rad(115.0) * (1.0 if randf() < 0.5 else -1.0))
		d = minf(0.7 + 1.2 * sev, _clear_distance(fly_start, dir, 0.7 + 1.2 * sev + 0.6) - 0.5)
	else:
		d = minf(d, free - 0.5)
	d = maxf(d, 0.3)
	land = _ground(fly_start + dir * d)
	var slide := minf(0.15 + 0.7 * sev, maxf(_clear_distance(land, dir, 1.2) - 0.5, 0.0))
	rest_pt = _ground(land + dir * slide)
	arc = 0.3 + 0.55 * sev
	yaw_spin = randf_range(-1.0, 1.0) * (0.3 + 0.8 * sev)


func cancel() -> void:
	if v == null:
		return
	phase = Phase.DONE
	roll = 0.0
	_snap_t = 0.0
	if not _body_only:
		v.rider.top_level = false
		v.rider.transform = Transform3D.IDENTITY


func is_active() -> bool:
	return phase != Phase.DONE and phase != Phase.BLEND


## World point the camera should look at: between the bike and the rider.
func focus() -> Vector3:
	var bike: Vector3 = v.get_parent().global_position
	if _body_only or not v._seg.has("Torso"):
		return bike
	var hip: Vector3 = v._seg["Torso"].global_position
	return bike.lerp(Vector3(hip.x, bike.y, hip.z), 0.5)


## Advance one frame. `hurry` (player holding a key) speeds up lying/getting up.
## Returns true when control can go back to the player.
func update(delta: float, hurry: bool) -> bool:
	var dt := delta * (1.8 if hurry and phase in [Phase.LIE, Phase.GETUP, Phase.WALK] else 1.0)
	t += dt
	since += delta
	wheel_spin = move_toward(wheel_spin, 0.0, delta * 9.0)
	if _body_only:
		return _update_body_only()
	# Bike tips over (accelerating, like falling), then a little bounce.
	if phase in [Phase.FALL, Phase.SLIDE, Phase.LIE, Phase.GETUP, Phase.WALK]:
		var k := clampf(since / 0.5, 0.0, 1.0)
		roll = BIKE_DOWN_ROLL * k * k
		if since > 0.5:
			roll = BIKE_DOWN_ROLL - 0.07 * sin((since - 0.5) * 18.0) * exp(-(since - 0.5) * 7.0)
	match phase:
		Phase.FALL:
			_do_fall()
		Phase.SLIDE:
			_do_slide()
		Phase.LIE:
			_do_lie()
		Phase.GETUP:
			_do_getup()
		Phase.WALK:
			_do_walk(dt)
		Phase.LIFT:
			_do_lift()
		Phase.MOUNT:
			if _do_mount():
				return true
	_blend_snapshot(dt)
	return false


func _next(p: Phase) -> void:
	phase = p
	t = 0.0


func _update_body_only() -> bool:
	# Graybox rider: no separate body, just drop the bike and stand it up.
	var k := clampf(since / 0.5, 0.0, 1.0)
	if since < 1.6:
		roll = BIKE_DOWN_ROLL * k * k
	else:
		roll = lerpf(BIKE_DOWN_ROLL, 0.0, smoothstep(1.6, 2.6, since))
	if since > 2.6:
		phase = Phase.DONE
		roll = 0.0
		return true
	return false


# ------------------------------------------------------------------ phases
func _do_fall() -> void:
	var k := clampf(t / dur.fall, 0.0, 1.0)
	var o := fly_start.lerp(land, k)
	o.y += arc * 4.0 * k * (1.0 - k)
	var fr := Transform3D(Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, yaw_spin * k), o)
	var pose: Dictionary
	if k < 0.5:
		pose = _mix(_tuck(), _dive(), smoothstep(0.0, 1.0, k / 0.5))
	else:
		pose = _mix(_dive(), _prone(), smoothstep(0.0, 1.0, (k - 0.5) / 0.5))
	_apply(_xf(pose, fr))
	if k >= 1.0:
		_sound("thud", -2.0 + 6.0 * sev, 0.8)
		_next(Phase.SLIDE)


func _do_slide() -> void:
	var k := clampf(t / dur.slide, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	_lie_frame = Transform3D(Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, yaw_spin), land.lerp(rest_pt, e))
	_apply(_xf(_prone(), _lie_frame))
	if k >= 1.0:
		_next(Phase.LIE)


func _do_lie() -> void:
	var k := clampf(t / dur.lie, 0.0, 1.0)
	var p := _prone()
	# Dazed at first; lifts and turns the head before getting up.
	var look := smoothstep(0.6, 1.0, k)
	p.hfwd = (p.hfwd as Vector3).lerp(Vector3(0, -0.35, -1).normalized(), look).normalized()
	p.hup = (p.hup as Vector3).lerp(Vector3(0, 0.6, -1).normalized(), look).normalized()
	_apply(_xf(p, _lie_frame))
	if k >= 1.0:
		_next(Phase.GETUP)


func _do_getup() -> void:
	var k := clampf(t / dur.getup, 0.0, 1.0)
	var p: Dictionary
	if k < 0.3:
		p = _mix(_prone(), _pushup(), smoothstep(0.0, 1.0, k / 0.3))
	elif k < 0.65:
		p = _mix(_pushup(), _kneel(), smoothstep(0.0, 1.0, (k - 0.3) / 0.35))
	else:
		p = _mix(_kneel(), _walk_pose(0.0, 0.0), smoothstep(0.0, 1.0, (k - 0.65) / 0.35))
	_apply(_xf(p, _lie_frame))
	if k >= 1.0:
		_setup_walk()
		_next(Phase.WALK)


func _setup_walk() -> void:
	var b := _bike_xf()
	var from := _lie_frame.origin
	var to := _ground(b * Vector3(-1.45, 0, -0.05))
	var travel := to - from
	travel.y = 0.0
	var face_end: Vector3 = b.basis.x                   # face the fallen bike
	var yaw0 := _yaw_of(-_lie_frame.basis.z)
	var yaw_t := _yaw_of(travel) if travel.length() > 0.3 else yaw0
	var move := travel.length() / 1.35 if travel.length() > 0.3 else 0.0
	_walk = {"from": from, "to": to, "yaw0": yaw0, "yaw_t": yaw_t, "yaw1": _yaw_of(face_end),
		"turn": 0.35, "move": move}
	_ph = 0.0


func _do_walk(dt: float) -> void:
	var turn: float = _walk.turn
	var move: float = _walk.move
	var total := turn * 2.0 + move
	var pos: Vector3 = _walk.from
	var yaw: float = _walk.yaw0
	var amt := 0.35
	if t < turn:
		yaw = lerp_angle(_walk.yaw0, _walk.yaw_t, smoothstep(0.0, 1.0, t / turn))
	elif t < turn + move:
		pos = (_walk.from as Vector3).lerp(_walk.to, (t - turn) / move)
		yaw = _walk.yaw_t
		amt = 1.0
	else:
		pos = _walk.to
		var k := clampf((t - turn - move) / turn, 0.0, 1.0)
		yaw = lerp_angle(_walk.yaw_t, _walk.yaw1, smoothstep(0.0, 1.0, k))
		amt = 0.35 * (1.0 - k)
	_ph += dt * (2.0 + 5.0 * amt)
	pos = _ground(pos)
	_apply(_xf(_walk_pose(_ph, amt), Transform3D(Basis(Vector3.UP, yaw), pos)))
	if t >= total:
		_next(Phase.LIFT)


func _do_lift() -> void:
	var k := clampf(t / dur.lift, 0.0, 1.0)
	var b := _bike_xf()
	var facing := Basis(Vector3.UP, -PI / 2)          # rider faces the bike (+X)
	var r0 := b * Transform3D(facing, Vector3(-1.45, 0, -0.05))
	var r2 := b * Transform3D(facing, Vector3(-0.62, 0, -0.05))
	var p: Dictionary
	if k < 0.3:
		p = _xf(_mix(_walk_pose(0.0, 0.0), _crouch(), smoothstep(0.0, 1.0, k / 0.3)), r0)
	else:
		var e := smoothstep(0.0, 1.0, (k - 0.3) / 0.7)
		var fr := Transform3D(r0.basis, r0.origin.lerp(r2.origin, e))
		p = _xf(_mix(_crouch(), _hold(), e), fr)
		roll = lerpf(BIKE_DOWN_ROLL, BIKE_HELD_ROLL, e)
	steer = lerpf(steer, 0.0, k)
	v.rotation.z = roll
	# Left hand on the (upper) right grip, right hand on the saddle.
	var hk := smoothstep(0.0, 1.0, k / 0.3)
	p.hl = (p.hl as Vector3).lerp(v._grip_r.global_position, hk)
	p.hr = (p.hr as Vector3).lerp(_saddle_world(), hk)
	_apply(p)
	if k >= 1.0:
		v._crank_angle = PEDAL_READY
		_next(Phase.MOUNT)


func _do_mount() -> bool:
	var k := clampf(t / dur.mount, 0.0, 1.0)
	var b := _bike_xf()
	roll = lerpf(BIKE_HELD_ROLL, REST_ROLL, smoothstep(0.0, 0.5, k))
	v.rotation.z = roll
	var m0 := _xf(_hold(), Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-0.62, 0, -0.05)))
	var m1 := _xf(_walk_pose(0.0, 0.0), Transform3D(Basis.IDENTITY, Vector3(-0.45, 0, 0.1)))
	var m2 := _pose(Vector3(-0.25, 1.04, 0.22), Vector3(0.25, 1, -0.15), Vector3(0, 0, -1),
		Vector3(-0.47, 0.085, 0.1), Vector3(-0.02, 0.95, 0.72), Vector3.ZERO, Vector3.ZERO,
		{"khr": Vector3(0, -1, 0.3).normalized()})
	var rz := Basis(Vector3.BACK, REST_ROLL)
	var hip_rest := rz * Vector3(0, 0.94, 0.13)
	var sh_rest := rz * Vector3(0, 1.46, -0.02)
	var m3 := _pose(hip_rest, (sh_rest - hip_rest).normalized(), Vector3(0, 0, -1),
		Vector3(-0.42, 0.085, -0.08), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var p: Dictionary
	if k < 0.3:
		p = _mix(m0, m1, smoothstep(0.0, 1.0, k / 0.3))
	elif k < 0.65:
		p = _mix(m1, m2, smoothstep(0.0, 1.0, (k - 0.3) / 0.35))
	else:
		p = _mix(m2, m3, smoothstep(0.0, 1.0, (k - 0.65) / 0.35))
	p = _xf(p, b)
	# Live targets: hands move from bar+saddle to both grips; right foot to the pedal.
	var hk := smoothstep(0.0, 1.0, k / 0.3)
	p.hl = v._grip_r.global_position.lerp(v._grip_l.global_position, hk)
	p.hr = _saddle_world().lerp(v._grip_r.global_position, hk)
	if k > 0.65:
		# Right foot comes down from over the rear wheel onto the raised pedal.
		p.fr = (b * (m2.fr as Vector3)).lerp(v._pedal_r.global_position + Vector3(0, 0.08, 0), smoothstep(0.65, 1.0, k))
	_apply(p)
	if k >= 1.0:
		# Hand over to the normal pose with a short cross-fade.
		_snapshot(0.3)
		v.rider.top_level = false
		v.rider.transform = Transform3D.IDENTITY
		phase = Phase.BLEND
		roll = 0.0
		return true
	return false


## Called by bike_visual after the normal pose during BLEND.
func blend_out(delta: float) -> void:
	_blend_snapshot(delta)
	if _snap_t <= 0.0:
		phase = Phase.DONE


# ------------------------------------------------------------------ poses
func _pose(hip: Vector3, up: Vector3, fwd: Vector3, fl: Vector3, fr: Vector3, hl: Vector3, hr: Vector3, extra := {}) -> Dictionary:
	var p := {"hip": hip, "up": up.normalized(), "fwd": fwd.normalized(), "fl": fl, "fr": fr, "hl": hl, "hr": hr,
		"hup": up.normalized(), "hfwd": fwd.normalized(), "ful": Vector3.UP, "fur": Vector3.UP,
		"ffl": fwd.normalized(), "ffr": fwd.normalized(), "khl": fwd.normalized(), "khr": fwd.normalized()}
	p.merge(extra, true)
	return p


func _walk_pose(ph: float, amt: float) -> Dictionary:
	var bob := absf(sin(ph)) * 0.025 * amt
	return _pose(Vector3(0, 0.95 - 0.03 * amt + bob, 0), Vector3(0, 1, -0.04 * amt), Vector3(0, 0, -1),
		Vector3(-0.1, 0.085 + maxf(0.0, cos(ph)) * 0.12 * amt, 0.02 - sin(ph) * 0.3 * amt),
		Vector3(0.1, 0.085 + maxf(0.0, -cos(ph)) * 0.12 * amt, 0.02 + sin(ph) * 0.3 * amt),
		Vector3(-0.24, 0.83, sin(ph) * 0.22 * amt), Vector3(0.24, 0.83, -sin(ph) * 0.22 * amt))


func _tuck() -> Dictionary:
	return _pose(Vector3(0, 1.0, 0), Vector3(0, 1, -0.35), Vector3(0, -0.35, -1),
		Vector3(-0.14, 0.45, 0.15), Vector3(0.12, 0.5, 0.0), Vector3(-0.32, 1.25, -0.45), Vector3(0.3, 1.3, -0.4),
		{"khl": Vector3(0, 0.3, -1).normalized(), "khr": Vector3(0, 0.3, -1).normalized()})


func _dive() -> Dictionary:
	return _pose(Vector3(0, 0.55, 0), Vector3(0, 0.25, -1), Vector3(0, -1, -0.25),
		Vector3(-0.16, 0.6, 0.8), Vector3(0.14, 0.5, 0.85), Vector3(-0.28, 0.3, -0.95), Vector3(0.3, 0.35, -0.9),
		{"hfwd": Vector3(0, -0.6, -1).normalized(), "khl": Vector3(0, -1, 0), "khr": Vector3(0, -1, 0),
		 "ful": Vector3(0, 0.2, -1).normalized(), "fur": Vector3(0, 0.2, -1).normalized()})


func _prone() -> Dictionary:
	return _pose(Vector3(0, 0.14, 0.05), Vector3(0, 0.02, -1), Vector3(0, -1, 0),
		Vector3(-0.2, 0.1, 0.95), Vector3(0.12, 0.1, 0.93), Vector3(-0.42, 0.07, -0.62), Vector3(0.45, 0.07, -0.2),
		{"hfwd": Vector3(0.75, -0.65, 0).normalized(), "hup": Vector3(0, 0.02, -1).normalized(),
		 "ful": Vector3(0, 0.1, -1).normalized(), "fur": Vector3(0, 0.1, -1).normalized(),
		 "ffl": Vector3(0, -1, 0), "ffr": Vector3(0, -1, 0), "khl": Vector3(0, -1, 0), "khr": Vector3(0, -1, 0)})


func _pushup() -> Dictionary:
	return _pose(Vector3(0, 0.42, 0.18), Vector3(0, 0.5, -1), Vector3(0, -1, -0.5),
		Vector3(-0.12, 0.1, 0.82), Vector3(0.12, 0.1, 0.82), Vector3(-0.24, 0.05, -0.32), Vector3(0.24, 0.05, -0.32),
		{"hfwd": Vector3(0, -0.6, -1).normalized(), "hup": Vector3(0, 0.6, -1).normalized(),
		 "ful": Vector3(0, 0.4, -1).normalized(), "fur": Vector3(0, 0.4, -1).normalized(),
		 "ffl": Vector3(0, -1, 0), "ffr": Vector3(0, -1, 0), "khl": Vector3(0, -1, 0), "khr": Vector3(0, -1, 0)})


func _kneel() -> Dictionary:
	return _pose(Vector3(0, 0.6, 0.08), Vector3(0, 1, -0.12), Vector3(0, -0.12, -1),
		Vector3(-0.12, 0.085, -0.38), Vector3(0.13, 0.12, 0.5), Vector3(-0.16, 0.62, -0.36), Vector3(0.2, 0.55, -0.08),
		{"khl": Vector3(0, 0, -1), "khr": Vector3(0, -1, 0), "fur": Vector3(0, 0.25, -1).normalized(),
		 "ffr": Vector3(0, -1, -0.2).normalized()})


func _crouch() -> Dictionary:
	return _pose(Vector3(0, 0.62, 0.12), Vector3(0, 0.6, -0.8), Vector3(0, -0.8, -0.6),
		Vector3(-0.15, 0.085, 0.05), Vector3(0.15, 0.085, 0.05), Vector3(-0.2, 0.3, -0.5), Vector3(0.2, 0.3, -0.5),
		{"khl": Vector3(-0.3, 0, -1).normalized(), "khr": Vector3(0.3, 0, -1).normalized(), "hfwd": Vector3(0, -0.7, -1).normalized()})


func _hold() -> Dictionary:
	return _pose(Vector3(0, 0.93, 0.05), Vector3(0, 1, -0.25), Vector3(0, -0.25, -1),
		Vector3(-0.13, 0.085, 0.05), Vector3(0.13, 0.085, 0.1), Vector3(-0.2, 0.9, -0.4), Vector3(0.2, 0.85, -0.3))


# ------------------------------------------------------------------ pose maths
const POINT_KEYS := ["hip", "fl", "fr", "hl", "hr"]
const DIR_KEYS := ["up", "fwd", "hup", "hfwd", "ful", "fur", "ffl", "ffr", "khl", "khr"]


func _xf(p: Dictionary, xf: Transform3D) -> Dictionary:
	var o := {}
	for k in POINT_KEYS:
		o[k] = xf * (p[k] as Vector3)
	for k in DIR_KEYS:
		o[k] = (xf.basis * (p[k] as Vector3)).normalized()
	return o


func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var o := {}
	for key in POINT_KEYS:
		o[key] = (a[key] as Vector3).lerp(b[key], k)
	for key in DIR_KEYS:
		var va: Vector3 = a[key]
		var vb: Vector3 = b[key]
		var m := va.lerp(vb, k)
		o[key] = m.normalized() if m.length_squared() > 1e-6 else vb
	return o


## Place every segment from a world-space pose.
func _apply(pw: Dictionary) -> void:
	var p := _xf(pw, v.rider.global_transform.affine_inverse())
	var seg: Dictionary = v._seg
	var up: Vector3 = p.up
	var fwd: Vector3 = p.fwd
	var torso := Transform3D(SB.seg_basis(up, fwd), p.hip)
	seg["Torso"].transform = torso
	seg["Head"].transform = Transform3D(SB.seg_basis(p.hup, p.hfwd), torso * Vector3(0, SB.TORSO, 0))
	var right := torso.basis.x
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var low: String = side.to_lower()
		var hip_j := torso * Vector3(sx * 0.09, 0, 0)
		var ankle: Vector3 = p["f" + low]
		var knee := SB.two_bone(hip_j, ankle, SB.THIGH, SB.SHIN, (p["kh" + low] as Vector3) + right * sx * 0.15)
		SB.place(seg["Thigh" + side], hip_j, knee, fwd)
		SB.place(seg["Shin" + side], knee, ankle, fwd)
		seg["Foot" + side].transform = Transform3D(SB.seg_basis(p["fu" + low], p["ff" + low]), ankle)
		var sh := torso * Vector3(sx * 0.19, 0.46, 0)
		var hand: Vector3 = p["h" + low]
		var elbow_hint := (right * sx * 0.7 - fwd * 0.4 - up * 0.3).normalized()
		var elbow := SB.two_bone(sh, hand, SB.UPPER_ARM, SB.FOREARM, elbow_hint)
		SB.place(seg["UpperArm" + side], sh, elbow, fwd)
		SB.place(seg["Forearm" + side], elbow, hand, fwd)


func _snapshot(length: float) -> void:
	_snap.clear()
	for n in v._seg:
		_snap[n] = (v._seg[n] as Node3D).global_transform
	_snap_len = length
	_snap_t = length


func _blend_snapshot(dt: float) -> void:
	if _snap_t <= 0.0:
		return
	var k := smoothstep(0.0, 1.0, 1.0 - _snap_t / _snap_len)
	for n in _snap:
		var node: Node3D = v._seg[n]
		node.global_transform = (_snap[n] as Transform3D).interpolate_with(node.global_transform, k)
	_snap_t -= dt


# ------------------------------------------------------------------ world queries
func _bike_xf() -> Transform3D:
	var body: Node3D = v.get_parent()
	return Transform3D(Basis(Vector3.UP, body.global_rotation.y), body.global_position)


func _saddle_world() -> Vector3:
	return v.to_global(Vector3(0, 0.94, 0.18))


func _yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _ground(p: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	if not hit:
		return p
	# Only real ground counts (curbs, ramps): never land on top of counters or walls.
	return Vector3(p.x, minf(hit.position.y, _base_y + 0.35), p.z)


## Free distance along `d` from `from` (probed at knee and chest height).
func _clear_distance(from: Vector3, d: Vector3, max_d: float) -> float:
	var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	var best := max_d
	var exclude := [v.get_parent().get_rid()]
	for h in [0.2, 0.45, 1.0]:
		var a: Vector3 = from + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(a, a + d * max_d, 1 | 4)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit:
			best = minf(best, a.distance_to(hit.position))
	return best


func _sound(key: String, db: float, pitch: float) -> void:
	var a = v.get_tree().get_first_node_in_group("audio")
	if a and v._seg.has("Torso"):
		a.play_at(key, v._seg["Torso"].global_position, db, pitch)
