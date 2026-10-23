extends Node3D
## The Daily Herald's depot clerk: sits by the counter reading the paper.
## When the paperboy rides up they lower the paper, look over, wave and say
## hello; they also react when a route starts and when it's finished.
## Built from pedestrian.glb segments (seated pose) + newspaper_open.glb.

const SB = preload("res://scripts/systems/segment_body.gd")
const Geo = preload("res://scripts/systems/geo.gd")
const DeliveryManager = preload("res://scripts/deliveries/delivery_manager.gd")

var engaged := 0.0          # 0 reading .. 1 looking at the player
var waving := false
var _seg := {}
var _paper: Node3D
var _bubble: Label3D
var _t := 0.0
var _wave_t := -1.0
var _say_t := 0.0
var _player_near := false
var _last_phase := -1


func _ready() -> void:
	add_to_group("depot_clerk")
	_build_furniture()
	if ResourceLoader.exists("res://assets/models/pedestrian.glb"):
		var model: Node3D = (load("res://assets/models/pedestrian.glb") as PackedScene).instantiate()
		model.name = "Clerk"
		add_child(model)
		_seg = SB.collect(model)
		SB.recolor(model, "Rider_Shirt", Color(0.45, 0.30, 0.20))     # brown cardigan
		SB.recolor(model, "Rider_Jeans", Color(0.32, 0.32, 0.34))     # grey trousers
		SB.recolor(model, "Rider_Hair", Color(0.72, 0.72, 0.70))      # grey hair
		SB.recolor(model, "Rider_Skin", Color(0.80, 0.62, 0.50))
		SB.recolor(model, "Rider_Shoe", Color(0.25, 0.15, 0.08))
	if ResourceLoader.exists("res://assets/models/newspaper_open.glb"):
		_paper = (load("res://assets/models/newspaper_open.glb") as PackedScene).instantiate()
		add_child(_paper)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 40
	_bubble.pixel_size = 0.0042
	_bubble.outline_size = 10
	_bubble.position = Vector3(0, 1.75, 0)
	_bubble.visible = false
	add_child(_bubble)
	_pose(0.0)


func _build_furniture() -> void:
	var wood := Geo.mat("chair_wood", Color(0.38, 0.24, 0.14), 0.7)
	# Chair (clerk faces local -Z; backrest behind at +Z).
	Geo.box(self, Vector3(0, 0.45, 0.05), Vector3(0.48, 0.05, 0.46), wood)
	for x in [-0.2, 0.2]:
		for z in [-0.15, 0.25]:
			Geo.box(self, Vector3(x, 0.22, z), Vector3(0.04, 0.45, 0.04), wood)
	Geo.box(self, Vector3(0, 0.75, 0.27), Vector3(0.48, 0.5, 0.04), wood)
	# Side table with a mug and a stack of today's papers.
	Geo.box(self, Vector3(0.68, 0.6, -0.05), Vector3(0.5, 0.04, 0.5), wood)
	Geo.box(self, Vector3(0.68, 0.3, -0.05), Vector3(0.06, 0.6, 0.06), wood)
	Geo.box(self, Vector3(0.68, 0.01, -0.05), Vector3(0.36, 0.02, 0.36), wood)
	Geo.cylinder(self, Vector3(0.82, 0.67, -0.15), 0.045, 0.1, Geo.mat("mug", Color(0.92, 0.92, 0.9), 0.3))
	if ResourceLoader.exists("res://assets/models/newspaper_folded.glb"):
		var ps: PackedScene = load("res://assets/models/newspaper_folded.glb")
		for i in 4:
			var p: Node3D = ps.instantiate()
			add_child(p)
			p.position = Vector3(0.62, 0.62 + i * 0.013, 0.02)
			p.rotation.y = randf_range(-0.1, 0.1)
	# Keep the bike out of the furniture.
	Geo.solid_box(self, Vector3(0.3, 0.6, 0.05), Vector3(1.3, 1.2, 0.8), null)


func _player():
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if ps.size() > 0 else null


