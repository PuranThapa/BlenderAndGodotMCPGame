extends Control
## GTA-style radar: a round minimap in the bottom-left that rotates with the
## rider (heading always up), with a north marker and edge blips for the next
## delivery and the depot. M toggles a large north-up map with street names.
## Drawn from the city's layout data (no second camera).
##
## Structure: self (layout) -> _mask (clips to a circle / rect) -> _content
## (roads, houses, route, traffic); _overlay draws the rim, N, blips, arrow.

const DeliveryManager = preload("res://scripts/deliveries/delivery_manager.gd")

const RADAR := 230.0
const RADAR_RANGE := 95.0      # world metres from centre to rim
const LARGE := 640.0
const EXTENT := 122.0          # large map: metres from centre to edge

var city: Node
var manager: Node
var player: Node3D
var large := false
var _t := 0.0
var _mask: Control
var _content: Control
var _overlay: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask = Control.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_mask.draw.connect(_draw_mask)
	add_child(_mask)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	_mask.add_child(_content)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_apply_size()


func setup(c: Node, m: Node, p: Node3D) -> void:
	city = c
	manager = m
	player = p
	_apply_size()


func toggle() -> void:
	large = not large
	_apply_size()


func _apply_size() -> void:
	var s := LARGE if large else RADAR
	if large:
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 0.5
		anchor_bottom = 0.5
		offset_left = -s * 0.5
		offset_right = s * 0.5
		offset_top = -s * 0.5
		offset_bottom = s * 0.5
	else:
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = 20.0
		offset_right = 20.0 + s
		offset_top = -20.0 - s
		offset_bottom = -20.0
	for c in [_mask, _content, _overlay]:
		if c:
			c.position = Vector2.ZERO
			c.size = Vector2(s, s)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if visible and _content:
		_content.queue_redraw()
		_overlay.queue_redraw()


## Pixels per metre.
func _scale() -> float:
	return (LARGE * 0.5 / EXTENT) if large else (RADAR * 0.5 / RADAR_RANGE)


## Rotation that turns the rider's heading to screen-up (radar only).
func _heading_rot() -> float:
	if large or player == null:
		return 0.0
	var f := -player.global_transform.basis.z
	return -PI / 2.0 - atan2(f.z, f.x)


## World point -> map pixel.
func w2m(p: Vector3) -> Vector2:
	var c := size * 0.5
	if large:
		return c + Vector2(p.x, p.z) * _scale()
	var rel := Vector2(p.x - player.global_position.x, p.z - player.global_position.z) * _scale()
	return c + rel.rotated(_heading_rot())


func _draw_mask() -> void:
	if large:
		_mask.draw_rect(Rect2(Vector2.ZERO, _mask.size), Color.WHITE)
	else:
		_mask.draw_circle(_mask.size * 0.5, RADAR * 0.5, Color.WHITE)


