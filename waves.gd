# Sound made visible, a mockup (2026-10-23): no overlay graphic, the
# world itself ripples like a pond (shaders/waves.gdshader). A chew
# sends a packet of rings out from the bite; the daylight hum rolls in
# from the exit as an endless train of packets, seen only while the
# gecko listens (Q, the meerkat stand). The rings are drawn over the
# rock, the decor and the light and under the creatures and the gecko,
# so only the ground moves. A creature hears a chew when its front
# reaches it, loud enough, and heads that way (slug.gd, long_slug.gd
# hear). Along the cave (cave on, the particle world): the sound field
# (sound_field.gd) gives each wave its distances round the rock, so the
# rings bend through the tunnels and fade behind walls, and a creature
# heads for the next corner on the sound's path rather than straight at
# it. Off, or in the bitmap world, straight circles that cross rock as
# if it were air. The look is tuned on wave_panel.gd (F1) and kept in
# waves.json.
extends Node2D

const SoundField = preload("res://sound_field.gd")
const MAX_WAVES := SoundField.TILES - 1   # Chew waves at once, a field tile each; the hum has tile 0
const SHADER_WAVES := 16         # The shader's arrays
const STALE_T := 0.1             # s a new wave waits before it is heard: a reused tile's readback can still be the last wave's
const CHEW := 0
const HUM := 1
const HEAR_MIN := 0.15           # Loudness left at the creature for it to hear
const MARK_T := 1.5              # s a heard line stays on the debug view
const CLS_EVERY := 6             # Frames between uploads of the world's classes to the field
const SAVE := "res://waves.json"
# The look's numbers: name, low, high, step. The panel builds a slider
# for each, per kind.
const PARAMS := [
	["speed", 40.0, 1200.0, 10.0],
	["wavelength", 4.0, 80.0, 1.0],
	["rings", 0.5, 8.0, 0.5],
	["amp", 0.0, 12.0, 0.25],
	["reach", 50.0, 4000.0, 10.0],
	["spread", 0.0, 3.0, 0.05],
	["glow", 0.0, 1.0, 0.01],
	["chroma", 0.0, 1.0, 0.01],
	["period", 0.2, 6.0, 0.1],
]
const DEFAULTS := [
	{"speed": 390.0, "wavelength": 4.0, "rings": 2.0, "amp": 5.75, "reach": 3970.0, "spread": 0.75,
		"glow": 0.0, "chroma": 1.0, "period": 1.0, "tint": Color(1.0, 0.72, 0.45)},
	{"speed": 390.0, "wavelength": 20.0, "rings": 2.0, "amp": 5.75, "reach": 3970.0, "spread": 0.75,
		"glow": 0.0, "chroma": 1.0, "period": 2.4, "tint": Color(0.55, 0.85, 1.0)},
]
# The cave's numbers, for both kinds: name, low, high, step, default.
const CAVE_PARAMS := [
	["water_cost", 1.0, 4.0, 0.1, 1.6],     # Sound through water: this many times the path
	["rock_cost", 1.0, 20.0, 0.5, 6.0],     # Through rock
	["rock_damp", 2.0, 200.0, 2.0, 24.0],   # px of rock that take a ring down to a third
]

var look: Array = [DEFAULTS[0].duplicate(), DEFAULTS[1].duplicate()]
var cave_look := {}              # CAVE_PARAMS by name
var cave := true                 # Rings along the cave (the sound field), not straight circles
var snap := true                 # Shifts by whole rock cells: the pixel art stays crisp
var bites := true                # The gecko's bites make chew waves
var bite_gap := 0.3              # s between two bites' waves at least
var hum_always := false          # The hum seen without listening (to tune it)
var hum_at := Vector2.ZERO       # Set by hand (J); the exit's centre otherwise
var hum_set := false
var listen := 0.0                # 0 to 1: how far the gecko is into its listen (main.gd)
var show_marks := false          # A line from each creature to the sound it heard (F1)
var sim: Node2D                  # The particle world, for its classes; null in the bitmap world

var _waves: Array = []           # [at, born, loudness, heard creatures, field tile]
var _time := 0.0                 # s of world time, the waves' clock
var _last_bite := -100.0
var _exit_at := Vector2.ZERO
var _has_exit := false
var _marks: Array = []           # [creature's ear, where it heads, born]
var _mat: ShaderMaterial
var _marks_node: Node2D
var _field: RefCounted           # sound_field.gd, with a sim
var _resets := {}                # Field tiles to clear on the next frame
var _hum_last = null             # The hum's source the field was last seeded from
var _creatures: Array = []       # Last tick's, for the field's ears
var _frame := 0


