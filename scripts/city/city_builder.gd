extends Node3D
## Builds the graybox "Maple Heights" district procedurally (seeded, so the
## layout is identical every run). Blocks are raised 0.1 m slabs so every road
## edge has a curb; roads are the gaps between blocks on the asphalt ground.
##
## Layout (top-down, -Z = north):
##   X roads (east-west):  Birch Lane z=-60, Main Road z=0, Park Road z=60
##   Z roads (north-south): Oak Ave x=-60, Maple St x=0, Elm St x=60
##   Depot on Main Road (north side of block x[-60,0] z[0,60]); park at x[0,60] z[0,60].

const Geo = preload("res://scripts/systems/geo.gd")
const DeliveryTarget = preload("res://scripts/deliveries/delivery_target.gd")
const DepotArea = preload("res://scripts/deliveries/depot_area.gd")
const Puddle = preload("res://scripts/city/puddle.gd")
const DepotClerk = preload("res://scripts/deliveries/depot_clerk.gd")
# Blocks (index = ix * 4 + iz) with a back-alley shortcut through the middle.
const ALLEY_BLOCKS := [5, 9]

const HALF := 110.0
const CURB := 0.1
const SIDEWALK := 2.5
const X_ROADS := [{"z": -60.0, "w": 7.0, "name": "Birch Lane"}, {"z": 0.0, "w": 10.0, "name": "Main Road"}, {"z": 60.0, "w": 7.0, "name": "Park Road"}]
const Z_ROADS := [{"x": -60.0, "w": 7.0, "name": "Oak Avenue"}, {"x": 0.0, "w": 7.0, "name": "Maple Street"}, {"x": 60.0, "w": 7.0, "name": "Elm Street"}]
const SHOP_NAMES := ["Corner Bakery", "Patel Grocers", "Kim's Hardware", "Bloom Florist", "City Pharmacy", "Rosa's Cafe", "Book Nook", "Quick Laundry", "Barber Bros", "Fresh Fish", "Sunrise Diner", "Bike Repair", "Post Office", "Toy Box"]

var houses: Array = []          # Array of DeliveryTarget nodes (one per house)
var depot: Node3D
var spawn_transform := Transform3D.IDENTITY
var ramps: Array = []
var blocks: Array = []          # [x0, x1, z0, z1] per block, index = ix * 4 + iz

var _rng := RandomNumberGenerator.new()
var _shop_i := 0
var _street_numbers := {}
var M := {}
var _models := {}

# Blender-built assets (see assets/blender/build_props.py and docs/ASSET_MANIFEST.md).
const MODELS := {
	"tree_round": "res://assets/models/tree_round.glb",
	"tree_tall": "res://assets/models/tree_tall.glb",
	# Realistic trees: branching photo-bark wood + photo leaf-cluster cards (build_trees.py).
	"tree_oak": "res://assets/models/tree_oak.glb",
	"tree_maple": "res://assets/models/tree_maple.glb",
	"tree_birch": "res://assets/models/tree_birch.glb",
	"lamp": "res://assets/models/street_lamp.glb",
	"mailbox": "res://assets/models/mailbox.glb",
	"bench": "res://assets/models/bench.glb",
	"car": "res://assets/models/car_hatchback.glb",
	"dog": "res://assets/models/dog.glb",
	"cat": "res://assets/models/cat.glb",
	"door": "res://assets/models/house_door.glb",
	"window": "res://assets/models/house_window.glb",
	"canopy": "res://assets/models/house_canopy.glb",
	"chimney": "res://assets/models/house_chimney.glb",
	"picket": "res://assets/models/fence_picket.glb",
	"shrub": "res://assets/models/shrub.glb",
	"flower_bed": "res://assets/models/flower_bed.glb",
}
const FACADE_SHADER := preload("res://assets/materials/facade.gdshader")
const ROOF_SHADER := preload("res://assets/materials/roof_tiles.gdshader")
const DOOR_COLORS := [Color(0.12, 0.30, 0.20), Color(0.55, 0.10, 0.10), Color(0.10, 0.15, 0.32), Color(0.40, 0.26, 0.15), Color(0.80, 0.62, 0.18), Color(0.20, 0.20, 0.22)]
const SHUTTER_COLORS := [Color(0.18, 0.28, 0.22), Color(0.12, 0.16, 0.26), Color(0.30, 0.30, 0.32), Color(0.45, 0.15, 0.12)]
const CAR_COLORS := [Color(0.62, 0.63, 0.65), Color(0.12, 0.22, 0.42), Color(0.50, 0.07, 0.07), Color(0.86, 0.86, 0.84), Color(0.07, 0.07, 0.08), Color(0.20, 0.32, 0.22)]


func _ready() -> void:
	_rng.seed = 20261023
	_make_materials()
	_build_ground()
	_build_blocks()
	_build_road_markings()
	_build_boundary()
	_build_parked_cars()
	_build_challenges()
	_build_road_details()


## True if `p` is on a carriageway (used by animals so they never bolt into traffic).
func is_on_road(p: Vector3) -> bool:
	if absf(p.x) > HALF or absf(p.z) > HALF:
		return false
	for r in X_ROADS:
		if absf(p.z - r.z) < r.w * 0.5 + 0.3:
			return true
	for r in Z_ROADS:
		if absf(p.x - r.x) < r.w * 0.5 + 0.3:
			return true
	return false


## Instances a Blender model, or returns null if it isn't available.
func _model(key: String, parent: Node3D, pos: Vector3, rot_y := 0.0, s := 1.0) -> Node3D:
	if not _models.has(key):
		_models[key] = load(MODELS[key]) if ResourceLoader.exists(MODELS[key]) else null
		if _models[key] != null and key.begins_with("tree_"):
			_dress_tree(_models[key])
	if _models[key] == null:
		return null
	var inst: Node3D = _models[key].instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * s
	parent.add_child(inst)
	return inst


