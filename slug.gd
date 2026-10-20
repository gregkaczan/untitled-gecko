# A glow slug: a small luminous creature that creeps along the cave's
# surfaces, a light in the dark, and food. It follows the nearest
# surface within reach at a fixed height, crawls along it, turns back
# where it is blocked and now and then on its own, and falls when it
# loses the surface. The gecko's tongue tip touching it catches it: it
# rides the tip back to the mouth and is swallowed, which brightens
# the gecko's own glow for a while (main.gd). Drawn by the blob layer
# as three blobs the gecko adds to its own (gecko.gd extra_blobs), lit
# by the sim's light pass as a glow source.
extends Node2D

const SPEED := 12.0            # px/s along the surface
const RIDE := 4.0              # Body centre over the surface
const REACH := 14.0            # How far it feels for a surface
const SETTLE := 2.0            # Most it moves toward its ride height in a tick
const TURN_GAP_MIN := 2.0      # s between turns of its own
const TURN_GAP_MAX := 7.0
const GRAVITY := 900.0
const CATCH_R := 7.0           # The tongue tip this close catches it
const COLOR := Color(0.72, 0.95, 0.42)
const GLOW := Color(0.45, 0.9, 0.4)
const GLOW_R := 10.0
const RADII := [3.6, 3.2, 2.6]

var pos := Vector2.ZERO
var up := Vector2.UP
var dir := 1.0
var vel := Vector2.ZERO
var clinging := false
var caught := false
var eaten := false
var _map: Node2D
var _turn_t := 3.0
var _rng := RandomNumberGenerator.new()
var _pulse := 0.0


func setup(map: Node2D, at: Vector2, seed_v: int) -> void:
	_map = map
	pos = at
	_rng.seed = seed_v
	_turn_t = _rng.randf_range(TURN_GAP_MIN, TURN_GAP_MAX)
	_pulse = _rng.randf() * TAU


func tick(dt: float, gecko: Node2D) -> void:
	_pulse += dt * 1.7
	if caught:
		# On the tongue: ride the tip; at the mouth, eaten.
		if gecko.tongue_out:
			pos = gecko.tongue_tip
		else:
			eaten = true
		return
	if gecko.tongue_out and not gecko.tongue_anchored and gecko.tongue_tip.distance_to(pos) <= CATCH_R:
		caught = true
		gecko.release_tongue()
		return
	var p: Dictionary = _map.probe(pos, REACH)
	if p.found:
		var n: Vector2 = p.normal if p.normal != Vector2.ZERO else (pos - p.nearest).normalized()
		if not clinging:
			clinging = true
			vel = Vector2.ZERO
		up = up.lerp(n, 0.3).normalized() if up.dot(n) > -0.5 else n
		var want: Vector2 = p.nearest + up * RIDE
		pos += (want - pos).limit_length(SETTLE)
		_turn_t -= dt
		if _turn_t <= 0.0:
			_turn_t = _rng.randf_range(TURN_GAP_MIN, TURN_GAP_MAX)
			dir = -dir
		var tangent := Vector2(-up.y, up.x) * dir
		var next := pos + tangent * SPEED * dt
		if _map.solid_within(next, 2.5):
			dir = -dir
		else:
			pos = next
	else:
		clinging = false
		vel.y += GRAVITY * dt
		var next := pos + vel * dt
		if _map.solid_within(next, 2.5):
			vel = Vector2.ZERO
		else:
			pos = next


# Its three blobs, head first along its way.
func blobs() -> Array:
	var tangent := Vector2(-up.y, up.x) * dir
	var out: Array = []
	for i in RADII.size():
		out.append([pos - tangent * (i * 3.2) + up * 0.5, RADII[i], COLOR])
	return out


func glow() -> Array:
	var k := 0.85 + 0.15 * sin(_pulse)
	return [pos, GLOW * k, GLOW_R]