func _process(delta: float) -> void:
	_t += delta
	var p = _player()
	var near := false
	if p:
		near = p.global_position.distance_to(global_position) < 9.0
	if near and not _player_near:
		_say("Morning! Your papers are on the counter.")
		_wave_t = 0.0
	_player_near = near
	var m := get_tree().get_first_node_in_group("delivery_manager")
	if m:
		if m.phase != _last_phase and _last_phase != -1:
			if m.phase == DeliveryManager.Phase.ACTIVE:
				_say("Good luck out there! Mind the dog on Park Road.")
			elif m.phase == DeliveryManager.Phase.FINISHED:
				_say("Nice work! Same time tomorrow.")
				_wave_t = 0.0
		_last_phase = m.phase
	if _wave_t >= 0.0:
		_wave_t += delta
		if _wave_t > 2.0:
			_wave_t = -1.0
	waving = _wave_t >= 0.0
	_say_t -= delta
	if _say_t <= 0.0:
		_bubble.visible = false
	var want := 1.0 if (near or waving or _say_t > 0.0) else 0.0
	engaged = move_toward(engaged, want, delta * 2.5)
	_pose(delta)


func _say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_say_t = 3.5


func _pose(_delta: float) -> void:
	if _seg.is_empty():
		return
	var e := smoothstep(0.0, 1.0, engaged)
	var fwd := Vector3(0, 0, -1)
	var breathe := sin(_t * 1.6) * 0.006
	var hip := Vector3(0, 0.55, 0.04)
	var torso_up := Vector3(0, 1, 0.07 * (1.0 - e)).normalized()
	var torso := Transform3D(SB.seg_basis(torso_up, fwd), hip + Vector3(0, breathe, 0))
	_seg["Torso"].transform = torso
	var neck := torso * Vector3(0, SB.TORSO, 0)
	# Head: down at the paper while reading; toward the player when engaged.
	var read_up := Vector3(0, 0.93, -0.36).normalized()
	var look_fwd := Vector3(0, -0.35, -1).normalized()
	var p = _player()
	if p and e > 0.0:
		var to: Vector3 = to_local(p.global_position + Vector3.UP * 1.2) - neck
		var yaw := clampf(atan2(-to.x, -to.z), -1.1, 1.1)
		var pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.4, 0.3)
		var engaged_fwd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		look_fwd = look_fwd.slerp(engaged_fwd, e)
	_seg["Head"].transform = Transform3D(SB.seg_basis(read_up.slerp(Vector3.UP, e), look_fwd), neck)
	# Legs: seated, thighs forward, shins down, feet flat.
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var h := torso * Vector3(sx * 0.1, 0, 0)
		var knee := h + Vector3(sx * 0.03, -0.02, -0.44)
		var ankle := knee + Vector3(0, -0.45, 0.04)
		SB.place(_seg["Thigh" + side], h, knee, fwd)
		SB.place(_seg["Shin" + side], knee, ankle, fwd)
		_seg["Foot" + side].transform = Transform3D(SB.seg_basis(Vector3.UP, fwd), ankle)
	# Paper: held up to read, or lowered onto the lap; an occasional page turn.
	var turn := maxf(0.0, sin(_t * 0.7)) ** 30
	var paper_up := Transform3D(Basis(Vector3.UP, sin(_t * 9.0) * 0.08 * turn), Vector3(0, 0.88, -0.42))
	var paper_lap := Transform3D(Basis(Vector3.RIGHT, -1.25), Vector3(0, 0.66, -0.12))
	if _paper:
		_paper.transform = paper_up.interpolate_with(paper_lap, e)
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var sh := torso * Vector3(sx * 0.19, 0.46, 0)
		var hand_read := Vector3(sx * 0.32, 1.06, -0.40)
		var hand_lap := Vector3(sx * 0.2, 0.68, -0.26)
		var hand := hand_read.lerp(hand_lap, e)
		if side == "R" and waving:
			hand = sh + Vector3(0.18 + sin(_wave_t * 11.0) * 0.12, 0.42, -0.12)
		var elbow := SB.two_bone(sh, hand, SB.UPPER_ARM, SB.FOREARM, Vector3(sx * 0.7, -0.6, 0.2).normalized())
		SB.place(_seg["UpperArm" + side], sh, elbow, fwd)
		SB.place(_seg["Forearm" + side], elbow, hand, fwd)
