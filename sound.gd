# The sounds, kept light: a few synthesised one-shots on the gecko's
# events (sound.gd is told them by the gecko's signals) and two loops,
# a cave drone everywhere and a daylight hum placed at the exit, so it
# grows as the gecko climbs toward the crack. The files are made by
# tools/gen_sounds.py; each play gets a little pitch variety. Positional
# players sit where the event happened, the listener is the camera.
extends Node2D

const DIR := "res://sounds/"
# No splash and no drip: both misfired (the user, 2026-10-21), so the
# water is silent for now; the files stay in sounds/ for a later try.
const ONE_SHOTS := ["step", "bite", "swallow", "tongue", "snap", "land", "burst", "crumble"]
const POOL := 10                 # Positional players for the one-shots
const STEP_DB := -26.0           # Footsteps barely there
const BITE_DB := -14.0
const SWALLOW_DB := -12.0
const TONGUE_DB := -16.0
const SNAP_DB := -14.0
const LAND_DB := -14.0
const BURST_DB := -6.0
const CRUMBLE_DB := -12.0
const SLIP_DB := -20.0
const LAND_MIN := 120.0          # px/s: a softer landing makes no sound
const DRONE_DB := -22.0
const HUM_DB := -10.0            # At the exit itself; attenuation takes it down with distance
const HUM_REACH := 700.0         # px from the exit the hum fades over
const STEP_GAP := 12             # Physics ticks between footstep sounds at least (0.2 s): the front feet only, at most five taps a second

var _streams := {}
var _pool: Array[AudioStreamPlayer2D] = []
var _next := 0
var _drone: AudioStreamPlayer
var _hum: AudioStreamPlayer2D
var _step_tick := -100         # Physics tick of the last footstep sound
var _on := OS.get_environment("GECKO_SOUND") != "0"
var _rng := RandomNumberGenerator.new()   # Its own: the gecko's steps and bites draw on the global one, and the suite seeds that


func _ready() -> void:
	_rng.seed = 5
	for n in ONE_SHOTS:
		_streams[n] = load(DIR + n + ".wav")
	for i in POOL:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 1400.0
		p.attenuation = 1.2
		add_child(p)
		_pool.append(p)
	_drone = AudioStreamPlayer.new()
	_drone.stream = _loop(load(DIR + "drone.wav"))
	_drone.volume_db = DRONE_DB
	add_child(_drone)
	_hum = AudioStreamPlayer2D.new()
	_hum.stream = _loop(load(DIR + "hum.wav"))
	_hum.volume_db = HUM_DB
	_hum.max_distance = HUM_REACH
	_hum.attenuation = 1.5
	add_child(_hum)
	if _on:
		_drone.play()


# Hooks the gecko's events up.
func listen(gecko: Node) -> void:
	gecko.stepped.connect(_on_step)
	gecko.bit.connect(func(at: Vector2) -> void: play("bite", at, BITE_DB, 0.85, 1.15))
	gecko.swallowed.connect(func() -> void: play("swallow", gecko.pos, SWALLOW_DB, 0.9, 1.1))
	gecko.tongue_shot.connect(func() -> void: play("tongue", gecko.pos, TONGUE_DB, 0.9, 1.2))
	gecko.tongue_hit.connect(func(at: Vector2) -> void: play("snap", at, SNAP_DB, 0.85, 1.15))
	gecko.landed.connect(func(speed: float) -> void:
		if speed >= LAND_MIN:
			play("land", gecko.pos, LAND_DB + clampf((speed - LAND_MIN) / 400.0, 0.0, 1.0) * 6.0 - 6.0, 0.9, 1.1))
	gecko.blasted.connect(func() -> void: play("burst", gecko.pos, BURST_DB, 0.9, 1.1))
	gecko.crumbled.connect(func(at: Vector2) -> void: play("crumble", at, CRUMBLE_DB, 0.85, 1.15))
	gecko.slipped.connect(func() -> void: play("step", gecko.pos, SLIP_DB, 0.55, 0.7))


# The daylight hum sits at the exit; no exit, no hum.
func set_exit(rect: Rect2) -> void:
	if rect.has_area() and _on:
		_hum.position = rect.get_center()
		if not _hum.playing:
			_hum.play()
	else:
		_hum.stop()


func play(name: String, at: Vector2, db: float, pitch_lo := 1.0, pitch_hi := 1.0) -> void:
	if not _on or not _streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.position = at
	p.stream = _streams[name]
	p.volume_db = db
	p.pitch_scale = _rng.randf_range(pitch_lo, pitch_hi)
	p.play()


func _on_step(at: Vector2, front: bool) -> void:
	# Four feet planting would rattle: the front feet only, and never
	# two taps within STEP_GAP, so a walk is a few taps a second.
	if not front:
		return
	var now := Engine.get_physics_frames()
	if now - _step_tick < STEP_GAP:
		return
	_step_tick = now
	play("step", at, STEP_DB, 0.8, 1.25)


func _loop(stream: AudioStreamWAV) -> AudioStreamWAV:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2   # 16-bit mono: two bytes a frame
	return stream
