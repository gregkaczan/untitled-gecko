# A shroom that bends: a decor mushroom sprite (setup) made a skinned
# chunk (sim.gd) on a chain of seven bones, six up the stem and the
# cap. The chain is a spring the CPU runs: each joint bends back to its
# rest (the stem as the sprite draws it), and the stem squashes along
# its length under a load and springs back. The particles follow the
# bones (pbd_predict.glsl), so the shroom is cells like any rock to the
# gecko, who stands on the cap, climbs the stem, bites the cap away or
# chews the stem through, and then what stood above the bite breaks
# into lumps, each link of the stem and the cap in pieces, that fall
# apart and are shoved one by one (critters.gd reads the bones' counts).
#
# A gecko landing on the cap squashes the stem; standing, it sits a
# little lower under the weight; a jump off the cap adds the stored
# squash and the cap's rise to the jump along the cap's up (boost), so a
# jump timed at the bottom of the dip goes highest. A load off the
# stem's line bends it. The shroom is heavy against the gecko (mass,
# more the bigger it is) and its springs are slow and damped about
# critically: it leans over a second or two and comes back without
# ringing, so the cap stays a floor the gecko can walk on.
extends RefCounted

const SceneBuilder = preload("res://tests/scene_builder.gd")

const SEGS := 6                # Stem bones: short, so a bite across the stem takes a bone's particles whole
const BEND_K := 9.0            # Joint stiffness (1/s^2): about 3 rad/s, a lean takes a second or so
const BEND_C := 6.0            # Joint damping (1/s): critical, a lean comes back without swinging past
const BEND_MAX := 0.3          # Most a joint bends (rad)
const SQUASH_K := 49.0         # Squash stiffness (1/s^2), about 1.1 Hz
const SQUASH_C := 11.0         # Squash damping (1/s): 0.8 of critical, a landing sinks and comes up once, barely past
const SQUASH_MAX := 0.4        # Most the stem squashes, of its height
const WEIGHT := 147.0          # The gecko's weight on the cap (px/s^2 of squash at mass 1): about 3 px of dip standing on a size 3
const LAND_K := 0.25           # Of a landing's speed that goes into the squash, at mass 1: a landing sinks the cap about 2 px past its standing dip
const BEND_LOAD := 0.00014     # Bend (rad/s^2) per px of the weight's lever off a joint, per px/s^2 of weight, at mass 1
const LAND_BEND := 0.01        # Bend speed (rad/s) per px of a landing off the stem's line, per 100 px/s, at mass 1
const MASS_K := 1.0 / 6.0      # Mass per size, over a base of 0.5: a size 3 weighs 1, a size 9 2 (the gecko's push on it divided by it)
const BOOST_K := 1.6           # Of the squash's spring speed (squash * sqrt(SQUASH_K)) a jump gets
const BOOST_MAX := 340.0       # Most a jump gains (one more jump's speed)
const GAP_STEP := 1.5          # px between the rows across the stem read for a gap (check_counts)
const CAP_GONE := 0.15         # A cap with fewer than this is eaten
const CAP_PIECES := 3          # A stem bitten through: each link above the bite a lump of its own, the cap cut across into this many
const SPRITE := "tall_b_0"      # The decor take (decor/stamps) every shroom is drawn from: a broad cap on a long bent stem
const MAX_SIZE := 10           # The editor's stamps go to 5; a scene may ask for more (critters_lab's big one)

var sim: Node2D
var map: Node2D
var base := Vector2.ZERO       # The root, on the floor
var up := Vector2.UP           # The stem's rest direction
var height := 30.0
var seg := 10.0
var cap_w := 14.0
var bone0 := -1
var chunk := 0
var cut := false               # The stem was bitten through: what stood above it fell
var cap_gone := false
var theta := PackedFloat32Array()   # Bend at each joint, the root first, the cap's last
var omega := PackedFloat32Array()
var squash := 0.0              # px the stem is shorter than at rest
var squash_v := 0.0            # px/s, positive squashing
var counts0 := PackedInt32Array()
var half_w := 3.0              # The stem's half width
var mass := 1.0
var _stem_n := -1              # The stem's living particles at the last check
var weight_at := Vector2.INF   # A weight on it other than the gecko's (a test's), where it bears
var _joints := PackedVector2Array()
var _rest_d := PackedFloat32Array()   # Each joint's bend at rest (the sprite's stem as drawn), the root's from up, the cap's back to up
var _angles := PackedFloat32Array()


