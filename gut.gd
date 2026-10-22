# The gut, always on screen at the bottom left: a soft stomach the
# chewed rock goes into. Each bite comes down the gullet as a bulge and
# drops in as a few jagged pieces in the bitten material's colour, which
# fall, bounce off the wall and each other, and shrink as they digest. A gut holding CAP_FILL of its own
# area takes no bite (gecko.gd gut_full): chewing straight through rock
# fills it, and the gecko waits for it or finds another way.
#
# Drawn in gut pixels on a small viewport shown at SCALE, so it reads as
# pixel art like the world. The wall is a ring of points, each sprung to
# its place on the rest shape and to its neighbours, so pieces push it
# out and it wobbles back, and it squeezes in a slow wave while there is
# something to digest. The pieces are discs to the physics and jagged
# polygons to the eye. The gecko's own moves shake it: the pieces feel
# the body's change of speed as a pull the other way. The gut has its
# own RNG, so the suite's seeding holds.
extends Control

const CaveMap = preload("res://cave_map.gd")

const VIEW := Vector2i(60, 56)  # The viewport in gut pixels
const SCALE := 4                # Screen pixels a gut pixel: a world art pixel at the camera's zoom
const CENTRE := Vector2(29.0, 34.0)
const RX := 22.0                # The rest shape: an ellipse this wide and tall (half axes)
const RY := 16.0
const DENT := 5.0               # The lesser curve: the top left pressed in, a bean
const N_WALL := 30
const THROAT_A := -0.30 * PI    # Where on the rest shape the gullet joins (top right)
const STUB := 4.0              # The gullet's stub out of the wall at the throat, just enough to show the way in
const WALL_K := 0.10            # Each wall point's spring to its rest place, a step
const WALL_DAMP := 0.86         # A wall point keeps this much of its speed, a step
const EDGE_K := 0.5             # How much of a neighbour's stretch a step takes back
const WALL_GIVE := 0.3          # The share of a piece's overlap with the wall the wall takes
const SQUEEZE := 0.03           # The digesting wave's depth, a share of the rest shape
const SQUEEZE_RATE := 2.4       # rad/s
const GRAVITY := 150.0          # Gut px/s²
const BOUNCE := 0.35
const SLIDE := 0.9              # The speed along the wall a piece keeps at a touch
const CAP_FILL := 0.55          # The pieces' area over the rest shape's at which the gut is full
const AREA_SCALE := 0.10        # Gut px² a world px² of bitten rock: a bite of radius 12 is about 45
const PIECE_MIN := 12.0         # A bite splits into pieces of this to PIECE_MAX gut px²
const PIECE_MAX := 28.0
const GONE := 0.6               # A piece smaller than this (gut px²) is digested
const DIGEST := 1.0             # Gut px² a piece loses a second
const GULP := 0.35              # Seconds a bite takes down the gullet
const GULP_GAP := 0.07          # Between the pieces of one bite
const SHAKE := 0.02             # The gecko's change of speed (world px/s²) to the pieces' pull (gut px/s²)
const SHAKE_MAX := 30.0         # Most speed (gut px/s) one tick's shake gives a piece
const STEPS := 2                # Physics substeps a tick

const MEMBRANE := Color(0.55, 0.27, 0.32)
const MEMBRANE_LIT := Color(0.80, 0.42, 0.48)   # The gecko's tongue colour, on the upper rim
const MEMBRANE_FULL := Color(0.78, 0.30, 0.30)
const INSIDE := Color(0.13, 0.05, 0.07, 0.92)
const ROCK := Color(0.47, 0.41, 0.35)          # Rock, lighter than in the world so it reads on the lining
const STONE := Color(0.52, 0.50, 0.46)         # A swallowed lump (the sim does not say its material)
const SLUG := Color(0.62, 0.95, 0.72)

