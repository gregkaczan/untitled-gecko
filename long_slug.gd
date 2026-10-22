# A long slug: a chain of blobs that creeps along the cave's surfaces by
# peristalsis. A wave of swelling runs along it from the tail to the
# head; the head moves only while the wave passes it, so the slug goes
# in slow surges, and the body lies along the track the head left, so
# it follows every bump of the rock. It turns back where it is blocked,
# the tail leading from then on, and now and then on its own. A tongue
# tip that touches it makes it flinch: it bunches up, glows brighter
# for a moment and turns away. Too big to swallow. Drawn by the blob
# layer with the gecko's own blobs (gecko.gd extra_blobs), and a faint
# glow at its middle (the sim's light pass).
extends RefCounted

const LINK := 3.6              # px between body points
const SPEED := 7.0             # Mean px/s along the surface
const RIDE := 3.8              # Head centre over the surface
const REACH := 12.0            # How far the head feels for a surface
const SETTLE := 1.5            # Most the head moves toward its ride height a tick
const PULSE := 2.4             # rad/s of the wave
const WAVE := 0.55             # rad of the wave between neighbouring points
const SWELL := 0.24            # Of a point's radius the wave adds
const TURN_MIN := 8.0
const TURN_MAX := 20.0
const GRAVITY := 900.0
const FLINCH_T := 1.2          # s of a flinch
const CATCH_R := 6.0           # The tongue tip this near a point is a touch
const COLOR := Color(0.86, 0.62, 0.74)
const GLOW := Color(0.75, 0.45, 0.7)

var map: Node2D
var radii := PackedFloat32Array()
var points := PackedVector2Array()
var head := Vector2.ZERO
var up := Vector2.UP
var dir := 1.0
var phase := 0.0
var clinging := false
var flinch := 0.0
var travelled := 0.0           # px the head has crept (the test reads it)
var _track := PackedVector2Array()   # The head's places, newest last, LINK / 2 apart
var _vel := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _turn_t := 10.0


func setup(map_in: Node2D, at: Vector2, length: float, seed_v: int) -> void:
	map = map_in
	head = at
	_rng.seed = seed_v
	dir = 1.0 if _rng.randf() < 0.5 else -1.0
	phase = _rng.randf() * TAU
	_turn_t = _rng.randf_range(TURN_MIN, TURN_MAX)
	var n := clampi(int(length / LINK), 6, 40)
	radii.resize(n)
	points.resize(n)
	for i in n:
		# Fullest a third of the way back, tapering to the tail.
		var t := float(i) / (n - 1)
		radii[i] = lerpf(2.6, 3.8, minf(t * 3.0, 1.0)) if t < 0.33 else lerpf(3.8, 1.5, (t - 0.33) / 0.67)
	# Settled on the surface nearest at, its body laid back along the
	# surface: the head crawls the body's length the other way first,
	# leaving the track, and is put back at the start of it.
	var q: Dictionary = map.nearest_solid(at, REACH * 3.0)
	if q.found and at.distance_to(q.nearest) > 0.01:
		up = (at - q.nearest).normalized()
		head = q.nearest + up * RIDE
	var start := head
	var back: Array = [head]
	dir = -dir
	var k := 0
	while k < n * 2 + 2:
		if _crawl(LINK * 0.5):
			back.append(head)
		k += 1
	dir = -dir
	_track.clear()
	for i in range(back.size() - 1, -1, -1):
		_track.append(back[i])
	head = start
	_lay()


# The head along the surface by dist px, the way it faces; false when
# blocked or off the surface (setup's lay of the body).
func _crawl(dist: float) -> bool:
	var q: Dictionary = map.nearest_solid(head, REACH)
	if not q.found:
		return false
	var nrm: Vector2 = (head - q.nearest).normalized() if head.distance_to(q.nearest) > 0.01 else up
	up = up.lerp(nrm, 0.5).normalized() if up.dot(nrm) > -0.5 else nrm
	head = q.nearest + up * RIDE
	var next := head + Vector2(-up.y, up.x) * dir * dist
	if map.solid_within(next, 2.0):
		return false
	head = next
	return true


