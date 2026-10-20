# The editor's decor brush (editor.gd, main.gd). Dragged along a
# surface it lays a run of a group's stamps edge to edge, the variant
# of each slot picked by its rules. A carpet group, one cut into ends
# and middles by tools/decor_split.py (the moss), runs as a left end,
# middles and a right end, each draped over the ground; a middle goes
# down only with ground for an end past it, so a run ends with its end
# before a cliff or a pit, and a new run starts once the cursor is on
# ground the old one could not reach. Any other group (shrooms, plants)
# is a scatter: whole takes and parts at random, spaced out, each slot
# taking the first variant whose feet (the columns of the art that
# reach its bottom row) find level ground, a single mushroom where a
# cluster would not stand, and the stamp set down on its lowest foot
# when nothing fits level. A click with no drag places one whole take.
# The brush works on the authoring map's cells through two callables,
# so tests/brush_test.gd drags it headless over grounds of its own.
extends RefCounted

const SceneBuilder = preload("res://tests/scene_builder.gd")
const REACH := 6          # Cells either way of the last base the next slot's surface may be; past that the run ends
const LEVEL := 1          # Cells a scatter stamp's feet may differ by and still count as level ground
const FIND := 32          # Cells either way of the cursor's cell the surface is looked for when a run starts
const START := 2          # Cells of drag before the first piece, so the direction is known

var map: Node2D
var place: Callable       # place(name, at, where, flags) -> Rect2: sets the stamp and records it, an empty rect when nothing was set
var taken: Callable       # taken(rect) -> bool: the rect meets a stamp placed before
var rng := RandomNumberGenerator.new()
var spacing := 0.0        # Px between stamps along the surface
var mirror := true        # Mirror at random
var pin := ""             # The variant to lay, or "" for the rules' pick
var runs: Array = []      # The runs laid, each the pieces in order as [name, flags]

var _names: Array = []
var _carpet := false
var _end_w := 0           # The widest end piece, in cells: the room a run needs past a middle
var _where := ""
var _along := Vector2i(1, 0)
var _up := Vector2i(0, -1)
var _start := Vector2.ZERO
var _dir := 0             # The run's direction along the surface, 0 until the drag shows it
var _base := Vector2i.ZERO   # The last piece's base cell (on the surface under its middle)
var _lo := 0              # The last piece's first and last cells along the surface
var _hi := 0
var _count := 0           # Pieces in the run; 0 while its first is still to be laid
var _capped := false      # The run is complete; the next piece starts a new one
var _last := ""


# The button down at `at`, on the surface `where` (floor, ceiling,
# wall_left, wall_right), with the group's stamps. A scatter lays its
# first stamp here at once; a carpet waits for the drag's direction.
func begin(names: Array, at: Vector2, where: String) -> void:
	_names = names
	_carpet = false
	_end_w = 0
	for n in names:
		var role := SceneBuilder.stamp_role(n)
		if role == "l" or role == "r":
			_carpet = true
			_end_w = maxi(_end_w, _width(n))
	_where = where
	_start = at
	_dir = 0
	_count = 0
	_capped = false
	_last = ""
	var fr: Array = SceneBuilder.frame(map, at, where)
	_along = fr[1]
	_up = fr[2]
	_base = _refine(fr[0])
	if not _carpet:
		_first()


# The cursor at `at` with the button down: every slot the cursor has
# passed gets its piece, each laid on the surface next to the last.
func drag(at: Vector2) -> void:
	var a := _along_of(at)
	if _dir == 0:
		var d := a - _along_of(_start)
		if absi(d) < START:
			return
		_dir = signi(d)
	var guard := 0
	while guard < 64:
		guard += 1
		if _capped:
			# The run is complete: a new one starts once the cursor is
			# on ground it could not reach.
			if _surface(a) != null:
				return
			_count = 0
			_capped = false
		if _count == 0:
			# The run's first piece, under the cursor as it goes: a stamp
			# in the way holds it off until the cursor has moved on.
			_base = _refine(SceneBuilder.frame(map, at, _where)[0])
			if not _first():
				return
			continue
		var cands := _cands("m" if _carpet else "")
		var probe := _slot(_width(cands[0].name))
		if (_dir > 0 and a < probe) or (_dir < 0 and a > probe):
			return
		var fit := _fit(cands, null)
		if fit.is_empty():
			# The ground is gone (a cliff, a pit) with no end laid: the
			# run is over as it stands.
			_cap()
			continue
		if _carpet and not _room_past(fit.base, _width(fit.name)):
			# No ground for an end past this slot: the end goes here.
			_cap()
			continue
		if not _lay(fit, fit.base):
			_skip(_width(fit.name))   # A stamp placed before is in the way: the run passes it