var gecko: Node2D               # Its speed shakes the gut; gut_full is set on it
var _rng := RandomNumberGenerator.new()
var _view: SubViewport
var _canvas: Node2D
var _pts := PackedVector2Array()   # The wall, clockwise on screen
var _prev := PackedVector2Array()
var _rest := PackedVector2Array()  # Each wall point's place about CENTRE
var _edge := PackedFloat32Array()  # Rest length from point i to i + 1
var _throat := 0
var _tube_top := Vector2.ZERO   # The gullet's open end, STUB out from the throat
var _cap := 0.0
var _pieces: Array = []            # {p, v, area, r, rot, spin, shape, col, rate}
var _gulps: Array = []             # {t, area, col, rate}: on their way down the gullet
var _t := 0.0
var _last_pos := Vector2.ZERO
var _last_vel := Vector2.ZERO
var _have_last := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(VIEW * SCALE)
	_view = SubViewport.new()
	_view.size = VIEW
	_view.transparent_bg = true
	_view.disable_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_gut)
	_view.add_child(_canvas)
	var shown := TextureRect.new()
	shown.texture = _view.get_texture()
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.size = size
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shown)


# The wall's rest shape, the throat, the gullet and the room, before
# the gut is in the tree.
func _init() -> void:
	_rng.seed = 7
	var best := INF
	for i in N_WALL:
		var a := TAU * i / N_WALL
		var r := Vector2(RX * cos(a), RY * sin(a))
		# The dent: the top left pressed in, fading round from its middle.
		var da := wrapf(a - 1.38 * PI, -PI, PI)
		r.y += DENT * exp(-da * da / 0.25)
		_rest.append(r)
		var dt := absf(wrapf(a - THROAT_A, -PI, PI))
		if dt < best:
			best = dt
			_throat = i
	for i in N_WALL:
		_edge.append(_rest[i].distance_to(_rest[(i + 1) % N_WALL]))
		_pts.append(CENTRE + _rest[i])
	_prev = _pts.duplicate()
	var e := _rest[(_throat + 1) % N_WALL] - _rest[(_throat - 1 + N_WALL) % N_WALL]
	_tube_top = _pts[_throat] - Vector2(-e.y, e.x).normalized() * STUB
	var poly := PackedVector2Array()
	for r in _rest:
		poly.append(r)
	_cap = absf(_area(poly)) * CAP_FILL


# Bitten or swallowed material on its way down: world_area in world px²
# of cells of kind (a CaveMap cell kind), split into pieces that drop in
# one after another.
func feed(kind: int, world_area: float) -> void:
	_feed(world_area * AREA_SCALE, _colour(kind), _rate(kind))


# A swallowed lump of cells (sim cells, PIXEL_SZ wide) or a slug.
func feed_lump(world_area: float, glow: bool) -> void:
	_feed(world_area * AREA_SCALE, SLUG if glow else STONE, 2.5 if glow else 0.8)


func full() -> bool:
	return held() >= _cap


# The area in the gut and on its way down, against what it holds when
# full: 0 empty, 1 full.
func fill() -> float:
	return held() / _cap


func held() -> float:
	var sum := 0.0
	for pc in _pieces:
		sum += pc.area
	for g in _gulps:
		sum += g.area
	return sum


func clear() -> void:
	_pieces.clear()
	_gulps.clear()
	_have_last = false


func _feed(area: float, col: Color, rate: float) -> void:
	var t := GULP
	if not _gulps.is_empty():
		t = maxf(t, _gulps.back().t + GULP_GAP)
	while area > GONE:
		var a := minf(area, _rng.randf_range(PIECE_MIN, PIECE_MAX))
		# A remainder too small to be a piece goes with this one.
		if area - a < PIECE_MIN * 0.5:
			a = area
		area -= a
		_gulps.append({t = t, area = a, col = col.lightened(_rng.randf_range(-0.08, 0.08)), rate = rate})
		t += GULP_GAP


func _colour(kind: int) -> Color:
	match kind:
		CaveMap.CELL_COPPER:
			return CaveMap.COPPER
		CaveMap.CELL_SAND:
			return CaveMap.SAND.lightened(0.2)
		CaveMap.CELL_CLAY:
			return CaveMap.CLAY.lightened(0.25)
		CaveMap.CELL_HARD:
			return Color(0.36, 0.36, 0.42)
		CaveMap.CELL_SHROOM:
			return CaveMap.SHROOM
		CaveMap.CELL_MOSS:
			return CaveMap.MOSS.lightened(0.2)
		CaveMap.CELL_CRUMBLE:
			return CaveMap.CRUMBLE
		CaveMap.CELL_THORN:
			return CaveMap.THORN
	return ROCK


