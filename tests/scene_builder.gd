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
# tunnel, ["funnel", x, y, w, depth] a V slot in a floor.
# Spawns: ["floor", x, y] on the first rock below (x, y), ["ceiling",
# x, y] under the first rock above, ["wall_left", x, y] on the first
# rock to the left, ["wall_right", x, y], ["at", x, y] exactly.
class_name SceneBuilder
extends RefCounted

const PATH := "res://tests/scenes.json"


static func load_all() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("no scenes file at " + PATH)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("scenes file is not valid JSON")
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
		"water":
			map.water_rect(_rect(op, 1))
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
