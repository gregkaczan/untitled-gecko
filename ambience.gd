# The cave's small life, from the sim's own particles: drops falling
# from the ceiling over pools (and their sound as they land), a puff of
# dust where a bite lands, bubbles while the gecko swims. The bitmap
# world has no particles, so there only the drip sound remains.
extends Node2D

const DRIP_GAP_MIN := 1.5      # s between drips
const DRIP_GAP_MAX := 5.0
const DRIP_FALL_G := 900.0     # The sim's gravity, for the drop's fall time
const SURFACE_SCAN := 8.0      # s between scans of the map for water surfaces (a few thousand cells, every fourth)
const DUST_N := 3              # Wisps a bite throws up
const DUST_LIFE := 0.003       # About 40 ticks of smoke
const BUBBLE_CHANCE := 0.1     # Per tick while swimming
const BUBBLE_LIFE := 0.002

var _map: Node2D
var _gecko: Node2D
var _sound: Node2D
var _surfaces: PackedVector2Array = []   # World points on water surfaces (cell centres)
var _scan_t := 0.0
var _drip_t := 2.0
var _pending: Array = []       # [time left, position] drip sounds waiting for their drop to land
var _rng := RandomNumberGenerator.new()


func setup(map: Node2D, gecko: Node2D, sound: Node2D) -> void:
	_map = map
	_gecko = gecko
	_sound = sound
	_rng.seed = 11
	gecko.bit.connect(_on_bite)


# The map changed (a scene built): forget the surfaces, scan again soon.
func reset() -> void:
	_surfaces = []
	_scan_t = 0.0
	_pending.clear()
	_drip_t = _rng.randf_range(1.0, 2.5)


func _physics_process(dt: float) -> void:
	if _map == null:
		return
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan()
		_scan_t = SURFACE_SCAN
	_drip_t -= dt
	if _drip_t <= 0.0:
		_drip_t = _rng.randf_range(DRIP_GAP_MIN, DRIP_GAP_MAX)
		_drip()
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i][0] -= dt
		if _pending[i][0] <= 0.0:
			_sound.play("drip", _pending[i][1], _sound.DRIP_DB, 0.8, 1.3)
			_pending.remove_at(i)
	if _gecko.swimming and _rng.randf() < BUBBLE_CHANCE:
		_map.spawn_puff(_gecko.chain.head() + Vector2(0.0, -2.0), 1, Vector2(0.0, -20.0), 8.0, BUBBLE_LIFE)


# Water cells with air above them, every fourth cell each way.
func _scan() -> void:
	var out := PackedVector2Array()
	var W: int = _map.W
	var H: int = _map.H
	var cell: float = _map.CELL
	var y := 4
	while y < H:
		var x := 2
		while x < W:
			if _map.is_water(x, y) and not _map.is_water(x, y - 1) and not _map.is_solid(x, y - 1):
				out.append(Vector2((x + 0.5) * cell, y * cell))
			x += 4
		y += 4
	_surfaces = out


# A drop from the ceiling over a random surface point; its sound when it lands.
func _drip() -> void:
	if _surfaces.is_empty():
		return
	var at: Vector2 = _surfaces[_rng.randi_range(0, _surfaces.size() - 1)]
	var ceiling = _map.ray_hit(at + Vector2(0.0, -2.0), Vector2.UP, 600.0)
	if ceiling == null:
		return
	var h: float = at.y - ceiling.y
	if h < 24.0:
		return
	_map.spawn_drop(Vector2(at.x, ceiling.y + 3.0))
	_pending.append([sqrt(2.0 * h / DRIP_FALL_G), at])


func _on_bite(at: Vector2) -> void:
	_map.spawn_puff(at, DUST_N, Vector2(0.0, -10.0), 25.0, DUST_LIFE)
