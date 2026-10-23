extends Node3D
## Spawns and coordinates the town's life: traffic loops, pedestrians, dogs
## and cats. Also arbitrates junctions (one car at a time) so traffic doesn't
## collide at crossings. Set `enabled = false` before the scene enters the tree
## to get a quiet town (used by the riding/delivery regression test).

const TrafficCar = preload("res://scripts/traffic/traffic_car.gd")
const Pedestrian = preload("res://scripts/pedestrians/pedestrian.gd")
const DogScript = preload("res://scripts/animals/dog.gd")
const CatScript = preload("res://scripts/animals/cat.gd")

const CAR_COLORS := [Color(0.62, 0.63, 0.65), Color(0.55, 0.08, 0.07), Color(0.10, 0.20, 0.40), Color(0.85, 0.85, 0.83), Color(0.08, 0.08, 0.09), Color(0.70, 0.55, 0.15)]
const SHIRTS := [Color(0.75, 0.20, 0.18), Color(0.20, 0.50, 0.30), Color(0.85, 0.75, 0.35), Color(0.35, 0.30, 0.55), Color(0.90, 0.88, 0.84), Color(0.25, 0.45, 0.65)]
const PANTS := [Color(0.15, 0.15, 0.17), Color(0.40, 0.33, 0.22), Color(0.20, 0.25, 0.38), Color(0.50, 0.48, 0.45)]
const HAIR := [Color(0.08, 0.06, 0.04), Color(0.35, 0.22, 0.10), Color(0.75, 0.60, 0.35), Color(0.55, 0.55, 0.55)]
const SKIN := [Color(0.85, 0.66, 0.52), Color(0.62, 0.43, 0.30), Color(0.42, 0.28, 0.18), Color(0.74, 0.53, 0.38)]

@export var enabled := true

var city: Node
var junctions: Array[Vector3] = []
var loops: Array = []
var _holders := {}
var _rng := RandomNumberGenerator.new()


func setup(c: Node, avoid: Vector3) -> void:
	city = c
	if not enabled:
		return
	_rng.seed = 4242
	for x in [-60.0, 0.0, 60.0]:
		for z in [-60.0, 0.0, 60.0]:
			junctions.append(Vector3(x, 0, z))
	_spawn_traffic(avoid)
	_spawn_pedestrians(avoid)
	_spawn_animals()


