# A slime: a blob of material 14 in the sim, a thick liquid that holds
# to itself (pbd_delta.glsl), with a brain here that keeps it one
# creature. Each tick the brain reads where its mass is (the sim sums
# the particles within its reach, sim.gd slime_mass), sets its centre a
# little ahead of that, the way it creeps, and the sim draws the
# particles in reach toward the centre and along the creep. The blob
# rolls slowly along the floor, turns back where it stalls and now and
# then on its own. A piece bitten or struck out of its reach is left an
# inert puddle; one splashed inside the reach is drawn back in. The
# gecko wades through it slowly and jumps out of it weakly (gecko.gd).
# Too little left in reach and the slime is dead, all puddle.
extends RefCounted

const SPEED := 20.0            # px/s the creep draws its particles toward (the blob makes about a third of it)
const LEAD := 0.0              # px the centre sits ahead of the mass (the drift moves it; a lead pulls the whole blob on and runs away)
const PULL := 60.0             # px/s^2 per px toward the centre: enough, with the sim bearing most of its weight, to hold a mound (and wobble like jelly)
const REACH_K := 2.0           # The reach over the blob's own radius
const REACH_PAD := 8.0
const MIN_COUNT := 12          # Fewer in reach and the slime is dead
const TURN_MIN := 6.0          # s between turns of its own
const TURN_MAX := 14.0
const STALL_T := 2.0           # s without moving a px, and it turns back

var sim: Node2D
var brain := -1
var centre := Vector2.ZERO
var mass := 0
var mass0 := 0
var dir := 1.0
var alive := true
var reach := 20.0
var _rng := RandomNumberGenerator.new()
var _turn_t := 8.0
var _stall_t := 0.0
var _stall_at := Vector2.ZERO
var _age := 0                  # Ticks since the spawn: the mass is read back a tick late, so the first ticks judge nothing


func setup(sim_in: Node2D, at: Vector2, radius: float, brain_i: int, seed_v: int) -> bool:
	sim = sim_in
	brain = brain_i
	_rng.seed = seed_v
	dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_turn_t = _rng.randf_range(TURN_MIN, TURN_MAX)
	mass0 = sim.spawn_slime(at, radius)
	if mass0 == 0:
		return false
	mass = mass0
	centre = at
	_stall_at = at
	reach = radius * REACH_K + REACH_PAD
	sim.set_slime(brain, centre, reach, PULL, Vector2(dir, 0.0), SPEED, true)
	return true


func step(dt: float) -> void:
	if not alive:
		return
	_age += 1
	var m: Array = sim.slime_mass(brain)
	if _age < 3:
		return
	mass = m[0]
	if mass < MIN_COUNT:
		alive = false
		sim.set_slime(brain, centre, 0.0, 0.0, Vector2.ZERO, 0.0, false)
		return
	var at: Vector2 = m[1]
	_turn_t -= dt
	_stall_t += dt
	if at.distance_to(_stall_at) > 1.0:
		_stall_at = at
		_stall_t = 0.0
	if _turn_t <= 0.0 or _stall_t > STALL_T:
		dir = -dir
		_turn_t = _rng.randf_range(TURN_MIN, TURN_MAX)
		_stall_t = 0.0
		_stall_at = at
	reach = sqrt(float(mass) * 4.0 / PI) * REACH_K + REACH_PAD
	centre = at + Vector2(dir * LEAD, 0.0)
	sim.set_slime(brain, centre, reach, PULL, Vector2(dir, 0.0), SPEED, true)
