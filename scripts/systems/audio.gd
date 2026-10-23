extends Node
## Game audio: ambience beds, the bike's rolling/freewheel/chain loops driven by
## the player's speed, and one-shot 2D/3D effects. Real recordings from
## Openverse (assets/audio/openverse, CC0/CC-BY, see CREDITS.json) are used when
## present; the rest are synthesized by assets/audio/source/gen_audio.py.
## Other scripts reach this node through the "audio" group:
## get_tree().get_first_node_in_group("audio").

const SFX := {
	"bell": "res://assets/audio/bell.wav",
	"roll": "res://assets/audio/roll_loop.wav",
	"freewheel": "res://assets/audio/freewheel_loop.wav",
	"chain": "res://assets/audio/chain_loop.wav",
	"brake": "res://assets/audio/brake.wav",
	"thud": "res://assets/audio/thud.wav",
	"crash": "res://assets/audio/crash.wav",
	"whoosh": "res://assets/audio/whoosh.wav",
	"paper_land": "res://assets/audio/paper_land.wav",
	"chime": "res://assets/audio/chime_good.wav",
	"fanfare": "res://assets/audio/fanfare.wav",
	"buzz": "res://assets/audio/buzz_bad.wav",
	"click": "res://assets/audio/click.wav",
	"engine": "res://assets/audio/engine_loop.wav",
	"horn": "res://assets/audio/horn.wav",
	"bark": "res://assets/audio/bark.wav",
	"meow": "res://assets/audio/meow.wav",
	"splash": "res://assets/audio/splash.wav",
	"birds": "res://assets/audio/birds_loop.wav",
	"city": "res://assets/audio/city_loop.wav",
	"wind": "res://assets/audio/wind_loop.wav",
}
const LOOPS := ["roll", "freewheel", "chain", "engine", "birds", "city", "wind"]

# Real recordings (Openverse) replacing the synthesized sound for a key; several
# files = random variant per play. Trims (dB) match each recording's loudness
# to the synthesized sound the game's volume levels were tuned for.
const REAL := {
	"bell": ["bell"], "bark": ["bark", "bark2"], "growl": ["growl"], "meow": ["meow", "meow2"],
	"horn": ["horn"], "splash": ["splash"], "paper_land": ["paper_land"], "crash": ["crash"],
	"engine": ["engine_loop"], "freewheel": ["freewheel_loop"], "chain": ["chain_loop"],
	"birds": ["birds_loop"], "city": ["city_loop"],
}
const REAL_TRIM_DB := {
	"bell": -4.4, "bark": -8.1, "bark2": -8.0, "growl": 0.9, "meow": -4.0, "meow2": -0.3,
	"horn": -1.2, "splash": 0.3, "paper_land": 4.0, "crash": 3.1, "engine_loop": -4.7,
	"freewheel_loop": -1.4, "chain_loop": -1.7, "birds_loop": 6.0, "city_loop": -8.6,
}
const REAL_DIR := "res://assets/audio/openverse/%s.wav"

var player: Node
var _streams := {}        # key -> Array of [AudioStream, trim_db]
var _pool: Array[AudioStreamPlayer] = []
var _roll: AudioStreamPlayer
var _freewheel: AudioStreamPlayer
var _chain: AudioStreamPlayer
var _bed_trim := {}       # player -> trim dB for the per-frame volume ramps
var _brake_cool := 0.0
# Headless (tests/CI) uses a dummy audio driver that never mixes, so stopped
# playbacks are never released and show up as leaks at exit. Nothing can be
# heard there anyway, so stay silent.
var silent := DisplayServer.get_name() == "headless"


func _ready() -> void:
	add_to_group("audio")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for key in SFX.keys() + ["growl"]:
		var variants: Array = []
		for file in REAL.get(key, []):
			var path: String = REAL_DIR % file
			if ResourceLoader.exists(path):
				variants.append([_prepare(key, load(path)), REAL_TRIM_DB.get(file, 0.0)])
		if variants.is_empty() and SFX.has(key) and ResourceLoader.exists(SFX[key]):
			variants.append([_prepare(key, load(SFX[key])), 0.0])
		if not variants.is_empty():
			_streams[key] = variants
	if "--audio-report" in OS.get_cmdline_user_args():
		for key in _streams:
			var files: Array = []
			for v in _streams[key]:
				files.append("%s (%.2fs, %+.1f dB)" % [v[0].resource_path.get_file(), v[0].get_length(), v[1]])
			print("AUDIO ", key, ": ", ", ".join(files))
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_bed("birds", -13.0)
	_bed("city", -21.0)
	_bed("wind", -24.0)
	_roll = _bed("roll", -80.0)
	_freewheel = _bed("freewheel", -80.0)
	_chain = _bed("chain", -80.0)


