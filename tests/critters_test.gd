# The chain critters' regression test, in the particle world (it needs
# the GPU: tools/critters_test.sh runs it on a virtual display). One
# case a run, CRIT_CASE naming it, on the critters_lab scene
# (tools/gen_scenes.py): the probe takes the keys from the scene's
# script, places the gecko, drives it, and checks numbers off the
# critters (critters.gd), the sim's bone counts and the cells the gecko
# reads. Prints a CRIT line a check and CRIT TEST OK or CRIT TEST FAILS.
#
# Cases: shroom_rest, shroom_land, shroom_boost, shroom_chew,
# shroom_cut, shroom_rock, decor, vine_swing, vine_cut, vine_climb, vine_catch,
# slime_creep, slime_bite, slime_wade, longslug, perf. Not tests, only
# when named: shots (frames of each critter) and slime_look (the sim's
# own render round each slime, a pixel a cell, to judge its texture,
# with a slime of the editor's largest size and a bigger one beside the
# lab's own).
#
#   (main.gd runs it as GECKO_PROBE=res://tests/critters_test.gd)
extends Node

const RIDE_H := 16.0

var main: Node2D
var _fails := 0
var _case := OS.get_environment("CRIT_CASE")


func _ready() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	print("CRIT %s %s: %s" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1


func _run() -> void:
	await _ticks(5)
	main._demo_step = -1
	var g: Node2D = main.gecko
	g.input_override = Vector2.ZERO
	var c: Node2D = main.critters
	if c.shrooms.size() < 3 or c.vines.size() < 1 or c.slimes.size() < 1 or c.long_slugs.size() < 1:
		_check("lab", false, "critters spawned: %d shrooms, %d vines, %d slimes, %d long slugs" % [c.shrooms.size(), c.vines.size(), c.slimes.size(), c.long_slugs.size()])
		_finish()
		return
	# The gecko out of the way at the left, standing, unless a case moves it.
	await _ticks(30)
	match _case:
		"shroom_rest": await _shroom_rest()
		"shroom_land": await _shroom_land()
		"shroom_boost": await _shroom_boost()
		"shroom_chew": await _shroom_chew()
		"shroom_cut": await _shroom_cut()
		"shroom_rock": await _shroom_rock()
		"decor": await _decor()
		"vine_swing": await _vine_swing()
		"vine_cut": await _vine_cut()
		"vine_climb": await _vine_climb()
		"vine_catch": await _vine_catch()
		"slime_creep": await _slime_creep()
		"slime_bite": await _slime_bite()
		"slime_wade": await _slime_wade()
		"longslug": await _longslug()
		"perf": await _perf()
		"perf_base": await _perf()
		"shots": await _shots()
		"slime_look": await _slime_look()
		_:
			_check("case", false, "no case " + _case)
	_finish()


func _finish() -> void:
	print("CRIT TEST %s %d" % ["OK" if _fails == 0 else "FAILS", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# --- helpers ---

func _cls(p: Vector2) -> int:
	var sim: Node2D = main.sim
	var x := int(floor(p.x / sim.PIXEL_SZ))
	var y := int(floor(p.y / sim.PIXEL_SZ))
	if x < 0 or y < 0 or x >= sim.RENDER_W or y >= sim.RENDER_H:
		return -1
	return sim.cells.decode_u32((y * sim.RENDER_W + x) * 4) % 256


# The cells of chunk id in rect: [count, centroid].
func _chunk_cells(id: int, r: Rect2) -> Array:
	var sim: Node2D = main.sim
	var n := 0
	var sum := Vector2.ZERO
	var ps: float = sim.PIXEL_SZ
	for y in range(int(r.position.y / ps), int(r.end.y / ps)):
		for x in range(int(r.position.x / ps), int(r.end.x / ps)):
			if x < 0 or y < 0 or x >= sim.RENDER_W or y >= sim.RENDER_H:
				continue
			if sim.cells.decode_u32((y * sim.RENDER_W + x) * 4) % 256 == sim.CT_CHUNK + id:
				n += 1
				sum += Vector2((x + 0.5) * ps, (y + 0.5) * ps)
	return [n, sum / n if n > 0 else Vector2.ZERO]


func _cells_of_class(cls: int, r: Rect2) -> Array:
	var sim: Node2D = main.sim
	var n := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ps: float = sim.PIXEL_SZ
	for y in range(int(r.position.y / ps), int(r.end.y / ps)):
		for x in range(int(r.position.x / ps), int(r.end.x / ps)):
			if sim.cells.decode_u32((y * sim.RENDER_W + x) * 4) % 256 == cls:
				n += 1
				var q := Vector2((x + 0.5) * ps, (y + 0.5) * ps)
				lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
				hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return [n, Rect2(lo, hi - lo) if n > 0 else Rect2()]


# The lumps in rect other than skip: chunk id -> the mean y of its cells.
func _lumps_in(r: Rect2, skip: int) -> Dictionary:
	var sim: Node2D = main.sim
	var ps: float = sim.PIXEL_SZ
	var sums := {}
	for y in range(int(r.position.y / ps), int(r.end.y / ps)):
		for x in range(int(r.position.x / ps), int(r.end.x / ps)):
			if x < 0 or y < 0 or x >= sim.RENDER_W or y >= sim.RENDER_H:
				continue
			var c: int = sim.cells.decode_u32((y * sim.RENDER_W + x) * 4)
			if c >= sim.CT_CHUNK and c < sim.CT_CRUMB and c - sim.CT_CHUNK != skip:
				var id: int = c - sim.CT_CHUNK
				var v: Vector2 = sums.get(id, Vector2.ZERO)
				sums[id] = v + Vector2(1.0, (y + 0.5) * ps)
	var out := {}
	for id in sums:
		out[id] = sums[id].y / sums[id].x
	return out


func _bone_total(s: RefCounted, from: int, to: int) -> int:
	var n := 0
	for i in range(from, to):
		n += maxi(main.sim.bone_count(s.bone0 + i), 0)
	return n


# The gecko let go of in the air at p, falling from rest.
func _drop_at(p: Vector2) -> void:
	var g: Node2D = main.gecko
	g.spawn(p, Vector2.UP)
	g.clinging = false
	g.vel = Vector2.ZERO
	g._unplant()


func _stand_at(x: float) -> void:
	var g: Node2D = main.gecko
	var fl: Vector2 = main.map.floor_below(Vector2(x, 700.0))
	g.spawn(Vector2(x, fl.y - RIDE_H), Vector2.UP)


# Lands on shroom s from 70 px over its cap and waits until the gecko
# holds it. Returns the ticks it took, -1 for never.
func _land_on(s: RefCounted) -> int:
	var cap: Vector2 = s.cap_xf().origin
	_drop_at(cap + Vector2(0.0, -70.0))
	for t in 90:
		await _ticks(1)
		if main.critters.held == s:
			return t
	return -1


# The highest the body centre rises over its start within ticks.
func _rise(ticks: int) -> float:
	var g: Node2D = main.gecko
	var y0: float = g.pos.y
	var top := y0
	for t in ticks:
		await _ticks(1)
		top = minf(top, g.pos.y)
	return y0 - top


# --- shrooms ---

func _shroom_rest() -> void:
	var s: RefCounted = main.critters.shrooms[0]
	await _ticks(60)
	var total := _bone_total(s, 0, s.SEGS + 1)
	var want := 0
	for n in s.counts0:
		want += n
	_check("rest_count", total >= int(want * 0.97) and total <= want, "%d of %d particles alive and counted" % [total, want])
	var cap: Vector2 = s.cap_xf().origin
	var id: int = s.chunk
	var cells: Array = _chunk_cells(id, Rect2(cap - Vector2(20.0, 20.0), Vector2(40.0, 30.0)))
	_check("rest_cells", cells[0] > 60, "%d cap cells read as the shroom's chunk" % cells[0])
	_check("rest_anchored", main.map.anchored.has(id) and main.map.chunk_at_world(cap + Vector2(0.0, -4.0)) == -1,
			"the shroom is ground to the gecko, not a lump")
	_check("rest_still", absf(s.squash) < 0.2 and absf(s.theta[0]) < 0.01, "squash %.2f px, bend %.3f rad" % [s.squash, s.theta[0]])


func _shroom_land() -> void:
	var s: RefCounted = main.critters.shrooms[0]
	var g: Node2D = main.gecko
	var t := await _land_on(s)
	_check("land_held", t >= 0, "the gecko holds the cap %d ticks after the drop" % t)
	var deepest := 0.0
	var after := INF
	var gap_lo := INF
	var gap_hi := -INF
	for i in 120:
		await _ticks(1)
		deepest = maxf(deepest, s.squash)
		if i > 30:
			after = minf(after, s.squash)
		if i > 60:
			var gap: float = s.cap_xf().origin.y - g.pos.y
			gap_lo = minf(gap_lo, gap)
			gap_hi = maxf(gap_hi, gap)
	_check("land_dip", deepest > 4.0 and deepest <= s.SQUASH_MAX * s.height + 0.01, "the landing squashed the stem %.1f px" % deepest)
	_check("land_calm", after > 2.0, "no bounce: after the dip the cap rises no higher than %.1f px low" % after)
	await _ticks(120)
	_check("land_settle", s.squash > 1.0 and s.squash < 6.0 and absf(s.squash_v) < 3.0,
			"standing, the cap sits %.1f px low (moving %.1f px/s)" % [s.squash, s.squash_v])
	_check("land_ride", main.critters.held == s and gap_hi - gap_lo < 4.0,
			"the gecko rides the sinking cap: its height over the cap varies %.1f px" % (gap_hi - gap_lo))


func _shroom_boost() -> void:
	var s: RefCounted = main.critters.shrooms[0]
	var g: Node2D = main.gecko
	# A plain jump off the floor.
	_stand_at(180.0)
	await _ticks(40)
	g.jump_override = true
	var plain := await _rise(70)
	# A jump off the cap at rest.
	await _land_on(s)
	await _ticks(180)
	g.jump_override = true
	var rest := await _rise(80)
	# A jump at the bottom of the landing's dip.
	var t := await _land_on(s)
	var last := -INF
	var jumped := false
	for i in 40:
		await _ticks(1)
		if s.squash < last and last > 3.0:
			g.jump_override = true
			jumped = true
			break
		last = s.squash
	# The rise, and the cap coming back up behind the gecko as it goes.
	var y0: float = g.pos.y
	var top_y := y0
	var recoil := 0.0
	for i in 90:
		await _ticks(1)
		top_y = minf(top_y, g.pos.y)
		recoil = minf(recoil, s.squash)
	var timed := y0 - top_y if jumped else 0.0
	_check("boost_rest", rest > plain + 6.0, "a jump off the cap at rest rises %.0f px, off the floor %.0f" % [rest, plain])
	_check("boost_timed", jumped and timed > plain * 1.2 and timed > rest, "a jump at the bottom of the dip rises %.0f px (held after %d ticks)" % [timed, t])
	_check("boost_cap", timed < plain * 4.5, "the boost is capped: %.0f px against %.0f" % [timed, plain])
	_check("boost_calm", recoil > -1.0, "the heavy cap comes back up after the jump without flying past (squash %.1f px)" % recoil)


func _shroom_chew() -> void:
	var s: RefCounted = main.critters.shrooms[0]
	var cap0 := _bone_total(s, s.SEGS, s.SEGS + 1)
	var top: Vector2 = s.cap_xf() * Vector2(8.0, 0.0)
	for i in 3:
		main.map.erase_circle(top + Vector2(-6.0 + i * 6.0, 0.0), 5.0)
		await _ticks(3)
	await _ticks(10)
	var cap1 := _bone_total(s, s.SEGS, s.SEGS + 1)
	_check("chew_cap", cap1 < cap0 * 0.85 and cap1 > 0, "bites took the cap from %d to %d particles" % [cap0, cap1])
	_check("chew_stands", not s.cut and _bone_total(s, 0, s.SEGS) > 0, "the stem stands")


func _shroom_cut() -> void:
	var s: RefCounted = main.critters.shrooms[1]
	var cap0: Vector2 = s.cap_xf().origin
	var mid: Vector2 = s.stem_point(0.5)
	main.map.erase_circle(mid, 5.0)
	await _ticks(4)
	main.map.erase_circle(mid, 5.0)
	var t := 0
	while t < 30 and not s.cut:
		await _ticks(1)
		t += 1
	var counts := []
	for i in s.SEGS + 1:
		counts.append("%d/%d" % [main.sim.bone_count(s.bone0 + i), s.counts0[i]])
	print("CRIT note cut: bone counts after the bites " + ", ".join(counts))
	_check("cut_seen", s.cut, "the stem was read as bitten through after %d ticks" % t)
	# What stood above the bite broke into lumps of their own (each link
	# of the stem, the cap in pieces), none of them ground, no sand, and
	# they fell.
	await _ticks(3)
	var area := Rect2(cap0 - Vector2(70.0, 50.0), Vector2(140.0, 150.0))
	var before := _lumps_in(area, s.chunk)
	var sand: Array = _cells_of_class(main.sim.CT_LOOSE, area)
	_check("cut_lumps", before.size() >= 4 and sand[0] < 10, "it broke into %d lumps (%d loose grains)" % [before.size(), sand[0]])
	var ground := 0
	for id in before:
		ground += 1 if main.map.anchored.has(id) else 0
	_check("cut_free", ground == 0, "%d of the pieces are ground" % ground)
	await _ticks(90)
	var fell := 0
	for id in before:
		var a: Array = _chunk_cells(id, area)
		fell += 1 if a[0] > 0 and a[1].y > before[id] + 6.0 else 0
	_check("cut_falls", fell >= before.size() - 1, "%d of %d pieces fell" % [fell, before.size()])
	_check("cut_stump", _bone_total(s, 0, 1) > 0 and main.map.anchored.has(s.chunk), "the stump stays, ground")


func _shroom_rock() -> void:
	var s: RefCounted = main.critters.shrooms[2]
	var g: Node2D = main.gecko
	var cap: Vector2 = s.cap_xf().origin
	var want := _bone_total(s, 0, s.SEGS + 1)
	# A weight on the cap's rim toward the pillar, two seconds.
	s.weight_at = cap + Vector2(14.0, -4.0)
	var worst := 0
	var bent := 0.0
	var bends := []
	for i in 120:
		await _ticks(1)
		var sum := 0.0
		for k in s.SEGS:
			sum += s.theta[k]
		bent = maxf(bent, absf(sum))
		bends.append(absf(sum))
		var pillar := Rect2(1632.0, 642.0, 56.0, 156.0)
		var cells: Array = _chunk_cells(s.chunk, pillar)
		worst = maxi(worst, cells[0])
	s.weight_at = Vector2.INF
	var total := _bone_total(s, 0, s.SEGS + 1)
	_check("rock_bent", bent > 0.05, "the weight bent the stem toward the pillar (%.2f rad at most)" % bent)
	var half_t := 0
	while half_t < bends.size() and bends[half_t] < bent * 0.5:
		half_t += 1
	_check("rock_slow", half_t >= 12, "it leans slowly: half its lean after %d ticks" % half_t)
	_check("rock_whole", total >= int(want * 0.95), "%d of %d particles after the load against the pillar" % [total, want])
	_check("rock_clear", worst == 0, "no shroom cell inside the pillar (worst %d)" % worst)
	await _ticks(120)
	var back := 0.0
	for k in s.SEGS:
		back += s.theta[k]
	_check("rock_back", absf(back) < 0.02, "let go, it stands straight again (%.3f rad)" % back)


# The decor's mushrooms bend too: each stamped by the editor on the
# lab's floor is a shroom (a cluster three, one a mushroom), with no
# standing cell left of it; a level's are made on load.
func _decor() -> void:
	var c: Node2D = main.critters
	var want := {"cluster_0": 3, "cluster_2": 3, "tall_a_0": 1, "tall_b_1": 1, "shroom_s_0": 1, "cluster_1_p2": 1}
	var x := 760.0
	for nm in want:
		var before: int = c.shrooms.size()
		var r: Rect2 = main.edit_stamp(nm, Vector2(x, 780.0), 12.0, "floor", "", {})
		await _ticks(4)
		var made: int = c.shrooms.size() - before
		var standing: Array = _cells_of_class(main.sim.CT_SOLID, r.grow(-1.0))
		_check("decor_" + nm, made == want[nm] and standing[0] == 0, "%s: %d shrooms (want %d), %d standing cells" % [nm, made, want[nm], standing[0]])
		x += 60.0
	# One bends under a weight like any shroom.
	var s: RefCounted = c.shrooms[c.shrooms.size() - 3]
	s.weight_at = s.cap_xf().origin + Vector2(10.0, -2.0)
	var bent := 0.0
	for i in 90:
		await _ticks(1)
		var sum := 0.0
		for k in s.SEGS:
			sum += s.theta[k]
		bent = maxf(bent, absf(sum))
	s.weight_at = Vector2.INF
	_check("decor_bends", bent > 0.03, "a stamped tall shroom bent %.2f rad under a weight" % bent)
	print("CRIT note decor: " + main.load_level("cave5"))
	await _ticks(10)
	_check("decor_level", c.shrooms.size() >= 3 and main._decor_plans.size() == c.shrooms.size(), "cave 5's mushrooms: %d shrooms of %d plans" % [c.shrooms.size(), main._decor_plans.size()])


# --- the vine ---

func _vine_swing() -> void:
	var v: RefCounted = main.critters.vines[0]
	await _ticks(30)
	var n: int = v.pts.size()
	var straight := 0.0
	for p in v.pts:
		straight = maxf(straight, absf(p.x - v.top.x))
	_check("swing_hangs", straight < 1.0, "hanging straight: the widest point %.2f px off" % straight)
	# A push on its foot.
	v.push(n - 1, Vector2(4.0, 0.0))
	v.push(n - 2, Vector2(3.0, 0.0))
	var amp := 0.0
	var late := 0.0
	var track_err := 0.0
	for i in 420:
		await _ticks(1)
		var dx: float = v.pts[n - 1].x - v.top.x
		if i < 90:
			amp = maxf(amp, absf(dx))
		if i > 360:
			late = maxf(late, absf(dx))
		if i == 20 or i == 45:
			var foot: Vector2 = v.pts[n - 3]
			var cells: Array = _chunk_cells(v.chunk, Rect2(foot - Vector2(12.0, 3.0), Vector2(24.0, 6.0)))
			track_err = maxf(track_err, absf(cells[1].x - foot.x) if cells[0] > 0 else 99.0)
	_check("swing_moves", amp > 8.0, "the push swung its foot %.1f px out" % amp)
	_check("swing_cells", track_err < 3.5, "the cells follow the rope (worst %.1f px off)" % track_err)
	_check("swing_damps", late < amp * 0.6, "it settles: %.1f px out after 6 s" % late)


func _vine_cut() -> void:
	var v: RefCounted = main.critters.vines[0]
	var n0: int = v.pts.size()
	var mid: Vector2 = v.pts[n0 / 2]
	main.map.erase_circle(mid, 4.0)
	var t := 0
	while t < 30 and v.pts.size() == n0:
		await _ticks(1)
		t += 1
	var cs := []
	for i in range(n0 / 2 - 3, n0 / 2 + 3):
		cs.append("%d/%d" % [main.sim.bone_count(v.bone0 + i), v.counts0[i]])
	print("CRIT note vcut: links round the bite " + ", ".join(cs) + " counts size %d bone0 %d" % [main.sim.bone_counts_i.size(), v.bone0])
	_check("vcut_seen", v.pts.size() < n0, "cut after %d ticks: %d of %d points left" % [t, v.pts.size(), n0])
	await _ticks(3)
	var foot: Vector2 = Vector2(v.top.x, v.top.y + n0 * v.SEG - 8.0)
	var id: int = main.map.chunk_at_world(foot)
	var before: Array = _chunk_cells(id, Rect2(foot - Vector2(30.0, 90.0), Vector2(60.0, 100.0)))
	await _ticks(60)
	var after: Array = _chunk_cells(id, Rect2(foot - Vector2(80.0, 90.0), Vector2(160.0, 200.0)))
	_check("vcut_falls", id >= 0 and id != v.chunk and after[0] > 0 and after[1].y > before[1].y + 10.0,
			"the lower part (lump %d) fell from y %.0f to %.0f" % [id, before[1].y, after[1].y])
	_check("vcut_top", not v.gone and v.pts.size() >= 2 and main.map.anchored.has(v.chunk), "the upper part still hangs")


func _vine_climb() -> void:
	var v: RefCounted = main.critters.vines[0]
	var g: Node2D = main.gecko
	var at: Vector2 = v.pts[v.pts.size() - 6]
	g.spawn(at + Vector2(-RIDE_H, 0.0), Vector2.LEFT)
	g.input_override = Vector2.ZERO
	var held_t := -1
	var y0: float = g.pos.y
	var moved := 0.0
	var torn_t := -1
	var climb_top := INF
	for i in 150:
		await _ticks(1)
		if i == 45:
			g.input_override = Vector2.UP
			y0 = g.pos.y
		if i > 45 and torn_t < 0 and main.critters.held == v:
			climb_top = minf(climb_top, g.pos.y)
		if held_t < 0 and main.critters.held == v:
			held_t = i
		if main.critters.held == v:
			moved = maxf(moved, absf(v.pts[v.pts.size() - 6].x - at.x))
		if torn_t < 0 and v.gone:
			torn_t = i
	g.input_override = Vector2.ZERO
	_check("climb_held", held_t >= 0 and held_t < 20, "the gecko holds the vine after %d ticks" % held_t)
	_check("climb_up", y0 - climb_top > 8.0, "it climbed %.0f px up the vine" % (y0 - climb_top))
	_check("climb_sways", moved > 8.0, "its weight swung the vine %.1f px" % moved)
	if main.VINE_TEAR:
		_check("climb_tears", torn_t > 50 and torn_t < 110, "the vine tore from the ceiling %d ticks into the hang (VINE_HOLD 1.2 s)" % torn_t)
	else:
		_check("climb_holds", torn_t < 0, "the vine held the whole 2.5 s hang (VINE_TEAR off); tore at %d" % torn_t)


# A catch in flight: the rope swings away with the gecko, slowly, and
# keeps it.
func _vine_catch() -> void:
	var v: RefCounted = main.critters.vines[0]
	var g: Node2D = main.gecko
	var n: int = v.pts.size()
	var at: Vector2 = v.pts[n - 8]
	_drop_at(at + Vector2(-34.0, -6.0))
	g.vel = Vector2(240.0, -80.0)
	var held_t := -1
	for i in 40:
		await _ticks(1)
		if main.critters.held == v:
			held_t = i
			break
	_check("catch_held", held_t >= 0, "the gecko caught the vine after %d ticks" % held_t)
	var out := 0.0
	var fastest := 0.0
	var late := 0.0
	var kept := 0
	for i in 240:
		await _ticks(1)
		var k := clampi(int(round(v.nearest(g.pos))), 1, n - 1)
		var moved: float = v.pts[k].distance_to(v.prev[k])
		out = maxf(out, v.pts[k].x - v.top.x)
		fastest = maxf(fastest, moved)
		if i >= 180:
			late = maxf(late, moved)
		kept += 1 if main.critters.held == v else 0
	_check("catch_swings", out > 12.0, "the catch swung the held place %.1f px out" % out)
	_check("catch_slow", fastest < 2.5, "slowly: at most %.2f px a tick" % fastest)
	_check("catch_settles", late < 0.25, "the swing has died out after 3 s (%.2f px a tick)" % late)
	_check("catch_kept", kept > 230, "the gecko held on %d of 240 ticks" % kept)


# --- the slime ---

func _slime_creep() -> void:
	var s: RefCounted = main.critters.slimes[0]
	var m0: Array = main.sim.slime_mass(s.brain)
	var span := 0.0
	var lo := INF
	var hi := -INF
	var path := []
	var went := 0.0
	var last: float = m0[1].x
	for i in 480:
		await _ticks(1)
		var m: Array = main.sim.slime_mass(s.brain)
		lo = minf(lo, m[1].x)
		hi = maxf(hi, m[1].x)
		if i % 30 == 29:
			went += absf(m[1].x - last)
			last = m[1].x
		if i % 60 == 0:
			path.append("%.0f%s" % [m[1].x, "+" if s.dir > 0 else "-"])
	print("CRIT note creep: its centre each second " + " ".join(path))
	var m1: Array = main.sim.slime_mass(s.brain)
	_check("creep_alive", s.alive and m1[0] >= int(m0[0] * 0.85), "%d of %d particles in its reach after 8 s" % [m1[0], m0[0]])
	_check("creep_moves", went > 25.0, "it crept %.0f px in 8 s (over %.0f px of floor)" % [went, hi - lo])
	var box: Array = _cells_of_class(main.sim.CT_SLIME, Rect2(1150.0, 600.0, 450.0, 220.0))
	var r := sqrt(float(m0[0]) * 4.0 / PI)
	_check("creep_whole", box[0] > 0 and box[1].size.x < r * 6.0 and box[1].size.y < r * 3.0,
			"one blob: %d cells in %s (radius %.0f)" % [box[0], str(box[1].size), r])
	_check("creep_on_floor", box[1].end.y <= 800.0 and box[1].end.y > 790.0, "lying on the floor (its foot at y %.0f)" % box[1].end.y)


func _slime_bite() -> void:
	var s: RefCounted = main.critters.slimes[0]
	await _ticks(30)
	var m0: Array = main.sim.slime_mass(s.brain)
	main.map.erase_circle(m0[1], 6.0)
	await _ticks(6)
	var m1: Array = main.sim.slime_mass(s.brain)
	_check("bite_eats", m1[0] < m0[0] * 0.92 and m1[0] > 0, "a bite took it from %d to %d particles" % [m0[0], m1[0]])
	main.map.break_circle(m1[1] + Vector2(6.0, 0.0), 8.0)
	await _ticks(2)
	var splash: Array = main.sim.slime_mass(s.brain)
	await _ticks(240)
	var m2: Array = main.sim.slime_mass(s.brain)
	_check("bite_alive", s.alive, "it lives on")
	_check("bite_gathers", m2[0] >= int(m1[0] * 0.8), "after a strike splashed it (%d in reach) it gathered %d of %d back" % [splash[0], m2[0], m1[0]])


func _slime_wade() -> void:
	var s: RefCounted = main.critters.slimes[0]
	var g: Node2D = main.gecko
	var m0: Array = main.sim.slime_mass(s.brain)
	# The free walk's speed, then the same walk into the slime.
	_stand_at(1180.0)
	await _ticks(30)
	g.input_override = Vector2.RIGHT
	await _ticks(30)
	var x0: float = g.pos.x
	await _ticks(20)
	var free_v: float = (g.pos.x - x0) / (20.0 / 60.0)
	var slow_ticks := 0
	var slow_dist := 0.0
	var last: float = g.pos.x
	for i in 240:
		await _ticks(1)
		if g.in_slime:
			slow_ticks += 1
			slow_dist += g.pos.x - last
		last = g.pos.x
	g.input_override = Vector2.ZERO
	var slow_v := slow_dist / maxf(slow_ticks / 60.0, 0.001)
	_check("wade_in", slow_ticks > 30, "%d ticks in the slime" % slow_ticks)
	_check("wade_slow", slow_v < free_v * 0.55 and free_v > 60.0, "in it %.0f px/s, out of it %.0f" % [slow_v, free_v])
	# A jump out of it is weak: the gecko set down in the middle of it.
	var m1: Array = main.sim.slime_mass(s.brain)
	_stand_at(m1[1].x)
	await _ticks(20)
	if g.in_slime and g.clinging:
		g.jump_override = true
		await _ticks(1)
		await _ticks(1)
		_check("wade_jump", -g.vel.y < g.JUMP_SPEED * 0.7, "a jump out of it leaves at %.0f px/s (a jump %.0f)" % [-g.vel.y, g.JUMP_SPEED])
	else:
		print("CRIT note wade: not standing in the slime for the jump (in %s, clinging %s)" % [str(g.in_slime), str(g.clinging)])
	print("CRIT note wade: slime %d particles" % m0[0])


# --- the long slug ---

func _longslug() -> void:
	var s: RefCounted = main.critters.long_slugs[0]
	var turned := false
	var d0: float = s.dir
	var off := 0.0
	var rmin := INF
	var rmax := -INF
	for i in 1500:
		await _ticks(1)
		if s.dir != d0:
			turned = true
		for k in s.points.size():
			var q: Dictionary = main.map.nearest_solid(s.points[k], 12.0)
			off = maxf(off, q.dist if q.found else 99.0)
		var r: float = s.radius_at(2) / s.radii[2]
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	_check("slug_creeps", s.travelled > 25.0, "it crept %.0f px in 25 s" % s.travelled)
	_check("slug_hugs", off < 7.0, "every point within %.1f px of the rock" % off)
	_check("slug_pulses", rmax - rmin > 0.15, "its girth swells %.2f of itself" % (rmax - rmin))
	_check("slug_turns", turned, "it turned back at least once")


# --- the cost ---

func _perf() -> void:
	var c: Node2D = main.critters
	var sim_us := 0
	for i in 120:
		await _ticks(1)
		sim_us += main._sim_us
	var base_sim := sim_us / 120.0
	print("CRIT note perf: before, the sim's parts (upload, dispatch, readback) %s us" % str(main.sim.t_parts))
	var crit_us := 0
	for i in 120:
		await _ticks(1)
		crit_us += c.last_us
	var base_crit := crit_us / 120.0
	print("CRIT note perf: before, the critters' parts (shrooms, vines, slimes, slugs, counts) %s us" % str(c.parts_us))
	# Thirty shrooms, ten vines, four slimes, six long slugs more.
	var made := 0
	var only := "none" if _case == "perf_base" else OS.get_environment("CRIT_PERF")   # shrooms, vines, slimes or slugs: only those added (a cost bisect); perf_base adds none
	for i in (30 if only in ["", "shrooms"] else 0):
		made += 1 if c.add_shroom(Vector2(140.0 + i * 55.0, 780.0), 1 + i % 5, i) else 0
	for i in (10 if only in ["", "vines"] else 0):
		made += 1 if c.add_vine(Vector2(880.0 + i * 26.0, 620.0), 60.0 + i * 8.0) else 0
	for i in (4 if only in ["", "slimes"] else 0):
		made += 1 if c.add_slime(Vector2(1200.0 + i * 60.0, 700.0), 8.0) else 0
	for i in (6 if only in ["", "slugs"] else 0):
		made += 1 if c.add_long_slug(Vector2(200.0 + i * 250.0, 790.0), 60.0) else 0
	await _ticks(30)
	sim_us = 0
	crit_us = 0
	var worst := 0
	for i in 240:
		await _ticks(1)
		sim_us += main._sim_us
		crit_us += c.last_us
		worst = maxi(worst, c.last_us)
	var full_sim := sim_us / 240.0
	print("CRIT note perf: after, the sim's parts %s us" % str(main.sim.t_parts))
	var full_crit := crit_us / 240.0
	print("CRIT note perf: after, the critters' parts %s us" % str(c.parts_us))
	var st := []
	for v in c.vines:
		var most := 0.0
		for i in v.pts.size():
			most = maxf(most, v.pts[i].distance_to(v.prev[i]))
		st.append("%d/%.4f" % [v._still, most])
	print("CRIT note perf: vines still for, moving " + ", ".join(st))
	print("CRIT note perf: %d added; sim tick %.0f -> %.0f us, critters %.0f -> %.0f us (worst %d)" % [made, base_sim, full_sim, base_crit, full_crit, worst])
	# The sim's own cost is told by tools/critters_test.sh from this run
	# against perf_base's (nothing added), both measured at the same
	# point in the run: the virtual display's GPU slows over a run's
	# first seconds whatever the world holds, so before and after in one
	# run do not compare.
	print("CRIT perf sim %.0f" % full_sim)
	if _case == "perf_base":
		return
	_check("perf_made", made >= 45, "%d of 50 added" % made)
	_check("perf_critters", full_crit < 1500.0, "the critters' CPU tick %.0f us with %d shrooms, %d vines, %d slimes, %d long slugs" % [full_crit, c.shrooms.size(), c.vines.size(), c.slimes.size(), c.long_slugs.size()])



# --- a look: frames of each critter, for the eye (not checked) ---

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://runs/critters/shot_%s.png" % name))


# Each slime as the sim draws it (unlit, a pixel a cell): resting, a
# moment later (the texture should ride along with it), and bitten in
# two. runs/critters/cells_slime_<slime>_<when>.png
func _slime_look() -> void:
	var c: Node2D = main.critters
	c.add_slime(Vector2(1200.0, 770.0), main.slime_radius(5))
	c.add_slime(Vector2(1480.0, 760.0), 30.0)
	var ps: float = main.sim.PIXEL_SZ
	for when in ["rest", "later", "bitten"]:
		if when == "later":
			await _ticks(90)
		elif when == "bitten":
			for s in c.slimes:
				main.map.erase_circle(s.centre + Vector2(0.0, -2.0), 3.0)
			await _ticks(40)
		else:
			await _ticks(150)
		await _ticks(1)
		for i in c.slimes.size():
			var s: RefCounted = c.slimes[i]
			var r: float = s.reach + 6.0
			var rect := Rect2i(int((s.centre.x - r) / ps), int((s.centre.y - r) / ps), int(r * 2.0 / ps), int(r * 2.0 / ps))
			main.sim._display_img.get_region(rect).save_png(ProjectSettings.globalize_path("res://runs/critters/cells_slime_%d_%s.png" % [i, when]))
	var sizes := []
	for s in c.slimes:
		sizes.append("reach %.0f mass %d" % [s.reach, s.mass])
	_check("slime_look", true, "%d slimes saved: %s" % [c.slimes.size(), ", ".join(sizes)])


func _shots() -> void:
	var c: Node2D = main.critters
	var g: Node2D = main.gecko
	var s: RefCounted = c.shrooms[0]
	await _shot("start")
	await _land_on(s)
	await _ticks(3)
	await _shot("shroom_land")
	await _ticks(120)
	await _shot("shroom_stand")
	var s2: RefCounted = c.shrooms[1]
	_stand_at(560.0)
	await _ticks(10)
	main.map.erase_circle(s2.stem_point(0.5), 5.0)
	await _ticks(20)
	await _shot("shroom_cut")
	await _ticks(60)
	await _shot("shroom_cut_fallen")
	var v: RefCounted = c.vines[0]
	_stand_at(930.0)
	var n: int = v.pts.size()
	v.push(n - 1, Vector2(4.0, 0.0))
	await _ticks(25)
	await _shot("vine_swing")
	_stand_at(1290.0)
	await _ticks(120)
	await _shot("slime")
	_stand_at(1760.0)
	await _ticks(240)
	await _shot("longslug")
	_stand_at(1560.0)
	await _ticks(30)
	await _shot("shroom_glow")
	_stand_at(410.0)
	await _ticks(30)
	await _shot("shroom_big")
	# The sim's own render (a pixel a cell, unlit) round each shroom, to
	# hold against its sprite.
	for k in c.shrooms.size():
		var sh: RefCounted = c.shrooms[k]
		var ps: float = main.sim.PIXEL_SZ
		var r := Rect2i(int((sh.base.x - sh.cap_w - 8.0) / ps), int((sh.base.y - sh.height - sh.cap_w * 1.6) / ps), int((sh.cap_w * 2.0 + 16.0) / ps), int((sh.height + sh.cap_w * 1.6 + 4.0) / ps))
		main.sim._display_img.get_region(r).save_png(ProjectSettings.globalize_path("res://runs/critters/cells_shroom_%d.png" % k))
	# The big one bent under a weight on its cap's rim: no holes open.
	var big: RefCounted = c.shrooms[c.shrooms.size() - 1]
	big.weight_at = big.cap_xf().origin + Vector2(-big.cap_w, -4.0)
	await _ticks(90)
	await _ticks(1)
	var bp: float = main.sim.PIXEL_SZ
	var br := Rect2i(int((big.base.x - big.cap_w * 2.0 - 8.0) / bp), int((big.base.y - big.height - big.cap_w * 1.6) / bp), int((big.cap_w * 4.0 + 16.0) / bp), int((big.height + big.cap_w * 1.6 + 4.0) / bp))
	main.sim._display_img.get_region(br).save_png(ProjectSettings.globalize_path("res://runs/critters/cells_bent.png"))
	big.weight_at = Vector2.INF
