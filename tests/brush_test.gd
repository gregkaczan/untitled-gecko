# The decor brush's headless test (decor_brush.gd): grounds of a few
# shapes carved in a blank map, the brush dragged along each, and its
# rules checked. A carpet run (the moss) is a left end, middles and a
# right end laid edge to edge, no two stamps overlapping, every laid
# column resting on the ground, the runs spanning the drag; a scatter
# (the shroom clusters, the tall shrooms) keeps its spacing and each
# stamp rests on solid too. Each case is drawn to runs/brush/<case>.png
# at 4x to look at. Prints a line a case and BRUSH TEST OK or FAILS.
#
#   godot --headless --path . -s tests/brush_test.gd
extends SceneTree

const CaveMapScript = preload("res://cave_map.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const DecorBrush = preload("res://decor_brush.gd")
const OUT := "res://runs/brush"
const FLOOR := 800.0
const CEIL := 100.0
const WALL := 1200.0
const SCALE := 4

var _map: Node2D
var _placed: Array = []
var _fails := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var groups := {}
	for n in SceneBuilder.png_stamps():
		var g: String = SceneBuilder.stamp_group(n)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(n)
	for g in groups:
		groups[g].sort()
	var cases := [
		["flat", "moss", "floor"], ["slope", "moss", "floor"], ["bumps", "moss", "floor"], ["steps", "moss", "floor"],
		["pit", "moss", "floor"], ["ceiling", "moss", "ceiling"], ["wall", "moss", "wall_right"], ["back", "moss", "floor"],
		["flat", "cluster", "floor"], ["bumps", "cluster", "floor"], ["slope", "tall_a", "floor"],
	]
	var first := {}
	for c in cases:
		first[c] = _case(c[0], c[1], groups[c[1]], c[2])
	# The same seed lays the same run twice.
	var again: Array = _case("bumps", "moss", groups["moss"], "floor", false)
	var same: bool = again == first[cases[2]]
	if not same:
		_fails += 1
	print("brush: determinism %s" % ("ok" if same else "FAIL"))
	print("BRUSH TEST " + ("OK" if _fails == 0 else "FAILS %d" % _fails))
	quit(1 if _fails > 0 else 0)


# One drag of the group along the ground; the names laid, for the determinism check.
func _case(ground: String, group: String, names: Array, where: String, draw := true) -> Array:
	_map = _ground(ground)
	_placed.clear()
	var carpet := false
	for n in names:
		if SceneBuilder.stamp_role(n) == "l":
			carpet = true
	var brush = DecorBrush.new()
	brush.map = _map
	brush.place = _place
	brush.taken = _taken
	brush.rng.seed = 11
	brush.spacing = 0.0 if carpet else 8.0
	var a := Vector2(200.0, FLOOR - 20.0)
	var b := Vector2(1000.0, FLOOR - 20.0)
	if where == "ceiling":
		a.y = CEIL + 20.0
		b.y = CEIL + 20.0
	elif where == "wall_right":
		a = Vector2(WALL - 20.0, 200.0)
		b = Vector2(WALL - 20.0, 700.0)
	if ground == "back":
		var t := a
		a = b
		b = t
	brush.begin(names, a, where)
	var steps := 400
	for i in range(1, steps + 1):
		brush.drag(a.lerp(b, float(i) / steps))
	brush.end(b)
	var fr: Array = SceneBuilder.frame(_map, a, where)
	var along: Vector2i = fr[1]
	var up: Vector2i = fr[2]
	# Overlaps: no two rects meet.
	var overlaps := 0
	for i in _placed.size():
		for j in range(i + 1, _placed.size()):
			if _placed[i].rect.intersects(_placed[j].rect):
				overlaps += 1
	# Resting: in every stamp, each column of the art that reaches its
	# bottom row (a foot; spikes and caps overhang) has, where it was
	# set, its cell nearest the surface on solid.
	var floating := 0
	var columns := 0
	for s in _placed:
		var png: Dictionary = SceneBuilder.png_stamps().get(s.name, {})
		if png.is_empty():
			continue
		var bottom := {}
		var pc: PackedInt32Array = png.cells
		for i in range(0, pc.size(), 3):
			bottom[pc[i]] = maxi(bottom.get(pc[i], -1), pc[i + 1])
		var cols := {}
		for c in s.cells:
			var key: int = c[0] if along.x != 0 else c[1]
			var depth: int = -(c[0] * up.x + c[1] * up.y)
			if not cols.has(key) or depth > cols[key].d:
				cols[key] = {"d": depth, "p": Vector2i(c[0], c[1])}
		var w: int = png.w
		for px in bottom:
			if bottom[px] != png.h - 1:
				continue
			var key: int = _lo(s.rect, along) + (w - 1 - px if s.flags.contains("h") else px)
			if not cols.has(key):
				continue
			columns += 1
			var under: Vector2i = cols[key].p - up
			if not _map.is_solid(under.x, under.y):
				floating += 1
	# Runs: a carpet's are an end, middles, the other end, edge to edge.
	var roles_bad := 0
	var gaps := 0
	var k := 0
	var sp := int(round(brush.spacing / _map.CELL))
	var dir := 1 if ground != "back" else -1
	for run in brush.runs:
		var prev := {}
		for i in run.size():
			var p: Dictionary = _placed[k]
			k += 1
			if carpet:
				var role: String = SceneBuilder.stamp_role(p.name)
				if p.flags.contains("h"):
					role = "r" if role == "l" else ("l" if role == "r" else role)
				var want := "m"
				if run.size() == 1:
					want = ""     # A click's whole take, or a start with no ground for its end
					if role == ("l" if dir > 0 else "r"):
						want = role
				elif i == 0:
					want = "l" if dir > 0 else "r"
				elif i == run.size() - 1:
					want = "r" if dir > 0 else "l"
				if role != want:
					roles_bad += 1
			if not prev.is_empty():
				var gap: int = _lo(p.rect, along) - _hi(prev.rect, along) - 1 if dir > 0 else _lo(prev.rect, along) - _hi(p.rect, along) - 1
				if gap != sp:
					gaps += 1
			prev = p
	# Span: the stamps cover the drag.
	var lo := 1 << 30
	var hi := -(1 << 30)
	for p in _placed:
		lo = mini(lo, _lo(p.rect, along))
		hi = maxi(hi, _hi(p.rect, along))
	var span: float = float(hi - lo + 1) * _map.CELL / absf(_along_px(b, along) - _along_px(a, along)) if _placed.size() > 0 else 0.0
	var ok: bool = overlaps == 0 and floating == 0 and roles_bad == 0 and gaps == 0 and span > 0.8 and span < 1.3
	if not ok:
		_fails += 1
	print("brush: %-8s %-8s %-10s pieces %2d runs %d overlaps %d floating %d/%d roles bad %d gaps %d span %.2f %s" % [
			ground, group, where, _placed.size(), brush.runs.size(), overlaps, floating, columns, roles_bad, gaps, span, "ok" if ok else "FAIL"])
	if draw:
		_draw(ground + "_" + group, where)
	if OS.get_environment("BRUSH_DEBUG") != "":
		var k2 := 0
		for run in brush.runs:
			var line := "  run:"
			for i in run.size():
				var p: Dictionary = _placed[k2]
				k2 += 1
				line += " %s%s[%d..%d]" % [p.name, "~" if p.flags.contains("h") else "", _lo(p.rect, along), _hi(p.rect, along)]
			print(line)
	var laid: Array = []
	for p in _placed:
		laid.append([p.name, p.flags, p.rect])
	return laid


func _lo(r: Rect2, along: Vector2i) -> int:
	return int(floor((r.position.x if along.x != 0 else r.position.y) / _map.CELL))


func _hi(r: Rect2, along: Vector2i) -> int:
	return int(floor((r.end.x if along.x != 0 else r.end.y) / _map.CELL)) - 1


func _along_px(p: Vector2, along: Vector2i) -> float:
	return p.x if along.x != 0 else p.y


func _place(name: String, at: Vector2, where: String, flags: String) -> Rect2:
	var rect: Rect2 = SceneBuilder.stamp_rect(_map, name, at, where)
	var cells: Array = SceneBuilder.stamp(_map, name, at, where, flags)
	_placed.append({"name": name, "flags": flags, "rect": rect, "cells": cells})
	return rect


func _taken(rect: Rect2) -> bool:
	for p in _placed:
		if p.rect.intersects(rect):
			return true
	return false


# A room with the floor at FLOOR, the ceiling at CEIL and a wall at
# WALL, shaped as the case asks.
func _ground(kind: String) -> Node2D:
	var m = CaveMapScript.new()
	m.blank()
	m.erase_rect(Rect2(0.0, CEIL, WALL, FLOOR - CEIL))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cell: float = m.CELL
	var h := 0
	match kind:
		"slope":
			# The floor climbs a cell every four columns from x 300 on
			for x in range(150, 600):
				var rise := (x - 150) / 4
				if rise > 0:
					m.fill_rect(Rect2(x * cell, FLOOR - rise * cell, cell, rise * cell))
		"bumps":
			for x in range(0, 600):
				if x % 3 == 0:
					h = clampi(h + rng.randi_range(-2, 2), 0, 6)
				if h > 0:
					m.fill_rect(Rect2(x * cell, FLOOR - h * cell, cell, h * cell))
		"steps":
			for x in range(0, 600):
				h = ((x / 12) % 4) * 3
				if h > 0:
					m.fill_rect(Rect2(x * cell, FLOOR - h * cell, cell, h * cell))
		"pit":
			# A pit 12 cells wide and 10 deep, and the floor dropping 8 cells past x 900
			m.erase_rect(Rect2(600.0, FLOOR, 24.0, 20.0))
			m.erase_rect(Rect2(900.0, FLOOR, 300.0, 16.0))
		"ceiling":
			for x in range(0, 600):
				if x % 4 == 0:
					h = clampi(h + rng.randi_range(-1, 1), 0, 4)
				if h > 0:
					m.fill_rect(Rect2(x * cell, CEIL, cell, h * cell))
		"wall":
			for y in range(50, 400):
				if y % 4 == 0:
					h = clampi(h + rng.randi_range(-1, 1), 0, 4)
				if h > 0:
					m.fill_rect(Rect2(WALL - h * cell, y * cell, h * cell, cell))
	return m


# The case drawn at SCALE: rock grey, air near black, decor in its
# palette colour, the rest in a plain tint.
func _draw(name: String, where: String) -> void:
	var cell: float = _map.CELL
	var r := Rect2i(75, int((FLOOR - 200.0) / cell), 450, 110)
	if where == "ceiling":
		r = Rect2i(75, int(CEIL / cell) - 10, 450, 40)
	elif where == "wall_right":
		r = Rect2i(int(WALL / cell) - 30, 80, 40, 300)
	var img := Image.create(r.size.x * SCALE, r.size.y * SCALE, false, Image.FORMAT_RGBA8)
	for y in r.size.y:
		for x in r.size.x:
			var v: int = _map.solid[(r.position.y + y) * _map.W + r.position.x + x]
			var col := Color(0.08, 0.08, 0.11)
			if v >= CaveMapScript.CELL_DECOR:
				col = CaveMapScript.DECOR_PALETTE[(v - CaveMapScript.CELL_DECOR) & 15]
			elif v == CaveMapScript.CELL_ROCK:
				col = Color(0.36, 0.34, 0.32)
			elif v != CaveMapScript.CELL_AIR:
				col = Color(0.5, 0.4, 0.3)
			img.fill_rect(Rect2i(x * SCALE, y * SCALE, SCALE, SCALE), col)
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
