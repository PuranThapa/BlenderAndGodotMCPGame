extends Area3D
## A rain puddle. Riding through at speed throws spray, plays a splash and
## scrubs ~15% of your speed. Readable (glossy dark patch) and avoidable.

const Geo = preload("res://scripts/systems/geo.gd")

var _cool := 0.0
var _spray: CPUParticles3D


func configure(radius_x: float, radius_z: float) -> void:
	add_to_group("puddles")
	collision_layer = Geo.LAYER_TRIGGERS
	collision_mask = Geo.LAYER_PLAYER
	monitorable = false
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius_x, radius_z)
	shape.height = 1.0
	cs.shape = shape
	cs.position.y = 0.5
	cs.scale = Vector3(radius_x / shape.radius, 1, radius_z / shape.radius)
	add_child(cs)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 24
	water.mesh = disc
	water.scale = Vector3(radius_x, 1, radius_z)
	water.position.y = 0.012
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.material_override = Geo.mat("puddle_water", Color(0.10, 0.11, 0.12), 0.03, 0.0, 0.3)
	add_child(water)
	_spray = CPUParticles3D.new()
	_spray.emitting = false
	_spray.one_shot = true
	_spray.amount = 40
	_spray.lifetime = 0.7
	_spray.explosiveness = 0.9
	_spray.direction = Vector3.UP
	_spray.spread = 60.0
	_spray.initial_velocity_min = 1.5
	_spray.initial_velocity_max = 3.5
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.scale_amount_min = 0.03
	_spray.scale_amount_max = 0.07
	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	drop.radial_segments = 6
	drop.rings = 3
	_spray.mesh = drop
	_spray.material_override = Geo.mat("spray", Color(0.75, 0.82, 0.88), 0.1)
	add_child(_spray)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or _cool > 0.0 or absf(body.speed) < 2.5:
		return
	_cool = 1.0
	body.speed *= 0.85
	_spray.global_position = body.global_position + Vector3.UP * 0.1
	_spray.restart()
	var a := get_tree().get_first_node_in_group("audio")
	if a:
		a.play_at("splash", body.global_position, 0.0, randf_range(0.9, 1.1))