# How fast a material digests, against rock's 1.
func _rate(kind: int) -> float:
	match kind:
		CaveMap.CELL_SAND, CaveMap.CELL_CLAY:
			return 1.5
		CaveMap.CELL_HARD:
			return 0.5
		CaveMap.CELL_COPPER:
			return 0.7
		CaveMap.CELL_SHROOM, CaveMap.CELL_MOSS:
			return 3.0
	return 1.0


func _physics_process(dt: float) -> void:
	_t += dt
	var pull := _shake(dt)
	for g in _gulps:
		g.t -= dt
	while not _gulps.is_empty() and _gulps[0].t <= 0.0:
		_drop_in(_gulps.pop_front())
	var h := dt / STEPS
	for s in STEPS:
		_step_wall()
		_step_pieces(h, pull)
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		pc.area -= DIGEST * pc.rate * dt
		if pc.area < GONE:
			_pieces.remove_at(i)
		else:
			pc.r = sqrt(pc.area / PI)
	if gecko:
		# Only a hand-played gecko is held back: the suite's scripted
		# digs must run as they were tuned.
		gecko.gut_full = full() and gecko.input_override == null
	if _canvas:
		_canvas.queue_redraw()


# The pull the pieces feel this tick from the gecko's change of speed,
# taken from its moves so a walk on a wall counts as much as a jump.
# A spawn's jump is no move.
func _shake(dt: float) -> Vector2:
	if gecko == null:
		return Vector2.ZERO
	var v: Vector2 = (gecko.pos - _last_pos) / dt
	var pull := Vector2.ZERO
	if _have_last and v.length() < 2000.0:
		pull = -(v - _last_vel) / dt * SHAKE
		pull = pull.limit_length(SHAKE_MAX / dt)
	else:
		v = Vector2.ZERO
	_last_pos = gecko.pos
	_last_vel = v
	_have_last = true
	return pull


func _drop_in(g: Dictionary) -> void:
	var n := _inward(_throat)
	var r := sqrt(g.area / PI)
	var shape := PackedVector2Array()
	var k := _rng.randi_range(5, 7)
	for j in k:
		var a := TAU * (j + _rng.randf_range(-0.3, 0.3)) / k
		shape.append(Vector2.from_angle(a) * _rng.randf_range(0.8, 1.25))
	_pieces.append({
		p = _pts[_throat] + n * (r + 1.5),
		v = (n + Vector2(_rng.randf_range(-0.4, 0.4), 0.0)) * 25.0,
		area = g.area, r = r, rot = _rng.randf() * TAU, spin = _rng.randf_range(-4.0, 4.0),
		shape = shape, col = g.col, rate = g.rate,
	})


func _step_wall() -> void:
	var busy := 1.0 if not _pieces.is_empty() else 0.0
	for i in N_WALL:
		var a := TAU * i / N_WALL
		var wave := 1.0 + SQUEEZE * busy * sin(_t * SQUEEZE_RATE - a * 2.0)
		var target := CENTRE + _rest[i] * wave
		var p := _pts[i]
		var v := (p - _prev[i]) * WALL_DAMP
		_prev[i] = p
		p += v
		p += (target - p) * WALL_K
		_pts[i] = target if i == _throat else p
	for it in 2:
		for i in N_WALL:
			var j := (i + 1) % N_WALL
			var d := _pts[j] - _pts[i]
			var l := d.length()
			if l < 0.001:
				continue
			var fix := d * ((l - _edge[i]) / l) * 0.5 * EDGE_K
			if i != _throat:
				_pts[i] += fix
			if j != _throat:
				_pts[j] -= fix


func _step_pieces(h: float, pull: Vector2) -> void:
	for pc in _pieces:
		pc.v += (Vector2(0.0, GRAVITY) + pull) * h
		pc.p += pc.v * h
		pc.rot += pc.spin * h
	var n := _pieces.size()
	for i in n:
		var a: Dictionary = _pieces[i]
		for j in range(i + 1, n):
			var b: Dictionary = _pieces[j]
			var d: Vector2 = b.p - a.p
			var l := d.length()
			var reach: float = a.r + b.r
			if l >= reach or l < 0.0001:
				continue
			var nrm := d / l
			var wa: float = b.area / (a.area + b.area)
			a.p -= nrm * (reach - l) * wa
			b.p += nrm * (reach - l) * (1.0 - wa)
			var vn: float = (b.v - a.v).dot(nrm)
			if vn < 0.0:
				var j_imp: float = -(1.0 + BOUNCE) * vn / (1.0 / a.area + 1.0 / b.area)
				a.v -= nrm * j_imp / a.area
				b.v += nrm * j_imp / b.area
	for pc in _pieces:
		_hit_wall(pc)


