# The editor's save and load, pixel for pixel. The generated cave is
# edited through the editor's own calls, in strokes as the panel makes
# them: paints of every kind (a rock island in the air, a hole in it,
# hard rock, bedrock, copper, moss, crumbling rock, thorns, a
# glowshroom, a gas pocket, sand, clay, water and lava in pits), decor
# laid by the brush along the island's top and set free on a floor, a
# ceiling and a wall, the procedural stamps (cones, a thorn bush, a
# vine, a slug) and lights of the three shapes. The view is shot, the
# level saved under its own name and loaded again, the view shot once
# more, and the two compared. What settles (water, lava, loose grains,
# lumps and vines) may differ: those cells in either shot, grown
# MASK_GROW cells, are left out, as is the panel. Everything else must
# match exactly: the authored cells, the sim's static cells, the decor,
# light, lump and slug lists, and every pixel of the view. The shots
# and a diff (the differences in magenta, the masked ones dim) go to
# runs/save/. Prints a line a check and SAVE TEST OK or FAILS.
#
#   tools/save_test.sh      a window on a virtual display: the sim needs a GPU
#   (main.gd runs it as GECKO_PROBE=res://tests/save_test.gd)
extends Node

const CaveMap = preload("res://cave_map.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const OUT := "res://runs/save"
const LEVEL := "savetest"
const MASK_GROW := 4           # Cells a settling cell's exclusion reaches
const SETTLE := 90             # Ticks the world runs after the edits, and again after the load
const VIEW := Vector2(960.0, 700.0)   # The camera for the shots: the island and the cave floor under it
const ISLAND := Vector2(940.0, 650.0)

var main: Node2D
var _fails := 0
var _notes: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var tree := get_tree()
	for i in 10:
		await tree.physics_frame
	main._set_debug(false)
	main.sim.set_light(false)
	main.blobs.visible = false
	main.gecko.visible = false
	var author: CaveMap = main._author
	if author == null:
		print("SAVE: no authoring map")
		print("SAVE TEST FAILS 1")
		tree.quit(1)
		return

	# --- The edits, a stroke each as the panel makes them ---
	# An island of rock in the air, so there is a floor, a ceiling and
	# walls of fresh rock in the view, and a hole in it.
	_stroke([[&"paint", ISLAND, 50.0, CaveMap.CELL_ROCK], [&"paint", ISLAND + Vector2(70.0, 8.0), 44.0, CaveMap.CELL_ROCK]])
	await tree.physics_frame
	_stroke([[&"paint", ISLAND + Vector2(10.0, -4.0), 14.0, CaveMap.CELL_AIR]])
	await tree.physics_frame
	# The other kinds, blobs in the air and on the island.
	_stroke([[&"paint", Vector2(1200.0, 560.0), 20.0, CaveMap.CELL_HARD], [&"paint", Vector2(1260.0, 560.0), 16.0, CaveMap.CELL_BEDROCK],
			[&"paint", Vector2(1310.0, 560.0), 14.0, CaveMap.CELL_COPPER]])
	await tree.physics_frame
	var top: float = author.floor_below(Vector2(900.0, 560.0)).y
	_stroke([[&"paint", Vector2(880.0, top), 10.0, CaveMap.CELL_MOSS], [&"paint", Vector2(1150.0, 700.0), 16.0, CaveMap.CELL_CRUMBLE],
			[&"paint", Vector2(700.0, 560.0), 12.0, CaveMap.CELL_THORN], [&"paint", Vector2(760.0, 560.0), 12.0, CaveMap.CELL_SHROOM],
			[&"paint", ISLAND + Vector2(40.0, 24.0), 8.0, CaveMap.CELL_GAS]])
	await tree.physics_frame
	# Pits in the cave floor, water in one and lava in the other; sand
	# and clay on the island.
	var fl1: float = author.floor_below(Vector2(1100.0, 800.0)).y
	var fl2: float = author.floor_below(Vector2(1250.0, 800.0)).y
	_stroke([[&"paint", Vector2(1100.0, fl1 + 20.0), 22.0, CaveMap.CELL_AIR], [&"paint", Vector2(1250.0, fl2 + 20.0), 22.0, CaveMap.CELL_AIR]])
	await tree.physics_frame
	await tree.physics_frame
	_stroke([[&"paint", Vector2(1100.0, fl1 + 26.0), 12.0, CaveMap.CELL_WATER], [&"paint", Vector2(1250.0, fl2 + 26.0), 10.0, CaveMap.CELL_LAVA],
			[&"paint", Vector2(1000.0, top - 12.0), 8.0, CaveMap.CELL_SAND], [&"paint", Vector2(930.0, top - 10.0), 7.0, CaveMap.CELL_CLAY]])
	await tree.physics_frame
	await tree.physics_frame
	# The brush: a run of moss along the island's top, mirrored at random.
	var moss: Array = []
	for n in SceneBuilder.png_stamps():
		if SceneBuilder.stamp_group(n) == "moss":
			moss.append(n)
	moss.sort()
	main.edit_begin()
	main.edit_brush_begin(moss, Vector2(900.0, top - 16.0), "floor", 0.0, true, "")
	for i in range(1, 25):
		main.edit_brush_drag(Vector2(900.0 + 100.0 * i / 24.0, top - 16.0))
		await tree.physics_frame
	main.edit_brush_end(Vector2(1000.0, top - 16.0))
	main.edit_end()
	await tree.physics_frame
	# Free stamps: on the cave floor, under the island, off its left wall.
	for st in [["cluster_0", Vector2(1120.0, 800.0), "floor", "h"], ["tall_a_0", Vector2(1320.0, 800.0), "floor", ""],
			["fern_1", Vector2(1040.0, 800.0), "floor", ""], ["vine_leaves_0", Vector2(930.0, 730.0), "ceiling", "h"],
			["moss_2", Vector2(860.0, 650.0), "wall_right", "d"]]:
		if not SceneBuilder.png_stamps().has(st[0]):
			_notes.append("no stamp " + st[0])
			continue
		_stroke([[&"stamp", st[0], st[1], st[2], st[3], {}]])
		await tree.physics_frame
	# The procedural stamps.
	_stroke([[&"stamp", "stalactite", Vector2(1000.0, 730.0), "nearest", "", {"size": 3, "variant": 1}]])
	await tree.physics_frame
	_stroke([[&"stamp", "stalagmite", Vector2(1340.0, 860.0), "nearest", "", {"size": 2, "variant": 3}]])
	await tree.physics_frame
	_stroke([[&"stamp", "thorn", Vector2(1390.0, 860.0), "floor", "", {"size": 2}]])
	await tree.physics_frame
	_stroke([[&"stamp", "vine", Vector2(960.0, 730.0), "nearest", "", {"size": 2}]])
	await tree.physics_frame
	_stroke([[&"stamp", "slug", Vector2(1180.0, 860.0), "nearest", "", {}]])
	await tree.physics_frame
	# The chain critters: a shroom, a slime, a long slug.
	_stroke([[&"stamp", "shroom", Vector2(1300.0, 860.0), "floor", "", {"size": 2, "variant": 1}]])
	await tree.physics_frame
	_stroke([[&"stamp", "slime", Vector2(1440.0, 850.0), "nearest", "", {"size": 1}]])
	await tree.physics_frame
	_stroke([[&"stamp", "longslug", Vector2(1500.0, 860.0), "nearest", "", {"size": 2}]])
	await tree.physics_frame
	# Lights of the three shapes.
	_stroke([[&"light", Vector2(700.0, 700.0), Vector2(700.0, 700.0), "torch", 20.0, 1.0, "point"]])
	_stroke([[&"light", Vector2(1200.0, 480.0), Vector2(1300.0, 540.0), "crystal", 24.0, 1.2, "cone"]])
	_stroke([[&"light", Vector2(600.0, 850.0), Vector2(760.0, 850.0), "glow", 12.0, 0.8, "strip"]])
	print("SAVE: edits made, decor %d lights %d lumps %d slugs %d gas %d" % [main._edit_decor.size(), main._edit_lights.size(), main._edit_lumps.size(), main._edit_slugs.size(), main._gas.size()])

	# --- Before: settle, shoot, keep the state ---
	for i in SETTLE:
		await tree.physics_frame
	var a := await _shot("a")

	# --- Save, load, settle, shoot ---
	print("SAVE: " + main.save_level(LEVEL))
	print("SAVE: " + main.load_version(LEVEL))
	main.sim.set_light(false)
	main.blobs.visible = false
	main.gecko.visible = false
	for i in SETTLE:
		await tree.physics_frame
	var b := await _shot("b")

	# --- The checks ---
	_check("cells", a.author == b.author, "the authored cells differ after the load")
	_check_static(a, b)
	_check("decor", a.decor == b.decor, "decor %s\n   vs %s" % [str(a.decor), str(b.decor)])
	_check("lights", a.lights == b.lights, "lights %s\n   vs %s" % [str(a.lights), str(b.lights)])
	_check("lumps", _rounded(a.lumps) == _rounded(b.lumps), "lumps %s\n   vs %s" % [str(a.lumps), str(b.lumps)])
	_check("slugs", a.slugs == b.slugs, "slugs %s vs %s" % [str(a.slugs), str(b.slugs)])
	_check("counts", a.counts == b.counts, "gas pockets, vines, slugs, lights, shrooms, slimes, long slugs %s vs %s" % [str(a.counts), str(b.counts)])
	_check("view", a.cam == b.cam, "the camera differs: %s vs %s" % [str(a.cam), str(b.cam)])
	_check_pixels(a, b)
	for n in _notes:
		print("SAVE: note: " + n)
	print("SAVE TEST " + ("OK" if _fails == 0 else "FAILS %d" % _fails))
	main._remove_level_files(LEVEL)
	tree.quit(1 if _fails > 0 else 0)


# One stroke: the button down, the ops a tick apart as the panel makes
# them (a paint a frame), the button up.
func _stroke(ops: Array) -> void:
	main.edit_begin()
	for op in ops:
		match op[0]:
			&"paint":
				main.edit_paint(op[1], op[2], op[3])
				await get_tree().physics_frame
			&"stamp":
				var r: Rect2 = main.edit_stamp(op[1], op[2], 0.0, op[3], op[4], op[5])
				if r.size == Vector2.ZERO and SceneBuilder.png_stamps().has(op[1]):
					_notes.append("%s at %s set nothing" % [op[1], str(op[2])])
			&"light":
				main.edit_light(op[1], op[2], op[3], op[4], op[5], op[6])
	main.edit_brush_end(Vector2.ZERO)
	main.edit_end()


# The camera on VIEW, the world drawn, the view's pixels and the state
# that must come back: the authored cells, the sim's cell classes, the
# lists, the camera's transform.
func _shot(name: String) -> Dictionary:
	var tree := get_tree()
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	main.edit_zoom(1.0, half)
	main._cam = VIEW
	main._cam_target = VIEW
	main._follow()
	main.edit_ghost({})
	main.edit_light_preview([])
	for s in main._slugs:
		s.visible = false
	await tree.physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
	main._author.save_cells_png(ProjectSettings.globalize_path(OUT + "/" + name + ".cells.png"))
	_class_png(main.sim.cells, OUT + "/" + name + ".classes.png")
	var decor: Array = []
	for d in main._edit_decor:
		decor.append([d.name, d.x, d.y, d.where, d.flags])
	var lumps: Array = []
	lumps.append_array(main._scene.get("lumps", []))
	if main._scene.is_empty():
		lumps.append_array(main._gen_lumps)
	lumps.append_array(main._edit_lumps)
	var slugs: Array = []
	slugs.append_array(main._scene.get("slugs", []))
	slugs.append_array(main._edit_slugs)
	return {"img": img, "author": (main._author.solid as PackedByteArray).duplicate(), "cells": (main.sim.cells as PackedByteArray).duplicate(),
			"decor": decor, "lights": main._edit_lights.duplicate(true), "lumps": lumps, "slugs": slugs,
			"counts": [main._gas.size(), main.critters.vines.size(), main._slugs.size(), main._lights.size(),
					main.critters.shrooms.size(), main.critters.slimes.size(), main.critters.long_slugs.size()],
			"cam": main.get_viewport().get_canvas_transform(), "panel": main._editor.panel_width()}


# The sim's cell classes as a picture: air black, water blue, static
# solid grey, lava orange, loose grains yellow, moss green, crumbling
# rock brown, thorns white, a chunk's cells magenta, a crumb dim red.
static func _class_png(cells: PackedByteArray, path: String) -> void:
	var W: int = CaveMap.W_FULL
	var H: int = CaveMap.H_FULL
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for i in W * H:
		var v := cells.decode_u32(i * 4)
		var col := Color.BLACK
		if v >= 256:
			col = Color(0.5, 0.1, 0.1)
		elif v >= 16:
			col = Color.MAGENTA
		else:
			match v:
				1: col = Color(0.2, 0.4, 0.9)
				2: col = Color(0.55, 0.55, 0.55)
				3: col = Color(1.0, 0.5, 0.1)
				4: col = Color(0.9, 0.8, 0.2)
				5: col = Color(0.2, 0.7, 0.2)
				6: col = Color(0.6, 0.4, 0.2)
				7: col = Color.WHITE
		img.set_pixel(i % W, i / W, col)
	img.save_png(ProjectSettings.globalize_path(path))


# A list's floats to three decimals: what the json keeps of them.
static func _rounded(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.001)
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_rounded(e))
		return out
	return v


