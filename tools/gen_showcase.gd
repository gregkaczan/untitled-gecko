# A cave to see everything in: four chambers carved by noise and joined
# by a winding passage and a switchback climb to a crack of daylight,
# every material laid where it belongs (bedrock under it all and round
# the edge, hard rock in seams, copper veins where the walls show them,
# sand in the floor's dips, clay by the lake, moss on its wet shores, a
# lake in the hall's basin, lava in a pit with embers round it, crumbling
# ledges on the climb, thorns on its walls, gas sealed in the rock beside
# the way, glowshroom flesh in the nooks), the decor brush run along
# the floors, ceilings and walls (moss carpets in the dark, ferns and
# plants by the way, shroom clusters and tall shrooms by the water, vine
# leaves under the ceilings, small shrooms on the ledges), cones hung
# and raised, two columns in the hall, vines over the lake, lumps on the
# floors, a slug, and lights of every kind and shape. Written as the
# editor writes a level (main.gd _level_dict): levels/<name>.json and
# levels/<name>.cells.png, which the game, the editor and the suite load.
#
#   godot --headless --path . -s tools/gen_showcase.gd [-- name seed]
extends SceneTree

const CaveMapScript = preload("res://cave_map.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const DecorBrush = preload("res://decor_brush.gd")
const W := 960
const H := 540
const CELL := 2.0
const EDGE := 6              # Cells of bedrock round the world
const BOTTOM := 18           # Rows of bedrock under everything

# The chambers, in cells: centre x, y and the radii; noise wobbles the rim.
const CHAMBERS := {
	"nook": [175, 335, 68, 50],    # The start: lit, a torch and a cone of torchlight down the way
	"hall": [430, 250, 135, 105],  # The great hall: the lake in its basin, columns, crystals
	"pit": [690, 395, 85, 52],     # The lava pit, embers round it
	"loft": [775, 135, 92, 58],    # The loft under the crack of daylight
}
# The way: polylines in cells with a radius, joining the chambers.
const WAYS := [
	[[[240, 335], [290, 320], [320, 290], [335, 270]], 10],              # nook to hall
	[[[555, 290], [595, 330], [625, 380], [650, 395]], 10],              # hall to pit
	[[[745, 355], [700, 318], [772, 282], [708, 244], [770, 206], [775, 180]], 9],   # the climb: a switchback
	[[[800, 85], [800, -6]], 5],                                         # the crack to the sky
]

var map: Node2D
var rng := RandomNumberGenerator.new()
var n1: FastNoiseLite
var n2: FastNoiseLite
var n3: FastNoiseLite
var decor: Array = []        # [name, x, y, where, flags]
var rects: Array = []        # The decor rects, for the brush's spacing
var lights: Array = []
var lumps: Array = []
var slugs: Array = []
var name := "showcase"
var seed_v := 11


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		name = args[0]
	if args.size() > 1:
		seed_v = int(args[1])
	rng.seed = seed_v
	n1 = _noise(seed_v, 0.035, 3)
	n2 = _noise(seed_v + 1, 0.012, 2)
	n3 = _noise(seed_v + 2, 0.045, 2)
	map = CaveMapScript.new()
	map.blank()
	_carve()
	_materials()
	_cones()
	_decor()
	_things()
	_write()
	quit()


static func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


# --- Cells ---

func _cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return CaveMapScript.CELL_BEDROCK
	return map.solid[y * W + x]


func _put(x: int, y: int, v: int) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		map.solid[y * W + x] = v


func _air(x: int, y: int) -> bool:
	var c := _cell(x, y)
	return c == CaveMapScript.CELL_AIR or c == CaveMapScript.CELL_WATER or c == CaveMapScript.CELL_LAVA or c == CaveMapScript.CELL_GAS


static func _px(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)


# --- The carve: chambers with noisy rims, pockets off them, the ways, smoothed ---

func _carve() -> void:
	for k in CHAMBERS:
		var c: Array = CHAMBERS[k]
		_blob(c[0], c[1], c[2], c[3], 0.45)
		# Side pockets off the rim, at random angles.
		for i in 4:
			var a := rng.randf_range(0.0, TAU)
			var px: int = c[0] + int(cos(a) * c[2] * 0.95)
			var py: int = c[1] + int(sin(a) * c[3] * 0.95)
			_blob(px, py, rng.randi_range(9, 18), rng.randi_range(7, 13), 0.5)
	for w in WAYS:
		var pts: Array = w[0]
		var r: float = float(w[1])
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var n := int(a.distance_to(b)) + 1
			for j in n + 1:
				var p := a.lerp(b, float(j) / n)
				var rr := r * (1.0 + 0.3 * n1.get_noise_2d(p.x * 2.0, p.y * 2.0))
				_disc(int(p.x), int(p.y), rr)
	# Smooth: specks go, nicks fill, twice.
	for pass_i in 2:
		var next: PackedByteArray = map.solid.duplicate()
		for y in range(1, H - 1):
			for x in range(1, W - 1):
				var open := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if (dx != 0 or dy != 0) and _air(x + dx, y + dy):
							open += 1
				if _air(x, y) and open <= 2:
					next[y * W + x] = CaveMapScript.CELL_ROCK
				elif not _air(x, y) and open >= 6:
					next[y * W + x] = CaveMapScript.CELL_AIR
		map.solid = next
	# The edge and the bottom are bedrock, but for the crack to the sky.
	for y in H:
		for x in W:
			var edge := x < EDGE or x >= W - EDGE or y >= H - EDGE or (y < EDGE and absi(x - 800) > 8)
			if edge or y >= H - BOTTOM:
				_put(x, y, CaveMapScript.CELL_BEDROCK)


func _blob(cx: int, cy: int, rx: int, ry: int, wobble: float) -> void:
	for y in range(cy - ry - 8, cy + ry + 9):
		for x in range(cx - rx - 8, cx + rx + 9):
			var e := pow(float(x - cx) / rx, 2.0) + pow(float(y - cy) / ry, 2.0)
			if e < 1.0 + wobble * n1.get_noise_2d(x, y):
				_put(x, y, CaveMapScript.CELL_AIR)


func _disc(cx: int, cy: int, r: float) -> void:
	var n := int(ceil(r))
	for y in range(cy - n, cy + n + 1):
		for x in range(cx - n, cx + n + 1):
			if Vector2(x - cx, y - cy).length() < r:
				_put(x, y, CaveMapScript.CELL_AIR)


# Cells of air within reach of this one, straight out.
func _near_air(x: int, y: int, reach: int) -> bool:
	for d in range(1, reach + 1):
		if _air(x + d, y) or _air(x - d, y) or _air(x, y + d) or _air(x, y - d):
			return true
	return false


# --- The materials, each with its reason ---

func _materials() -> void:
	# Hard rock in long thin seams through the rock.
	for y in range(EDGE, H - BOTTOM):
		for x in range(EDGE, W - EDGE):
			if _cell(x, y) == CaveMapScript.CELL_ROCK and absf(n2.get_noise_2d(x, y)) < 0.012:
				_put(x, y, CaveMapScript.CELL_HARD)
	# Copper veins: a few, each from a chamber's wall into the rock,
	# wobbling, so the wall shows its end and a bite follows it in.
	for k in CHAMBERS:
		var c: Array = CHAMBERS[k]
		for i in 2:
			var a := rng.randf_range(0.0, TAU)
			var d := Vector2(cos(a), sin(a))
			var p := Vector2(c[0], c[1])
			var steps := 0
			while _air(int(p.x), int(p.y)) and steps < 400:
				p += d
				steps += 1
			_vein(p + d * 2.0, d, rng.randi_range(22, 44))
	# The lake in the hall's basin, lava in the pit's.
	var hall: Array = CHAMBERS.hall
	_blob(hall[0], hall[1] + hall[3] + 10, 62, 34, 0.3)
	var pit: Array = CHAMBERS.pit
	_blob(pit[0], pit[1] + pit[3] + 4, 36, 22, 0.3)
	# A bedrock lip under the lava, so no bite lets it out below.
	for y in range(pit[1] + pit[3] + 26, pit[1] + pit[3] + 40):
		for x in range(pit[0] - 50, pit[0] + 51):
			if not _air(x, y):
				_put(x, y, CaveMapScript.CELL_BEDROCK)
	map.water_rect(Rect2(_px(hall[0] - 70, hall[1] + hall[3] + 2), Vector2(140.0 * CELL, 60.0 * CELL)))
	for y in range(pit[1] + pit[3] + 6, pit[1] + pit[3] + 36):
		for x in range(pit[0] - 40, pit[0] + 41):
			if _cell(x, y) == CaveMapScript.CELL_AIR:
				_put(x, y, CaveMapScript.CELL_LAVA)
	# Moss on the lake's wet shores and under the dripping ceiling over it.
	map.coat_moss(Rect2(_px(hall[0] - 110, hall[1] + hall[3] - 30), Vector2(50.0 * CELL, 50.0 * CELL)))
	map.coat_moss(Rect2(_px(hall[0] + 55, hall[1] + hall[3] - 30), Vector2(60.0 * CELL, 50.0 * CELL)))
	# Sand in the floors' dips, clay by the lake and a clump on the pit's shore.
	for p in [[hall[0] - 60, hall[1] - 20], [CHAMBERS.nook[0] + 30, CHAMBERS.nook[1]], [pit[0] - 60, pit[1] - 10]]:
		var fl: Vector2 = map.floor_below(_px(p[0], p[1]))
		map.material_circle(Vector2(fl.x, fl.y + 6.0), 14.0, CaveMapScript.CELL_SAND)
	for p in [[hall[0] - 95, hall[1] + hall[3] + 20], [hall[0] + 90, hall[1] + hall[3] + 24]]:
		var wl: Vector2 = map.wall_beside(_px(p[0], p[1]), 1 if p[0] > hall[0] else -1)
		map.material_circle(wl + Vector2(6.0 if p[0] > hall[0] else -6.0, 0.0), 11.0, CaveMapScript.CELL_CLAY)
	# Crumbling rock: an overhang on the hall's right, and the climb's middle ledge.
	map.paint_kind(Rect2(_px(hall[0] + 100, hall[1] - 90), Vector2(50.0 * CELL, 30.0 * CELL)), CaveMapScript.CELL_ROCK, CaveMapScript.CELL_CRUMBLE)
	map.paint_kind(Rect2(_px(755, 285), Vector2(40.0 * CELL, 16.0 * CELL)), CaveMapScript.CELL_ROCK, CaveMapScript.CELL_CRUMBLE)
	# Gas sealed in the rock beside the way: a bite opens it.
	for p in [[300, 300], [612, 350], [735, 262]]:
		var g := _inside(p[0], p[1], 9)
		if g.x >= 0:
			map.material_circle(_px(g.x, g.y), 11.0, CaveMapScript.CELL_GAS)
	# Glowshroom flesh in the dark nooks of the hall and the loft.
	for p in [[hall[0] - 120, hall[1] - 70], [hall[0] + 120, hall[1] + 30], [CHAMBERS.loft[0] - 80, CHAMBERS.loft[1] + 20]]:
		var g := _inside(p[0], p[1], 3)
		if g.x >= 0:
			map.material_circle(_px(g.x, g.y), 7.0, CaveMapScript.CELL_SHROOM)
	# Thorns on the climb's walls and one bush on the loft's floor.
	for p in [[Vector2(1416.0, 640.0), "wall_left"], [Vector2(1540.0, 560.0), "wall_right"], [Vector2(1430.0, 500.0), "wall_left"]]:
		SceneBuilder.stamp(map, "thorn", p[0], p[1])
	SceneBuilder.stamp(map, "thorn_s", _px(CHAMBERS.loft[0] + 50, CHAMBERS.loft[1] + 30), "floor")


# A vein of copper from p along d, wobbling with the noise, 2 cells thick.
func _vein(p: Vector2, d: Vector2, length: int) -> void:
	var n := Vector2(-d.y, d.x)
	for i in length:
		var q := p + d * i + n * (6.0 * n1.get_noise_2d(p.x + i * 3.0, p.y - i * 3.0))
		for dy in 2:
			for dx in 2:
				var x := int(q.x) + dx
				var y := int(q.y) + dy
				if _cell(x, y) == CaveMapScript.CELL_ROCK or _cell(x, y) == CaveMapScript.CELL_HARD:
					_put(x, y, CaveMapScript.CELL_COPPER)


# A point `deep` cells inside the rock nearest to (x, y), scanning out
# in four directions; (-1, -1) for none.
func _inside(x: int, y: int, deep: int) -> Vector2i:
	for d in range(0, 40):
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var p: Vector2i = Vector2i(x, y) + dir * d
			if not _air(p.x, p.y) and _cell(p.x, p.y) != CaveMapScript.CELL_BEDROCK:
				var q: Vector2i = p + dir * deep
				if not _air(q.x, q.y) and _cell(q.x, q.y) != CaveMapScript.CELL_BEDROCK:
					return q
	return Vector2i(-1, -1)


# --- Cones and columns ---

func _cones() -> void:
	for k in CHAMBERS:
		var c: Array = CHAMBERS[k]
		var x: int = c[0] - c[2] + 8
		while x < c[0] + c[2] - 8:
			var at := _px(x, c[1])
			if _air(x, c[1]):
				var ceil_y: float = map.ceiling_above(at).y
				var floor_y: float = map.floor_below(at).y
				var gap := floor_y - ceil_y
				if gap > 90.0 and rng.randf() < 0.7:
					var h := rng.randf_range(14.0, minf(52.0, gap * 0.35))
					SceneBuilder.cone(map, Vector2(at.x, ceil_y), h, true, rng.randi_range(0, 3))
				if gap > 70.0 and rng.randf() < 0.3:
					var h := rng.randf_range(10.0, minf(30.0, gap * 0.25))
					SceneBuilder.cone(map, Vector2(at.x, floor_y), h, false, rng.randi_range(0, 3))
			x += rng.randi_range(8, 18)
	# Two columns in the hall, ceiling to floor.
	var hall: Array = CHAMBERS.hall
	for cx in [hall[0] - 70, hall[0] + 80]:
		var at := _px(cx, hall[1])
		var cy: float = map.ceiling_above(at).y
		var fy: float = map.floor_below(at).y
		if fy - cy > 60.0 and fy - cy < 260.0:
			SceneBuilder._apply(map, ["column", at.x, cy, fy, 14.0, seed_v + cx])


# --- Decor: the brush along the surfaces, free stamps where a run would not do ---

func _group(g: String) -> Array:
	var out: Array = []
	for n in SceneBuilder.png_stamps():
		if SceneBuilder.stamp_group(n) == g:
			out.append(n)
	out.sort()
	return out


func _place(stamp: String, at: Vector2, where: String, flags: String) -> Rect2:
	var rect: Rect2 = SceneBuilder.stamp_rect(map, stamp, at, where)
	var cells: Array = SceneBuilder.stamp(map, stamp, at, where, flags)
	if cells.is_empty():
		return Rect2()
	decor.append([stamp, at.x, at.y, where, flags])
	rects.append(rect)
	return rect


func _taken(r: Rect2) -> bool:
	for q in rects:
		if q.intersects(r):
			return true
	return false


# The brush dragged along a floor or ceiling from x0 to x1 (cells), the
# cursor kept 10 px off the surface found below or above the y given.
func _run(group: String, x0: int, x1: int, y_ref: int, where: String, spacing: float, k: int) -> void:
	var brush = DecorBrush.new()
	brush.map = map
	brush.place = _place
	brush.taken = _taken
	brush.rng.seed = seed_v * 31 + k
	brush.spacing = spacing
	brush.mirror = true
	var first := true
	var x := x0
	while (x <= x1) if x1 >= x0 else (x >= x1):
		var at := _px(x, y_ref)
		if _air(x, y_ref):
			var p := at
			if where == "ceiling":
				p.y = map.ceiling_above(at).y + 10.0
			else:
				p.y = map.floor_below(at).y - 10.0
			if first:
				brush.begin(_group(group), p, where)
				first = false
			else:
				brush.drag(p)
		x += 2 if x1 >= x0 else -2
	if not first:
		brush.end(_px(x1, y_ref))


# Along a wall, from y0 to y1, the cursor 10 px off the wall beside the x given.
func _run_wall(group: String, y0: int, y1: int, x_ref: int, where: String, spacing: float, k: int) -> void:
	var brush = DecorBrush.new()
	brush.map = map
	brush.place = _place
	brush.taken = _taken
	brush.rng.seed = seed_v * 31 + k
	brush.spacing = spacing
	var first := true
	var dir := 1 if where == "wall_right" else -1
	for y in range(y0, y1 + 1, 2):
		var at := _px(x_ref, y)
		if not _air(x_ref, y):
			continue
		var p := at
		p.x = map.wall_beside(at, dir).x - dir * 10.0
		if first:
			brush.begin(_group(group), p, where)
			first = false
		else:
			brush.drag(p)
	if not first:
		brush.end(_px(x_ref, y1))


func _decor() -> void:
	var nook: Array = CHAMBERS.nook
	var hall: Array = CHAMBERS.hall
	var pit: Array = CHAMBERS.pit
	var loft: Array = CHAMBERS.loft
	# Ferns and plants by the way in the lit start, along its floor.
	_run("fern", nook[0] - 50, nook[0] + 20, nook[1], "floor", 14.0, 1)
	_run("plant", nook[0] + 24, nook[0] + 60, nook[1], "floor", 10.0, 2)
	# The hall: white moss carpets in the dark on the left floor and the
	# right, clusters and tall shrooms on the lake's shores, vine leaves
	# under the ceiling, small shrooms on the far ledge.
	_run("moss", hall[0] - 125, hall[0] - 70, hall[1] - 10, "floor", 0.0, 3)
	_run("moss", hall[0] + 70, hall[0] + 125, hall[1] - 10, "floor", 0.0, 4)
	_run("cluster", hall[0] - 100, hall[0] - 60, hall[1] + 60, "floor", 12.0, 5)
	_run("tall_a", hall[0] + 60, hall[0] + 105, hall[1] + 60, "floor", 16.0, 6)
	_run("tall_b", hall[0] - 60, hall[0] - 30, hall[1] + 40, "floor", 18.0, 7)
	_run("vine_leaves", hall[0] - 90, hall[0] + 90, hall[1] - 40, "ceiling", 22.0, 8)
	_run("shroom_s", hall[0] + 20, hall[0] + 60, hall[1] - 60, "floor", 12.0, 9)
	_run("moss", hall[0] - 40, hall[0] + 40, hall[1] - 60, "ceiling", 0.0, 10)
	# The pit's shore: ferns away from the lava, a moss carpet on the far side.
	_run("fern", pit[0] - 75, pit[0] - 45, pit[1] - 10, "floor", 12.0, 11)
	_run("moss", pit[0] + 40, pit[0] + 75, pit[1] - 10, "floor", 0.0, 12)
	# The climb: moss up a wall, small shrooms on a ledge.
	_run_wall("moss", 250, 330, 735, "wall_left", 0.0, 13)
	_run("shroom_s", 760, 780, 275, "floor", 10.0, 14)
	# The loft: plants and a fern under the daylight, vine leaves from its ceiling.
	_run("plant", loft[0] - 60, loft[0] - 10, loft[1], "floor", 10.0, 15)
	_run("fern", loft[0] + 10, loft[0] + 60, loft[1], "floor", 14.0, 16)
	_run("vine_leaves", loft[0] - 50, loft[0] + 50, loft[1] - 20, "ceiling", 26.0, 17)
	_run("cluster", loft[0] - 80, loft[0] - 65, loft[1] + 20, "floor", 12.0, 18)
	# More along the way: ferns on the hall's floors, small shrooms in
	# the start, plants on the climb's ledges, tall shrooms past the pit,
	# vine leaves in the start and over the pit.
	_run("fern", hall[0] - 70, hall[0] - 40, hall[1] + 40, "floor", 12.0, 19)
	_run("fern", hall[0] + 30, hall[0] + 60, hall[1] + 40, "floor", 12.0, 20)
	_run("shroom_s", nook[0] - 60, nook[0] - 40, nook[1], "floor", 10.0, 21)
	_run("plant", 700, 720, 310, "floor", 10.0, 22)
	_run("plant", 760, 775, 236, "floor", 10.0, 23)
	_run("tall_b", pit[0] - 40, pit[0] - 10, pit[1] - 10, "floor", 16.0, 24)
	_run("vine_leaves", nook[0] - 50, nook[0] + 50, nook[1] - 20, "ceiling", 24.0, 25)
	_run("vine_leaves", pit[0] - 60, pit[0] + 60, pit[1] - 20, "ceiling", 24.0, 26)
	_run("moss", loft[0] + 20, loft[0] + 70, loft[1], "floor", 0.0, 27)


# --- Vines, lumps, a slug, the lights ---

func _things() -> void:
	var nook: Array = CHAMBERS.nook
	var hall: Array = CHAMBERS.hall
	var pit: Array = CHAMBERS.pit
	var loft: Array = CHAMBERS.loft
	# Vines over the lake and from the loft's ceiling.
	for p in [[hall[0] - 30, hall[1] - 20, 110.0], [hall[0] + 30, hall[1] - 20, 80.0], [hall[0] + 5, hall[1] - 20, 140.0], [loft[0] + 30, loft[1], 60.0],
			[hall[0] - 100, hall[1] - 20, 70.0], [pit[0] + 20, pit[1] - 20, 50.0]]:
		var at := _px(p[0], p[1])
		lumps.append(["vine", at.x, at.y, p[2]])
	# Lumps on the floors: a boulder too heavy to drag in the hall, stones
	# to carry, a clump of clay by the lake, heaps of sand in the start.
	for p in [["boulder", hall[0] + 40, hall[1], 16.0], ["boulder", hall[0] - 20, hall[1], 11.0], ["boulder", nook[0] - 20, nook[1], 4.5],
			["boulder", pit[0] - 30, pit[1] - 20, 5.0], ["clay", hall[0] - 80, hall[1] + 40, 9.0]]:
		var at := _px(p[1], p[2])
		lumps.append([p[0], at.x, at.y, p[3]])
	for p in [[nook[0] + 45, nook[1]], [loft[0] + 40, loft[1]]]:
		var fl: Vector2 = map.floor_below(_px(p[0], p[1]))
		lumps.append(["sand", fl.x, fl.y - 20.0, 18.0])
	# A slug on the hall's floor.
	var sl: Vector2 = map.floor_below(_px(hall[0] - 110, hall[1] + 20))
	slugs.append([sl.x, sl.y - 6.0])
	# Lights: a torch at the start and a cone of its light down the way;
	# crystals in the hall's dark, a strip of them along a ledge; embers
	# round the lava; a glow by the shroom clusters; the moon through the crack.
	var t := _px(nook[0] - 40, nook[1] - 30)
	lights.append([t.x, t.y, "torch", 36.0, 1.2, "point", t.x, t.y])
	var ta := _px(nook[0] + 50, nook[1] - 10)
	var tb := _px(nook[0] + 110, nook[1] - 20)
	lights.append([ta.x, ta.y, "torch", 36.0, 1.0, "cone", tb.x, tb.y])
	var c1 := _px(hall[0] - 80, hall[1] - 80)
	lights.append([c1.x, c1.y, "crystal", 34.0, 1.1, "point", c1.x, c1.y])
	var s0 := _px(hall[0] + 60, hall[1] - 95)
	var s1 := _px(hall[0] + 130, hall[1] - 85)
	lights.append([s0.x, s0.y, "crystal", 16.0, 0.8, "strip", s1.x, s1.y])
	var e0 := _px(pit[0] - 42, pit[1] + pit[3] - 4)
	var e1 := _px(pit[0] + 42, pit[1] + pit[3] - 4)
	lights.append([e0.x, e0.y, "ember", 12.0, 1.2, "strip", e1.x, e1.y])
	var e2 := _px(pit[0] + 60, pit[1] - 30)
	lights.append([e2.x, e2.y, "ember", 10.0, 1.0, "point", e2.x, e2.y])
	var g := _px(hall[0] - 80, hall[1] + 50)
	lights.append([g.x, g.y, "glow", 14.0, 1.0, "point", g.x, g.y])
	var m0 := _px(800, 8)
	var m1 := _px(loft[0] - 10, loft[1] + 50)
	lights.append([m0.x, m0.y, "moon", 56.0, 1.0, "cone", m1.x, m1.y])


# --- The files, and a word on what was made ---

func _write() -> void:
	var nook: Array = CHAMBERS.nook
	var spawn_at := _px(nook[0] - 10, nook[1] - 10)
	var png := "res://levels/%s.cells.png" % name
	map.save_cells_png(ProjectSettings.globalize_path(png))
	var scene := {"base": name, "spawn": ["floor", spawn_at.x, spawn_at.y], "exit": [1580.0, 0.0, 40.0, 40.0],
			"lumps": lumps, "slugs": slugs, "decor": decor, "lights": lights}
	var level := {"bases": {name: [["blank"], ["cells", png]]}, "scripts": {}, "scenes": {name: scene},
			"saved_at": Time.get_datetime_string_from_system(false, true), "kind": "saved",
			"generator": "tools/gen_showcase.gd %s %d" % [name, seed_v]}
	var f := FileAccess.open("res://levels/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(level, " "))
	f.close()
	# What is in it, and whether the way holds together: the air
	# reachable from the spawn against all of it.
	var kinds := {}
	for v in map.solid:
		kinds[v] = kinds.get(v, 0) + 1
	var reach := _reach(Vector2i(int(spawn_at.x / CELL), int(spawn_at.y / CELL)))
	var air := 0
	for y in H:
		for x in W:
			if _air(x, y):
				air += 1
	print("%s: seed %d, decor %d, lights %d, lumps %d, slugs %d; air reachable from the spawn %d of %d cells (%.0f%%)" % [
			name, seed_v, decor.size(), lights.size(), lumps.size(), slugs.size(), reach, air, 100.0 * reach / maxf(air, 1.0)])
	var names := {0: "air", 1: "rock", 2: "water", 3: "copper", 4: "sand", 5: "clay", 6: "lava", 7: "hard", 8: "bedrock", 9: "shroom", 10: "moss", 11: "crumble", 12: "gas", 13: "thorn"}
	var line := "cells:"
	var dec := 0
	for k in kinds:
		if k >= 16:
			dec += kinds[k]
		else:
			line += " %s %d" % [names.get(k, str(k)), kinds[k]]
	print(line + " decor %d" % dec)


func _reach(from: Vector2i) -> int:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var queue: Array[Vector2i] = [from]
	seen[from.y * W + from.x] = 1
	var i := 0
	while i < queue.size():
		var c: Vector2i = queue[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H or seen[q.y * W + q.x] == 1 or not _air(q.x, q.y):
				continue
			seen[q.y * W + q.x] = 1
			queue.append(q)
	return queue.size()