# A piece against the wall: pushed back inside if it got out, and off
# every segment it overlaps, the wall taking WALL_GIVE of the push.
func _hit_wall(pc: Dictionary) -> void:
	if not Geometry2D.is_point_in_polygon(pc.p, _pts):
		var best := INF
		var bi := 0
		var bq := Vector2.ZERO
		for i in N_WALL:
			var q := Geometry2D.get_closest_point_to_segment(pc.p, _pts[i], _pts[(i + 1) % N_WALL])
			var l: float = q.distance_squared_to(pc.p)
			if l < best:
				best = l
				bi = i
				bq = q
		pc.p = bq + _seg_in(bi) * pc.r
		_bounce(pc, _seg_in(bi))
		return
	for i in N_WALL:
		var j := (i + 1) % N_WALL
		var q := Geometry2D.get_closest_point_to_segment(pc.p, _pts[i], _pts[j])
		var d: Vector2 = pc.p - q
		var l := d.length()
		if l >= pc.r:
			continue
		var nrm := d / l if l > 0.0001 else _seg_in(i)
		var pen: float = pc.r - l
		pc.p += nrm * pen * (1.0 - WALL_GIVE)
		var seg := _pts[j] - _pts[i]
		var u := clampf((q - _pts[i]).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		if i != _throat:
			_pts[i] -= nrm * pen * WALL_GIVE * (1.0 - u)
		if j != _throat:
			_pts[j] -= nrm * pen * WALL_GIVE * u
		_bounce(pc, nrm)


func _bounce(pc: Dictionary, nrm: Vector2) -> void:
	var vn: float = pc.v.dot(nrm)
	if vn >= 0.0:
		return
	var vt: Vector2 = pc.v - nrm * vn
	pc.v = vt * SLIDE - nrm * vn * BOUNCE
	pc.spin = lerpf(pc.spin, vt.dot(nrm.orthogonal()) / maxf(pc.r, 0.5), 0.3)


# The inward normal of segment i (from point i to i + 1); the wall runs
# clockwise on screen.
func _seg_in(i: int) -> Vector2:
	var e := _pts[(i + 1) % N_WALL] - _pts[i]
	return Vector2(-e.y, e.x).normalized()


func _inward(i: int) -> Vector2:
	return (_seg_in(i) + _seg_in((i - 1 + N_WALL) % N_WALL)).normalized()


func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _draw_gut() -> void:
	var c := _canvas
	var outer := PackedVector2Array()
	for i in N_WALL:
		outer.append(_pts[i] - _inward(i) * 1.6)
	if Geometry2D.triangulate_polygon(outer).is_empty() or Geometry2D.triangulate_polygon(_pts).is_empty():
		return
	var f := clampf(fill(), 0.0, 1.0)
	var skin := MEMBRANE.lerp(MEMBRANE_FULL, maxf(f - 0.8, 0.0) / 0.2)
	# The gullet's stub, swelling as a bite comes through.
	var throat := _pts[_throat]
	c.draw_line(_tube_top, throat, skin, 5.0)
	for g in _gulps:
		var u := clampf(1.0 - g.t / GULP, 0.0, 1.0)
		c.draw_circle(_tube_top.lerp(throat, u), 3.2, skin)
	c.draw_colored_polygon(outer, skin)
	c.draw_line(_tube_top, throat, INSIDE, 2.0)
	c.draw_colored_polygon(_pts, INSIDE)
	for pc in _pieces:
		var poly := PackedVector2Array()
		for v in pc.shape:
			poly.append(pc.p + (v as Vector2).rotated(pc.rot) * pc.r)
		c.draw_colored_polygon(poly, pc.col)
	# The light on the upper rim.
	var rim := PackedVector2Array()
	for i in range(N_WALL / 2 + 2, N_WALL - 1):
		rim.append(outer[i])
	c.draw_polyline(rim, MEMBRANE_LIT, 1.0)
