extends Node
## Owns the route: which houses are on it, paper inventory, timer, score and
## results. Input: the player's Interact press. Output: signals for the HUD.

const Geo = preload("res://scripts/systems/geo.gd")

signal message(text: String, kind: String)   # kind: info | good | bad
signal changed
signal route_finished(results: Dictionary)

enum Phase { AT_DEPOT, ACTIVE, RETURNING, FINISHED }

@export var route_size := 5
@export var spare_papers := 2
@export var deadline_sec := 420.0
@export var max_delivery_speed := 3.5      # m/s; must slow down to hand a paper over

var phase := Phase.AT_DEPOT
var route: Array = []
var papers := 0
var elapsed := 0.0
var score := 0
var delivered := 0
var delivered_late := 0
var wrong := 0
var crashes := 0
var route_number := 0
var _end_confirm_until := 0.0
var _current_size := 5

var city: Node
var player: Node


func _sfx(key: String, db := 0.0, pitch := 1.0) -> void:
	var a := get_tree().get_first_node_in_group("audio")
	if a:
		a.play(key, db, pitch)


func setup(c: Node, p: Node) -> void:
	city = c
	player = p
	add_to_group("delivery_manager")
	player.crashed.connect(_on_player_crashed)
	player.landed.connect(_on_player_landed)
	player.hit_by_car.connect(func() -> void: message.emit("A car clipped you! Use the crossings and watch the traffic.", "bad"))
	player.dog_nipped.connect(_on_dog_nipped)
	for d in get_tree().get_nodes_in_group("depot"):
		d.player_entered.connect(_on_depot_entered)
	message.emit("Welcome to Maple Heights! Press E at the depot to pick up today's papers.", "info")
	changed.emit()


var _next_refresh := 0.0


func _physics_process(delta: float) -> void:
	if phase == Phase.ACTIVE or phase == Phase.RETURNING:
		elapsed += delta
	_next_refresh -= delta
	if _next_refresh <= 0.0 and phase == Phase.ACTIVE:
		_next_refresh = 0.5
		_update_next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()


func interact() -> void:
	if player == null:
		return
	# Re-validate the trigger references: after a teleport/respawn the exit
	# signal may not have fired yet, leaving a stale zone.
	if player.nearby_target != null and not player.nearby_target.overlaps_body(player):
		player.nearby_target = null
	if player.nearby_depot != null and not player.nearby_depot.overlaps_body(player):
		player.nearby_depot = null
	if player.nearby_target != null:
		_try_deliver(player.nearby_target)
	elif player.nearby_depot != null:
		_depot_action()
	elif phase == Phase.AT_DEPOT:
		message.emit("Head to the depot forecourt to pick up papers.", "info")
	elif phase == Phase.ACTIVE:
		message.emit("No house here. Stop at the gate of a highlighted house.", "info")


func _depot_action() -> void:
	match phase:
		Phase.AT_DEPOT, Phase.FINISHED:
			start_route()
		Phase.ACTIVE:
			var now := Time.get_ticks_msec() / 1000.0
			if now < _end_confirm_until:
				finish_route()
			else:
				_end_confirm_until = now + 4.0
				message.emit("%d deliveries left. Press E again to end the route early." % pending_count(), "info")
		Phase.RETURNING:
			finish_route()


func start_route() -> void:
	route_number += 1
	for h in city.houses:
		h.set_on_route(false)
	# Progression: each new route adds a house (up to +3), keeps the time per
	# house constant, and gives fewer spare papers.
	_current_size = route_size + mini(route_number - 1, 3)
	deadline_sec = 60.0 + 72.0 * _current_size
	route = _pick_route()
	for h in route:
		h.set_on_route(true)
	papers = route.size() + maxi(1, spare_papers - floori((route_number - 1) / 2.0))
	elapsed = 0.0
	score = 0
	delivered = 0
	delivered_late = 0
	wrong = 0
	crashes = 0
	phase = Phase.ACTIVE
	_update_next()
	message.emit("Route %d: %d papers loaded. Deliver to %d houses!" % [route_number, papers, route.size()], "good")
	_sfx("chime", -6.0, 0.9)
	changed.emit()