## Stop every player and drop stream references on shutdown so no playback
## objects outlive the scene (otherwise Godot reports leaked AudioStreamWAVs).
func _exit_tree() -> void:
	for cls in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for p in get_tree().root.find_children("*", cls, true, false):
			p.stop()
			p.stream = null
	_streams.clear()


func _prepare(key: String, s: AudioStream) -> AudioStream:
	if key in LOOPS and s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


## A random variant for `key`: [stream, trim_db].
func _pick(key: String) -> Array:
	var v: Array = _streams[key]
	return v[randi() % v.size()]


func setup(p: Node) -> void:
	player = p


func stream(key: String) -> AudioStream:
	return _pick(key)[0] if _streams.has(key) else null


func _bed(key: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if _streams.has(key):
		var v := _pick(key)
		p.stream = v[0]
		db += v[1]
		_bed_trim[p] = v[1]
	p.volume_db = db
	add_child(p)
	if p.stream and not silent:
		p.play(randf() * p.stream.get_length())
	return p


## 2D one-shot (UI, the rider's own sounds).
func play(key: String, db := 0.0, pitch := 1.0) -> void:
	if silent or not _streams.has(key):
		return
	var v := _pick(key)
	for p in _pool:
		if not p.playing:
			p.stream = v[0]
			p.volume_db = db + v[1]
			p.pitch_scale = pitch
			p.play()
			return


## Positional one-shot (barks, splashes, paper landing, horns).
func play_at(key: String, pos: Vector3, db := 0.0, pitch := 1.0, max_dist := 45.0) -> void:
	if silent or not _streams.has(key) or not is_inside_tree():
		return
	var v := _pick(key)
	var p := AudioStreamPlayer3D.new()
	p.stream = v[0]
	p.volume_db = db + v[1]
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 6.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Looping positional source parented to `node` (car engines).
func attach_loop(node: Node3D, key: String, db: float, max_dist := 40.0) -> AudioStreamPlayer3D:
	if silent or not _streams.has(key):
		return null
	var v := _pick(key)
	var p := AudioStreamPlayer3D.new()
	p.stream = v[0]
	p.volume_db = db + v[1]
	p.max_distance = max_dist
	p.unit_size = 5.0
	node.add_child(p)
	p.play(randf() * p.stream.get_length())
	return p


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var spd: float = absf(player.speed)
	var grounded: bool = player.is_on_floor()
	var pedal: bool = Input.get_action_strength("pedal") > 0.0 and player.controls_enabled
	var t := clampf(spd / 10.0, 0.0, 1.0)
	# Tyres: louder and brighter with speed, silent in the air.
	_roll.volume_db = lerpf(_roll.volume_db, (linear_to_db(t) - 6.0 + _bed_trim.get(_roll, 0.0)) if grounded and spd > 0.3 else -80.0, 10.0 * delta)
	_roll.pitch_scale = 0.8 + 0.5 * t
	# Coasting ticks the freewheel; pedalling makes chain noise.
	var coasting: bool = spd > 1.0 and not pedal
	_freewheel.volume_db = lerpf(_freewheel.volume_db, (-14.0 + _bed_trim.get(_freewheel, 0.0)) if coasting else -80.0, 12.0 * delta)
	_freewheel.pitch_scale = clampf(0.5 + spd / 8.0, 0.5, 1.8)
	_chain.volume_db = lerpf(_chain.volume_db, (-16.0 + _bed_trim.get(_chain, 0.0)) if pedal and spd > 0.5 else -80.0, 12.0 * delta)
	_chain.pitch_scale = clampf(0.7 + spd / 12.0, 0.7, 1.6)
	_brake_cool = maxf(0.0, _brake_cool - delta)
	if Input.is_action_just_pressed("brake") and spd > 4.5 and grounded and _brake_cool <= 0.0:
		play("brake", -10.0, randf_range(0.95, 1.05))
		_brake_cool = 1.5
