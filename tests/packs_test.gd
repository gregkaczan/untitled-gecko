# The packs' art in the game (tools/pack_import.py), checked in the
# particle world on levels/packs_lab.json (it needs the GPU:
# tools/packs_test.sh runs it on a virtual display). One case a run,
# PACK_CASE naming it; a PACK line a check and PACK TEST OK or FAILS.
#
# Cases: bands (each band draws its decor in its own palette), rig (the
# new shrooms and plants are rigged), plant_sway (a plant bends under a
# weight and comes back), strand (held at both ends, brushed aside and
# back, cut by a bite), support (moss under a ledge falls when the ledge
# is chewed away), worm (creeps, its skin rides it), jelly (stays in the
# water, darts, pops when bitten), water_tint (rock in the pool is
# bluer than dry rock). Not a test, only when named: shots (a frame of
# each band, runs/packs/shot_*.png).
#
#   (main.gd runs it as GECKO_PROBE=res://tests/packs_test.gd)
extends Node

const DecorPalettes = preload("res://decor_palettes.gd")
const CaveMap = preload("res://cave_map.gd")

var main: Node2D
var _fails := 0
var _case := OS.get_environment("PACK_CASE")


func _ready() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	print("PACK %s %s: %s" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1


func _run() -> void:
	await _ticks(5)
	main._demo_step = -1
	main.gecko.input_override = Vector2.ZERO
	await _ticks(30)
	match _case:
		"bands": await _bands()
		"rig": await _rig()
		"plant_sway": await _plant_sway()
		"strand": await _strand()
		"support": await _support()
		"worm": await _worm()
		"jelly": await _jelly()
		"water_tint": await _water_tint()
		"shots": await _shots()
		"tour": await _tour()
		"perf": await _perf()
		_:
			_check("case", false, "no case " + _case)
	print("PACK TEST %s %d" % ["OK" if _fails == 0 else "FAILS", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# The sim's rendered colour of cell (x, y), this tick.
func _rendered(x: int, y: int) -> Color:
	var sim: Node2D = main.sim
	var b: PackedByteArray = sim._rd.buffer_get_data(sim._buf, (sim.O_RN + y * sim.RENDER_W + x) * 4, 4)
	return Color8(b[0], b[1], b[2], b[3])


# Each band's decor drawn in its palette: every standing decor cell of a
# band (not a shroom's, those are lifted out) within a few steps of the
# palette colour its index has there.
func _bands() -> void:
	var kinds: PackedByteArray = main._baked.solid
	var w: int = main.sim.RENDER_W
	for band in [[0, 380, "warm"], [400, 700, "garden"], [720, 1080, "mycelium"]]:
		var n := 0
		var bad := 0
		var worst := 0.0
		for y in range(int(band[0] / 2.0), int(band[1] / 2.0)):
			for x in w:
				var k := kinds[y * w + x]
				if k < CaveMap.CELL_DECOR or main.sim.cells.decode_u32((y * w + x) * 4) & 255 != 2:
					continue
				var want := DecorPalettes.colour_at(k - CaveMap.CELL_DECOR, x, y, 2.0)
				var got := _rendered(x, y)
				var d := maxf(maxf(absf(want.r - got.r), absf(want.g - got.g)), absf(want.b - got.b))
				worst = maxf(worst, d)
				n += 1
				if d > 0.05:
					bad += 1
				if n >= 400:
					break
			if n >= 400:
				break
		_check("bands_" + band[2], n > 20 and bad == 0, "%d decor cells read, %d off their %s colour, worst %.3f" % [n, bad, band[2], worst])
	_check("bands_list", DecorPalettes.bands.size() == 3 and DecorPalettes.bands[2][1] == "mycelium", str(DecorPalettes.bands))


func _rig() -> void:
	var c: Node2D = main.critters
	var plants := 0
	var shrooms := 0
	for s in c.shrooms:
		if s.plant:
			plants += 1
		else:
			shrooms += 1
	# 7 mycelium and 12 warm mushrooms are laid; a few may be too small
	# to bend (a cap on a stub stays decor).
	_check("rig_shrooms", shrooms >= 14, "%d shrooms that bend" % shrooms)
	_check("rig_plants", plants >= 4, "%d plants that bend (5 laid)" % plants)


func _plant_sway() -> void:
	var c: Node2D = main.critters
	var p: RefCounted = null
	for s in c.shrooms:
		if s.plant and s.up.y < 0.0:
			p = s
			break
	if p == null:
		_check("plant", false, "no standing plant")
		return
	p.weight_at = p.stem_point(1.0) + Vector2(12.0, 0.0)
	var most := 0.0
	for i in 90:
		await _ticks(1)
		for t in p.theta:
			most = maxf(most, absf(t))
	p.weight_at = Vector2.INF
	await _ticks(300)
	var left := 0.0
	for t in p.theta:
		left = maxf(left, absf(t))
	_check("plant_bends", most > 0.03, "most bend %.3f rad under a weight off its tip" % most)
	_check("plant_back", left < 0.01, "bend %.4f rad 5 s after the weight went" % left)


func _strand() -> void:
	var c: Node2D = main.critters
	_check("strand_count", c.strands.size() == 3, "%d strands" % c.strands.size())
	if c.strands.is_empty():
		return
	var held := 0
	for st in c.strands:
		if st.pinned[0] == 1 and st.pinned[st.pts.size() - 1] == 1:
			held += 1
	_check("strand_held", held == c.strands.size(), "%d of %d held at both ends" % [held, c.strands.size()])
	var st: RefCounted = c.strands[0]
	await _ticks(240)   # Settled under its weight from the drawn line first
	var m: int = st.pts.size() / 2
	var start: Vector2 = st.pts[m]
	var most := 0.0
	for i in 12:
		st.step(1.0 / 60.0, [[start + Vector2(0.0, 4.0), 3.0]])
		most = maxf(most, (st.pts[m] as Vector2).distance_to(start))
	await _ticks(360)
	var back: float = (st.pts[m] as Vector2).distance_to(start)
	_check("strand_brushed", most > 2.0, "pushed %.1f px by a body passing under it" % most)
	_check("strand_settles", back < 3.0, "%.1f px from its rest 6 s later" % back)
	var k: int = st.pts.size() / 3
	var at: Vector2 = st.pts[k]
	var before: float = st.pts[k + 1].y
	main.map.erase_circle(at + Vector2(1.0, 0.0), 2.0)
	await _ticks(120)
	var cut := 0
	for f in st.cut:
		cut += f
	_check("strand_cut", cut >= 1, "%d links cut by a bite" % cut)
	_check("strand_parts_hang", st.pts[k + 1].y > before + 3.0, "the point past the cut from y %.1f to %.1f" % [before, st.pts[k + 1].y])


func _support() -> void:
	var sup: RefCounted = main.map.support
	_check("support_pieces", sup.pieces.size() > 10, "%d pieces of decor" % sup.pieces.size())
	var before: int = sup.released
	# The ledge (1400 to 1520 at y 540 to 556) chewed away, a bite a tick.
	var x := 1404.0
	while x <= 1520.0:
		main.map.erase_circle(Vector2(x, 548.0), 10.0, true)
		await _ticks(1)
		x += 8.0
	await _ticks(8)
	var fell: int = sup.released - before
	_check("support_released", fell > 60, "%d decor cells came loose" % fell)
	# Lumps below where the moss hung, a second later.
	await _ticks(60)
	var lumps := 0
	var w: int = main.sim.RENDER_W
	for y in range(300, 340):
		for xx in range(690, 770):
			if main.sim.cells.decode_u32((y * w + xx) * 4) & 255 >= 16:
				lumps += 1
	_check("support_fell", lumps > 20, "%d lump cells on the garden floor under the ledge" % lumps)


func _worm() -> void:
	var c: Node2D = main.critters
	var worms: Array = c.long_slugs.filter(func(s) -> bool: return not s.sprite.is_empty())
	_check("worm_count", worms.size() == 2, "%d worms" % worms.size())
	if worms.is_empty():
		return
	var wm: RefCounted = worms[0]
	var t0: float = wm.travelled
	await _ticks(480)
	_check("worm_creeps", wm.travelled - t0 > 3.0, "crept %.1f px in 8 s" % (wm.travelled - t0))
	var skin: Array = wm.skin()   # Where the pixels lie (the drawing's quads follow the same frame)
	var far := 0.0
	for px in skin:
		var best := INF
		for p in wm.points:
			best = minf(best, (px[0] as Vector2).distance_to(p))
		far = maxf(far, best)
	var tall := 0.0
	for px in wm.sprite:
		tall = maxf(tall, float(px[1]))
	_check("worm_skin", skin.size() == wm.sprite.size() * 4 and far < tall + 8.0, "%d pixels, the farthest %.1f px off its body (the sprite %.0f px tall)" % [skin.size(), far, tall])


func _jelly() -> void:
	var c: Node2D = main.critters
	_check("jelly_count", c.jellies.size() == 2, "%d jellyfish" % c.jellies.size())
	if c.jellies.is_empty():
		return
	var j: RefCounted = c.jellies[0]
	var start: Vector2 = j.pos
	var wet := 0
	var most := 0.0
	for i in 600:
		await _ticks(1)
		if j.in_water:
			wet += 1
		most = maxf(most, j.pos.distance_to(start))
	_check("jelly_in_water", wet >= 590, "in the water %d of 600 ticks" % wet)
	_check("jelly_darts", most > 4.0, "went %.1f px from where it began in 10 s" % most)
	main.map.erase_circle(j.pos, 2.0)
	await _ticks(60)
	_check("jelly_pops", c.jellies.size() == 1, "%d left a second after a bite on one" % c.jellies.size())


func _water_tint() -> void:
	await _ticks(10)
	var rw := _blue(700, 525)   # The pool's floor (x 1400 to 1440, y 1050)
	var rd := _blue(450, 525)   # The rock under the dry floor (x 900)
	_check("water_tint", rw > rd * 1.3, "blue over red %.2f under the pool, %.2f dry" % [rw, rd])


# Blue over red of the rendered cells in 20 x 2 from (x, y).
func _blue(x: int, y: int) -> float:
	var b := 0.0
	var r := 0.0
	for j in 2:
		for i in 20:
			var c := _rendered(x + i, y + j)
			b += c.b
			r += c.r
	return b / maxf(r, 0.01)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://runs/packs/shot_%s.png" % name))


# The gecko set on the floor under p: the camera goes with it.
func _look_at(p: Vector2) -> void:
	var fl: Vector2 = main.map.floor_below(p)
	main.gecko.spawn(Vector2(p.x, fl.y - 16.0), Vector2.UP)
	main._cam_reset()


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://runs/packs"))
	for v in [["mycelium", Vector2(640, 900)], ["pool", Vector2(1260, 900)], ["garden", Vector2(640, 600)], ["garden_ledge", Vector2(1300, 600)], ["warm", Vector2(560, 300)]]:
		_look_at(v[1])
		await _ticks(20)
		await _shot(v[0])
	# The ledge chewed away: the moss under it falls.
	_look_at(Vector2(1300, 600))
	var x := 1404.0
	while x <= 1520.0:
		main.map.erase_circle(Vector2(x, 548.0), 10.0, true)
		await _ticks(1)
		x += 8.0
	await _ticks(8)
	await _shot("ledge_fall_0")
	await _ticks(40)
	await _shot("ledge_fall_1")
	# A strand brushed by the gecko walking under it.
	_look_at(Vector2(380, 900))
	main.gecko.input_override = Vector2(1.0, 0.0)
	await _ticks(90)
	await _shot("walk_0")
	await _ticks(60)
	await _shot("walk_1")
	main.gecko.input_override = Vector2.ZERO


# The art tunnel (levels/art_tunnel.json, PACK_CASE=tour with
# GECKO_SCENE=art_tunnel:hold): a frame at each stretch of it.
func _tour() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://runs/packs"))
	for v in [["t1_warm", Vector2(300, 300)], ["t2_garden", Vector2(800, 600)], ["t3_garden_lip", Vector2(1050, 600)], ["t4_myc", Vector2(1500, 900)], ["t5_pool", Vector2(1700, 900)]]:
		_look_at(v[1])
		await _ticks(40)
		await _shot(v[0])


# The cost of the drawn creatures and threads (critters.gd draw_us) and
# the critters' tick, and the frame, at each stretch of the art tunnel:
# PACK note lines, mean over 2 s.
func _perf() -> void:
	for v in [["warm", Vector2(300, 300)], ["garden", Vector2(1000, 600)], ["myc", Vector2(1550, 900)]]:
		_look_at(v[1])
		await _ticks(60)
		var n := 0
		var d := Vector3.ZERO
		var tick := 0.0
		var frame := 0.0
		var sim_t := 0.0
		for i in 120:
			await get_tree().process_frame
			var du: PackedInt32Array = main.critters.draw_us
			d += Vector3(du[0], du[1], du[2])
			tick += main.critters.last_us
			frame += Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0
			sim_t += main.sim.t_parts.y
			n += 1
		d /= n
		print("PACK note perf %s: draw strands %d us, worms %d us, jellyfish %d us; critters tick %d us; sim dispatch %d us; process %d us" % [v[0], d.x, d.y, d.z, tick / n, sim_t / n, frame / n])
