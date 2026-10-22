# The gut's headless test (gut.gd): bites of rock fed at the chew's pace
# until the gut is full, a stand-in gecko shaken by jumps and landings on
# the way, then left to digest. Checked every tick: no piece out of the
# wall, the wall neither collapsed nor blown up, nothing NaN, gut_full on
# the gecko as the gut says. Then that it fills within FILL_BITES, has
# room again soon after the chewing stops, and empties in the end.
# Prints a line a check and GUT TEST OK or FAILS.
#
#   godot --headless --path . -s tests/gut_test.gd
extends SceneTree

const Gut = preload("res://gut.gd")
const CaveMap = preload("res://cave_map.gd")
const DT := 1.0 / 60.0
const BITE := PI * 12.0 * 12.0     # World px² of a full bite of rock
const CHEW_TICKS := 24             # A bite every 0.4 s
const FILL_BITES := Vector2i(8, 24)
const ROOM_AFTER := 4.0            # Seconds after the last bite by which a bite fits again
const EMPTY_AFTER := 120.0

var _fails := 0
var _gut: Gut
var _gecko: Node2D


func _initialize() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar pos := Vector2.ZERO\nvar gut_full := false\nvar input_override = null\n"
	s.reload()
	_gecko = Node2D.new()
	_gecko.set_script(s)
	root.add_child(_gecko)
	_gut = Gut.new()
	_gut.gecko = _gecko
	root.add_child(_gut)
	var rest := absf(_poly_area(_gut._pts))
	var bites := 0
	var full_at := -1
	var bad := 0
	var tick := 0
	# Chew until full, the gecko hopping every 1.5 s.
	while full_at < 0 and bites < 40:
		if tick % CHEW_TICKS == 0:
			_gut.feed(CaveMap.CELL_ROCK if bites % 3 else CaveMap.CELL_COPPER, BITE)
			bites += 1
		_move(tick)
		_gut._physics_process(DT)
		bad += _check(rest)
		if _gut.full():
			full_at = bites
		tick += 1
	_say(full_at >= FILL_BITES.x and full_at <= FILL_BITES.y, "fills after %d bites (want %d to %d)" % [full_at, FILL_BITES.x, FILL_BITES.y])
	_say(_gecko.gut_full, "a hand-played gecko is told the gut is full")
	_gecko.input_override = Vector2.ZERO
	_gut._physics_process(DT)
	_say(not _gecko.gut_full, "a scripted gecko is never held back")
	_gecko.input_override = null
	# Leave it to digest.
	var room_t := -1.0
	var empty_t := -1.0
	var t := 0.0
	var last := _gut.held()
	var grew := 0
	while t < EMPTY_AFTER + 10.0 and empty_t < 0.0:
		_move(tick)
		_gut._physics_process(DT)
		bad += _check(rest)
		var h := _gut.held()
		if h > last + 0.001:
			grew += 1
		last = h
		t += DT
		tick += 1
		if room_t < 0.0 and _gut.held() + BITE * Gut.AREA_SCALE < _gut._cap:
			room_t = t
		if _gut._pieces.is_empty() and _gut._gulps.is_empty():
			empty_t = t
	_say(room_t >= 0.0 and room_t <= ROOM_AFTER, "room for a bite %.1f s after the last (want under %.1f)" % [room_t, ROOM_AFTER])
	_say(empty_t >= 0.0 and empty_t <= EMPTY_AFTER, "empty %.1f s after the last bite (want under %.0f)" % [empty_t, EMPTY_AFTER])
	_say(grew == 0, "digesting only shrinks (%d ticks grew)" % grew)
	_say(bad == 0, "every tick: pieces inside, the wall whole, nothing NaN (%d bad)" % bad)
	_gut.feed(CaveMap.CELL_SAND, BITE)
	_gut.clear()
	_say(_gut.held() == 0.0, "clear empties it")
	print("GUT TEST OK" if _fails == 0 else "GUT TEST FAILS (%d)" % _fails)
	quit(0 if _fails == 0 else 1)


# The stand-in gecko walks, and every 90 ticks jumps (300 px/s up for
# 20 ticks) and lands hard.
func _move(tick: int) -> void:
	var v := Vector2(60.0, 0.0)
	if tick % 90 < 20:
		v = Vector2(40.0, -300.0)
	elif tick % 90 < 30:
		v = Vector2(0.0, 400.0)
	_gecko.pos += v * DT


func _check(rest: float) -> int:
	var bad := 0
	var pts: PackedVector2Array = _gut._pts
	var a := absf(_poly_area(pts))
	if not (a > rest * 0.6 and a < rest * 1.6):
		bad += 1
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y)):
			bad += 1
	for pc in _gut._pieces:
		if not (is_finite(pc.p.x) and is_finite(pc.p.y)) or not Geometry2D.is_point_in_polygon(pc.p, pts):
			bad += 1
	return bad


func _poly_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _say(ok: bool, what: String) -> void:
	print("GUT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