func _make_materials() -> void:
	# Photo textures from Pixabay (see assets/textures/pixabay/CREDITS.json).
	M.asphalt = Geo.tex_mat("tex_asphalt", "asphalt", 4.0, Color(0.85, 0.85, 0.87), 0.93, 0.8)
	M.concrete = Geo.tex_mat("tex_concrete", "concrete", 2.5, Color(0.88, 0.90, 0.95), 0.9, 0.6)
	M.curb = Geo.mat("curb", Color(0.70, 0.69, 0.66), 0.85)
	M.grass = Geo.tex_mat("tex_grass", "grass", 3.0, Color(0.95, 1.0, 0.92), 0.95, 0.8)
	M.grass_wild = Geo.tex_mat("tex_grass_wild", "grass", 5.0, Color(1.0, 0.98, 0.82), 0.95, 0.8)
	M.white_paint = Geo.mat("paint_white", Color(0.88, 0.88, 0.84), 0.7)
	M.yellow_paint = Geo.mat("paint_yellow", Color(0.85, 0.68, 0.20), 0.7)
	M.glass = Geo.mat("glass", Color(0.16, 0.21, 0.26), 0.12, 0.0, 0.4)
	M.frame = Geo.mat("window_frame", Color(0.92, 0.91, 0.88), 0.6)
	M.hedge = Geo.tex_mat("tex_hedge", "hedge", 1.6, Color(0.82, 0.9, 0.8), 0.9, 1.2)
	M.trunk = Geo.mat("trunk", Color(0.32, 0.23, 0.16), 0.95)
	M.leaves = [Geo.mat("leaves_a", Color(0.22, 0.40, 0.16), 0.95, 0.3), Geo.mat("leaves_b", Color(0.30, 0.45, 0.18), 0.95, 0.3), Geo.mat("leaves_c", Color(0.18, 0.33, 0.17), 0.95, 0.3)]
	M.metal_dark = Geo.mat("metal_dark", Color(0.18, 0.19, 0.20), 0.5, 0.0, 0.6)
	M.stone = Geo.mat("stone_wall", Color(0.52, 0.49, 0.44), 0.95, 0.3)
	M.wood = Geo.mat("wood", Color(0.42, 0.28, 0.17), 0.85)
	M.dirt = Geo.mat("dirt", Color(0.45, 0.36, 0.25), 0.95, 0.2)
	M.water = Geo.mat("water", Color(0.20, 0.32, 0.36), 0.05, 0.0, 0.2)
	# Facades: brick, painted clapboard siding, or render (assets/materials/facade.gdshader).
	M.walls = [
		_facade(0, Color(0.56, 0.29, 0.22)),
		_facade(1, Color(0.86, 0.80, 0.67)),
		_facade(1, Color(0.90, 0.89, 0.85)),
		_facade(1, Color(0.58, 0.64, 0.52)),
		_facade(1, Color(0.52, 0.58, 0.63)),
		_facade(2, Color(0.80, 0.55, 0.40)),
		_facade(0, Color(0.42, 0.24, 0.20)),
	]
	M.roof_colors = [Color(0.24, 0.24, 0.26), Color(0.36, 0.23, 0.17), Color(0.55, 0.24, 0.16), Color(0.31, 0.34, 0.39)]
	M.roofs = []
	for c in M.roof_colors:
		M.roofs.append(Geo.mat("roof_%s" % c.to_html(false), c, 0.85, 0.2))
	M.doors = [
		Geo.mat("door_green", Color(0.12, 0.30, 0.20), 0.6),
		Geo.mat("door_red", Color(0.55, 0.10, 0.10), 0.6),
		Geo.mat("door_navy", Color(0.10, 0.15, 0.32), 0.6),
		Geo.mat("door_wood", Color(0.40, 0.26, 0.15), 0.7),
		Geo.mat("door_yellow", Color(0.80, 0.62, 0.18), 0.6),
	]
	M.awnings = [
		Geo.mat("awning_red", Color(0.65, 0.15, 0.12), 0.9),
		Geo.mat("awning_green", Color(0.15, 0.40, 0.25), 0.9),
		Geo.mat("awning_blue", Color(0.15, 0.30, 0.55), 0.9),
		Geo.mat("awning_stripe", Color(0.85, 0.75, 0.55), 0.9),
	]
	M.cars = [
		Geo.mat("car_silver", Color(0.70, 0.71, 0.73), 0.3, 0.0, 0.6),
		Geo.mat("car_blue", Color(0.15, 0.25, 0.45), 0.3, 0.0, 0.6),
		Geo.mat("car_red", Color(0.55, 0.08, 0.08), 0.3, 0.0, 0.6),
		Geo.mat("car_white", Color(0.88, 0.88, 0.86), 0.3, 0.0, 0.5),
		Geo.mat("car_black", Color(0.08, 0.08, 0.09), 0.3, 0.0, 0.6),
	]


