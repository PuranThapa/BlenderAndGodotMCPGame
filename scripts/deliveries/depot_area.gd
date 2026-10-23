extends Area3D
## Depot forecourt: pick up papers to start a route, return here to finish.

const Geo = preload("res://scripts/systems/geo.gd")

signal player_entered
signal player_exited


func configure(size: Vector3) -> void:
	add_to_group("depot")
	collision_layer = Geo.LAYER_TRIGGERS
	collision_mask = Geo.LAYER_PLAYER
	monitorable = false
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		b.nearby_depot = self
		player_entered.emit()


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player") and b.nearby_depot == self:
		b.nearby_depot = null
		player_exited.emit()