func _check(what: String, ok: bool, why: String) -> void:
	if not ok:
		_fails += 1
	print("SAVE: %-8s %s%s" % [what, "ok" if ok else "FAIL", "" if ok else ": " + why])


# A cell's class off the sim's readback, crumbs as air (sim_map.gd).
static func _cls(cells: PackedByteArray, i: int) -> int:
	var v := cells.decode_u32(i * 4)
	return 0 if v >= 256 else v


static func _static(c: int) -> bool:
	return c == 2 or c == 5 or c == 6 or c == 7


static func _settles(c: int) -> bool:
	return c == 1 or c == 3 or c == 4 or c == 8 or c >= 16


# The sim's static cells (rock and its bands, decor) must be the same
# set before and after, where nothing that settles sits (a resting lump
# claims the floor cells it touches, a grain can lie in one); the first
# differences are named.
func _check_static(a: Dictionary, b: Dictionary) -> void:
	var W: int = CaveMap.W_FULL
	var n: int = W * CaveMap.H_FULL
	var bad := 0
	var first: Array = []
	for i in n:
		var ca := _cls(a.cells, i)
		var cb := _cls(b.cells, i)
		if _settles(ca) or _settles(cb):
			continue
		if _static(ca) != _static(cb) or (_static(ca) and ca != cb):
			bad += 1
			if first.size() < 8:
				first.append("(%d, %d) %d->%d" % [(i % W) * 2, (i / W) * 2, ca, cb])
	_check("solid", bad == 0, "%d static cells differ in the sim, e.g. %s" % [bad, ", ".join(first)])