# The button up: a click lays one whole take; a carpet's run gets its end.
func end(_at: Vector2) -> void:
	if _dir == 0:
		if _count == 0:
			_lay(_cands("")[0], _base)
	else:
		_cap()


# The first piece of a run at _base: a scatter's first stamp; a carpet's
# start end, or a whole take when no end would fit past it (a ledge
# too short for a run), which completes the run. False when a stamp
# placed before is in the way.
func _first() -> bool:
	if not _carpet:
		var cands := _cands("")
		var fit := _fit(cands, _base)
		if fit.is_empty():
			return _lay(cands[0], _base)
		return _lay(fit, fit.base)
	var start: Dictionary = _cands("l" if _dir > 0 else "r")[0]
	if _room_past(_base, _width(start.name)):
		return _lay(start, _base)
	if _lay(_cands("")[0], _base):
		_capped = true
		return true
	return false


# A carpet's end at the next slot, if ground is there; the run is
# complete either way.
func _cap() -> void:
	if _count > 0 and _carpet and not _capped:
		var pick: Dictionary = _cands("r" if _dir > 0 else "l")[0]
		var base: Variant = _surface(_slot(_width(pick.name)))
		if base != null:
			_lay(pick, base)
	_capped = true


# Whether the ground past a piece w cells wide at `base` reaches the
# middle of the widest end's slot.
func _room_past(base: Vector2i, w: int) -> bool:
	var a0 := _along_cell(base)
	var after := a0 + (w - w / 2) + _sp() + _end_w / 2 if _dir > 0 else a0 - w / 2 - _sp() - _end_w + _end_w / 2
	return SceneBuilder.surface_cell(map, base, _along, _up, after - a0, REACH) != null


# The surface cell under the middle of a slot, near the last piece's base.
func _surface(cx: int) -> Variant:
	return SceneBuilder.surface_cell(map, _base, _along, _up, cx - _along_cell(_base), REACH)


# The nearest surface cell at a cell's column, within FIND cells: a
# cursor inside rock or high in the air still starts a run on the ground.
func _refine(c: Vector2i) -> Vector2i:
	var s: Variant = SceneBuilder.surface_cell(map, c, _along, _up, 0, FIND)
	return s if s != null else c


# The middle cell (along the surface) of the next slot for a piece w
# cells wide: past the last piece by the spacing.
func _slot(w: int) -> int:
	if _dir > 0:
		return _hi + 1 + _sp() + w / 2
	return _lo - _sp() - w + w / 2


func _skip(w: int) -> void:
	if _dir > 0:
		_hi += _sp() + w
	else:
		_lo -= _sp() + w


func _sp() -> int:
	return int(round(spacing / map.CELL))


# The candidate that fits its slot: each is tried at its own slot (or
# at `fixed`, a first piece's base); a carpet's piece fits wherever the
# slot has a surface, a scatter's where its feet find level ground,
# and failing that the one with the most level ground, set down on its
# lowest foot. Empty when no slot has a surface.
func _fit(cands: Array, fixed: Variant) -> Dictionary:
	var best := {}
	var best_spread := 1 << 20
	for c in cands:
		var w := _width(c.name)
		var base: Variant = fixed if fixed != null else _surface(_slot(w))
		if base == null:
			continue
		if _carpet:
			return {"name": c.name, "flags": c.flags, "base": base}
		var feet := _feet(c.name, c.flags, base)
		if feet[0] <= LEVEL:
			return {"name": c.name, "flags": c.flags, "base": base + _up * feet[1]}
		if feet[0] < best_spread:
			best_spread = feet[0]
			best = {"name": c.name, "flags": c.flags, "base": base + _up * feet[1]}
	return best