func _ready() -> void:
	z_as_relative = false
	z_index = 3                  # Over the light (2), under the slug blobs (5) and the gecko (6)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/waves.gdshader")
	material = _mat
	_marks_node = Node2D.new()
	_marks_node.z_as_relative = false
	_marks_node.z_index = 60
	_marks_node.draw.connect(_draw_marks)
	get_parent().add_child.call_deferred(_marks_node)   # Beside, not under: a child would hide with the rings
	for p in CAVE_PARAMS:
		cave_look[p[0]] = p[4]
	if sim:
		_field = SoundField.new()
		_mat.set_shader_parameter("field", _field.texture)
		_mat.set_shader_parameter("field_cell", SoundField.CELL)
		_mat.set_shader_parameter("field_size", SoundField.FIELD)
		_mat.set_shader_parameter("tiles_x", SoundField.TILES_X)
		for t in SoundField.TILES:
			_resets[t] = true
	load_look()
	visible = false


func _exit_tree() -> void:
	if _field:
		_field.free_all()


# Whether the rings follow the cave this frame: asked for, and a field to follow.
func along_cave() -> bool:
	return cave and _field != null and _field.ok()


# A chew wave at a point, at full loudness unless told. The oldest
# goes when every tile is taken.
func emit_at(at: Vector2, loud := 1.0) -> void:
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	var used := {}
	for w in _waves:
		used[w[4]] = true
	var tile := 1
	while used.has(tile):
		tile += 1
	_resets[tile] = true
	_waves.append([at, _time, loud, {}, tile])


# A bite of the gecko's: a chew wave, no closer than bite_gap to the last.
func bite(at: Vector2) -> void:
	if not bites or _time - _last_bite < bite_gap:
		return
	_last_bite = _time
	emit_at(at)


func set_exit(rect: Rect2) -> void:
	_has_exit = rect.has_area()
	_exit_at = rect.get_center()


func hum_source() -> Variant:
	if hum_set:
		return hum_at
	return _exit_at if _has_exit else null


func clear() -> void:
	_waves.clear()
	_marks.clear()
	_hum_last = null


# One world tick: the clock, the fronts reaching creatures, spent waves
# dropped. Creatures are anything with ear() and hear(at). Along the
# cave a creature hears by the field's distance at its ear (read back a
# frame or two late) and heads for the corner the field holds there;
# straight, by the distance and toward the source.
func tick(dt: float, creatures: Array) -> void:
	_time += dt
	_creatures = creatures
	var c: Dictionary = look[CHEW]
	var tail: float = c.rings * c.wavelength * (1.0 + c.spread)
	var follow := along_cave()
	var ears: Array = _field.heard_ears if follow else []
	for i in range(_waves.size() - 1, -1, -1):
		var w: Array = _waves[i]
		var r: float = (_time - w[1]) * c.speed
		if r > c.reach + tail:
			_waves.remove_at(i)
			continue
		var heard: Dictionary = w[3]
		if follow and _time - w[1] < STALE_T:
			continue
		for cr in creatures:
			if heard.has(cr):
				continue
			var ear: Vector2 = cr.ear()
			var d := ear.distance_to(w[0])
			var to: Vector2 = w[0]
			var gain := 1.0
			if follow:
				var k := ears.find(cr)
				var f = _field.at(k, w[4]) if k >= 0 else null
				if f == null:
					continue
				d = f[1]
				gain = exp(-f[2] / cave_look.rock_damp)
				# The next corner on the way, unless it is the ear's own cell.
				if f[0].distance_to(ear) > SoundField.CELL * 1.5:
					to = f[0]
			if d > r:
				continue
			heard[cr] = true
			var fall := clampf(1.0 - d / c.reach, 0.0, 1.0)
			if fall * fall * w[2] * gain >= HEAR_MIN:
				cr.hear(to)
				_marks.append([ear, to, _time])
	while not _marks.is_empty() and _time - _marks[0][2] > MARK_T:
		_marks.pop_front()