func _facade(pattern: int, color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("base_color", color)
	m.set_meta("color", color)
	return m


func _roof_material(tile: Color, gable: Color) -> ShaderMaterial:
	var key := "roofmat_%s_%s" % [tile.to_html(false), gable.to_html(false)]
	if not M.has(key):
		var m := ShaderMaterial.new()
		m.shader = ROOF_SHADER
		m.set_shader_parameter("tile_color", tile)
		m.set_shader_parameter("gable_color", gable)
		M[key] = m
	return M[key]


## Overrides every surface whose material is named `mat_name` (from Blender) with `color`.
func _recolor(node: Node, mat_name: String, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m != null and m.resource_name == mat_name:
				var c := m.duplicate() as StandardMaterial3D
				c.albedo_color = color
				mi.set_surface_override_material(si, c)


func _build_ground() -> void:
	# Asphalt inside the district, grass outside it. One collision slab for all.
	Geo.solid_box(self, Vector3(0, -0.5, 0), Vector3(300, 1.0, 300), null)
	Geo.box(self, Vector3(0, -0.01, 0), Vector3(HALF * 2.0, 0.02, HALF * 2.0), M.asphalt)
	for s in [-1.0, 1.0]:
		Geo.box(self, Vector3(s * (HALF + 20.0), -0.005, 0), Vector3(40, 0.02, 300), M.grass_wild)
		Geo.box(self, Vector3(0, -0.005, s * (HALF + 20.0)), Vector3(220, 0.02, 40), M.grass_wild)


func _road_half_x(x: float) -> float:
	for r in Z_ROADS:
		if is_equal_approx(r.x, x):
			return r.w * 0.5
	return 0.0


func _road_half_z(z: float) -> float:
	for r in X_ROADS:
		if is_equal_approx(r.z, z):
			return r.w * 0.5
	return 0.0


func _road_name_z(z: float) -> String:
	for r in X_ROADS:
		if is_equal_approx(r.z, z):
			return r.name
	return ""


func _road_name_x(x: float) -> String:
	for r in Z_ROADS:
		if is_equal_approx(r.x, x):
			return r.name
	return ""


func _build_blocks() -> void:
	var xs := [-HALF, -60.0, 0.0, 60.0, HALF]
	var zs := [-HALF, -60.0, 0.0, 60.0, HALF]
	for ix in 4:
		for iz in 4:
			var x0: float = xs[ix] + _road_half_x(xs[ix])
			var x1: float = xs[ix + 1] - _road_half_x(xs[ix + 1])
			var z0: float = zs[iz] + _road_half_z(zs[iz])
			var z1: float = zs[iz + 1] - _road_half_z(zs[iz + 1])
			blocks.append([x0, x1, z0, z1])
			var block := Node3D.new()
			block.name = "Block_%d_%d" % [ix, iz]
			add_child(block)
			_build_block_slab(block, x0, x1, z0, z1)
			_build_block_contents(block, ix, iz, x0, x1, z0, z1, xs, zs)


func _build_block_slab(block: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, CURB * 0.5, (z0 + z1) * 0.5)
	var size := Vector3(x1 - x0, CURB, z1 - z0)
	# Lighter curb stones form the slab edge; the sidewalk sits a hair above them.
	Geo.solid_box(block, c, size, M.curb)
	Geo.box(block, c + Vector3(0, 0.002, 0), Vector3(size.x - 0.4, CURB, size.z - 0.4), M.concrete)
	Geo.box(block, Vector3(c.x, CURB + 0.003, c.z), Vector3(size.x - SIDEWALK * 2.0, 0.006, size.z - SIDEWALK * 2.0), M.grass)
	# Street lights along the curb on every side that faces a road.
	for i in range(1, int((x1 - x0) / 26.0) + 1):
		var x := x0 + i * (x1 - x0) / (int((x1 - x0) / 26.0) + 1)
		if absf(z0 + HALF) > 1.0:
			_street_light(block, Vector3(x, CURB, z0 + 0.5), 0.0)
		if absf(z1 - HALF) > 1.0:
			_street_light(block, Vector3(x, CURB, z1 - 0.5), PI)


func _build_block_contents(block: Node3D, ix: int, iz: int, x0: float, x1: float, z0: float, z1: float, _xs: Array, zs: Array) -> void:
	var north_road: float = zs[iz]
	var south_road: float = zs[iz + 1]
	var north_faces_road := absf(north_road) < HALF - 1.0
	var south_faces_road := absf(south_road) < HALF - 1.0
	var inner_n := z0 + SIDEWALK
	var inner_s := z1 - SIDEWALK

	if ix == 2 and iz == 2:
		_build_park(block, x0, x1, z0, z1)
		return

	# North edge (front faces -Z, toward the road at z0).
	if north_faces_road:
		var name_n := _road_name_z(north_road)
		if name_n == "Main Road":
			if ix == 1 and iz == 2:
				_build_depot(block, Vector3(-30.0, CURB, inner_n))
				_frontage_shops(block, x0 + 3.0, -42.0, inner_n, -1.0)
				_frontage_shops(block, -18.0, x1 - 3.0, inner_n, -1.0)
			else:
				_frontage_shops(block, x0 + 3.0, x1 - 3.0, inner_n, -1.0)
		else:
			_frontage_houses(block, x0 + 9.0, x1 - 9.0, inner_n, -1.0, name_n)
	# South edge (front faces +Z).
	if south_faces_road:
		var name_s := _road_name_z(south_road)
		if name_s == "Main Road":
			_frontage_shops(block, x0 + 3.0, x1 - 3.0, inner_s, 1.0)
		else:
			_frontage_houses(block, x0 + 9.0, x1 - 9.0, inner_s, 1.0, name_s)
	# Side edges get hedges and trees so cross streets don't look empty.
	for side in [[x0 + SIDEWALK, 1.0], [x1 - SIDEWALK, -1.0]]:
		var ex: float = side[0]
		if absf(ex) > HALF - SIDEWALK - 1.0:
			continue
		var zz := z0 + 24.0
		var alley := (ix * 4 + iz) in ALLEY_BLOCKS
		while zz < z1 - 24.0:
			if not (alley and absf(zz - (z0 + z1) * 0.5) < 3.5):
				_tree(block, Vector3(ex + side[1] * 1.5, CURB, zz), _rng.randf_range(0.9, 1.3))
			zz += _rng.randf_range(7.0, 10.0)
		if not (north_faces_road and _road_name_z(north_road) == "Main Road") and not (south_faces_road and _road_name_z(south_road) == "Main Road"):
			Geo.solid_box(block, Vector3(ex + side[1] * 0.4, CURB + 0.45, (z0 + z1) * 0.5), Vector3(0.7, 0.9, (z1 - z0) - 46.0), M.hedge)


func _next_number(street: String) -> int:
	var n: int = _street_numbers.get(street, 0) + 1
	_street_numbers[street] = n
	return n


## Places houses facing a road. `front_z` is the inner sidewalk edge, `facing`
## is +1 when the road is to +Z, -1 when it is to -Z.
func _frontage_houses(block: Node3D, xa: float, xb: float, front_z: float, facing: float, street: String) -> void:
	var x := xa
	while x < xb - 9.0:
		var lot_w := _rng.randf_range(11.0, 14.5)
		if x + lot_w > xb:
			break
		_house(block, Vector3(x + lot_w * 0.5, CURB, front_z), facing, lot_w, street)
		x += lot_w


func _house(parent: Node3D, front: Vector3, facing: float, lot_w: float, street: String) -> void:
	var number := _next_number(street)
	var address := "%d %s" % [number, street]
	var h := Node3D.new()
	h.name = "House_" + address.replace(" ", "_")
	h.position = front
	# Local +Z points at the road.
	h.rotation.y = 0.0 if facing > 0.0 else PI
	parent.add_child(h)

	var w := _rng.randf_range(7.0, minf(lot_w - 3.0, 10.0))
	var d := _rng.randf_range(7.5, 10.0)
	var storeys := 1 if _rng.randf() < 0.35 else 2
	var wall_h := 2.9 * storeys + 0.3
	var yard := _rng.randf_range(4.5, 6.5)
	var wall_m: Material = M.walls[_rng.randi() % M.walls.size()]
	var roof_m: Material = M.roofs[_rng.randi() % M.roofs.size()]
	var body_c := Vector3(_rng.randf_range(-0.8, 0.8), wall_h * 0.5, -yard - d * 0.5)
	Geo.solid_box(h, body_c, Vector3(w, wall_h, d), wall_m)
	# Foundation plinth.
	Geo.box(h, Vector3(body_c.x, 0.15, body_c.z), Vector3(w + 0.1, 0.3, d + 0.1), M.stone)

	# Roof: gable with ridge either along or across the lot.
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	var roof_h := _rng.randf_range(1.6, 2.6)
	if _rng.randf() < 0.5:
		pm.size = Vector3(w + 0.6, roof_h, d + 0.6)
	else:
		pm.size = Vector3(d + 0.6, roof_h, w + 0.6)
		roof.rotation.y = PI / 2
	roof.mesh = pm
	roof.material_override = _roof_material(M.roof_colors[M.roofs.find(roof_m)], wall_m.get_meta("color", Color(0.8, 0.8, 0.8)))
	roof.position = Vector3(body_c.x, wall_h + roof_h * 0.5, body_c.z)
	h.add_child(roof)
	# Chimney on some houses.
	if _rng.randf() < 0.5:
		var chim_pos := Vector3(body_c.x + w * 0.3, wall_h + roof_h * 0.3, body_c.z + d * 0.15)
		if _model("chimney", h, chim_pos, 0.0, 1.0) == null:
			Geo.box(h, Vector3(body_c.x + w * 0.3, wall_h + roof_h * 0.6, body_c.z + d * 0.15), Vector3(0.6, roof_h * 1.2, 0.6), M.walls[0])

	# Front door, canopy, step.
	var face_z := -yard + 0.04
	var door_x := body_c.x + _rng.randf_range(-w * 0.3, w * 0.3)
	var door_m: Material = M.doors[_rng.randi() % M.doors.size()]
	var wall_face := -yard
	var door := _model("door", h, Vector3(door_x, 0.15, wall_face))
	if door != null:
		_recolor(door, "Door_Paint", DOOR_COLORS[_rng.randi() % DOOR_COLORS.size()])
		var canopy := _model("canopy", h, Vector3(door_x, 2.55, wall_face))
		if canopy != null:
			_recolor(canopy, "Canopy_Roof", M.roof_colors[M.roofs.find(roof_m)])
	else:
		Geo.box(h, Vector3(door_x, 1.15, face_z), Vector3(1.0, 2.1, 0.1), door_m)
		Geo.box(h, Vector3(door_x, 1.15, face_z - 0.01), Vector3(1.2, 2.25, 0.08), M.frame)
		Geo.box(h, Vector3(door_x, 2.45, face_z + 0.45), Vector3(1.8, 0.1, 0.9), roof_m)
	Geo.box(h, Vector3(door_x, 0.075, face_z + 0.5), Vector3(1.7, 0.15, 1.0), M.stone)
	# Front garden: shrubs at the house corners, flower beds either side of the door.
	for sx in [-1.0, 1.0]:
		_model("shrub", h, Vector3(body_c.x + sx * (w * 0.5 - 0.5), 0.0, wall_face + 0.7), _rng.randf() * TAU, _rng.randf_range(0.8, 1.2))
		var bed_x: float = door_x + sx * 2.1
		if absf(bed_x - body_c.x) < w * 0.5 - 1.4:
			_model("flower_bed", h, Vector3(bed_x, 0.0, wall_face + 0.55))
	Geo.label(h, Vector3(door_x + 0.9, 2.0, face_z + 0.06), str(number), 40, Color(0.95, 0.95, 0.9))

	# Windows on the front face, per storey. Some houses have shutters.
	var shutters := _rng.randf() < 0.45 and w >= 8.0
	var shutter_color: Color = SHUTTER_COLORS[_rng.randi() % SHUTTER_COLORS.size()]
	for s in storeys:
		var y := 1.55 + s * 2.9
		var count := 2 if w < 8.5 else 3
		for i in count:
			var wx := body_c.x - w * 0.5 + w * (i + 0.5) / count
			if s == 0 and absf(wx - door_x) < 1.3:
				continue
			_window(h, Vector3(wx, y, wall_face), 0.0, shutters, shutter_color)
	# A side window each side so the silhouette isn't blank.
	for sx in [-1.0, 1.0]:
		_window(h, Vector3(body_c.x + sx * w * 0.5, 1.55, body_c.z), sx * PI / 2, false, shutter_color)

	# Path from sidewalk to door, front hedge/fence with a gate gap, mailbox.
	Geo.box(h, Vector3(door_x, 0.008, -yard * 0.5), Vector3(1.3, 0.016, yard), M.concrete)
	var gap := 1.8
	var left_len := (door_x - gap * 0.5) - (-lot_w * 0.5 + 0.3)
	var right_len := (lot_w * 0.5 - 0.3) - (door_x + gap * 0.5)
	var fence_m: Material = M.hedge if _rng.randf() < 0.6 else M.frame
	var fence_h := 0.8 if fence_m == M.hedge else 0.9
	var picket: bool = fence_m != M.hedge and MODELS.has("picket") and ResourceLoader.exists(MODELS["picket"])
	for seg in [[-lot_w * 0.5 + 0.3, left_len], [door_x + gap * 0.5, right_len]]:
		if seg[1] <= 0.3:
			continue
		var cx: float = seg[0] + seg[1] * 0.5
		if picket:
			# Invisible collider + Blender picket sections stretched to fit the run.
			Geo.solid_box(h, Vector3(cx, 0.5, -0.4), Vector3(seg[1], 1.0, 0.2), null)
			var n := maxi(1, ceili(seg[1] / 2.0))
			var piece: float = seg[1] / n
			for k in n:
				var inst := _model("picket", h, Vector3(seg[0] + piece * (k + 0.5), 0.0, -0.4))
				inst.scale.x = piece / 2.0
		else:
			Geo.solid_box(h, Vector3(cx, fence_h * 0.5, -0.4), Vector3(seg[1], fence_h, 0.45), fence_m)
	var mail_x := door_x + gap * 0.5 + 0.45
	if _model("mailbox", h, Vector3(mail_x, 0, -0.85)) == null:
		Geo.box(h, Vector3(mail_x, 0.55, -0.85), Vector3(0.08, 1.1, 0.08), M.wood)
		Geo.box(h, Vector3(mail_x, 1.15, -0.85), Vector3(0.28, 0.25, 0.45), M.metal_dark)
	# Yard tree and side boundary.
	if _rng.randf() < 0.7:
		_tree(h, Vector3(_rng.randf_range(-lot_w * 0.4, -lot_w * 0.2) if door_x > 0 else _rng.randf_range(lot_w * 0.2, lot_w * 0.4), 0, -yard * 0.35), _rng.randf_range(0.7, 1.0), true)
	Geo.box(h, Vector3(lot_w * 0.5 - 0.1, 0.5, -(yard + d) * 0.5 - 0.5), Vector3(0.15, 1.0, yard + d - 1.0), M.wood)

	# Delivery target covering the front path, reaching onto the sidewalk so the
	# player can stop at the gate and deliver. Papers land on the footpath in
	# front of the gate (local +Z is toward the road; the sidewalk spans 0..SIDEWALK).
	var target := Area3D.new()
	target.set_script(DeliveryTarget)
	target.name = "DeliveryTarget"
	target.position = Vector3(door_x, 1.0, -yard * 0.5 + 1.0)
	h.add_child(target)
	target.configure(address, Vector3(door_x, 0.06, SIDEWALK * 0.4), Vector3(3.2, 2.5, yard + 3.5))
	houses.append(target)


func _frontage_shops(block: Node3D, xa: float, xb: float, front_z: float, facing: float) -> void:
	var x := xa
	while x < xb - 6.0:
		var w := _rng.randf_range(9.0, 14.0)
		if x + w > xb:
			w = xb - x
			if w < 6.0:
				break
		_shop(block, Vector3(x + w * 0.5, CURB, front_z), facing, w - 0.4)
		x += w


func _shop(parent: Node3D, front: Vector3, facing: float, w: float) -> void:
	var s := Node3D.new()
	s.position = front
	s.rotation.y = 0.0 if facing > 0.0 else PI
	parent.add_child(s)
	var shop_name: String = SHOP_NAMES[_shop_i % SHOP_NAMES.size()]
	_shop_i += 1
	s.name = "Shop_" + shop_name.replace(" ", "_").replace("'", "")
	var d := _rng.randf_range(10.0, 14.0)
	var hgt := _rng.randf_range(4.5, 9.0)
	var wall_m: Material = M.walls[_rng.randi() % M.walls.size()]
	Geo.solid_box(s, Vector3(0, hgt * 0.5, -0.6 - d * 0.5), Vector3(w, hgt, d), wall_m)
	Geo.box(s, Vector3(0, hgt + 0.3, -0.6 - d * 0.5), Vector3(w + 0.2, 0.6, d + 0.2), M.stone)
	# Shopfront glazing, door and awning.
	Geo.box(s, Vector3(0, 1.6, -0.56), Vector3(w - 1.2, 2.4, 0.06), M.glass)
	Geo.box(s, Vector3(0, 0.25, -0.54), Vector3(w - 1.0, 0.5, 0.1), M.frame)
	Geo.box(s, Vector3(w * 0.3, 1.2, -0.52), Vector3(1.1, 2.3, 0.08), M.doors[_rng.randi() % M.doors.size()])
	var aw := Geo.box(s, Vector3(0, 3.1, 0.2), Vector3(w - 0.6, 0.08, 1.7), M.awnings[_rng.randi() % M.awnings.size()])
	aw.rotation.x = deg_to_rad(-12)
	Geo.box(s, Vector3(0, 3.65, -0.55), Vector3(w - 1.0, 0.7, 0.1), Geo.mat("sign_board", Color(0.12, 0.13, 0.15), 0.6))
	Geo.label(s, Vector3(0, 3.65, -0.48), shop_name, 72, Color(0.98, 0.93, 0.80))
	if hgt > 6.5:
		for i in 3:
			var wx := -w * 0.5 + w * (i + 0.5) / 3.0
			if _model("window", s, Vector3(wx, 5.4, -0.6)) == null:
				Geo.box(s, Vector3(wx, 5.4, -0.56), Vector3(1.2, 1.3, 0.06), M.glass)


func _build_depot(block: Node3D, front: Vector3) -> void:
	depot = Node3D.new()
	depot.name = "Depot"
	depot.position = front
	block.add_child(depot)
	var brick: Material = M.walls[6]
	# Forecourt (local +Z faces the road at -world Z, so rotate PI).
	depot.rotation.y = PI
	Geo.box(depot, Vector3(0, 0.006, -5.0), Vector3(20, 0.012, 10), Geo.mat("forecourt", Color(0.45, 0.45, 0.46), 0.9, 0.2))
	Geo.solid_box(depot, Vector3(0, 3.5, -16.0), Vector3(20, 7.0, 12), brick)
	Geo.box(depot, Vector3(0, 7.2, -16.0), Vector3(20.4, 0.4, 12.4), M.stone)
	# Roller doors and loading dock.
	for dx in [-5.5, 5.5]:
		Geo.box(depot, Vector3(dx, 1.9, -9.97), Vector3(4.0, 3.6, 0.08), Geo.mat("roller_door", Color(0.55, 0.57, 0.58), 0.5, 0.0, 0.5))
	Geo.box(depot, Vector3(0, 1.2, -9.96), Vector3(1.1, 2.2, 0.08), M.doors[0])
	Geo.box(depot, Vector3(0, 5.2, -9.9), Vector3(14, 1.4, 0.15), Geo.mat("depot_sign", Color(0.12, 0.18, 0.32), 0.6))
	Geo.label(depot, Vector3(0, 5.2, -9.8), "THE DAILY HERALD — DISTRIBUTION", 110, Color(1.0, 0.95, 0.75))
	# Stacks of newspaper bundles on pallets.
	var paper := Geo.mat("newsprint", Color(0.86, 0.84, 0.78), 0.95)
	for i in 4:
		var px := -8.0 + i * 1.4
		Geo.solid_box(depot, Vector3(px, 0.08, -8.6), Vector3(1.2, 0.16, 1.0), M.wood)
		for j in 1 + i % 3:
			Geo.box(depot, Vector3(px, 0.32 + j * 0.3, -8.6), Vector3(1.0, 0.28, 0.8), paper)
	# Pickup counter.
	Geo.solid_box(depot, Vector3(3.0, 0.5, -8.8), Vector3(3.0, 1.0, 0.8), M.wood)
	# The depot clerk, seated by the counter facing the forecourt (depot +Z).
	var clerk := Node3D.new()
	clerk.set_script(DepotClerk)
	clerk.name = "DepotClerk"
	clerk.position = Vector3(6.2, 0.0, -8.4)
	clerk.rotation.y = PI
	depot.add_child(clerk)
	var area := Area3D.new()
	area.set_script(DepotArea)
	area.name = "DepotArea"
	area.position = Vector3(0, 1.0, -5.0)
	depot.add_child(area)
	area.configure(Vector3(18, 3, 9.5))
	# Player spawns in the forecourt facing the road (world -Z).
	spawn_transform = Transform3D(Basis.IDENTITY, front + Vector3(-2.0, 0.05, 4.0))


func _build_park(block: Node3D, x0: float, x1: float, z0: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Paths crossing the park.
	Geo.box(block, Vector3(cx, CURB + 0.008, cz), Vector3(x1 - x0 - 5.0, 0.012, 3.0), M.concrete)
	Geo.box(block, Vector3(cx, CURB + 0.008, cz), Vector3(3.0, 0.012, z1 - z0 - 5.0), M.concrete)
	# Pond with a stone rim (rim has collision; water is just below).
	var pond_c := Vector3(cx + 13.0, CURB, cz - 12.0)
	Geo.box(block, pond_c + Vector3(0, 0.01, 0), Vector3(12, 0.02, 8), M.water)
	for e in [[Vector3(0, 0.2, -4.2), Vector3(12.8, 0.4, 0.4)], [Vector3(0, 0.2, 4.2), Vector3(12.8, 0.4, 0.4)], [Vector3(-6.2, 0.2, 0), Vector3(0.4, 0.4, 8.0)], [Vector3(6.2, 0.2, 0), Vector3(0.4, 0.4, 8.0)]]:
		Geo.solid_box(block, pond_c + e[0], e[1], M.stone)
	# Trees scattered, avoiding paths, pond and ramp area.
	for i in 40:
		var p := Vector3(_rng.randf_range(x0 + 4, x1 - 4), CURB, _rng.randf_range(z0 + 4, z1 - 4))
		if absf(p.x - cx) < 3.5 or absf(p.z - cz) < 3.5:
			continue
		if absf(p.x - pond_c.x) < 8 and absf(p.z - pond_c.z) < 6:
			continue
		if p.x < cx and p.z > cz:
			continue
		_tree(block, p, _rng.randf_range(0.9, 1.5))
	# Benches along the path.
	for bx in [-12.0, -6.0, 8.0, 14.0]:
		_bench(block, Vector3(cx + bx, CURB, cz + 2.4))
	# Bike area (south-west quadrant): kicker ramp, a jump over a log, and a mound.
	var ramp_area := Vector3(cx - 13.0, CURB, cz + 13.0)
	_ramp(block, ramp_area + Vector3(0, 0, 4.0), 0.0, 3.0, 4.0, 16.0)
	Geo.solid_box(block, ramp_area + Vector3(0, 0.25, -2.0), Vector3(3.0, 0.5, 0.5), M.trunk)
	_ramp(block, ramp_area + Vector3(-8.0, 0, -4.0), PI / 2, 2.5, 3.0, 12.0)
	Geo.label(block, ramp_area + Vector3(3.5, 1.6, 4.0), "BMX TRACK", 64, Color(1, 0.85, 0.3), true)


## A wedge ramp: low end at `pos`, rising toward local -Z (forward when rot_y = 0).
func _ramp(parent: Node3D, pos: Vector3, rot_y: float, width: float, length: float, angle_deg: float) -> void:
	var a := deg_to_rad(angle_deg)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	var thick := 0.3
	# Tilted slab whose top surface starts at ground level.
	var center := Vector3(0, sin(a) * length * 0.5 - cos(a) * thick * 0.5, -cos(a) * length * 0.5 - sin(a) * thick * 0.5)
	var body := Geo.solid_box(root, center, Vector3(width, thick, length), M.wood, Vector3(a, 0, 0))
	body.name = "Ramp"
	var top_h := sin(a) * length
	# Support block under the lip so it reads as solid.
	Geo.box(root, Vector3(0, top_h * 0.5 - 0.05, -cos(a) * length + 0.25), Vector3(width, top_h, 0.5), M.dirt)
	ramps.append(root)


func _bench(parent: Node3D, pos: Vector3) -> void:
	if _model("bench", parent, pos) != null:
		Geo.solid_box(parent, pos + Vector3(0, 0.45, 0.02), Vector3(1.8, 0.9, 0.55), null)
		return
	Geo.solid_box(parent, pos + Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.5), M.wood)
	Geo.box(parent, pos + Vector3(0, 0.8, 0.22), Vector3(1.8, 0.4, 0.06), M.wood)
	for sx in [-0.75, 0.75]:
		Geo.box(parent, pos + Vector3(sx, 0.22, 0), Vector3(0.08, 0.45, 0.45), M.metal_dark)


func _tree(parent: Node3D, pos: Vector3, s: float, narrow := false) -> void:
	var r := _rng.randf()
	var variant := "tree_oak" if r < 0.38 else ("tree_maple" if r < 0.75 else "tree_birch")
	if narrow:
		# Close to buildings: slim birches or small maples only.
		variant = "tree_birch" if r < 0.6 else "tree_maple"
		s *= 0.7
	if not ResourceLoader.exists(MODELS[variant]):
		variant = "tree_round" if r < 0.65 else "tree_tall"
	var trunk_r := 0.15 if variant == "tree_birch" else 0.27
	if _model(variant, parent, pos, _rng.randf() * TAU, s * 0.85) != null:
		Geo.static_cylinder(parent, pos + Vector3(0, 1.5 * s, 0), trunk_r * s, 3.0 * s)
		return
	var trunk_h := 2.2 * s
	Geo.cylinder(parent, pos + Vector3(0, trunk_h * 0.5, 0), 0.16 * s, trunk_h, M.trunk)
	var leaf: Material = M.leaves[_rng.randi() % M.leaves.size()]
	Geo.sphere(parent, pos + Vector3(0, trunk_h + 1.3 * s, 0), Vector3(3.2, 2.8, 3.2) * s, leaf)
	Geo.sphere(parent, pos + Vector3(0.6 * s, trunk_h + 2.4 * s, 0.3 * s), Vector3(2.2, 2.0, 2.2) * s, leaf)
	Geo.sphere(parent, pos + Vector3(-0.7 * s, trunk_h + 0.9 * s, -0.4 * s), Vector3(2.0, 1.8, 2.0) * s, leaf)
	Geo.static_cylinder(parent, pos + Vector3(0, trunk_h * 0.5, 0), 0.2 * s, trunk_h)


func _street_light(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var r := Node3D.new()
	r.position = pos
	r.rotation.y = rot_y
	parent.add_child(r)
	Geo.static_cylinder(r, Vector3(0, 1.5, 0), 0.1, 3.0)
	if _model("lamp", r, Vector3.ZERO) != null:
		return
	Geo.cylinder(r, Vector3(0, 3.0, 0), 0.07, 6.0, M.metal_dark)
	Geo.box(r, Vector3(0, 5.95, -0.7), Vector3(0.08, 0.08, 1.4), M.metal_dark)
	Geo.box(r, Vector3(0, 5.88, -1.35), Vector3(0.25, 0.1, 0.5), M.metal_dark)


func _build_road_markings() -> void:
	var y := 0.012
	for r in X_ROADS:
		var z: float = r.z
		var hw: float = r.w * 0.5
		var x := -HALF + 2.0
		while x < HALF - 2.0:
			if not _near_z_road(x, 5.0):
				Geo.box(self, Vector3(x + 1.5, y, z), Vector3(3.0, 0.01, 0.15), M.yellow_paint if r.name == "Main Road" else M.white_paint)
			x += 6.0
		# Crossings on both sides of each intersection.
		for zr in Z_ROADS:
			for sx in [-1.0, 1.0]:
				var cx: float = zr.x + sx * (zr.w * 0.5 + 2.2)
				_zebra(Vector3(cx, y, z), r.w, true)
		# Edge lines.
		for sz in [-1.0, 1.0]:
			var xx := -HALF
			for zr in Z_ROADS + [{"x": HALF, "w": 0.0}]:
				var seg_end: float = zr.x - zr.w * 0.5 - 0.5
				if seg_end > xx + 1.0:
					Geo.box(self, Vector3((xx + seg_end) * 0.5, y, z + sz * (hw - 0.35)), Vector3(seg_end - xx, 0.01, 0.12), M.white_paint)
				xx = zr.x + zr.w * 0.5 + 0.5
	for r in Z_ROADS:
		var x: float = r.x
		var z := -HALF + 2.0
		while z < HALF - 2.0:
			if not _near_x_road(z, 6.0):
				Geo.box(self, Vector3(x, y, z + 1.5), Vector3(0.15, 0.01, 3.0), M.white_paint)
			z += 6.0
		# Give-way lines where side streets meet Main Road.
		for sz in [-1.0, 1.0]:
			Geo.box(self, Vector3(x, y, sz * 5.4), Vector3(r.w, 0.01, 0.3), M.white_paint)


func _near_z_road(x: float, margin: float) -> bool:
	for r in Z_ROADS:
		if absf(x + 1.5 - r.x) < r.w * 0.5 + margin:
			return true
	return false


func _near_x_road(z: float, margin: float) -> bool:
	for r in X_ROADS:
		if absf(z + 1.5 - r.z) < r.w * 0.5 + margin:
			return true
	return false


func _zebra(center: Vector3, road_w: float, along_x_road: bool) -> void:
	var n := int(road_w / 1.0)
	for i in n:
		var off := -road_w * 0.5 + 0.5 + i * 1.0
		if along_x_road:
			Geo.box(self, center + Vector3(0, 0, off), Vector3(3.0, 0.01, 0.5), M.white_paint)
		else:
			Geo.box(self, center + Vector3(off, 0, 0), Vector3(0.5, 0.01, 3.0), M.white_paint)


func _build_boundary() -> void:
	# Low stone wall with a tree line beyond: reads as the edge of town rather
	# than an invisible wall. A taller invisible collider stops ramp jumps over it.
	var e := HALF + 0.6
	for s in [-1.0, 1.0]:
		Geo.solid_box(self, Vector3(s * e, 0.7, 0), Vector3(1.0, 1.4, e * 2.0 + 1.0), M.stone)
		Geo.solid_box(self, Vector3(0, 0.7, s * e), Vector3(e * 2.0 + 1.0, 1.4, 1.0), M.stone)
		Geo.solid_box(self, Vector3(s * (e + 1.0), 4.0, 0), Vector3(0.5, 8.0, e * 2.0 + 3.0), null)
		Geo.solid_box(self, Vector3(0, 4.0, s * (e + 1.0)), Vector3(e * 2.0 + 3.0, 8.0, 0.5), null)
	var p := -HALF
	while p < HALF:
		for s in [-1.0, 1.0]:
			_tree(self, Vector3(s * (HALF + _rng.randf_range(4, 12)), 0, p), _rng.randf_range(1.2, 1.8))
			_tree(self, Vector3(p, 0, s * (HALF + _rng.randf_range(4, 12))), _rng.randf_range(1.2, 1.8))
		p += _rng.randf_range(6.0, 9.0)
	# Road-closed barriers where roads meet the wall.
	var barrier := Geo.mat("barrier", Color(0.85, 0.35, 0.10), 0.7)
	for r in X_ROADS:
		for s in [-1.0, 1.0]:
			Geo.box(self, Vector3(s * (HALF - 0.4), 1.1, r.z), Vector3(0.2, 0.5, r.w), barrier)
	for r in Z_ROADS:
		for s in [-1.0, 1.0]:
			Geo.box(self, Vector3(r.x, 1.1, s * (HALF - 0.4)), Vector3(r.w, 0.5, 0.2), barrier)


## Parked cars along the kerbs: obstacles that narrow the road. Kept clear of
## junctions and crossings. Each gets its own paint colour.
func _build_parked_cars() -> void:
	# Only on stretches the traffic loops don't use (|x| > 63 on Birch Lane and
	# Main Road; anywhere on Park Road), so parked cars never block moving ones.
	var spots := [
		["Birch Lane", -85.0, 1.0], ["Birch Lane", -98.0, -1.0], ["Birch Lane", 84.0, 1.0], ["Birch Lane", 97.0, -1.0],
		["Main Road", -80.0, -1.0], ["Main Road", -96.0, 1.0], ["Main Road", 86.0, -1.0],
		["Park Road", -40.0, -1.0], ["Park Road", 20.0, 1.0], ["Park Road", 88.0, 1.0],
	]
	var i := 0
	for spot in spots:
		var road: Dictionary = {}
		for r in X_ROADS:
			if r.name == spot[0]:
				road = r
		var side: float = spot[2]
		# Drive on the right: cars on the +Z side face -X, on the -Z side face +X.
		var pos := Vector3(spot[1], 0.0, road.z + side * (road.w * 0.5 - 1.15))
		var yaw := PI / 2 if side > 0.0 else -PI / 2
		var car := _model("car", self, pos, yaw)
		if car == null:
			return
		car.name = "ParkedCar%d" % i
		_paint_car(car, CAR_COLORS[i % CAR_COLORS.size()])
		var body := Geo.solid_box(self, pos + Vector3(0, 0.75, 0), Vector3(1.8, 1.5, 4.1), null, Vector3(0, yaw, 0))
		body.collision_layer = Geo.LAYER_WORLD | Geo.LAYER_VEHICLES
		i += 1


func _paint_car(car: Node, color: Color) -> void:
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si)
			if m != null and m.resource_name == "Car_Paint":
				var painted := m.duplicate() as StandardMaterial3D
				painted.albedo_color = color
				mi.set_surface_override_material(si, painted)


func _window(parent: Node3D, pos: Vector3, rot_y: float, shutters: bool, shutter_color: Color) -> void:
	var win := _model("window", parent, pos, rot_y)
	if win == null:
		var face := Node3D.new()
		face.position = pos
		face.rotation.y = rot_y
		parent.add_child(face)
		Geo.box(face, Vector3(0, 0, 0.02), Vector3(1.3, 1.4, 0.06), M.frame)
		Geo.box(face, Vector3(0, 0, 0.04), Vector3(1.1, 1.2, 0.06), M.glass)
		return
	var sh := win.find_child("Shutters", true, false) as Node3D
	if sh != null:
		sh.visible = shutters
		if shutters:
			_recolor(sh, "Shutter_Paint", shutter_color)


# ---------------------------------------------------------------- challenges
func _build_challenges() -> void:
	for bi in ALLEY_BLOCKS:
		_build_alley(bi)
	# Roadworks: Maple Street south of Main Road (west half closed) and Park
	# Road (north half closed). Neither stretch carries traffic.
	_roadworks(Vector3(-1.75, 0, 16.0), Vector3(3.5, 0, 9.0), "Maple Street")
	_roadworks(Vector3(34.0, 0, 58.25), Vector3(9.0, 0, 3.5), "Park Road")
	# Puddles on Park Road and Oak Avenue.
	for p in [Vector3(-30.0, 0.0, 61.5), Vector3(10.0, 0.0, 58.8), Vector3(70.0, 0.0, 61.2), Vector3(-61.0, 0.0, 30.0)]:
		_puddle(self, p, _rng.randf_range(1.0, 1.6), _rng.randf_range(0.7, 1.1))
	_bus_stop(Vector3(30.0, CURB, 6.9))


## Gravel back alley through the middle of a block, walled from the back
## gardens. One has puddles and a crate slalom, the other a ramp over a log.
func _build_alley(bi: int) -> void:
	var b: Array = blocks[bi]
	var zc: float = (b[2] + b[3]) * 0.5
	var xa: float = b[0] + SIDEWALK
	var xb: float = b[1] - SIDEWALK
	var root := Node3D.new()
	root.name = "Alley_%d" % bi
	add_child(root)
	Geo.box(root, Vector3((b[0] + b[1]) * 0.5, CURB + 0.007, zc), Vector3(b[1] - b[0], 0.012, 3.4), Geo.tex_mat("tex_gravel", "gravel", 0.45, Color(0.9, 0.87, 0.8), 0.95, 0.8))
	var wall_m := _facade(0, Color(0.50, 0.30, 0.24))
	for sz in [-1.0, 1.0]:
		Geo.solid_box(root, Vector3((xa + xb) * 0.5, CURB + 0.7, zc + sz * 1.95), Vector3(xb - xa - 1.0, 1.4, 0.3), wall_m)
	var alley_sign := Geo.label(root, Vector3(xa + 0.2, CURB + 2.0, zc), "ALLEY  shortcut", 48, Color(1, 0.9, 0.6), true)
	alley_sign.name = "AlleySign"
	var mid: float = (xa + xb) * 0.5
	if bi == ALLEY_BLOCKS[0]:
		_puddle(root, Vector3(mid - 10.0, CURB, zc), 1.3, 0.9)
		_puddle(root, Vector3(mid + 12.0, CURB, zc + 0.3), 1.1, 0.8)
		# Crate slalom: alternate sides, leave a 1.6 m gap each time.
		for i in 4:
			var cx: float = mid - 3.0 + i * 3.0
			var side := 1.0 if i % 2 == 0 else -1.0
			Geo.solid_box(root, Vector3(cx, CURB + 0.4, zc + side * 0.95), Vector3(0.8, 0.8, 1.2), M.wood)
		# Bins against the wall.
		for i in 2:
			Geo.solid_box(root, Vector3(xb - 4.0 - i * 1.0, CURB + 0.55, zc - 1.45), Vector3(0.7, 1.1, 0.6), Geo.mat("bin_green", Color(0.15, 0.32, 0.20), 0.6))
	else:
		# Ride west (toward -X) up the kicker and clear the log.
		_ramp(root, Vector3(mid + 6.0, CURB, zc), PI / 2, 2.4, 3.0, 15.0)
		Geo.solid_box(root, Vector3(mid - 0.5, CURB + 0.22, zc), Vector3(0.45, 0.45, 2.6), M.trunk)
		_puddle(root, Vector3(mid - 9.0, CURB, zc), 1.2, 0.9)


func _puddle(parent: Node3D, pos: Vector3, rx: float, rz: float) -> void:
	var p := Area3D.new()
	p.set_script(Puddle)
	parent.add_child(p)
	p.global_position = pos
	p.configure(rx, rz)


## Barriers + cones + spoil heap closing part of a road. `size` is the
## closed area's extent (x, _, z).
func _roadworks(center: Vector3, size: Vector3, street: String) -> void:
	var root := Node3D.new()
	root.name = "Roadworks_" + street.replace(" ", "_")
	add_child(root)
	var orange := Geo.mat("barrier_orange", Color(0.90, 0.40, 0.08), 0.6)
	var white := Geo.mat("barrier_white", Color(0.92, 0.92, 0.90), 0.6)
	var long_x := size.x > size.z
	var length: float = size.x if long_x else size.z
	var n := int(length / 1.8)
	for i in n + 1:
		var t := -length * 0.5 + i * (length / n)
		for side in [-1.0, 1.0]:
			var off: float = side * ((size.z if long_x else size.x) * 0.5)
			var pos := center + (Vector3(t, 0, off) if long_x else Vector3(off, 0, t))
			_cone(root, pos)
	# Barrier boards across the ends (solid).
	for side in [-1.0, 1.0]:
		var end := center + (Vector3(side * length * 0.5, 0, 0) if long_x else Vector3(0, 0, side * length * 0.5))
		var across := Vector3(0.15, 1.0, size.z) if long_x else Vector3(size.x, 1.0, 0.15)
		Geo.solid_box(root, end + Vector3(0, 0.5, 0), across, null)
		for k in 3:
			var y := 0.35 + k * 0.25
			var bar := Geo.box(root, end + Vector3(0, y, 0), Vector3(across.x, 0.12, across.z) + Vector3(0.02, 0, 0.02), orange if k % 2 == 0 else white)
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Dug-up patch and spoil heap inside (also solid so nobody rides through).
	Geo.box(root, center + Vector3(0, 0.01, 0), Vector3(size.x - 0.6, 0.02, size.z - 0.6), M.dirt)
	Geo.solid_box(root, center + Vector3(0, 0.35, 0), Vector3(size.x * 0.5, 0.7, size.z * 0.5), null)
	Geo.sphere(root, center + Vector3(0, 0.1, 0), Vector3(size.x * 0.55, 1.2, size.z * 0.55), M.dirt)
	var post := center + (Vector3(-length * 0.5 - 1.5, 0, 0) if long_x else Vector3(0, 0, -length * 0.5 - 1.5))
	Geo.cylinder(root, post + Vector3(0, 1.0, 0), 0.04, 2.0, M.metal_dark)
	Geo.label(root, post + Vector3(0, 2.2, 0), "ROAD WORKS", 64, Color(1.0, 0.75, 0.2), true)


func _cone(parent: Node3D, pos: Vector3) -> void:
	if not M.has("cone_mesh"):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.18
		cm.height = 0.7
		cm.radial_segments = 10
		M.cone_mesh = cm
	var mi := MeshInstance3D.new()
	mi.mesh = M.cone_mesh
	mi.material_override = Geo.mat("cone_orange", Color(0.95, 0.42, 0.08), 0.6)
	mi.position = pos + Vector3(0, 0.35, 0)
	parent.add_child(mi)
	Geo.box(parent, pos + Vector3(0, 0.42, 0), Vector3(0.22, 0.08, 0.22), Geo.mat("cone_band", Color(0.95, 0.95, 0.92), 0.5))
	Geo.box(parent, pos + Vector3(0, 0.02, 0), Vector3(0.42, 0.04, 0.42), M.metal_dark)


func _bus_stop(pos: Vector3) -> void:
	var r := Node3D.new()
	r.name = "BusStop"
	r.position = pos
	add_child(r)
	var glass := Geo.mat("shelter_glass", Color(0.55, 0.65, 0.70), 0.1, 0.0, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.35
	Geo.box(r, Vector3(0, 1.2, 0.45), Vector3(3.2, 2.1, 0.04), glass)
	Geo.box(r, Vector3(0, 2.35, 0.0), Vector3(3.4, 0.08, 1.2), M.metal_dark)
	for sx in [-1.6, 1.6]:
		Geo.box(r, Vector3(sx, 1.2, 0.45), Vector3(0.06, 2.3, 0.06), M.metal_dark)
	Geo.solid_box(r, Vector3(0, 1.2, 0.45), Vector3(3.3, 2.4, 0.15), null)
	_bench(r, Vector3(0, 0, 0.15))
	Geo.cylinder(r, Vector3(2.1, 1.3, -0.4), 0.04, 2.6, M.metal_dark)
	Geo.static_cylinder(r, Vector3(2.1, 1.3, -0.4), 0.06, 2.6)
	Geo.box(r, Vector3(2.1, 2.5, -0.4), Vector3(0.5, 0.5, 0.04), Geo.mat("bus_sign", Color(0.15, 0.35, 0.65), 0.5))
	# Sign faces the road (-Z): Label3D reads from +Z, so turn it around.
	Geo.label(r, Vector3(2.1, 2.5, -0.43), "BUS", 64, Color.WHITE).rotation.y = PI


# ---------------------------------------------------------------- road details
## Kerb drains, manhole covers and repaired asphalt patches.
func _build_road_details() -> void:
	var grate := Geo.mat("drain_grate", Color(0.08, 0.08, 0.08), 0.5, 0.0, 0.6)
	var iron := Geo.mat("manhole", Color(0.18, 0.18, 0.19), 0.55, 0.0, 0.5)
	var patch := Geo.mat("asphalt_patch", Color(0.15, 0.15, 0.16), 0.95, 0.07)
	for r in X_ROADS:
		var x := -HALF + 8.0
		while x < HALF - 8.0:
			if not _near_z_road(x, 3.0):
				for sz in [-1.0, 1.0]:
					Geo.box(self, Vector3(x, 0.012, r.z + sz * (r.w * 0.5 - 0.25)), Vector3(0.7, 0.01, 0.35), grate)
			x += 18.0
	for r in Z_ROADS:
		var z := -HALF + 8.0
		while z < HALF - 8.0:
			if not _near_x_road(z, 3.0):
				for sx in [-1.0, 1.0]:
					Geo.box(self, Vector3(r.x + sx * (r.w * 0.5 - 0.25), 0.012, z), Vector3(0.35, 0.01, 0.7), grate)
			z += 18.0
	for i in 22:
		var on_x := _rng.randf() < 0.6
		var p: Vector3
		if on_x:
			var r: Dictionary = X_ROADS[_rng.randi() % X_ROADS.size()]
			p = Vector3(_rng.randf_range(-HALF + 10, HALF - 10), 0.0, r.z + _rng.randf_range(-1.5, 1.5))
		else:
			var r: Dictionary = Z_ROADS[_rng.randi() % Z_ROADS.size()]
			p = Vector3(r.x + _rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-HALF + 10, HALF - 10))
		if i % 3 == 0:
			var mh := Geo.cylinder(self, p + Vector3(0, 0.006, 0), 0.35, 0.012, iron)
			mh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var pt := Geo.box(self, p + Vector3(0, 0.003, 0), Vector3(_rng.randf_range(1.0, 3.0), 0.006, _rng.randf_range(0.8, 2.0)), patch, _rng.randf_range(-0.2, 0.2))
			pt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const LEAF_SHADER := preload("res://assets/materials/leaves.gdshader")


## Swap the tree model's Blender materials (by name) for the game's: the leaf
## shader on "Leaves_*" and photo bark on "Bark_*". Done once per model on the
## shared meshes, so every instance gets them.
func _dress_tree(scene: PackedScene) -> void:
	var tmp := scene.instantiate()
	for mi in tmp.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(si)
			if m == null:
				continue
			var n := m.resource_name
			if n.begins_with("Leaves_"):
				mesh.surface_set_material(si, _leaf_material("leaves_small" if n == "Leaves_Small" else "leaves_broad"))
			elif n.begins_with("Bark_"):
				mesh.surface_set_material(si, _bark_material("bark_birch" if n == "Bark_Birch" else "bark_oak"))
	tmp.free()


func _leaf_material(atlas: String) -> ShaderMaterial:
	var key := "leafmat_" + atlas
	if not M.has(key):
		var m := ShaderMaterial.new()
		m.shader = LEAF_SHADER
		m.set_shader_parameter("albedo_tex", load("res://assets/textures/trees/%s.png" % atlas))
		m.set_shader_parameter("tint", Color(0.95, 1.0, 0.92) if atlas == "leaves_broad" else Color(1.0, 1.0, 0.9))
		M[key] = m
	return M[key]


func _bark_material(tex: String) -> StandardMaterial3D:
	var key := "barkmat_" + tex
	if not M.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/pixabay/%s_albedo.jpg" % tex)
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/pixabay/%s_normal.png" % tex)
		m.normal_scale = 1.2
		m.roughness = 0.95
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		M[key] = m
	return M[key]
