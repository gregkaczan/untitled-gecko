# A vine that is a rope: a chain of points the CPU runs (verlet, its
# top pinned under the ceiling), each link a bone of a skinned chunk
# (sim.gd), so the vine is cells to the gecko, who climbs it as before.
# It hangs and swings: the gecko's weight hangs on the point it holds,
# a catch in flight swings the rope away with the gecko (critters.gd
# CATCH_K), its jump off kicks the rope back, and a link knocks against
# rock. A
# link bitten through lets go of the rope below it, which falls as a
# lump of its own (critters.gd reads the links' counts); with main.gd's
# VINE_TEAR on, a hang longer than VINE_HOLD tears the whole vine from
# the ceiling.
extends RefCounted

const SEG := 4.0               # Link length (px)
const ITERS := 4               # Constraint passes a tick (the anchor's reach does the rest)
const DAMP := 0.995            # Of a point's speed kept each tick
const DAMP_HELD := 0.985       # The same while the gecko hangs on it: a swing under the gecko dies out in a couple of seconds
const GRAVITY := 900.0
const LOAD_MASS := 40.0        # The gecko's mass, in points: heavier than most of a vine, so its weight leans the rope until the body hangs under the anchor
const LOAD_SPAN := 3.0         # Points either side of the held place the gecko's mass is shared over (its body's length on the rope): a move along the rope does not hand the mass to a point at rest
const LEAN_K := 0.5            # Of the weight's lever off the rope's line that leans it: a full lean puts the body under the anchor, a slant the gecko climbs as a staircase of cells
const LEAF_EVERY := 10.0       # px between leaves, alternating sides
const REST_TICKS := 30
const REST_MOVE := 0.01        # px a tick under which a point is still (the constraints never quite settle a hanging rope)

var sim: Node2D
var map: Node2D
var top := Vector2.ZERO
var pts := PackedVector2Array()
var prev := PackedVector2Array()
var bone0 := -1
var chunk := 0
var counts0 := PackedInt32Array()
var hang := 0.0                # Seconds the gecko has hung on it (main.gd's snap)
var gone := false              # Torn down or cut to nothing: no longer driven
var _share := PackedFloat32Array()   # Of the gecko's mass each point carries this tick
var _still := 0                # Ticks in a row nothing moved: past REST_TICKS the rope sleeps (no work) until held or kicked
var _total := -1               # Its living particles at the last check


# A vine hanging from top (the first air under a ceiling), length px
# long or until it meets something. False when it does not fit.
func setup(sim_in: Node2D, map_in: Node2D, top_in: Vector2, length: float, seed_v: int) -> bool:
	sim = sim_in
	map = map_in
	top = top_in
	var ps: float = sim.PIXEL_SZ
	var cx := int(floor(top.x / ps))
	var cy := int(floor(top.y / ps))
	var rows := maxi(int(length / ps), 2)
	var col: Array = []
	for k in rows:
		var y := cy + k
		if y >= sim.RENDER_H or _taken(cx, y):
			break
		col.append(Vector2i(cx, y))
	if col.size() < 4:
		return false
	var n := int(floor((col.size() * ps) / SEG)) + 1
	n = maxi(n, 2)
	bone0 = sim.alloc_bones(n - 1)
	if bone0 < 0:
		return false
	pts.resize(n)
	prev.resize(n)
	for i in n:
		pts[i] = top + Vector2(0.0, SEG * i)
		prev[i] = pts[i]
	counts0.resize(n - 1)
	counts0.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cells: Array = []
	var skin := {}
	var fracs := {}
	var side := 1 if rng.randf() < 0.5 else -1
	var next_leaf := LEAF_EVERY * rng.randf_range(0.5, 1.0)
	for c in col:
		var a: float = (c.y + 0.5) * ps - top.y
		var bw := _bone_of(a, n - 1)
		cells.append(c)
		skin[c] = [bone0 + bw[0], bw[1]]
		fracs[c] = sim.FRAC_SKIN + ((5 if c.y % 3 else 6) + 0.5) * sim.SKIN_BAND
		counts0[bw[0]] += 1
		if a >= next_leaf and a < col.size() * ps - 4.0:
			next_leaf += LEAF_EVERY * rng.randf_range(0.8, 1.2)
			# A leaf: two cells out to one side, the outer one up a row.
			for leaf in [Vector2i(c.x + side, c.y), Vector2i(c.x + side * 2, c.y - 1)]:
				if leaf.x < 0 or leaf.x >= sim.RENDER_W or _taken(leaf.x, leaf.y) or skin.has(leaf):
					continue
				cells.append(leaf)
				skin[leaf] = [bone0 + bw[0], bw[1]]
				fracs[leaf] = sim.FRAC_SKIN + ((4 if rng.randf() < 0.85 else 11) + 0.5) * sim.SKIN_BAND
				counts0[bw[0]] += 1
			side = -side
	for i in n - 1:
		sim.set_bone_rest(bone0 + i, pts[i], PI * 0.5)
		sim.set_bone(bone0 + i, pts[i], PI * 0.5)
		sim.set_bone_drive(bone0 + i, true)
	chunk = sim.spawn_chunk(cells, sim.MAT_STONE, {}, -1.0, skin, fracs)
	if chunk == 0:
		return false
	map.anchored[chunk] = true
	return true


