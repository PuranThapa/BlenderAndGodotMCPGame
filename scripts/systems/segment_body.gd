extends RefCounted
## Helpers for the rigid-segment humans (rider.glb / pedestrian.glb).
## Each segment is authored along local -Y from its pivot and faces -Z.

const SEGMENTS := ["Torso", "Head", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "ThighL", "ThighR", "ShinL", "ShinR", "FootL", "FootR"]
const TORSO := 0.50
const UPPER_ARM := 0.30
const FOREARM := 0.30
const THIGH := 0.46
const SHIN := 0.44


## Returns {name: Node3D} for every segment, or {} if the model is incomplete.
static func collect(model: Node) -> Dictionary:
	var seg := {}
	for n in SEGMENTS:
		var node := model.find_child(n, true, false) as Node3D
		if node == null:
			return {}
		seg[n] = node
	return seg


## Basis whose +Y is `up` and whose -Z is as close to `fwd` as possible.
static func seg_basis(up: Vector3, fwd: Vector3) -> Basis:
	var f := fwd - up * fwd.dot(up)
	if f.length_squared() < 1e-6:
		f = Vector3(0, 0, -1).cross(up).cross(up)
	var z := -f.normalized()
	return Basis(up.cross(z), up, z)


## Pivot at `a`, segment's -Y pointing at `b`.
static func place(node: Node3D, a: Vector3, b: Vector3, fwd: Vector3) -> void:
	node.transform = Transform3D(seg_basis((a - b).normalized(), fwd), a)


## Recolours surfaces whose Blender material is `mat_name`.
static func recolor(node: Node, mat_name: String, color: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m != null and m.resource_name == mat_name:
				var c := m.duplicate() as StandardMaterial3D
				c.albedo_color = color
				mi.set_surface_override_material(si, c)


## Analytic two-bone IK: returns the middle joint (elbow/knee) position.
static func two_bone(root: Vector3, target: Vector3, l1: float, l2: float, bend: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.001)
	var dir := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := (bend - dir * bend.dot(dir)).normalized()
	return root + dir * a + perp * h