func _process(_dt: float) -> void:
	var src = hum_source()
	if _field:
		_step_field(src)
	var hum_show := 0.0
	if src != null:
		hum_show = 1.0 if hum_always else listen
	visible = not _waves.is_empty() or hum_show > 0.0
	_marks_node.visible = show_marks and not _marks.is_empty()
	if _marks_node.visible:
		_marks_node.queue_redraw()
	if not visible:
		return
	var data := PackedVector4Array()
	data.resize(SHADER_WAVES)
	var tiles := PackedFloat32Array()
	tiles.resize(SHADER_WAVES)
	for i in _waves.size():
		var w: Array = _waves[i]
		data[i] = Vector4(w[0].x, w[0].y, _time - w[1], w[2])
		tiles[i] = w[4]
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	_mat.set_shader_parameter("zoom", zoom)
	_mat.set_shader_parameter("count", _waves.size())
	_mat.set_shader_parameter("waves", data)
	_mat.set_shader_parameter("wave_tile", tiles)
	_mat.set_shader_parameter("cave", along_cave())
	_mat.set_shader_parameter("hum_show", hum_show)
	if src != null:
		_mat.set_shader_parameter("hum_at", src)
	_mat.set_shader_parameter("hum_time", _time)
	queue_redraw()


# The field's frame: each tile seeded at its source (the hum's at 0),
# a tile cleared when its wave is new or the hum moved, the world's
# classes now and then, the creatures' ears.
func _step_field(src: Variant) -> void:
	if src != _hum_last:
		_resets[0] = true
		_hum_last = src
	var seeds := PackedFloat32Array()
	seeds.resize(SoundField.TILES * 4)
	if src != null:
		seeds[0] = src.x
		seeds[1] = src.y
		seeds[2] = 1.0
	for w in _waves:
		var k: int = w[4] * 4
		seeds[k] = w[0].x
		seeds[k + 1] = w[0].y
		seeds[k + 2] = 1.0
	for t in _resets:
		seeds[t * 4 + 3] = 1.0
	_resets.clear()
	_frame += 1
	var cls := PackedByteArray()
	if _frame % CLS_EVERY == 1 and sim.cells.size() == SoundField.CLS_W * SoundField.CLS_H * 4:
		cls = sim.cells
	_field.water_cost = cave_look.water_cost
	_field.rock_cost = cave_look.rock_cost
	_field.step(seeds, cls, _creatures)


# The rect the camera sees, in the world: the shader runs over all of it.
func _draw() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport_rect().size
	var a := inv * Vector2.ZERO
	var b := inv * size
	draw_rect(Rect2(a, b - a).abs().grow(4.0), Color.WHITE)


func _draw_marks() -> void:
	for m in _marks:
		var k: float = 1.0 - (_time - m[2]) / MARK_T
		var col := Color(look[CHEW].tint, k)
		_marks_node.draw_line(m[0], m[1], col, 1.0)
		_marks_node.draw_circle(m[0], 3.0, col, false, 1.0)


# The look's numbers to the shader, after any change on the panel.
func apply_look() -> void:
	for p in PARAMS:
		var n: String = p[0]
		_mat.set_shader_parameter(n, PackedFloat32Array([look[CHEW][n], look[HUM][n]]))
	var t0: Color = look[CHEW].tint
	var t1: Color = look[HUM].tint
	_mat.set_shader_parameter("tint", PackedVector3Array([Vector3(t0.r, t0.g, t0.b), Vector3(t1.r, t1.g, t1.b)]))
	_mat.set_shader_parameter("snap", snap)
	_mat.set_shader_parameter("rock_damp", cave_look.rock_damp)


func save_look() -> String:
	var out := {"snap": snap, "cave": cave, "bites": bites, "bite_gap": bite_gap, "cave_look": cave_look, "kinds": []}
	for k in look:
		var d: Dictionary = k.duplicate()
		d.tint = (k.tint as Color).to_html(false)
		out.kinds.append(d)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f == null:
		return "could not write " + SAVE
	f.store_string(JSON.stringify(out, "\t"))
	return "saved " + SAVE


func load_look() -> void:
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary:
			snap = d.get("snap", snap)
			cave = d.get("cave", cave)
			bites = d.get("bites", bites)
			bite_gap = d.get("bite_gap", bite_gap)
			var cl: Dictionary = d.get("cave_look", {})
			for p in CAVE_PARAMS:
				cave_look[p[0]] = float(cl.get(p[0], cave_look[p[0]]))
			var kinds: Array = d.get("kinds", [])
			for i in mini(kinds.size(), look.size()):
				for p in PARAMS:
					look[i][p[0]] = float(kinds[i].get(p[0], look[i][p[0]]))
				look[i].tint = Color.html(String(kinds[i].get("tint", look[i].tint.to_html(false))))
	apply_look()


func reset_look() -> void:
	look = [DEFAULTS[0].duplicate(), DEFAULTS[1].duplicate()]
	for p in CAVE_PARAMS:
		cave_look[p[0]] = p[4]
	snap = true
	cave = true
	apply_look()
