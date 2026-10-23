extends CanvasLayer
## HUD built in code: objective + direction arrow, papers/timer/score, speed,
## transient messages, controls help, pause menu and route results.
## Runs while paused so the pause menu works.

const DeliveryManager = preload("res://scripts/deliveries/delivery_manager.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const CONTROLS := "W/↑ Pedal    S/↓ Brake/Reverse    A D/← → Steer    Space Hop\nC/V Camera    E Deliver/Interact    B Bell    M Map    R Reset    H Help    Esc Pause    RMB drag: look"

var manager: Node
var player: Node

var _objective: Label
var _distance: Label
var _arrow: Control
var _stats: Label
var _speed: Label
var _message: Label
var _help: Label
var _pause: Control
var _results: Control
var _results_label: Label
var _msg_time := 0.0
var _cam_label: Label
var minimap: Control
var _fade: ColorRect
var _credits: Control
var _root: Control


func setup(m: Node, p: Node, c: Node = null) -> void:
	manager = m
	player = p
	if c != null:
		minimap.setup(c, m, p)
	manager.message.connect(show_message)
	manager.route_finished.connect(_show_results)
	player.camera_mode_changed.connect(func(fp: bool) -> void: _cam_label.text = "View: First person" if fp else "View: Third person")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := _panel(root, Vector2(16, 16), Vector2(560, 88))
	_objective = _label(top, Vector2(14, 8), 22, Color(1, 0.95, 0.8))
	_distance = _label(top, Vector2(70, 46), 18, Color(0.8, 0.9, 1.0))
	_arrow = Control.new()
	_arrow.position = Vector2(36, 60)
	_arrow.draw.connect(_draw_arrow)
	top.add_child(_arrow)

	# Top-right stats box: a PanelContainer so the dark background always
	# grows to fit its text (a fixed-size panel let the last line spill out).
	var right := PanelContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.05, 0.07, 0.1, 0.55)
	rsb.set_corner_radius_all(8)
	rsb.content_margin_left = 14
	rsb.content_margin_right = 14
	rsb.content_margin_top = 8
	rsb.content_margin_bottom = 10
	right.add_theme_stylebox_override("panel", rsb)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -266
	right.offset_right = -16
	right.offset_top = 16
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(right)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 19)
	_stats.add_theme_color_override("font_color", Color.WHITE)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_stats)

	var spd := _panel(root, Vector2(16, 0), Vector2(200, 70))
	# Sits to the right of the round radar in the bottom-left corner.
	spd.anchor_top = 1.0
	spd.anchor_bottom = 1.0
	spd.offset_left = 266
	spd.offset_right = 466
	spd.offset_top = -90
	spd.offset_bottom = -20
	_speed = _label(spd, Vector2(14, 4), 30, Color.WHITE)
	_cam_label = _label(spd, Vector2(14, 42), 14, Color(0.8, 0.8, 0.8))
	_cam_label.text = "View: Third person"

	_help = _label(root, Vector2(0, 0), 15, Color(1, 1, 1, 0.85))
	_help.text = CONTROLS
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.anchor_left = 1.0
	_help.anchor_right = 1.0
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = -900
	_help.offset_right = -16
	_help.offset_top = -60
	_help.offset_bottom = -12
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override("outline_size", 5)

	_message = _label(root, Vector2.ZERO, 26, Color.WHITE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.anchor_top = 0.0
	_message.offset_top = 130
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_message.add_theme_constant_override("outline_size", 8)

	minimap = Control.new()
	minimap.set_script(Minimap)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	_root = root
	_pause = _build_pause(root)
	# Fade in from black: hides the first second of shader compilation.
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	var title := Label.new()
	title.text = "Paper Boy: Morning Delivery"
	title.add_theme_font_size_override("font_size", 40)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_fade.add_child(title)
	var tw := _fade.create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(_fade, "modulate:a", 0.0, 0.9)
	tw.tween_callback(_fade.hide)
	_results = _build_results(root)


func _panel(parent: Control, pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.55)
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _label(parent: Control, pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	b.pressed.connect(func() -> void:
		var a := get_tree().get_first_node_in_group("audio")
		if a:
			a.play("click", -6.0))
	parent.add_child(b)
	return b


func _overlay(root: Control) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.9)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	pc.add_theme_stylebox_override("panel", sb)
	pc.visible = false
	root.add_child(pc)
	return pc


func _build_pause(root: Control) -> Control:
	var pc := _overlay(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var t := Label.new()
	t.text = "Paused"
	t.add_theme_font_size_override("font_size", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var c := Label.new()
	c.text = CONTROLS.replace("    ", "\n")
	c.add_theme_font_size_override("font_size", 16)
	v.add_child(c)
	var vol := HBoxContainer.new()
	var vl := Label.new()
	vl.text = "Master volume"
	vol.add_child(vl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.custom_minimum_size = Vector2(160, 24)
	slider.value_changed.connect(func(val: float) -> void: AudioServer.set_bus_volume_db(0, linear_to_db(maxf(val, 0.0001))))
	vol.add_child(slider)
	v.add_child(vol)
	_button(v, "Resume", func() -> void: set_paused(false))
	_button(v, "Credits", _show_credits)
	_button(v, "Restart", _restart)
	_button(v, "Quit", func() -> void: get_tree().quit())
	return pc


func _build_results(root: Control) -> Control:
	var pc := _overlay(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	_results_label = Label.new()
	_results_label.add_theme_font_size_override("font_size", 20)
	v.add_child(_results_label)
	_button(v, "Continue", _close_results)
	return pc


func _show_credits() -> void:
	if _credits == null:
		_credits = _overlay(_root)
		var box := VBoxContainer.new()
		_credits.add_child(box)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(900, 520)
		box.add_child(scroll)
		var text := Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(870, 0)
		text.add_theme_font_size_override("font_size", 14)
		var f := FileAccess.open("res://credits.txt", FileAccess.READ)
		text.text = f.get_as_text() if f else "Credits file missing."
		scroll.add_child(text)
		_button(box, "Back", func() -> void: _credits.visible = false)
	_credits.visible = true


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _close_results() -> void:
	_results.visible = false
	set_paused(false)


func set_paused(p: bool) -> void:
	get_tree().paused = p
	_pause.visible = p and not _results.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _results.visible:
			_results.visible = false
			set_paused(false)
		else:
			set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_map"):
		minimap.toggle()


func show_message(text: String, kind: String) -> void:
	_message.text = text
	var col := Color.WHITE
	match kind:
		"good":
			col = Color(0.6, 1.0, 0.6)
		"bad":
			col = Color(1.0, 0.55, 0.45)
	_message.add_theme_color_override("font_color", col)
	_message.modulate.a = 1.0
	_msg_time = 3.5


func _show_results(r: Dictionary) -> void:
	var mins := floori(r.time / 60.0)
	var secs := int(r.time) % 60
	_results_label.text = "Route %d complete!\n\nDelivered: %d / %d   (on time %d, late %d)\nMissed: %d    Wrong address: %d    Crashes: %d\nAccuracy: %.0f%%    Time: %d:%02d\nTime bonus: +%d    Perfect-route bonus: +%d\n\nScore: %d\nEarnings: $%.2f\n\nNext route unlocked: %d houses. Press E at the depot." % [
		r.route, r.delivered, r.total, r.on_time, r.late, r.missed, r.wrong, r.crashes, r.accuracy, mins, secs, r.time_bonus, r.accuracy_bonus, r.score, r.earnings, r.next_size]
	_results.visible = true
	get_tree().paused = true


func _process(delta: float) -> void:
	if manager == null:
		return
	_objective.text = manager.objective_text()
	var remaining: float = manager.deadline_sec - manager.elapsed
	var timer_txt := "--:--"
	if manager.phase == DeliveryManager.Phase.ACTIVE or manager.phase == DeliveryManager.Phase.RETURNING:
		var r := absi(int(remaining))
		timer_txt = ("%d:%02d" % [floori(r / 60.0), r % 60]) if remaining >= 0 else ("LATE +%d:%02d" % [floori(r / 60.0), r % 60])
	var left: int = manager.pending_count() if manager.route.size() > 0 and manager.phase != DeliveryManager.Phase.FINISHED else 0
	_stats.text = "Papers: %d\nDeliveries left: %d\nTime: %s\nScore: %d" % [manager.papers, left, timer_txt, manager.score]
	_speed.text = "%d km/h" % roundi(player.get_speed_kmh())
	if _msg_time > 0.0:
		_msg_time -= delta
		_message.modulate.a = clampf(_msg_time, 0.0, 1.0)
	var obj = manager.objective_position()
	if obj != null:
		var d: float = (obj - player.global_position).length()
		_distance.text = "%d m" % roundi(d)
		_arrow.visible = true
	else:
		_distance.text = ""
		_arrow.visible = false
	if player.nearby_target != null and player.nearby_target.is_pending() and manager.phase == DeliveryManager.Phase.ACTIVE:
		_distance.text += "    [E] Deliver to %s" % player.nearby_target.address
	elif player.nearby_depot != null and manager.phase != DeliveryManager.Phase.RETURNING:
		_distance.text += "    [E] Depot"
	_arrow.queue_redraw()


## Arrow pointing toward the objective relative to the active camera's heading.
func _draw_arrow() -> void:
	var obj = manager.objective_position() if manager else null
	if obj == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to: Vector3 = obj - cam.global_position
	var fwd := -cam.global_transform.basis.z
	var ang := atan2(to.x, to.z) - atan2(fwd.x, fwd.z)
	var pts := PackedVector2Array([Vector2(0, -18), Vector2(12, 12), Vector2(0, 5), Vector2(-12, 12)])
	var rot := Transform2D(-ang, Vector2.ZERO)
	for i in pts.size():
		pts[i] = rot * pts[i]
	_arrow.draw_colored_polygon(pts, Color(0.4, 0.85, 1.0))