func _taken(x: int, y: int) -> bool:
	return sim.cells.size() >= sim.RENDER_W * sim.RENDER_H * 4 and sim.cells.decode_u32((y * sim.RENDER_W + x) * 4) != 0


# The link a point a px down the vine belongs to, and its weight toward
# the next (a blend over the joints, as the shroom's stem).
static func _bone_of(a: float, links: int) -> Array:
	var t := a / SEG
	var k := clampi(int(floor(t)), 0, links - 1)
	var f := clampf(t - k, 0.0, 1.0)
	if f < 0.5 and k > 0:
		return [k - 1, 0.5 + f]
	if k >= links - 1:
		return [k, 0.0]
	return [k, maxf(f - 0.5, 0.0)]


# The point nearest p and where along the rope (index plus fraction).
func nearest(p: Vector2) -> float:
	var best := INF
	var at := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			at = i + t
	return at


func point_at(at: float) -> Vector2:
	var i := clampi(int(floor(at)), 0, pts.size() - 2)
	return pts[i].lerp(pts[i + 1], at - i)


# One tick of the rope. held: where along it the gecko holds on (-1 for
# nowhere), load: where the gecko's body is (it clings beside the rope,
# so its weight hangs off the rope's line and swings the rope until the
# body is under the anchor), kick: a change of the held place's speed
# this tick (px/s: the gecko's catch, its jump off). Returns how far the held place moved, for the
# gecko to ride.
func step(dt: float, held: float, kick: Vector2, load := Vector2.INF) -> Vector2:
	if gone or pts.size() < 2:
		return Vector2.ZERO
	if held < 0.0 and kick == Vector2.ZERO and _still > REST_TICKS:
		return Vector2.ZERO
	var before := point_at(held) if held >= 0.0 else Vector2.ZERO
	var n := pts.size()
	_share_out(held, n)
	var g := Vector2(0.0, GRAVITY * dt * dt)
	var damp := DAMP_HELD if held >= 0.0 else DAMP
	for i in range(1, n):
		var v := (pts[i] - prev[i]) * damp
		prev[i] = pts[i]
		var acc := g
		var m := _share[i] * LOAD_MASS
		if m > 0.0:
			v += kick * dt
			if load != Vector2.INF:
				# The body hangs off the rope's line: its weight's lever
				# about this point leans the rope until the body is
				# under the anchor (the point's own gravity, the rope's
				# geometry, pulls back).
				var depth := maxf(pts[i].y - top.y, 8.0)
				acc.x -= GRAVITY * LEAN_K * m / (1.0 + m) * (load.x - pts[i].x) / depth * dt * dt
		pts[i] += v + acc
	for _it in ITERS:
		for i in n - 1:
			var wa := 0.0 if i == 0 else 1.0 / (1.0 + _share[i] * LOAD_MASS)
			var wb := 1.0 / (1.0 + _share[i + 1] * LOAD_MASS)
			var d := pts[i + 1] - pts[i]
			var l := d.length()
			if l < 0.0001 or wa + wb <= 0.0:
				continue
			var corr := d * ((l - SEG) / l / (wa + wb))
			pts[i] += corr * wa
			pts[i + 1] -= corr * wb
		pts[0] = top
	# A long rope's links never quite settle under the passes above (a
	# stretch runs up and down it): no point may be further from the
	# anchor than the rope between them (long range attachment), which
	# holds the rope's length whatever its length.
	for i in range(1, n):
		var d := pts[i] - top
		var reach := SEG * i
		if d.length_squared() > reach * reach:
			pts[i] = top + d.normalized() * reach
	var most := 0.0
	for i in range(1, n):
		if map.rock_world(pts[i]):
			pts[i] = prev[i]
		most = maxf(most, pts[i].distance_squared_to(prev[i]))
	_still = _still + 1 if most < REST_MOVE * REST_MOVE else 0
	for i in n - 1:
		var d := pts[i + 1] - pts[i]
		sim.set_bone(bone0 + i, pts[i], d.angle(), d.length() / SEG)
	if held < 0.0:
		return Vector2.ZERO
	return point_at(held) - before


