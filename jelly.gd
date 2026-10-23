# A jellyfish: a creature of the water, drawn from its sheet
# (decor/critters/jelly.png, Elthen's: 32 px frames, a row a motion:
# drifting, the pulse, a bob, the pop, and a puddle). It hangs in the
# water, sinking slowly, and every few seconds it pulses: the bell
# squeezes (the pulse row) and on the squeeze it darts off in a
# direction of its own choosing, mostly up and to the side, never out of
# the water (a pulse that would take it out turns back down), and drifts
# to a stop. Out of the water it falls, and lies as a puddle until it
# slips back in. A tongue tip or a bite that touches it pops it. A faint
# pink glow (the light pass). Drawn on the GPU (draw_on,
# critter_layer.gd), the water's hue over it.
extends RefCounted

const FRAME := 32              # px of a frame in the sheet
const DRIFT_ROW := 0
const PULSE_ROW := 1
const POP_ROW := 3
const PUDDLE_ROW := 4
const FRAMES := 5              # Frames in a motion's row (the pop has 7)
const POP_FRAMES := 7
const FPS := 8.0               # Frames a second of a motion
const SINK := 6.0              # px/s^2 down in the water: it hangs, slowly going down
const DRAG := 1.6              # 1/s: a dart fades out in a second or so
const DART := 85.0             # px/s a pulse gives
const PULSE_MIN := 1.8         # s between pulses
const PULSE_MAX := 4.0
const GRAVITY := 900.0
const TOUCH_R := 7.0           # A tongue tip or a bite this near the bell pops it
const GLOW := Color(0.85, 0.45, 0.75)

var map: Node2D
var pos := Vector2.ZERO        # The bell's centre
var vel := Vector2.ZERO
var alive := true
var popped := false            # Popping: the pop row plays, then it is gone
var in_water := true
var mirror := false
var _t := 0.0                  # Into the motion playing, s
var _row := DRIFT_ROW
var _next := 2.0
var _dart_dir := Vector2.UP
var _darted := false
var _rng := RandomNumberGenerator.new()
var _sheet: Image
var _tex: ImageTexture
var _bell := Vector2(16.0, 12.0)   # The bell's centre in a frame, px


func setup(map_in: Node2D, at: Vector2, sheet: Image, seed_v: int) -> void:
	map = map_in
	pos = at
	_sheet = sheet
	_rng.seed = seed_v
	_next = _rng.randf_range(0.3, PULSE_MAX)
	_t = _rng.randf() * FRAMES / FPS
	mirror = _rng.randf() < 0.5


# Water about p: a few of the cells round it (the water's particles
# leave cells empty between them, so one cell flickers).
func _water(p: Vector2) -> bool:
	var c: float = map.CELL
	var cx := int(floor(p.x / c))
	var cy := int(floor(p.y / c))
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if map.is_water(cx + dx, cy + dy):
				n += 1
	return n >= 3


func tick(dt: float, gecko: Node2D, bites: Array) -> void:
	if not alive:
		return
	_t += dt
	if popped:
		if _t * FPS >= POP_FRAMES:
			alive = false
		return
	# Touched: the tongue's tip, or a bite.
	var touch := false
	if gecko and gecko.tongue_out and gecko.tongue_tip.distance_to(pos) <= TOUCH_R:
		touch = true
		gecko.release_tongue()
	for b in bites:
		if (b[0] as Vector2).distance_to(pos) <= float(b[1]) + TOUCH_R:
			touch = true
	if touch:
		pop()
		return
	in_water = _water(pos)
	if in_water:
		vel += Vector2(0.0, SINK) * dt
		vel *= exp(-DRAG * dt)
		_next -= dt
		if _row == DRIFT_ROW and _next <= 0.0:
			_row = PULSE_ROW
			_t = 0.0
			_darted = false
			var a := _rng.randf_range(-1.2, 1.2)
			_dart_dir = Vector2.UP.rotated(a)
			# Not out of the water: a dart whose end is dry turns down.
			if not _water(pos + _dart_dir * 18.0):
				_dart_dir = Vector2(_dart_dir.x, absf(_dart_dir.y)).normalized()
			mirror = _dart_dir.x < 0.0
		if _row == PULSE_ROW:
			if not _darted and _t * FPS >= 2.0:
				vel += _dart_dir * DART
				_darted = true
			if _t * FPS >= FRAMES:
				_row = DRIFT_ROW
				_t = 0.0
				_next = _rng.randf_range(PULSE_MIN, PULSE_MAX)
	else:
		_row = PUDDLE_ROW
		vel.y += GRAVITY * dt
		vel.x *= exp(-4.0 * dt)
	var nxt := pos + vel * dt
	# The water's skin: in the water it stays under it.
	if in_water and not _water(nxt) and not map.rock_world(nxt) and nxt.y < pos.y:
		nxt.y = pos.y
		vel.y = maxf(vel.y, 0.0)
	# Its body against the rock: the centre, the bell's top 6 px over it
	# and its sides 8 px out, the tentacles' ends 14 under it.
	for o in [Vector2.ZERO, Vector2(0.0, -6.0), Vector2(0.0, 14.0), Vector2(-8.0, 0.0), Vector2(8.0, 0.0)]:
		if map.rock_world(nxt + o):
			vel *= -0.3
			nxt = pos
			break
	pos = nxt
	if in_water and _row == PUDDLE_ROW:
		_row = DRIFT_ROW
		_t = 0.0


func pop() -> void:
	popped = true
	_row = POP_ROW
	_t = 0.0


# The frame showing now: [row, column].
func frame() -> Vector2i:
	var n := POP_FRAMES if _row == POP_ROW else FRAMES
	var k := int(_t * FPS)
	if _row == PUDDLE_ROW:
		k = mini(k, 2)
	elif _row != DRIFT_ROW:
		k = mini(k, n - 1)
	else:
		k = k % n
	return Vector2i(k, _row)


# Its pixels now: [world position, colour] each, a sheet pixel a cell.
func skin(cell: float) -> Array:
	var out: Array = []
	if not alive or _sheet == null:
		return out
	var f := frame()
	var ox := f.x * FRAME
	var oy := f.y * FRAME
	var base := pos - _bell * cell
	for y in FRAME:
		for x in FRAME:
			if ox + x >= _sheet.get_width() or oy + y >= _sheet.get_height():
				continue
			var c := _sheet.get_pixel(ox + x, oy + y)
			if c.a < 0.5:
				continue
			var xx := (FRAME - 1 - x) if mirror else x
			out.append([base + Vector2(xx + 0.5, y + 0.5) * cell, Color(c.r, c.g, c.b)])
	return out


# The jellyfish on the GPU (critter_layer.gd): its frame of the sheet,
# a sheet pixel a cell, on the cell grid, mirrored when it faces left.
func draw_on(c: CanvasItem, cell: float) -> void:
	if not alive or _sheet == null:
		return
	if _tex == null:
		_tex = ImageTexture.create_from_image(_sheet)
	var f := frame()
	var base := ((pos - _bell * cell) / cell).floor() * cell
	var sz := Vector2(FRAME, FRAME) * cell
	var dst := Rect2(base + Vector2(sz.x, 0.0), Vector2(-sz.x, sz.y)) if mirror else Rect2(base, sz)
	c.draw_texture_rect_region(_tex, dst, Rect2(f.x * FRAME, f.y * FRAME, FRAME, FRAME))


func glow() -> Array:
	return [pos, GLOW * (0.5 if not popped else 0.2), 10.0]