func _pick_route() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + route_number
	var north: Array = []
	var south: Array = []
	for h in city.houses:
		if h.global_position.z < 0.0:
			north.append(h)
		else:
			south.append(h)
	_shuffle(north, rng)
	_shuffle(south, rng)
	# Mix of nearby houses and ones across Main Road.
	var picked: Array = []
	var n_south := int(ceil(_current_size * 0.5))
	picked.append_array(south.slice(0, n_south))
	picked.append_array(north.slice(0, _current_size - n_south))
	# Order by nearest-neighbour from the depot to suggest a sensible route.
	var ordered: Array = []
	var pos: Vector3 = player.global_position
	while not picked.is_empty():
		var best = picked[0]
		for h in picked:
			if h.drop_point.distance_to(pos) < best.drop_point.distance_to(pos):
				best = h
		ordered.append(best)
		picked.erase(best)
		pos = best.drop_point
	return ordered


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _try_deliver(target: Node) -> void:
	if phase != Phase.ACTIVE:
		if phase == Phase.AT_DEPOT:
			message.emit("You have no papers yet. Pick them up at the depot.", "info")
		elif phase == Phase.RETURNING:
			message.emit("Route done! Head back to the depot.", "info")
		return
	if absf(player.speed) > max_delivery_speed:
		message.emit("Slow down to deliver!", "bad")
		return
	if not target.is_on_route():
		wrong += 1
		score -= 10
		message.emit("Wrong address: %s isn't on your route. (-10)" % target.address, "bad")
		_sfx("buzz", -8.0)
		changed.emit()
		return
	if not target.is_pending():
		message.emit("Already delivered to %s." % target.address, "info")
		return
	if papers <= 0:
		message.emit("Out of papers! Return to the depot.", "bad")
		_sfx("buzz", -8.0)
		return
	papers -= 1
	var late := elapsed > deadline_sec
	target.mark_delivered(late)
	delivered += 1
	if late:
		delivered_late += 1
		score += 50
		message.emit("Delivered to %s (late) +50" % target.address, "info")
	else:
		score += 100
		message.emit("Delivered to %s! +100" % target.address, "good")
	_throw_paper(target.drop_point)
	_sfx("whoosh", -8.0, randf_range(0.9, 1.1))
	if pending_count() == 0:
		phase = Phase.RETURNING
		message.emit("All papers delivered! Ride back to the depot to finish.", "good")
	_update_next()
	changed.emit()


const PAPER_MODEL := "res://assets/models/newspaper_folded.glb"


func _throw_paper(to: Vector3) -> void:
	# The printed, banded Daily Herald (Blender model) leaves the rider's right
	# hand, tumbles, and lands flat on the footpath.
	var paper: Node3D
	if ResourceLoader.exists(PAPER_MODEL):
		paper = (load(PAPER_MODEL) as PackedScene).instantiate()
		get_tree().current_scene.add_child(paper)
	else:
		paper = Node3D.new()
		get_tree().current_scene.add_child(paper)
		Geo.box(paper, Vector3(0, 0.035, 0), Vector3(0.34, 0.07, 0.24), Geo.mat("newsprint_folded", Color(0.90, 0.88, 0.82), 0.95))
	paper.add_to_group("delivered_papers")
	var visual: Node = player.get_node_or_null("Visual")
	var from: Vector3 = player.global_position + Vector3.UP * 1.2
	if visual and visual.has_method("play_throw"):
		visual.play_throw()
		from = visual.right_hand_position()
	paper.global_position = from
	var land_yaw: float = randf_range(-0.6, 0.6) + player.global_rotation.y
	var tw := paper.create_tween()
	tw.tween_method(_fly_paper.bind(paper, from, to + Vector3.DOWN * 0.055, land_yaw), 0.0, 1.0, 0.6)
	tw.tween_callback(_paper_landed.bind(to))


func _paper_landed(at: Vector3) -> void:
	var a := get_tree().get_first_node_in_group("audio")
	if a:
		a.play_at("paper_land", at, -2.0)
		a.play("chime", -10.0)


