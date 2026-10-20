# Test scenes for the movement suite: terrain built from primitives on
# the bitmap map, a spawn point, and a scripted input, all read from
# tests/scenes.json (written by tools/gen_scenes.py). GECKO_SCENE=name or
# name:script picks one; main.gd builds it in place of the cave, runs
# the script through the demo pilot, and quits when it ends.
#
# Terrain ops (world px): ["blank"], ["cave", seed], ["room", x, y, w, h]
# and ["erase", ...] clear a rect, ["fill", x, y, w, h] fills one,
# ["disc", x, y, r], ["hole", x, y, r], ["below", x0, y0, x1, y1] rock
# under a line, ["above", ...] rock over one, ["stairs", x, y, n, w, h,
# dir], ["specks", seed, x0, x1, y, count] loose cells on the line y,
# ["cell", x, y, v], ["water", x, y, w, h], ["tunnel", x0, y0, x1, y1,
# r] and ["ragged", x0, y0, x1, y1, r, seed] carve a bored or chewed
# tunnel, ["funnel", x, y, w, depth] a V slot in a floor. The other
# materials as rects: ["sand", x, y, w, h], ["clay", ...] (loose, flow
# in the particle world, ground in the bitmap), ["lava", ...], ["hard",
# ...] (rock that takes several bites), ["bedrock", ...] (rock no bite
# opens); ["sand_disc", x, y, r] and ["clay_disc", ...] as discs.
# Spawns: ["floor", x, y] on the first rock below (x, y), ["ceiling",
# x, y] under the first rock above, ["wall_left", x, y] on the first
# rock to the left, ["wall_right", x, y], ["at", x, y] exactly.
# ["copper", x, y, w, h] makes a vein. A scene may also carry "lumps",
# loose lumps spawned after the terrain in the particle world (["boulder"
# | "clay", x, y, r] resting on the first floor below (x, y), ["sand", x,
# y, r] a heap about it), and "exit", a rect [x, y, w, h] the body
# centre enters to finish the level (main.gd). The levels (levels/*.json,
# written by tools/gen_clutch.py) are in the same format and are merged
# into the suite's scenes.
class_name SceneBuilder
extends RefCounted

const PATH := "res://tests/scenes.json"
const LEVELS_DIR := "res://levels"


# Every level file in levels/ (the clutch, and what the editor saves).
static func level_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(LEVELS_DIR + "/" + f)
	out.sort()
	return out


static func load_all() -> Dictionary:
	var data: Dictionary = _load(PATH)
	for path in level_files():
		var level: Dictionary = _load(path)
		for key in ["bases", "scripts", "scenes"]:
			if not data.has(key):
				data[key] = {}
			data[key].merge(level.get(key, {}), true)
	return data