## Filled world-space rectangle (handles radar rotation).
func _quad(x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
	var pts := PackedVector2Array([w2m(Vector3(x0, 0, z0)), w2m(Vector3(x1, 0, z0)), w2m(Vector3(x1, 0, z1)), w2m(Vector3(x0, 0, z1))])
	_content.draw_colored_polygon(pts, col)


func _draw_content() -> void:
	if city == null or player == null:
		return
	var s := _scale()
	_content.draw_rect(Rect2(Vector2.ZERO, _content.size), Color(0.20, 0.27, 0.17, 0.92))
	var half: float = city.HALF
	_quad(-half, -half, half, half, Color(0.24, 0.24, 0.26))
	for i in city.blocks.size():
		var b: Array = city.blocks[i]
		_quad(b[0], b[2], b[1], b[3], Color(0.62, 0.61, 0.58))
		_quad(b[0] + 2.5, b[2] + 2.5, b[1] - 2.5, b[3] - 2.5, Color(0.25, 0.45, 0.22) if i == 10 else Color(0.36, 0.48, 0.30))
	# House footprints, set back ~10 m from the gate.
	for h in city.houses:
		var hx: Transform3D = h.get_parent().global_transform
		var cpos := hx * Vector3(0, 0, -10.0)
		var ax := hx.basis.x * 4.0
		var az := hx.basis.z * 4.5
		_content.draw_colored_polygon(PackedVector2Array([w2m(cpos - ax - az), w2m(cpos + ax - az), w2m(cpos + ax + az), w2m(cpos - ax + az)]), Color(0.62, 0.42, 0.36))
	if city.depot:
		var dp := w2m(city.depot.global_position)
		_content.draw_rect(Rect2(dp - Vector2(7, 7), Vector2(14, 14)), Color(0.15, 0.30, 0.65))
		_content.draw_string(get_theme_default_font(), dp + Vector2(-4, 5), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if large:
		var font := get_theme_default_font()
		for r in city.X_ROADS:
			_content.draw_string(font, w2m(Vector3(-100, 0, r.z)) + Vector2(0, 4), r.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.85))
		for r in city.Z_ROADS:
			_content.draw_set_transform(w2m(Vector3(r.x, 0, 100)) + Vector2(4, 0), -PI / 2)
			_content.draw_string(font, Vector2.ZERO, r.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.85))
			_content.draw_set_transform(Vector2.ZERO)
	# Route houses.
	if manager:
		var nxt = manager._nearest_pending() if manager.phase == DeliveryManager.Phase.ACTIVE else null
		for h in manager.route:
			var mp := w2m(h.drop_point)
			if h.is_pending():
				var col := Color(0.4, 0.9, 1.0) if h == nxt else Color(1.0, 0.8, 0.25)
				var rad := 5.0 + (sin(_t * 5.0) * 1.5 if h == nxt else 0.0)
				_content.draw_circle(mp, rad, col)
				_content.draw_arc(mp, rad + 1.5, 0, TAU, 16, Color(0, 0, 0, 0.6), 1.5)
			elif h.is_on_route():
				_content.draw_circle(mp, 3.5, Color(0.35, 0.85, 0.35))
	for car in get_tree().get_nodes_in_group("traffic"):
		_content.draw_circle(w2m(car.global_position), maxf(2.5, 1.0 * s), Color(0.9, 0.25, 0.2))
	for dog in get_tree().get_nodes_in_group("dogs"):
		_content.draw_circle(w2m(dog.global_position), 2.5, Color(0.95, 0.6, 0.2))
	for ped in get_tree().get_nodes_in_group("pedestrians"):
		_content.draw_circle(w2m(ped.global_position), 1.8, Color(0.95, 0.95, 0.95, 0.8))


func _draw_overlay() -> void:
	if player == null:
		return
	var c := size * 0.5
	var font := get_theme_default_font()
	if large:
		_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.5), false, 2.0)
		_overlay.draw_string(font, Vector2(10, 20), "Maple Heights  (M to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		_arrow(w2m(player.global_position), atan2(-player.global_transform.basis.z.x, player.global_transform.basis.z.z))
		return
	var r := RADAR * 0.5
	_overlay.draw_arc(c, r - 1.0, 0, TAU, 64, Color(0.05, 0.06, 0.08, 0.9), 5.0)
	_overlay.draw_arc(c, r - 4.0, 0, TAU, 64, Color(1, 1, 1, 0.35), 1.5)
	# North marker on the rim.
	var n_dir := Vector2(0, -1).rotated(_heading_rot())
	var n_pos := c + n_dir * (r - 4.0)
	_overlay.draw_circle(n_pos, 10.0, Color(0.08, 0.09, 0.12))
	_overlay.draw_string(font, n_pos + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	# Edge blips for the objective (next house or depot) when off the radar.
	if manager:
		var targets := []
		var nxt = manager._nearest_pending() if manager.phase == DeliveryManager.Phase.ACTIVE else null
		if nxt:
			targets.append([nxt.drop_point, Color(0.4, 0.9, 1.0)])
		if city and city.depot and (manager.phase != DeliveryManager.Phase.ACTIVE):
			targets.append([city.depot.global_position, Color(0.3, 0.5, 1.0)])
		for tg in targets:
			var mp := w2m(tg[0])
			var off: Vector2 = mp - c
			if off.length() > r - 12.0:
				var ep := c + off.normalized() * (r - 12.0)
				_overlay.draw_circle(ep, 6.5, tg[1])
				_overlay.draw_arc(ep, 7.5, 0, TAU, 16, Color(0, 0, 0, 0.7), 1.5)
	_arrow(c, 0.0)


func _arrow(at: Vector2, ang: float) -> void:
	var pts := PackedVector2Array([Vector2(0, -10), Vector2(7, 7), Vector2(0, 3), Vector2(-7, 7)])
	var xf := Transform2D(ang, at)
	for i in pts.size():
		pts[i] = xf * pts[i]
	_overlay.draw_colored_polygon(pts, Color.WHITE)
	_overlay.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8), 1.5)