# ---------------------------------------------------------------- traffic
## Closed loop through `corners` with bezier-rounded corners of radius r.
static func rounded_loop(corners: Array, r: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := corners.size()
	for i in n:
		var c: Vector3 = corners[i]
		var a: Vector3 = c + (corners[(i - 1 + n) % n] - c).normalized() * r
		var b: Vector3 = c + (corners[(i + 1) % n] - c).normalized() * r
		for k in 7:
			var t := k / 6.0
			pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts


func _spawn_traffic(avoid: Vector3) -> void:
	var model: PackedScene = load("res://assets/models/car_hatchback.glb") if ResourceLoader.exists("res://assets/models/car_hatchback.glb") else null
	# Drive on the right. Loop A: Main Rd east -> Elm St north -> Birch Ln west -> Oak Ave south.
	var loop_a := rounded_loop([Vector3(-61.75, 0, 2.5), Vector3(61.75, 0, 2.5), Vector3(61.75, 0, -61.75), Vector3(-61.75, 0, -61.75)], 6.0)
	# Loop B (clockwise around the block x 0..60, z -60..0): Main Rd west -> Maple St north -> Birch Ln east -> Elm St south.
	var loop_b := rounded_loop([Vector3(58.25, 0, -2.5), Vector3(1.75, 0, -2.5), Vector3(1.75, 0, -58.25), Vector3(58.25, 0, -58.25)], 4.0)
	loops = [loop_a, loop_b]
	var i := 0
	for spec in [[loop_a, 4], [loop_b, 2]]:
		var pts: PackedVector3Array = spec[0]
		var count: int = spec[1]
		var car_len := _loop_length(pts)
		for k in count:
			var d := car_len * k / count
			# Never spawn within 35 m of the player.
			var tries := 0
			while _point_on(pts, d).distance_to(avoid) < 35.0 and tries < 20:
				d += 10.0
				tries += 1
			var car := AnimatableBody3D.new()
			car.set_script(TrafficCar)
			car.name = "TrafficCar%d" % i
			add_child(car)
			car.cruise_speed = _rng.randf_range(8.0, 10.0)
			car.setup(self, pts, d, CAR_COLORS[i % CAR_COLORS.size()], model)
			i += 1


func _loop_length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in pts.size():
		l += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return l


func _point_on(pts: PackedVector3Array, d: float) -> Vector3:
	var total := _loop_length(pts)
	d = fposmod(d, total)
	for i in pts.size():
		var seg := pts[i].distance_to(pts[(i + 1) % pts.size()])
		if d <= seg:
			return pts[i].lerp(pts[(i + 1) % pts.size()], d / maxf(seg, 0.001))
		d -= seg
	return pts[0]


func junction_ahead(_car: Node, pos: Vector3, fwd: Vector3, reach: float) -> int:
	for j in junctions.size():
		var rel := junctions[j] - pos
		rel.y = 0.0
		var along := rel.dot(fwd)
		if along > -4.0 and along < reach and (rel - fwd * along).length() < 7.0:
			return j
	return -1


func junction_distance(j: int, pos: Vector3) -> float:
	var rel := junctions[j] - pos
	rel.y = 0.0
	return rel.length()


func request_junction(j: int, car: Node) -> bool:
	var h = _holders.get(j)
	if h == null or not is_instance_valid(h) or h == car:
		_holders[j] = car
		return true
	return false


func release_junction(j: int, car: Node) -> void:
	if _holders.get(j) == car:
		_holders.erase(j)


# ---------------------------------------------------------------- pedestrians
func _spawn_pedestrians(avoid: Vector3) -> void:
	var model: PackedScene = load("res://assets/models/pedestrian.glb") if ResourceLoader.exists("res://assets/models/pedestrian.glb") else null
	var n := 0
	# Sidewalk loops around four blocks (1.25 m in from the kerb).
	for bi in [5, 6, 9, 2]:
		if bi >= city.blocks.size():
			continue
		var b: Array = city.blocks[bi]
		var y: float = city.CURB
		var inset := 1.25
		var ring := PackedVector3Array([
			Vector3(b[0] + inset, y, b[2] + inset), Vector3(b[1] - inset, y, b[2] + inset),
			Vector3(b[1] - inset, y, b[3] - inset), Vector3(b[0] + inset, y, b[3] - inset)])
		if n % 2 == 1:
			ring.reverse()
		var start := 0
		for k in 4:
			if ring[k].distance_to(avoid) > 25.0:
				start = k
				break
		_add_pedestrian(model, ring, start, "loop", n)
		n += 1
	# Zebra-crossing walkers on Main Road (Maple St and Elm St junctions).
	for x in [-5.7, 54.3]:
		_add_pedestrian(model, PackedVector3Array([Vector3(x, city.CURB, -6.4), Vector3(x, city.CURB, 6.4)]), 0, "crossing", n)
		n += 1


func _add_pedestrian(model: PackedScene, pts: PackedVector3Array, start: int, mode: String, i: int) -> void:
	var p := AnimatableBody3D.new()
	p.set_script(Pedestrian)
	p.name = "Pedestrian%d" % i
	add_child(p)
	p.setup(model, pts, start, mode, {
		"Rider_Shirt": SHIRTS[i % SHIRTS.size()],
		"Rider_Jeans": PANTS[(i * 3) % PANTS.size()],
		"Rider_Hair": HAIR[(i * 5) % HAIR.size()],
		"Rider_Skin": SKIN[(i * 7) % SKIN.size()],
	})


# ---------------------------------------------------------------- animals
func _spawn_animals() -> void:
	var dog_scene: PackedScene = load("res://assets/models/dog.glb") if ResourceLoader.exists("res://assets/models/dog.glb") else null
	var cat_scene: PackedScene = load("res://assets/models/cat.glb") if ResourceLoader.exists("res://assets/models/cat.glb") else null
	if dog_scene:
		# Yard dog: behind the fence of the first Birch Lane house, barks at passers-by.
		for h in city.houses:
			if h.address.ends_with("Birch Lane"):
				var house := h.get_parent() as Node3D
				_add_dog(dog_scene, house.to_global(Vector3(h.position.x + 1.8, 0.0, -2.2)), house.global_rotation.y + PI, false, "YardDog")
				break
		# Chaser dog: on the Park Road sidewalk. Telegraphs, then gives a short chase.
		_add_dog(dog_scene, Vector3(-22.0, city.CURB, 64.8), PI / 2, true, "ChaserDog")
	if cat_scene:
		_add_cat(cat_scene, Vector3(8.0, city.CURB, 7.2), 2.4, "ParkCat")
		_add_cat(cat_scene, Vector3(-12.0, city.CURB, -55.0), 0.6, "BirchCat")


func _add_dog(scene: PackedScene, pos: Vector3, yaw: float, chaser: bool, dog_name: String) -> void:
	var d: Node3D = scene.instantiate()
	d.set_script(DogScript)
	d.name = dog_name
	d.chaser = chaser
	add_child(d)
	d.global_position = pos
	d.rotation.y = yaw
	d.home = pos
	d.home_yaw = yaw


func _add_cat(scene: PackedScene, pos: Vector3, yaw: float, cat_name: String) -> void:
	var c: Node3D = scene.instantiate()
	c.set_script(CatScript)
	c.name = cat_name
	c.city = city
	add_child(c)
	c.global_position = pos
	c.rotation.y = yaw
	c.home = pos