# The gecko's mass over the points round the held place (index plus
# fraction, -1 for none), most at the place, none LOAD_SPAN + 1 away.
func _share_out(held: float, n: int) -> void:
	_share.resize(n)
	_share.fill(0.0)
	if held < 0.0:
		return
	var tot := 0.0
	for k in range(maxi(1, int(floor(held - LOAD_SPAN))), mini(n - 1, int(ceil(held + LOAD_SPAN))) + 1):
		var w := maxf(LOAD_SPAN + 1.0 - absf(k - held), 0.0)
		_share[k] = w
		tot += w
	if tot > 0.0:
		for k in n:
			_share[k] /= tot


# After the sim's tick: when the vine lost particles (a bite, a strike),
# its cells are read along its line, and the first place with none of
# them is a cut (the leaves beside the line do not hold it together):
# the rope below lets go, a lump of its own.
func check_counts() -> void:
	if gone or bone0 < 0:
		return
	var counts: PackedInt32Array = sim.bone_counts_i
	if counts.size() < bone0 + pts.size() - 1:
		return
	var total := 0
	for i in pts.size() - 1:
		total += counts[bone0 + i]
	if _total >= 0 and total < _total:
		var k := _gap()
		if k >= 0:
			sim.release_bones(bone0 + k, bone0 + pts.size() - 1)
			pts.resize(k + 1)
			prev.resize(k + 1)
			if pts.size() < 2:
				gone = true
			_total = -1
			return
	_total = total


# The first link along whose line no cell of the vine lies, or -1.
func _gap() -> int:
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var across := Vector2(-ab.y, ab.x).normalized()
		var t := 0.0
		while t < 1.0:
			var at := a + ab * t
			if map.anchored_at_world(at) != chunk and map.anchored_at_world(at + across) != chunk and map.anchored_at_world(at - across) != chunk:
				return i
			t += 0.375
	return -1


# A push on point k (px a tick): the rope wakes and swings.
func push(k: int, d: Vector2) -> void:
	if k > 0 and k < pts.size():
		prev[k] -= d
		_still = 0


# Torn from the ceiling: the whole vine falls as a lump.
func tear() -> void:
	if gone:
		return
	sim.release_bones(bone0, bone0 + pts.size() - 1)
	map.anchored.erase(chunk)
	gone = true