func _fly_paper(t: float, paper: Node3D, from: Vector3, to: Vector3, land_yaw: float) -> void:
	paper.global_position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 1.0
	# Spin flat like a frisbee with a little wobble, settling to land_yaw.
	paper.rotation = Vector3(sin(t * PI) * 0.35, land_yaw + (1.0 - t) * TAU * 1.5, sin(t * TAU) * 0.15 * (1.0 - t))


func pending_count() -> int:
	var n := 0
	for h in route:
		if h.is_pending():
			n += 1
	return n


func next_target() -> Node:
	for h in route:
		if h.is_pending():
			return h
	return null


func _update_next() -> void:
	var nxt := _nearest_pending()
	for h in route:
		h.set_next(h == nxt)
	# The rider glances at the next house when it's close.
	var visual: Node = player.get_node_or_null("Visual") if player else null
	if visual and "look_target" in visual:
		if nxt and phase == Phase.ACTIVE and nxt.drop_point.distance_to(player.global_position) < 16.0:
			visual.look_target = nxt.drop_point + Vector3.UP * 1.0
		else:
			visual.look_target = null


func _nearest_pending() -> Node:
	var best: Node = null
	for h in route:
		if h.is_pending() and (best == null or h.drop_point.distance_to(player.global_position) < best.drop_point.distance_to(player.global_position)):
			best = h
	return best


func objective_position() -> Variant:
	match phase:
		Phase.ACTIVE:
			var n := _nearest_pending()
			return n.drop_point if n else null
		Phase.RETURNING, Phase.AT_DEPOT, Phase.FINISHED:
			var depots := get_tree().get_nodes_in_group("depot")
			return depots[0].global_position if depots.size() > 0 else null
	return null


func objective_text() -> String:
	match phase:
		Phase.AT_DEPOT:
			return "Pick up papers at the Daily Herald depot (E)"
		Phase.ACTIVE:
			var n := _nearest_pending()
			return "Deliver to %s" % n.address if n else ""
		Phase.RETURNING:
			return "Return to the depot"
		Phase.FINISHED:
			return "Route complete. Press E at the depot for a new route"
	return ""


func _on_depot_entered() -> void:
	if phase == Phase.RETURNING:
		finish_route()


func _on_player_crashed(_impact: float) -> void:
	if phase == Phase.ACTIVE or phase == Phase.RETURNING:
		crashes += 1
		score -= 10
		message.emit("Ouch! Crashed (-10). Back on the bike...", "bad")
		changed.emit()
	else:
		message.emit("Ouch! Watch where you're going.", "bad")


func _on_dog_nipped() -> void:
	if phase == Phase.ACTIVE or phase == Phase.RETURNING:
		score -= 5
		changed.emit()
	message.emit("A dog nipped at your ankle! (-5) Pedal away when you hear a growl.", "bad")


func _on_player_landed(air: float, hard: bool) -> void:
	if hard:
		message.emit("Hard landing!", "bad")
	elif air > 0.6 and (phase == Phase.ACTIVE or phase == Phase.RETURNING):
		score += 5
		message.emit("Nice jump! +5", "good")
		changed.emit()


func finish_route() -> void:
	var total := route.size()
	var missed := pending_count()
	for h in route:
		if h.is_pending():
			h.set_on_route(false)
	var on_time := delivered - delivered_late
	var time_bonus := 0
	if missed == 0 and elapsed < deadline_sec:
		time_bonus = int((deadline_sec - elapsed) * 0.5)
	var accuracy_bonus := 100 if (missed == 0 and wrong == 0) else 0
	score += time_bonus + accuracy_bonus
	var results := {
		"route": route_number,
		"total": total,
		"delivered": delivered,
		"on_time": on_time,
		"late": delivered_late,
		"missed": missed,
		"wrong": wrong,
		"crashes": crashes,
		"time": elapsed,
		"time_bonus": time_bonus,
		"accuracy_bonus": accuracy_bonus,
		"accuracy": (100.0 * delivered / total) if total > 0 else 0.0,
		"score": score,
		"earnings": maxf(0.0, score * 0.05),
		"next_size": route_size + mini(route_number, 3),
	}
	phase = Phase.FINISHED
	_update_next()
	_sfx("fanfare", -6.0)
	route_finished.emit(results)
	changed.emit()
