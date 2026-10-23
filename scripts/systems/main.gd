extends Node3D
## Wires the city, player, delivery manager and HUD together.
##
## Dev/test hooks (pass after `--` on the command line):
##   --shot=/abs/path.png   save a screenshot after --shot-frames (default 90) and quit
##   --fp                   start in first-person view
##   --at=x,z,yaw_deg       start at a world position instead of the depot
##   --start-route          pick up papers immediately
##   --cam=x,y,z,tx,ty,tz   override with a free camera looking at a point
##   --deliver-next         start a route, ride to the nearest house and deliver
##   --map                  open the large map
##   --credits              show the credits screen
##   --crash=speed          force a crash at that impact speed (m/s) at frame 100
##   --crash-wall           (with --crash) crash head-on into the depot wall
##   --film=/abs/prefix     save a frame every --film-every frames from frame 100
##   --paper-cam            (with --deliver-next) close-up of the landed paper
##   --results              show a sample end-of-route results screen

@onready var city: Node3D = $City
@onready var player: CharacterBody3D = $Player
@onready var manager: Node = $DeliveryManager
@onready var hud: CanvasLayer = $HUD
@onready var living: Node3D = $LivingCity
@onready var audio: Node = $Audio

var _args := {}
var _frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_ready_hooks()
	player.teleport(city.spawn_transform)
	audio.setup(player)
	manager.setup(city, player)
	living.setup(city, city.spawn_transform.origin)
	hud.setup(manager, player, city)
	if _args.has("at"):
		var p: PackedStringArray = _args["at"].split(",")
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[2]))), Vector3(float(p[0]), 0.3, float(p[1])))
		player.teleport(xf)
	if _args.has("start-route"):
		manager.start_route()
	if _args.has("results"):
		manager.start_route()
		for h in manager.route.slice(0, 3):
			h.mark_delivered(false)
			manager.delivered += 1
			manager.score += 100
		manager.finish_route.call_deferred()
	if _args.has("credits"):
		hud._show_credits.call_deferred()
	if _args.has("map"):
		hud.minimap.toggle.call_deferred()
	if _args.has("fp"):
		player.toggle_camera()
	if _args.has("cam"):
		var c: PackedStringArray = _args["cam"].split(",")
		var cam := Camera3D.new()
		cam.far = 800.0
		add_child(cam)
		cam.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		cam.look_at(Vector3(float(c[3]), float(c[4]), float(c[5])))
		cam.current = true


func _ready_hooks() -> void:
	# Driven by the tree's frame signal so it also runs while the game is paused
	# (e.g. on the results screen).
	get_tree().process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _args.has("crash") and _frames == 100:
		# Dev: crash at the given impact speed on an open stretch of Main Road.
		if _args.has("crash-wall"):
			# Head-on into the depot wall (rider must deflect, not pass through).
			player.teleport(Transform3D(Basis(Vector3.UP, PI), Vector3(-30, 0.3, 16.6)))
			player._crash(float(_args["crash"]), Vector3(0, 0, 1))
		else:
			player.teleport(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(30, 0.3, -1.5)))
			player._crash(float(_args["crash"]), Vector3(-1, 0, 0))
	if _args.has("film") and _frames >= 100 and (_frames - 100) % int(_args.get("film-every", "15")) == 0:
		var idx: int = floori((_frames - 100) / float(_args.get("film-every", "15")))
		get_viewport().get_texture().get_image().save_png("%s_%03d.png" % [_args["film"], idx])
		if idx >= int(_args.get("film-count", "40")):
			print("FILM_DONE ", idx)
			get_tree().quit()
	# After the launch fade-in (~1.25 s) so the throw is visible in screenshots.
	if _frames == 100 and _args.has("deliver-next"):
		_deliver_next()
	if not _args.has("shot"):
		return
	if _frames == int(_args.get("shot-frames", "90")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args["shot"])
		print("SCREENSHOT_SAVED %s fps=%d draw_calls=%d objects=%d primitives=%d" % [_args["shot"], Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		get_tree().quit()


## Dev hook: stand on the footpath beside the next route house, facing along
## the street, and deliver, so the landing spot can be screenshotted.
func _deliver_next() -> void:
	if manager.route.is_empty():
		manager.start_route()
	var t: Node3D = manager._nearest_pending()
	var house := t.get_parent() as Node3D
	var along := house.global_transform.basis.x
	var to_road := house.global_transform.basis.z
	var pos: Vector3 = t.drop_point + to_road * 0.6 + along * 1.3 + Vector3.UP * 0.2
	player.teleport(Transform3D(Basis.looking_at(-along, Vector3.UP), pos))
	for i in 6:
		await get_tree().physics_frame
	manager.interact()
	if _args.has("paper-cam"):
		# Close-up of where the paper lands.
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = t.drop_point + to_road * 0.5 - along * 0.9 + Vector3.UP * 0.6
		cam.look_at(t.drop_point)
		cam.fov = 50.0
		cam.current = true
