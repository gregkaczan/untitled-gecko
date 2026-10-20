# The cave's depth, in the particle world: a far wall behind the air,
# a noise of darker rock larger than the world that moves at a fraction
# of the camera's speed, and a near layer in front of everything, a few
# dark dripstone silhouettes hung from the ceilings and raised from the
# floors of the cell map, moving a little faster than the world. Both
# at the rock's 2 px cells, nearest filtered, and snapped to the
# camera's grid every tick so they never shimmer (main.gd _follow).
extends Node2D

const CELL := 2.0
const FAR := 0.15              # The far wall's share of the camera's motion
const NEAR := 1.25             # The near layer's: past 1, it moves faster than the world
const FAR_MARGIN := Vector2i(60, 36)   # Cells of far wall beyond the world's edge each way, for its drift
const FAR_BASE := Color(0.075, 0.072, 0.095)
const NEAR_COLOR := Color(0.02, 0.02, 0.03, 0.78)
const NEAR_CHANCE_CEIL := 0.14 # Per scanned column with a ceiling
const NEAR_CHANCE_FLOOR := 0.08
const NEAR_STEP := 14          # Columns scanned, in cells

var _far: Sprite2D
var _near: Sprite2D
var _far_tex: ImageTexture
var _near_tex: ImageTexture
var _w := 0
var _h := 0
var _grid := 0.5
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_far = Sprite2D.new()
	_far.centered = false
	_far.scale = Vector2(CELL, CELL)
	_far.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_near = Sprite2D.new()
	_near.centered = false
	_near.scale = Vector2(CELL, CELL)
	_near.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_near.z_as_relative = false
	_near.z_index = 7
	add_child(_near)


# The far wall goes under the sim's particle sprite: a child of the sim
# node, drawn after its backdrop rect and before the particles.
func attach_far(sim: Node2D) -> void:
	sim.add_child(_far)
	sim.move_child(_far, 0)


func set_grid(g: float) -> void:
	_grid = g


# Builds both layers for a cell map (CaveMap kinds, w by h cells).
func build(kinds: PackedByteArray, w: int, h: int, seed_v: int) -> void:
	_w = w
	_h = h
	_rng.seed = seed_v
	_build_far(seed_v)
	_build_near(kinds)


func _build_far(seed_v: int) -> void:
	var fw := _w + FAR_MARGIN.x * 2
	var fh := _h + FAR_MARGIN.y * 2
	var img := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = seed_v
	grain.frequency = 0.35
	var blotch := FastNoiseLite.new()
	blotch.seed = seed_v + 1
	blotch.frequency = 0.045
	for y in fh:
		for x in fw:
			var g := grain.get_noise_2d(x, y) * 0.035
			var b := blotch.get_noise_2d(x, y) * 0.03
			var c := FAR_BASE + Color(g + b, g + b, g + b * 1.3, 0.0)
			img.set_pixel(x, y, c)
	_far_tex = ImageTexture.create_from_image(img)
	_far.texture = _far_tex


# Dripstone silhouettes: cones hung from ceiling cells (air with solid
# above) and raised from floor cells, a few columns apart, where the
# air is tall enough that they do not fill it.
func _build_near(kinds: PackedByteArray) -> void:
	var img := Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x := 3
	# No cell map (the generated cave): no near layer.
	while kinds.size() >= _w * _h and x < _w - 3:
		var y := 1
		while y < _h - 1:
			var air := _is_air(kinds, x, y)
			if air and not _is_air(kinds, x, y - 1) and _rng.randf() < NEAR_CHANCE_CEIL:
				var span := _air_span(kinds, x, y, 1)
				if span >= 10:
					_cone(img, x, y, mini(_rng.randi_range(3, 7), span / 3), _rng.randi_range(1, 3), 1)
			if air and not _is_air(kinds, x, y + 1) and _rng.randf() < NEAR_CHANCE_FLOOR:
				var span := _air_span(kinds, x, y, -1)
				if span >= 10:
					_cone(img, x, y, mini(_rng.randi_range(2, 5), span / 3), _rng.randi_range(1, 2), -1)
			y += 1
		x += NEAR_STEP
	_near_tex = ImageTexture.create_from_image(img)
	_near.texture = _near_tex


func _is_air(kinds: PackedByteArray, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return false
	return kinds[y * _w + x] == 0


func _air_span(kinds: PackedByteArray, x: int, y: int, dir: int) -> int:
	var n := 0
	while _is_air(kinds, x, y + dir * n) and n < 64:
		n += 1
	return n


func _cone(img: Image, x: int, y: int, h: int, half_w: int, dir: int) -> void:
	for r in h:
		var t := float(r) / maxf(h - 1, 1)
		var hw := int(round(half_w * (1.0 - t)))
		for dx in range(-hw, hw + 1):
			var px := x + dx
			var py := y + dir * r
			if px >= 0 and px < _w and py >= 0 and py < _h:
				img.set_pixel(px, py, NEAR_COLOR)


# Each layer's place for this camera position, on the camera's grid.
func follow(cam: Vector2) -> void:
	var centre := Vector2(_w, _h) * CELL * 0.5
	var far_pos := -Vector2(FAR_MARGIN) * CELL + (cam - centre) * FAR
	_far.position = (far_pos / _grid).round() * _grid
	var near_pos := (cam - centre) * (1.0 - NEAR)
	_near.position = (near_pos / _grid).round() * _grid
