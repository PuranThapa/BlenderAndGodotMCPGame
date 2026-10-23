extends RefCounted
## Shared helpers for building graybox geometry and materials from code.
## Meshes and materials are cached so repeated props share resources.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_VEHICLES := 4
const LAYER_NPCS := 8
const LAYER_TRIGGERS := 16

static var _materials: Dictionary = {}
static var _unit_box: BoxMesh
static var _unit_cyl: CylinderMesh
static var _unit_sphere: SphereMesh
static var _noise_tex: NoiseTexture2D


static func noise_texture() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.02
		n.fractal_octaves = 4
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 256
		_noise_tex.height = 256
		_noise_tex.seamless = true
		_noise_tex.noise = n
		# Keep variation subtle: map noise to 78%..100% brightness.
		var g := Gradient.new()
		g.set_color(0, Color(0.78, 0.78, 0.78))
		g.set_color(1, Color(1, 1, 1))
		_noise_tex.color_ramp = g
	return _noise_tex


## Returns a cached material. `detail` adds a triplanar noise albedo for surface variation.
static func mat(name: String, color: Color, roughness := 0.85, detail := 0.0, metallic := 0.0) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if detail > 0.0:
		m.albedo_texture = noise_texture()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * detail
	_materials[name] = m
	return m


static func emissive_mat(name: String, color: Color, energy := 1.5, alpha := 1.0) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[name] = m
	return m


static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
	return _unit_box


static func unit_cylinder() -> CylinderMesh:
	if _unit_cyl == null:
		_unit_cyl = CylinderMesh.new()
		_unit_cyl.top_radius = 0.5
		_unit_cyl.bottom_radius = 0.5
		_unit_cyl.height = 1.0
		_unit_cyl.radial_segments = 12
		_unit_cyl.rings = 1
	return _unit_cyl


static func unit_sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 16
		_unit_sphere.rings = 8
	return _unit_sphere


## Visual-only box centred at `pos` with full extents `size`.
static func box(parent: Node, pos: Vector3, size: Vector3, material: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box()
	mi.material_override = material
	mi.position = pos
	mi.rotation.y = rot_y
	mi.scale = size
	parent.add_child(mi)
	return mi


## Box with matching static collision.
static func solid_box(parent: Node, pos: Vector3, size: Vector3, material: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation = rot
	parent.add_child(body)
	if material != null:
		var mi := MeshInstance3D.new()
		mi.mesh = unit_box()
		mi.material_override = material
		mi.scale = size
		body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body


static func cylinder(parent: Node, pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_cylinder()
	mi.material_override = material
	mi.position = pos
	mi.scale = Vector3(radius * 2.0, height, radius * 2.0)
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_sphere()
	mi.material_override = material
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


## Cylinder stretched between two local points (for frame tubes, limbs, poles).
static func tube(parent: Node, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_cylinder()
	mi.material_override = material
	parent.add_child(mi)
	set_tube(mi, a, b, radius)
	return mi


static func set_tube(mi: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		mi.visible = false
		return
	mi.visible = true
	var q := Quaternion(Vector3.UP, d / length)
	mi.transform = Transform3D(Basis(q).scaled(Vector3(radius * 2.0, length, radius * 2.0)), (a + b) * 0.5)


static func static_cylinder(parent: Node, pos: Vector3, radius: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	return body


static func label(parent: Node, pos: Vector3, text: String, font_size := 64, color := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


## Photo-textured material (Pixabay sources in assets/textures/pixabay), mapped
## in world space so any box surface tiles it: `tile_m` metres per repeat.
## Falls back to a plain colour if the texture isn't present.
static func tex_mat(name: String, tex: String, tile_m: float, tint := Color.WHITE, roughness := 0.9, normal_scale := 1.0) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	var albedo_path := "res://assets/textures/pixabay/%s_albedo.jpg" % tex
	var normal_path := "res://assets/textures/pixabay/%s_normal.png" % tex
	m.albedo_color = tint
	m.roughness = roughness
	if ResourceLoader.exists(albedo_path):
		m.albedo_texture = load(albedo_path)
		if ResourceLoader.exists(normal_path):
			m.normal_enabled = true
			m.normal_texture = load(normal_path)
			m.normal_scale = normal_scale
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[name] = m
	return m