# Lays the shroom out on the air above base (the floor's surface point)
# from the decor sprite SPRITE: size 1 to 5 at its own scale, 6 to 10
# at twice it; an odd variant mirrors it. Its pixels are the cells, in
# their own colours, glowing where the decor's do; the stem's
# centreline, read row by row up to the cap, is the chain's rest pose
# (the bent stem rests bent). False when it does not fit (no free
# slots, no air, no sprite).
func setup(sim_in: Node2D, map_in: Node2D, base_in: Vector2, size: int, variant: int, _seed_v: int) -> bool:
	sim = sim_in
	map = map_in
	size = clampi(size, 1, MAX_SIZE)
	mass = 0.5 + size * MASS_K
	var pick := sprite_for(size, variant)
	var sc: int = pick[1]
	var stamp: Dictionary = SceneBuilder.png_stamps().get(pick[0], {})
	if stamp.is_empty():
		return false
	var mirror: bool = pick[2]
	var w: int = stamp.w
	var h: int = stamp.h
	var art := {}                  # Vector2i art pixel -> decor kind (its skin band)
	var widths := PackedInt32Array()
	widths.resize(h)
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(h)
	hi.resize(h)
	lo.fill(w)
	hi.fill(-1)
	var cs: PackedInt32Array = stamp.cells
	for k in range(0, cs.size(), 3):
		var x: int = (w - 1 - cs[k]) if mirror else cs[k]
		var y: int = cs[k + 1]
		art[Vector2i(x, y)] = cs[k + 2]
		lo[y] = mini(lo[y], x)
		hi[y] = maxi(hi[y], x)
	var widest := 0
	for y in h:
		widths[y] = hi[y] - lo[y] + 1 if hi[y] >= 0 else 0
		widest = maxi(widest, widths[y])
	# The cap: from the lowest row as wide as most of the widest up.
	var cap_y := 0
	for y in range(h - 1, -1, -1):
		if widths[y] >= int(ceil(widest * 0.55)):
			cap_y = y
			break
	if cap_y >= h - 2:
		return false
	# The stem's centre on each row under the cap, smoothed over three.
	var ps: float = sim.PIXEL_SZ
	var cell := ps * sc
	var raw := PackedFloat32Array()
	raw.resize(h)
	for y in range(cap_y + 1, h):
		raw[y] = (lo[y] + hi[y]) * 0.5 if hi[y] >= 0 else raw[y - 1]
	var mid := PackedFloat32Array()
	mid.resize(h)
	var stem_w := 1
	for y in range(cap_y + 1, h):
		var n := 0
		var sum := 0.0
		for d in [-1, 0, 1]:
			if y + d > cap_y and y + d < h:
				sum += raw[y + d]
				n += 1
		mid[y] = sum / n
		stem_w = maxi(stem_w, widths[y])
	# Where the sprite sits: the stem's foot on base, on the cell grid.
	var bottom := (floorf(base_in.y / ps) + 1.0) * ps
	var ox := snappedf(base_in.x - (mid[h - 1] + 0.5) * cell, ps)
	var oy := bottom - h * cell
	var line := PackedVector2Array([Vector2(ox + (mid[h - 1] + 0.5) * cell, bottom)])
	for y in range(h - 1, cap_y, -1):
		line.append(Vector2(ox + (mid[y] + 0.5) * cell, oy + (y + 0.5) * cell))
	line.append(Vector2(ox + (mid[cap_y + 1] + 0.5) * cell, oy + (cap_y + 1) * cell))
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	base = line[0]
	height = total
	seg = height / SEGS
	half_w = stem_w * cell * 0.5
	cap_w = widest * cell * 0.5
	# The chain's rest pose: the line cut into SEGS equal links.
	var rest := PackedVector2Array()
	for i in SEGS + 1:
		rest.append(_along(line, seg * i))
	_rest_d.resize(SEGS + 1)
	var prev_a := up.angle()
	for i in SEGS:
		var ang := (rest[i + 1] - rest[i]).angle()
		_rest_d[i] = wrapf(ang - prev_a, -PI, PI)
		prev_a = ang
	_rest_d[SEGS] = wrapf(up.angle() - prev_a, -PI, PI)
	theta.resize(SEGS + 1)
	theta.fill(0.0)
	omega.resize(SEGS + 1)
	omega.fill(0.0)
	bone0 = sim.alloc_bones(SEGS + 1)
	if bone0 < 0:
		return false
	var cells: Array = []
	var skin := {}
	var fracs := {}
	counts0.resize(SEGS + 1)
	counts0.fill(0)
	for px in art:
		var band: int = art[px]
		for j in sc:
			for i in sc:
				var c := Vector2i(int(round((ox + (px.x * sc + i) * ps) / ps)), int(round((oy + (px.y * sc + j) * ps) / ps)))
				if c.x < 0 or c.y < 0 or c.x >= sim.RENDER_W or c.y >= sim.RENDER_H or skin.has(c):
					continue
				if sim.cells.size() >= sim.RENDER_W * sim.RENDER_H * 4 and sim.cells.decode_u32((c.y * sim.RENDER_W + c.x) * 4) != 0:
					continue
				var bone := SEGS
				var wt := 0.0
				if px.y > cap_y:
					var t := _arc_of(rest, Vector2((c.x + 0.5) * ps, (c.y + 0.5) * ps)) / seg
					var k := clampi(int(floor(t)), 0, SEGS - 1)
					var f := t - k
					if f < 0.5 and k > 0:
						bone = k - 1
						wt = 0.5 + f
					else:
						bone = k
						wt = maxf(f - 0.5, 0.0)
				cells.append(c)
				skin[c] = [bone0 + bone, wt]
				fracs[c] = sim.FRAC_SKIN + (band + 0.5) * sim.SKIN_BAND
				counts0[bone] += 1
	if cells.is_empty():
		return false
	_pose()
	for i in SEGS + 1:
		sim.set_bone_rest(bone0 + i, _joints[i], _angles[i])
		sim.set_bone(bone0 + i, _joints[i], _angles[i], _stretch(i))
		sim.set_bone_drive(bone0 + i, true)
	chunk = sim.spawn_chunk(cells, sim.MAT_STONE, {}, -1.0, skin, fracs)
	if chunk == 0:
		return false
	map.anchored[chunk] = true
	return true