func tick(dt: float, gecko: Node2D) -> void:
	flinch = maxf(flinch - dt, 0.0)
	phase += dt * PULSE * (3.0 if flinch > 0.0 else 1.0)
	if gecko.tongue_out and not gecko.tongue_anchored and flinch <= 0.0:
		for p in points:
			if gecko.tongue_tip.distance_to(p) <= CATCH_R:
				flinch = FLINCH_T
				gecko.release_tongue()
				_turn()
				break
	var p: Dictionary = map.nearest_solid(head, REACH)
	if p.found:
		var n: Vector2 = (head - p.nearest).normalized() if head.distance_to(p.nearest) > 0.01 else up
		if not clinging:
			clinging = true
			_vel = Vector2.ZERO
		up = up.lerp(n, 0.25).normalized() if up.dot(n) > -0.5 else n
		var want: Vector2 = p.nearest + up * RIDE
		head += (want - head).limit_length(SETTLE)
		_turn_t -= dt
		if _turn_t <= 0.0:
			_turn()
		# The head surges while the wave passes it.
		var surge := maxf(sin(phase), 0.0)
		var spd := SPEED * 2.4 * surge * surge * (0.0 if flinch > 0.0 else 1.0)
		var tangent := Vector2(-up.y, up.x) * dir
		var next := head + tangent * spd * dt
		if map.solid_within(next, 2.0):
			_turn()
		else:
			travelled += head.distance_to(next)
			head = next
	else:
		clinging = false
		_vel.y += GRAVITY * dt
		var next := head + _vel * dt
		if map.solid_within(next, 2.0):
			_vel = Vector2.ZERO
		else:
			head = next
	if _track.is_empty() or head.distance_to(_track[_track.size() - 1]) >= LINK * 0.5:
		_track.append(head)
		var keep := points.size() * 2 + 4
		if _track.size() > keep:
			_track = _track.slice(_track.size() - keep)
	_lay()


# Turns back: the tail leads from here, so the track and the body are
# reversed rather than the head swung round through the body.
func _turn() -> void:
	dir = -dir
	_turn_t = _rng.randf_range(TURN_MIN, TURN_MAX)
	if points.size() > 1:
		var tr := PackedVector2Array()
		for i in range(points.size() - 1, -1, -1):
			tr.append(points[i])
		_track = tr
		head = points[points.size() - 1]
		var r := radii.duplicate()
		for i in r.size():
			radii[i] = r[r.size() - 1 - i]


# The body along the head's track, a link apart from the head back.
func _lay() -> void:
	points[0] = head
	var i := 1
	var want := LINK
	var acc := 0.0
	var k := _track.size() - 1
	var from := head
	while i < points.size() and k >= 0:
		var to := _track[k]
		var d := from.distance_to(to)
		if acc + d >= want and d > 0.0001:
			var t := (want - acc) / d
			from = from.lerp(to, t)
			points[i] = from
			i += 1
			acc = 0.0
			continue
		acc += d
		from = to
		k -= 1
	while i < points.size():
		points[i] = points[i - 1]
		i += 1


func radius_at(i: int) -> float:
	var r := radii[i] * (1.0 + SWELL * maxf(sin(phase - i * WAVE), 0.0))
	return r * (0.8 if flinch > 0.0 else 1.0)


func blobs() -> Array:
	var out: Array = []
	for i in points.size():
		out.append([points[i] + up * 0.4, radius_at(i), COLOR.lightened(0.1 * maxf(sin(phase - i * WAVE), 0.0))])
	return out


func glow() -> Array:
	var k := 0.55 + 0.15 * sin(phase) + (0.4 if flinch > 0.0 else 0.0)
	return [points[points.size() / 3], GLOW * k, 10.0]