# How level the ground under a stamp's feet is at a base: the spread
# of their surfaces in cells, and the lowest foot's offset along up. A
# foot with no surface within REACH makes the spread huge.
func _feet(name: String, flags: String, base: Vector2i) -> Array:
	var png: Dictionary = SceneBuilder.png_stamps().get(name, {})
	var feet: PackedInt32Array = png.get("feet", PackedInt32Array())
	if feet.is_empty():
		return [0, 0]
	var w: int = png.w
	var lo := 1 << 20
	var hi := -(1 << 20)
	for px in feet:
		var a: int = (w - 1 - px if flags.contains("h") else px) - w / 2
		var s: Variant = SceneBuilder.surface_cell(map, base, _along, _up, a, REACH)
		if s == null:
			return [1 << 19, 0]
		var off: Vector2i = s - base - _along * a
		var k := off.x * _up.x + off.y * _up.y
		lo = mini(lo, k)
		hi = maxi(hi, k)
	return [hi - lo, lo]


# Lays a pick with its base cell on the surface: false when a stamp
# placed before is in the way.
func _lay(pick: Dictionary, base: Vector2i) -> bool:
	var at := _point(base)
	var rect: Rect2 = SceneBuilder.stamp_rect(map, pick.name, at, _where)
	if taken.call(rect):
		return false
	place.call(pick.name, at, _where, pick.flags)
	var s: Variant = SceneBuilder.surface_cell(map, base, _along, _up, 0, REACH)
	_base = s if s != null else base
	var cell: float = map.CELL
	if _along.x != 0:
		_lo = int(floor(rect.position.x / cell))
		_hi = int(floor(rect.end.x / cell)) - 1
	else:
		_lo = int(floor(rect.position.y / cell))
		_hi = int(floor(rect.end.y / cell)) - 1
	if _count == 0:
		runs.append([])
	_count += 1
	_last = pick.name
	runs[-1].append([pick.name, pick.flags])
	return true


# The candidates for a role, in random order: "l", "m" or "r" of a
# carpet, "" a whole take or a part. The pinned variant alone when
# there is one; else the group's with the role, an end of the other
# side mirrored counting too, the last one laid left out when there is
# a choice. Each is {name, flags}.
func _cands(role: String) -> Array:
	var flags := "d" if _carpet else ""
	if pin != "":
		return [{"name": pin, "flags": flags + ("h" if mirror and rng.randf() < 0.5 else "")}]
	var cands: Array = []
	for n in _names:
		var r := SceneBuilder.stamp_role(n)
		if role == "":
			if r == "" or r == "p":
				cands.append([n, mirror and rng.randf() < 0.5])
		elif role == "m":
			if r == "m":
				cands.append([n, mirror and rng.randf() < 0.5])
		elif r == role:
			cands.append([n, false])
		elif mirror and ((role == "l" and r == "r") or (role == "r" and r == "l")):
			cands.append([n, true])
	if cands.is_empty():
		for n in _names:
			cands.append([n, false])
	if cands.size() > 1:
		cands = cands.filter(func(c: Array) -> bool: return c[0] != _last)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Array = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	var out: Array = []
	for c in cands:
		out.append({"name": c[0], "flags": flags + ("h" if c[1] else "")})
	return out


func _width(name: String) -> int:
	return SceneBuilder.stamp_size(map, name).x


func _along_of(p: Vector2) -> int:
	var cell: float = map.CELL
	return int(floor(p.x / cell)) if _along.x != 0 else int(floor(p.y / cell))


func _along_cell(c: Vector2i) -> int:
	return c.x if _along.x != 0 else c.y


# The world point a stamp is placed at for a base cell: the cell's own
# centre, which the surface search (SceneBuilder.frame) takes as the
# base since it is solid, even when the stamp is set down below the
# surface under its middle.
func _point(base: Vector2i) -> Vector2:
	var cell: float = map.CELL
	return Vector2((base.x + 0.5) * cell, (base.y + 0.5) * cell)