# The sprite a shroom of this size and variant is drawn from: [stamp
# name, scale, mirrored] (setup; main.gd's ghost reads its size).
static func sprite_for(size: int, variant: int) -> Array:
	return [SPRITE, 1 + (clampi(size, 1, MAX_SIZE) - 1) / 5, posmod(variant, 2) == 1]


# The point dist along a polyline (its end past it).
static func _along(line: PackedVector2Array, dist: float) -> Vector2:
	for i in line.size() - 1:
		var l := line[i].distance_to(line[i + 1])
		if dist <= l and l > 0.0:
			return line[i].lerp(line[i + 1], dist / l)
		dist -= l
	return line[line.size() - 1]


# How far along the polyline its nearest point to p lies.
static func _arc_of(line: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var at := 0.0
	var acc := 0.0
	for i in line.size() - 1:
		var ab := line[i + 1] - line[i]
		var l2 := ab.length_squared()
		var t := clampf((p - line[i]).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var d := p.distance_squared_to(line[i] + ab * t)
		if d < best:
			best = d
			at = acc + sqrt(l2) * t
		acc += sqrt(l2)
	return at


func _stretch(i: int) -> float:
	return 1.0 - squash / height if i < SEGS else 1.0


# The joints and the bones' angles from the bend and the squash.
func _pose() -> void:
	_joints.resize(SEGS + 1)
	_angles.resize(SEGS + 1)
	var a := up.angle()
	var p := base
	var s := seg * (1.0 - squash / height)
	for i in SEGS:
		a += _rest_d[i] + theta[i]
		_joints[i] = p
		_angles[i] = a
		p += Vector2.from_angle(a) * s
	_joints[SEGS] = p
	_angles[SEGS] = a + _rest_d[SEGS] + theta[SEGS]


# A point up the posed stem, t of the way from the root to the cap.
func stem_point(t: float) -> Vector2:
	var a := clampf(t, 0.0, 1.0) * SEGS
	var k := mini(int(floor(a)), SEGS - 1)
	return _joints[k].lerp(_joints[k + 1], a - k)


# The cap's frame now: its joint, along its up.
func cap_xf() -> Transform2D:
	return Transform2D(_angles[SEGS], _joints[SEGS])


func cap_up() -> Vector2:
	return Vector2.from_angle(_angles[SEGS])


# One tick: the weight at load_at (Vector2.INF for none), a landing's
# speed (0 for none), and the bones set for the sim.
func step(dt: float, load_at: Vector2, land_speed: float) -> void:
	if cut:
		return
	if load_at == Vector2.INF:
		load_at = weight_at
	if load_at == Vector2.INF and land_speed == 0.0 and _at_rest():
		return
	var old_t := theta.duplicate()
	var old_s := squash
	if land_speed > 0.0:
		squash_v += land_speed * LAND_K / mass
		if load_at != Vector2.INF:
			var off := (load_at - base).dot(Vector2(-up.y, up.x))
			for i in SEGS + 1:
				omega[i] += off * LAND_BEND * land_speed * 0.01 / (i + 1) / mass
	var f := 0.0
	if load_at != Vector2.INF and not cap_gone:
		f = WEIGHT / mass * maxf(Vector2.DOWN.dot(-cap_up()), 0.0)
	squash_v += (-SQUASH_K * squash - SQUASH_C * squash_v + f) * dt
	squash = clampf(squash + squash_v * dt, -0.12 * height, SQUASH_MAX * height)
	if squash >= SQUASH_MAX * height and squash_v > 0.0:
		squash_v = 0.0
	for i in SEGS + 1:
		var tq := 0.0
		if load_at != Vector2.INF and i < _joints.size():
			var r := load_at - _joints[i]
			tq = r.x * WEIGHT * BEND_LOAD / mass
		omega[i] += (-BEND_K * theta[i] - BEND_C * omega[i] + tq) * dt
		theta[i] = clampf(theta[i] + omega[i] * dt, -BEND_MAX, BEND_MAX)
	_pose()
	# Rock: a rim of the cap or the stem's top pressed into it, the
	# bend and the squash go back to last tick's and stop.
	if _in_rock():
		theta = old_t
		squash = old_s
		omega.fill(0.0)
		squash_v = 0.0
		_pose()
	_upload()


# Straight, unsquashed and still: nothing to do until a load comes.
func _at_rest() -> bool:
	if absf(squash) > 0.01 or absf(squash_v) > 0.05:
		return false
	for i in theta.size():
		if absf(theta[i]) > 0.0005 or absf(omega[i]) > 0.005:
			return false
	return true


func _in_rock() -> bool:
	var xf := cap_xf()
	for q in [Vector2(2.0, cap_w), Vector2(2.0, -cap_w), Vector2(cap_w * 0.5, cap_w * 0.7), Vector2(cap_w * 0.5, -cap_w * 0.7), Vector2(cap_w * 0.8, 0.0)]:
		if map.rock_world(xf * q):
			return true
	return false


# How far up the stem the first row across it with none of its cells
# is, or -1: read at the stem's posed line, from a little over the root
# to the cap.
func _gap() -> float:
	var a := 2.0
	var s := 1.0 - squash / height
	while a < height - 1.0:
		var k := clampi(int(floor(a / seg)), 0, SEGS - 1)
		var along := Vector2.from_angle(_angles[k])
		var at := _joints[k] + along * (a - k * seg) * s
		var across := Vector2(-along.y, along.x)
		var hit := false
		var b := -half_w - 1.0
		while b <= half_w + 1.0 and not hit:
			hit = map.anchored_at_world(at + across * b) == chunk
			b += 1.0
		if not hit:
			return a
		a += GAP_STEP
	return -1.0


func _upload() -> void:
	for i in SEGS + 1:
		sim.set_bone(bone0 + i, _joints[i], _angles[i], _stretch(i))


# The speed a jump off the cap gains along the cap's up: the squash's
# stored spring and the cap's own rise.
func boost() -> Vector2:
	if cut or cap_gone:
		return Vector2.ZERO
	var spd := BOOST_K * maxf(squash, 0.0) * sqrt(SQUASH_K) + maxf(-squash_v, 0.0)
	return cap_up() * minf(spd, BOOST_MAX)


# Where the bone nearest p carried p this tick: for the gecko riding it.
func bone_frames() -> Array:
	var out: Array = []
	for i in SEGS + 1:
		out.append(Transform2D(_angles[i], _joints[i]))
	return out


# After the sim's tick: when the stem lost particles (a bite, a strike),
# its cells are read row by row across it, up its posed line, and the
# first row with none of its cells is a cut: the bones from there up
# let go, each link and each piece of the cap a lump of its own
# (sim.gd release_bones split). A cap bitten away
# leaves a stem.
func check_counts() -> void:
	if cut or bone0 < 0:
		return
	var n := 0
	for i in SEGS:
		var k: int = sim.bone_count(bone0 + i)
		if k < 0:
			return
		n += k
	if _stem_n >= 0 and n < _stem_n:
		var gap := _gap()
		if gap >= 0.0:
			var k := clampi(int(floor(gap / (height / SEGS))), 0, SEGS - 1)
			sim.release_bones(bone0 + k, bone0 + SEGS + 1, CAP_PIECES, cap_w * 2.0 / CAP_PIECES)
			cut = true
			return
	_stem_n = n
	var nc: int = sim.bone_count(bone0 + SEGS)
	if nc >= 0 and counts0[SEGS] > 0 and nc < int(counts0[SEGS] * CAP_GONE):
		cap_gone = true