static func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("no scenes file at " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("scenes file is not valid JSON: " + path)
		return {}
	return data


# "scene" or "scene:script" to {scene, script, steps}, steps in the
# demo pilot's format.
static func pick(spec: String) -> Dictionary:
	var all := load_all()
	var parts := spec.split(":")
	var name := parts[0]
	var scenes: Dictionary = all.get("scenes", {})
	if not scenes.has(name):
		push_error("no scene named " + name)
		return {}
	var scene: Dictionary = scenes[name]
	var script_name := ""
	if parts.size() > 1:
		script_name = parts[1]
	elif scene.has("scripts") and scene.scripts.size() > 0:
		script_name = scene.scripts[0]
	var raw: Array = []
	if scene.has("script"):
		raw = scene.script
	else:
		raw = all.get("scripts", {}).get(script_name, [])
	return {"name": name, "scene": scene, "script": script_name, "steps": _steps(raw), "bases": all.get("bases", {})}


static func _vec(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


# [secs, [ix, iy], jump?, chew?, lmb?, [ax, ay]?] to the demo step array.
static func _steps(raw: Array) -> Array:
	var out: Array = []
	for st in raw:
		var step: Array = [float(st[0]), _vec(st[1]),
			bool(st[2]) if st.size() > 2 else false,
			bool(st[3]) if st.size() > 3 else false,
			bool(st[4]) if st.size() > 4 else false,
			_vec(st[5]) if st.size() > 5 else Vector2.ZERO]
		out.append(step)
	return out


static func total_seconds(steps: Array) -> float:
	var t := 0.0
	for st in steps:
		t += st[0]
	return t


static func build(map: Node2D, scene: Dictionary, bases: Dictionary) -> void:
	var ops: Array = []
	if scene.has("base"):
		ops.append_array(bases.get(scene.base, []))
	ops.append_array(scene.get("terrain", []))
	for op in ops:
		_apply(map, op)
	map.repaint_all()


static func _rect(op: Array, i: int) -> Rect2:
	return Rect2(float(op[i]), float(op[i + 1]), float(op[i + 2]), float(op[i + 3]))


# The ops of one name in a scene's base and its own terrain, for what
# main.gd and ambience.gd apply themselves (gas pockets, currents,
# drip zones), since the build runs on a CPU map the sim is made from.
static func ops_of(scene: Dictionary, bases: Dictionary, name: String) -> Array:
	var out: Array = []
	var ops: Array = []
	if scene.has("base"):
		ops.append_array(bases.get(scene.base, []))
	ops.append_array(scene.get("terrain", []))
	for op in ops:
		if String(op[0]) == name:
			out.append(op)
	return out


static func _apply(map: Node2D, op: Array) -> void:
	match String(op[0]):
		"blank":
			map.blank()
		"cave":
			map.generate(int(op[1]))
		"room", "erase":
			map.erase_rect(_rect(op, 1))
		"fill":
			map.fill_rect(_rect(op, 1))
		"disc":
			map.fill_circle(Vector2(op[1], op[2]), float(op[3]))
		"hole":
			map.erase_circle(Vector2(op[1], op[2]), float(op[3]))
		"below":
			map.fill_below_line(Vector2(op[1], op[2]), Vector2(op[3], op[4]))
		"above":
			map.fill_above_line(Vector2(op[1], op[2]), Vector2(op[3], op[4]))
		"stairs":
			# n steps of w by h rising from the floor line y, to the right
			# (dir 1) or the left (dir -1), starting at x.
			var n := int(op[3])
			var w := float(op[4])
			var h := float(op[5])
			var dir := float(op[6])
			for i in n:
				var x0 := float(op[1]) + dir * w * i
				if dir < 0.0:
					x0 -= w
				map.fill_rect(Rect2(x0, float(op[2]) - h * (i + 1), w, h * (i + 1)))
		"specks":
			var rng := RandomNumberGenerator.new()
			rng.seed = int(op[1])
			for i in int(op[5]):
				var x := rng.randf_range(float(op[2]), float(op[3]))
				map.set_cell_world(Vector2(x, float(op[4])), 1)
		"cell":
			map.set_cell_world(Vector2(op[1], op[2]), int(op[3]))
		"cells":
			# ["cells", path]: the whole cell map from a PNG the editor saved.
			map.load_cells_png(String(op[1]))
		"water":
			map.water_rect(_rect(op, 1))
		"copper":
			map.copper_rect(_rect(op, 1))
		"sand", "clay", "lava", "hard", "bedrock":
			map.material_rect(_rect(op, 1), _kind(map, String(op[0])))
		"decor":
			# ["decor", name, x, y, "floor" | "ceiling"]: a stamp from DECOR
			# set cell by cell on the first floor below (x, y), or hanging
			# from the first ceiling above, only where there is air.
			_stamp(map, String(op[1]), Vector2(op[2], op[3]), String(op[4]) if op.size() > 4 else "floor")
		"moss":
			# ["moss", x, y, w, h]: the rock faces inside the rect are coated.
			map.coat_moss(_rect(op, 1))
		"crumble":
			# ["crumble", x, y, w, h]: the rock inside the rect crumbles under a hold.
			map.paint_kind(_rect(op, 1), map.CELL_ROCK, map.CELL_CRUMBLE)
		"gas":
			# ["gas", x, y, w, h]: a sealed pocket of gas (main.gd bursts it).
			map.material_rect(_rect(op, 1), map.CELL_GAS)
		"current", "drips":
			# ["current", x, y, w, h, dx, dy, speed] and ["drips", x0, x1, y,
			# rate]: read by main.gd and ambience.gd (ops_of), not built here.
			pass
		"stalactites", "stalagmites":
			# [op, x0, x1, y, n, seed, hmin, hmax]: n cones of rock between
			# x0 and x1 hanging from the ceiling line y (stalactites) or
			# standing on the floor line y (stalagmites), hmin to hmax px
			# tall, about half as wide at the base as tall, seeded.
			_cones(map, float(op[1]), float(op[2]), float(op[3]), int(op[4]), int(op[5]), float(op[6]), float(op[7]),
					1.0 if String(op[0]) == "stalactites" else -1.0)
		"column":
			# ["column", x, y0, y1, w, seed]: a stalagnate from the ceiling
			# line y0 to the floor line y1, w px at its ends, a waist of a
			# cell or two in the middle, seeded for its wobble.
			_column(map, float(op[1]), float(op[2]), float(op[3]), float(op[4]), int(op[5]))
		"sand_disc", "clay_disc":
			map.material_circle(Vector2(op[1], op[2]), float(op[3]), _kind(map, String(op[0]).trim_suffix("_disc")))
		"tunnel":
			var a := Vector2(op[1], op[2])
			var b := Vector2(op[3], op[4])
			var r := float(op[5])
			var n := int(a.distance_to(b) / 2.0) + 1
			for i in n + 1:
				map.erase_circle(a.lerp(b, float(i) / n), r)
		"ragged":
			# Like the chew: every 2 px a bite of a random size, a little off
			# the line, so the walls come out as the gecko leaves them.
			var a := Vector2(op[1], op[2])
			var b := Vector2(op[3], op[4])
			var r := float(op[5])
			var rng := RandomNumberGenerator.new()
			rng.seed = int(op[6])
			var n := int(a.distance_to(b) / 2.0) + 1
			for i in n + 1:
				var jitter := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
				map.erase_circle(a.lerp(b, float(i) / n) + jitter, rng.randf_range(r - 2.5, r + 0.5))
		"funnel":
			# A V slot: from width w at the floor line y to one cell at depth.
			var depth := float(op[4])
			var rows := int(depth / 4.0)
			for i in rows:
				var w := lerpf(float(op[3]), 4.0, float(i) / maxf(rows - 1, 1))
				map.erase_rect(Rect2(float(op[1]) - w * 0.5, float(op[2]) + i * 4.0, w, 4.0))
		_:
			push_error("unknown terrain op " + String(op[0]))


# Decor stamps: cells relative to the base cell (the one on the surface
# under the stamp's middle), x right, y up the stamp (toward the air),
# each a cell kind. The glowshrooms are the first; parts drawn as small
# images with a palette of kinds can replace these tables.
const DECOR := {
	"shroom_s": [[0, 1, 9], [-1, 2, 9], [0, 2, 9], [1, 2, 9]],
	"shroom_m": [[0, 1, 9], [0, 2, 9], [-2, 3, 9], [-1, 3, 9], [0, 3, 9], [1, 3, 9], [2, 3, 9], [-1, 4, 9], [0, 4, 9], [1, 4, 9]],
	"shroom_cluster": [[0, 1, 9], [0, 2, 9], [-2, 3, 9], [-1, 3, 9], [0, 3, 9], [1, 3, 9], [2, 3, 9], [-1, 4, 9], [0, 4, 9], [1, 4, 9],
			[4, 1, 9], [3, 2, 9], [4, 2, 9], [5, 2, 9], [-4, 1, 9], [-5, 2, 9], [-4, 2, 9], [-3, 2, 9]],
}


# Cones: dir 1 grows down from a ceiling line, -1 up from a floor line.
# Each is rows of rock narrowing from its base by a power curve, so it
# comes out pointed, a cell at the tip, on the cell grid.
static func _cones(map: Node2D, x0: float, x1: float, y: float, n: int, seed_v: int, hmin: float, hmax: float, dir: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cell: float = map.CELL
	for i in n:
		var x := snappedf(lerpf(x0, x1, (i + rng.randf_range(0.2, 0.8)) / n), cell)
		var h := snappedf(rng.randf_range(hmin, hmax), cell)
		var w := snappedf(h * rng.randf_range(0.4, 0.6), cell)
		var rows := int(h / cell)
		for r in rows:
			var t := float(r) / maxf(rows - 1, 1)
			var rw := maxf(snappedf(w * pow(1.0 - t, 0.75), cell), cell)
			var ry := y + dir * r * cell if dir > 0.0 else y - (r + 1) * cell
			map.fill_rect(Rect2(x - rw * 0.5, ry, rw, cell))


static func _column(map: Node2D, x: float, y0: float, y1: float, w: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cell: float = map.CELL
	var rows := int((y1 - y0) / cell)
	var lean := rng.randf_range(-0.15, 0.15)
	for r in rows:
		var t := float(r) / maxf(rows - 1, 1)
		# Wide at both ends, a waist in the middle: the two cones met.
		var k := absf(t - 0.5) * 2.0
		var rw := maxf(snappedf(lerpf(cell * 1.5, w, pow(k, 1.6)), cell), cell)
		var cx := snappedf(x + lean * (t - 0.5) * (y1 - y0), cell)
		map.fill_rect(Rect2(cx - rw * 0.5, y0 + r * cell, rw, cell))


# For the editor: a stamp or a cone placed by hand.
static func stamp(map: Node2D, name: String, at: Vector2, where: String) -> void:
	_stamp(map, name, at, where)


static func cone(map: Node2D, at: Vector2, h: float, down: bool) -> void:
	_cones(map, at.x - 2.0, at.x + 2.0, at.y, 1, int(at.x) + int(at.y), h, h, 1.0 if down else -1.0)


static func _stamp(map: Node2D, name: String, at: Vector2, where: String) -> void:
	if not DECOR.has(name):
		push_error("unknown decor " + name)
		return
	var cell: float = map.CELL
	var cx := int(floor(at.x / cell))
	var cy: int
	var dir := -1
	if where == "ceiling":
		var c: Vector2 = map.ceiling_above(at)
		cy = int(floor(c.y / cell)) - 1   # The last solid row of the ceiling
		dir = 1
	else:
		var f: Vector2 = map.floor_below(at)
		cy = int(floor(f.y / cell))       # The first solid row of the floor
	# The tables are on the 4 px grid: each entry fills a block of s by s
	# cells on a finer one, so a stamp keeps its size in px.
	var s := maxi(int(round(4.0 / cell)), 1)
	for c in DECOR[name]:
		for j in s:
			for i in s:
				var x: int = cx + c[0] * s + i
				var y: int = cy + dir * (c[1] * s + j)
				if not map.is_solid(x, y) and not map.is_water(x, y):
					map.set_cell_world(Vector2((x + 0.5) * cell, (y + 0.5) * cell), int(c[2]))


static func _kind(map: Node2D, name: String) -> int:
	match name:
		"sand":
			return map.CELL_SAND
		"clay":
			return map.CELL_CLAY
		"lava":
			return map.CELL_LAVA
		"hard":
			return map.CELL_HARD
		"bedrock":
			return map.CELL_BEDROCK
		_:
			return map.CELL_ROCK


# The scene's loose lumps, on the world as built (the bitmap world's
# spawns do nothing). A lump rests on the first floor below its point,
# clipped to the air there, so one bigger than its passage fills it.
# The slugs' start points: ["slugs"] entries [x, y] put on the nearest
# surface by slug.gd itself.
static func slug_points(scene: Dictionary) -> Array:
	var out: Array = []
	for s in scene.get("slugs", []):
		out.append(Vector2(s[0], s[1]))
	return out


# Returns the vines spawned, [chunk id, anchor] each, for main.gd's
# snap rule; a vine is ["vine", x, y, length]: hanging from the first
# ceiling above (x, y), length px.
static func spawn_lumps(map: Node2D, scene: Dictionary) -> Array:
	var vines: Array = []
	for lump in scene.get("lumps", []):
		var p := Vector2(lump[1], lump[2])
		var r := float(lump[3])
		match String(lump[0]):
			"sand":
				map.spawn_sand(p, r)
			"vine":
				var c: Vector2 = map.ceiling_above(p)
				var top := Vector2(p.x, c.y + 2.0)
				var id: int = map.spawn_vine(top, r)
				if id > 0:
					vines.append([id, top])
			"clay", "boulder":
				var fl: Vector2 = map.floor_below(p)
				var at := Vector2(p.x, fl.y - r - 2.0)
				if lump[0] == "clay":
					map.spawn_clay(at, r)
				else:
					map.spawn_boulder(at, r)
			_:
				push_error("unknown lump " + String(lump[0]))
	return vines


# The rect the body centre enters to finish, empty for a scene without one.
static func exit_rect(scene: Dictionary) -> Rect2:
	var e: Array = scene.get("exit", [])
	if e.size() < 4:
		return Rect2()
	return Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3]))


# Body centre and up vector for the scene's spawn.
static func spawn_point(map: Node2D, scene: Dictionary, ride_h: float) -> Dictionary:
	var sp: Array = scene.get("spawn", ["floor", 960, 540])
	var p := Vector2(sp[1], sp[2])
	match String(sp[0]):
		"floor":
			var fl: Vector2 = map.floor_below(p)
			return {"pos": Vector2(p.x, fl.y - ride_h), "up": Vector2.UP}
		"ceiling":
			var c: Vector2 = map.ceiling_above(p)
			return {"pos": Vector2(p.x, c.y + ride_h), "up": Vector2.DOWN}
		"wall_left":
			var hit = map.ray_hit(p, Vector2.LEFT, 400.0)
			var wx: float = hit.x + 4.0 - fmod(hit.x, 4.0) if hit != null else p.x
			return {"pos": Vector2(wx + ride_h, p.y), "up": Vector2.RIGHT}
		"wall_right":
			var hit = map.ray_hit(p, Vector2.RIGHT, 400.0)
			var wx: float = hit.x - fmod(hit.x, 4.0) if hit != null else p.x
			return {"pos": Vector2(wx - ride_h, p.y), "up": Vector2.LEFT}
		_:
			var u := Vector2.UP
			if sp.size() > 4:
				u = Vector2(sp[3], sp[4])
			return {"pos": p, "up": u}