# Every pixel of the view outside the mask (the panel, and the settling
# cells of either shot grown MASK_GROW) must match. The diff image
# marks the differences in magenta, the masked ones in a dim cyan.
func _check_pixels(a: Dictionary, b: Dictionary) -> void:
	var ia: Image = a.img
	var ib: Image = b.img
	var w := ia.get_width()
	var h := ia.get_height()
	if w != ib.get_width() or h != ib.get_height():
		_check("pixels", false, "the shots differ in size")
		return
	var W: int = CaveMap.W_FULL
	var H: int = CaveMap.H_FULL
	var n := W * H
	# The mask on the cell grid: what settles, in either shot, grown.
	var m := PackedByteArray()
	m.resize(n)
	for i in n:
		if _settles(_cls(a.cells, i)) or _settles(_cls(b.cells, i)):
			m[i] = 1
	var grown := PackedByteArray()
	grown.resize(n)
	for i in n:
		if m[i] == 1:
			var x := i % W
			var y := i / W
			for dy in range(-MASK_GROW, MASK_GROW + 1):
				var yy := y + dy
				if yy < 0 or yy >= H:
					continue
				for dx in range(-MASK_GROW, MASK_GROW + 1):
					var xx := x + dx
					if xx >= 0 and xx < W:
						grown[yy * W + xx] = 1
	# A screen pixel's cell, by column and by row (the view is axis aligned).
	var inv: Transform2D = (a.cam as Transform2D).affine_inverse()
	var cx := PackedInt32Array()
	var cy := PackedInt32Array()
	cx.resize(w)
	cy.resize(h)
	for sx in w:
		cx[sx] = int(floor((inv * Vector2(sx + 0.5, 0.5)).x / CaveMap.CELL_FULL))
	for sy in h:
		cy[sy] = int(floor((inv * Vector2(0.5, sy + 0.5)).y / CaveMap.CELL_FULL))
	var panel := int(ceil(float(a.panel))) + 4
	var da: PackedByteArray = ia.get_data()
	var db: PackedByteArray = ib.get_data()
	var diff: Image = ib.duplicate()
	var bad := 0
	var masked := 0
	var tiles := {}
	for sy in h:
		var row := cy[sy]
		for sx in w:
			var i := (sy * w + sx) * 4
			if da[i] == db[i] and da[i + 1] == db[i + 1] and da[i + 2] == db[i + 2]:
				continue
			var col := cx[sx]
			var out := sx < panel or col < 0 or col >= W or row < 0 or row >= H or grown[row * W + col] == 1
			if out:
				masked += 1
				diff.set_pixel(sx, sy, Color(0.2, 0.5, 0.5))
			else:
				bad += 1
				diff.set_pixel(sx, sy, Color(1.0, 0.0, 1.0))
				tiles[Vector2i(sx / 32, sy / 32)] = tiles.get(Vector2i(sx / 32, sy / 32), 0) + 1
	diff.save_png(ProjectSettings.globalize_path(OUT + "/diff.png"))
	var where: Array = []
	var keys: Array = tiles.keys()
	keys.sort_custom(func(p, q) -> bool: return tiles[p] > tiles[q])
	for k in keys.slice(0, 10):
		var wp: Vector2 = inv * Vector2(k.x * 32 + 16, k.y * 32 + 16)
		where.append("%d px at world %d, %d" % [tiles[k], int(wp.x), int(wp.y)])
	print("SAVE: pixels %d differ outside the mask, %d within it (%s)" % [bad, masked, "settling matter" if masked > 0 else "none"])
	_check("pixels", bad == 0, "in %d tiles of 32 px: %s" % [tiles.size(), "; ".join(where)])
