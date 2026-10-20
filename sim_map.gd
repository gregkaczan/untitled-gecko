# World queries over the particle sim's per-pixel cell classes, with the
# bitmap map's API, so the gecko does not know which world it stands on.
# The geometry helpers (probe, rays, clearance) are inherited; only the
# cell tests and the edits change. Edits go to the GPU: a melt capsule
# deletes particles, an explosion scatters them, a fill spawns them.
extends "res://cave_map.gd"

var sim: Node2D
var _slot := 0


func _ready() -> void:
	pass


func _process(_dt: float) -> void:
	pass


func generate(seed_value: int) -> void:
	sim.build(seed_value)
	sim.tick()


# Rebuilds the particles from a cell map (a test scene built on a CaveMap).
func build_cells(kinds: PackedByteArray) -> void:
	sim.build(0, kinds)
	sim.tick()


func _cls(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 2
	var c: PackedByteArray = sim.cells
	if c.size() < W * H * 4:
		return 0
	return c.decode_u32((y * W + x) * 4)


func is_solid(x: int, y: int) -> bool:
	var c := _cls(x, y)
	return c == 2 or c == 3


func is_water(x: int, y: int) -> bool:
	return _cls(x, y) == 1


# Chew and brush share four melt slots in turn, so several bites in one
# tick all land.
func erase_circle(p: Vector2, radius: float) -> void:
	sim.melt_circle(p, radius, _slot)
	_slot = (_slot + 1) % 4


func blast(p: Vector2, radius: float) -> void:
	sim.trigger_explosion_at(p, radius)


func fill_circle(p: Vector2, radius: float) -> void:
	sim.fill_circle(p, radius)


func fill_rect(r: Rect2) -> void:
	sim.fill_rect(r)
