extends Area3D
## One house's delivery zone. Every house has one; only those on the active
## route show a marker. The player registers itself as `nearby_target` while
## inside, and the DeliveryManager decides what pressing Interact does.

const Geo = preload("res://scripts/systems/geo.gd")

enum State { IDLE, PENDING, NEXT, DELIVERED }

var address := ""
var drop_point := Vector3.ZERO      # world-space landing spot on the footpath in front of the gate
var state := State.IDLE
var delivered_late := false

var _marker: Node3D
var _beam: MeshInstance3D
var _label: Label3D
var _t := 0.0


func configure(addr: String, house_local_drop: Vector3, size: Vector3) -> void:
	address = addr
	add_to_group("delivery_target")
	collision_layer = Geo.LAYER_TRIGGERS
	collision_mask = Geo.LAYER_PLAYER
	monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	add_child(cs)
	drop_point = get_parent().to_global(house_local_drop)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_marker = Node3D.new()
	_marker.top_level = true
	add_child(_marker)
	_marker.global_position = drop_point
	_beam = Geo.cylinder(_marker, Vector3(0, 6.0, 0), 0.35, 12.0, Geo.emissive_mat("beam_pending", Color(1.0, 0.78, 0.25), 1.2, 0.28))
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = Geo.label(_marker, Vector3(0, 3.2, 0), address, 56, Color(1, 0.92, 0.6), true)
	_label.no_depth_test = false
	_set_state(State.IDLE)


func _set_state(s: State) -> void:
	state = s
	if _marker == null:
		return
	_marker.visible = s == State.PENDING or s == State.NEXT
	match s:
		State.PENDING:
			_beam.material_override = Geo.emissive_mat("beam_pending", Color(1.0, 0.78, 0.25), 1.2, 0.22)
			_beam.scale = Vector3(0.5, 12.0, 0.5)
			_label.modulate = Color(1, 0.92, 0.6, 0.85)
		State.NEXT:
			_beam.material_override = Geo.emissive_mat("beam_next", Color(0.35, 0.85, 1.0), 1.6, 0.35)
			_beam.scale = Vector3(0.8, 12.0, 0.8)
			_label.modulate = Color(0.7, 0.95, 1.0, 1.0)


func set_on_route(on_route: bool) -> void:
	delivered_late = false
	_set_state(State.PENDING if on_route else State.IDLE)


func set_next(is_next: bool) -> void:
	if state == State.PENDING or state == State.NEXT:
		_set_state(State.NEXT if is_next else State.PENDING)


func mark_delivered(late: bool) -> void:
	delivered_late = late
	_set_state(State.DELIVERED)


func is_on_route() -> bool:
	return state == State.PENDING or state == State.NEXT or state == State.DELIVERED


func is_pending() -> bool:
	return state == State.PENDING or state == State.NEXT


func _process(delta: float) -> void:
	if _marker and _marker.visible:
		_t += delta
		_label.position.y = 3.2 + sin(_t * 2.0) * 0.12


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.nearby_target = self


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player") and body.nearby_target == self:
		body.nearby_target = null
