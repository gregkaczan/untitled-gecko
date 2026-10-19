# Gecko: the player body for the movement spike. A chain body hovers at
# ride height over the cave bitmap and four feet hold anchors on it. The
# gecko clings while a surface is in reach and at least MIN_FEET feet are
# planted; otherwise it falls under gravity until it meets a surface again,
# at any angle. Input is projected onto the surface tangent, so the key
# pressed always moves the gecko that way on screen: right on the ceiling
# walks right, up on a wall climbs. Jump pushes away along the normal.
#
# Legs are two pairs, front (shoulder) and back (hip), each with a near
# foot drawn over the body and a far foot drawn behind it. Feet step in a
# trot: a foot whose diagonal partner is mid-step lifts early, a foot whose
# same-end partner is mid-step waits, so two feet stay planted.
extends Node2D

const Chain = preload("res://chain.gd")

const WALK_SPEED := 150.0
const WALK_ACCEL := 1600.0
const RIDE_H := 16.0           # Body centre height above the nearest solid
const BODY_R := 9.0            # Clearance the body centre always keeps from rock
const CHEW_R := 13.0           # Radius of one bite
const CHEW_REACH := 19.0       # Bite centre distance ahead of the body centre
const PROBE_R := 32.0          # Reach of the body's surface search
const SURF_TURN := 14.0        # Up vector turn rate toward the surface normal (rad/s)
const LOSE_SURFACE_D := 26.0   # Nearest solid farther than this = nothing to hold
const RAY_HALF := 12.0         # Half the span between the two surface rays
const RAY_LEN := 34.0          # How far down each surface ray looks
const JUMP_SPEED := 340.0
const GRAVITY := 900.0
const AIR_ACCEL := 600.0
const AIR_MAX := 220.0
const NO_CLING_TIME := 0.18    # Grace after a jump or a drop before clinging again
const FEET_GRACE := 0.2        # Time with too few feet planted before dropping
const MIN_FEET := 2
const HEAD_LEAD := 15.0        # Head sits this far ahead of the body centre
const HEAD_SPEED := 420.0      # How fast the head swings round on a turn
const RADII := [7.0, 8.5, 8.5, 7.5, 5.5, 3.5, 2.5]
const LINK := 8.0
const MAX_BEND := 1.0
const BODY_HUG := 20.0         # How far past its radius a chain point looks for the surface
const HUG_RATE := 12.0         # Pull rate of trailing points onto the surface (1/s)
const FRONT_HIP := 1
const BACK_HIP := 3
const FOOT_SPREAD := 11.0      # Foot rest distance from its hip along the tangent
const FOOT_LEAD := 12.0        # Extra rest offset in the walking direction at full speed
const LEG_REACH := 24.0        # Farthest a foot searches for an anchor from its rest spot
const MAX_LEG := 28.0          # Hip to anchor distance that forces a planted foot to let go
const STEP_LEN := 11.0         # Anchor drift from the rest spot that triggers a step
const STEP_TIME := 0.08
const STEP_HEIGHT := 5.0
const BODY_COLOR := Color(0.56, 0.63, 0.40)
const LEG_COLOR := Color(0.42, 0.48, 0.29)
const FAR_LEG_COLOR := Color(0.27, 0.32, 0.19)


class Foot:
	var hip := 1              # Chain point the leg hangs from
	var end := 1.0            # +1 front, -1 back
	var side := 1.0           # +1 near (drawn over the body), -1 far
	var planted := false
	var anchor := Vector2.ZERO
	var pos := Vector2.ZERO
	var stepping := false
	var step_from := Vector2.ZERO
	var step_to := Vector2.ZERO
	var step_t := 0.0


var map: Node2D
var blobs: Node2D
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var up := Vector2.UP
var facing := 1.0
var speed_along := 0.0
var clinging := false
var no_cling := 0.0
var feet_short := 0.0
var chain: Chain
var feet: Array[Foot] = []
var input_override = null      # Vector2 from the demo pilot, null for real input
var jump_override := false
var chew_override := false
var chewing := false
var _bite := Vector2.ZERO
var debug := true

var _far: Node2D
var _debug_layer: Node2D
var _last_probe := {}
var _tick := 0
var _trace := OS.get_environment("GECKO_TRACE") != ""


func _ready() -> void:
	z_index = 6
	chain = Chain.new(Vector2.ZERO, RADII, LINK, MAX_BEND)
	for end in [1.0, -1.0]:
		for side in [1.0, -1.0]:
			var f := Foot.new()
			f.hip = FRONT_HIP if end > 0.0 else BACK_HIP
			f.end = end
			f.side = side
			feet.append(f)
	_far = Node2D.new()
	_far.z_index = -2
	_far.draw.connect(_draw_legs.bind(-1.0))
	add_child(_far)
	_debug_layer = Node2D.new()
	_debug_layer.z_index = 14
	_debug_layer.draw.connect(_draw_debug)
	add_child(_debug_layer)


func spawn(at: Vector2) -> void:
	pos = at
	vel = Vector2.ZERO
	up = Vector2.UP
	facing = 1.0
	speed_along = 0.0
	clinging = true
	no_cling = 0.0
	feet_short = 0.0
	chain.reset(pos + Vector2.RIGHT * HEAD_LEAD, Vector2.RIGHT)
	for f in feet:
		f.planted = false
		f.stepping = false
		f.pos = chain.points[f.hip]


func _physics_process(dt: float) -> void:
	var inp := _read_input()
	var jump := _read_jump()
	chewing = _read_chew()
	no_cling = maxf(no_cling - dt, 0.0)
	if chewing:
		_chew(inp)
	if clinging:
		_update_clinging(inp, jump, dt)
	else:
		_update_airborne(inp, dt)
	_update_chain(dt)
	_update_feet(dt)
	_tick += 1
	if _trace:
		var hd := chain.head()
		print("t%d pos(%.0f,%.0f) head(%.0f,%.0f) hip(%.0f,%.0f) up(%.2f,%.2f) dist %.1f spd %.0f %s" % [
			_tick, pos.x, pos.y, hd.x, hd.y, chain.points[FRONT_HIP].x, chain.points[FRONT_HIP].y,
			up.x, up.y, _last_probe.get("dist", -1.0), speed_along, "cling" if clinging else "air"])
	_push_blobs()
	queue_redraw()
	_far.queue_redraw()
	_debug_layer.queue_redraw()


func _read_input() -> Vector2:
	if input_override != null:
		return input_override
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _read_jump() -> bool:
	if input_override != null:
		var j := jump_override
		jump_override = false
		return j
	return Input.is_action_just_pressed("jump")


func _read_chew() -> bool:
	if input_override != null:
		return chew_override
	return Input.is_action_pressed("chew")


# One bite ahead of the body in the input direction (screen space, so
# right digs level and down digs down), or straight ahead with no input.
# Its height is anchored to the row the gecko stands on, within reach of
# the body's own level, so a level tunnel keeps its floor and the body
# always fits through the hole it chews.
func _chew(inp: Vector2) -> void:
	var dir: Vector2 = inp.normalized() if inp.length() > 0.2 else _tangent() * facing
	var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
	var base: Vector2 = floor_pt if floor_pt != null else pos - up * RIDE_H
	var play := CHEW_R - BODY_R - 1.0
	var h := clampf((base + up * (CHEW_R + 3.0) - pos).dot(up), -play, play)
	_bite = pos + up * h + dir * CHEW_REACH
	map.erase_circle(_bite, CHEW_R)


func _tangent() -> Vector2:
	return Vector2(-up.y, up.x)


func _update_clinging(inp: Vector2, jump: bool, dt: float) -> void:
	var tangent := _tangent()
	var s := 0.0
	if inp.length() > 0.2:
		s = clampf(inp.dot(tangent) * sqrt(2.0), -1.0, 1.0)
	if absf(s) > 0.3:
		facing = signf(s)
	speed_along = move_toward(speed_along, s * WALK_SPEED, WALK_ACCEL * dt)
	var blocked := not _move(tangent * speed_along * dt)
	if blocked:
		speed_along = 0.0
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	if not p.found or p.dist > LOSE_SURFACE_D:
		_drop()
		return
	# Blocked by rock ahead: turn up toward that rock's normal, so walking
	# into a wall ends standing on the wall, and up means climb. Chewing
	# through it instead, the gecko holds still and waits for the hole.
	var n: Vector2
	if blocked and chewing:
		n = Vector2.ZERO
	elif blocked:
		n = _obstacle_normal(p)
	else:
		n = _surface_normal(p)
	if n != Vector2.ZERO:
		up = _turn_toward(up, n, SURF_TURN * dt)
	# Ride-height nudge, away from (or toward) the nearest rock rather
	# than along up, so a body squeezed against a side wall can get clear.
	var away: Vector2 = (pos - p.nearest).normalized() if p.dist > 0.01 else up
	_move(away * (RIDE_H - p.dist) * minf(1.0, 20.0 * dt))
	if jump:
		_jump()
		return
	var planted := 0
	for f in feet:
		if f.planted:
			planted += 1
	if planted < MIN_FEET:
		feet_short += dt
	else:
		feet_short = 0.0
	if feet_short > FEET_GRACE:
		_drop()


func _update_airborne(inp: Vector2, dt: float) -> void:
	vel.y += GRAVITY * dt
	if absf(inp.x) > 0.2:
		vel.x = move_toward(vel.x, inp.x * AIR_MAX, AIR_ACCEL * dt)
	var blocked := not _move(vel * dt)
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	if not p.found:
		return
	var n: Vector2 = p.normal
	if n == Vector2.ZERO:
		n = (pos - p.nearest).normalized()
	if blocked:
		var into := vel.dot(n)
		if into < 0.0:
			vel -= n * into
	if no_cling <= 0.0 and p.dist <= RIDE_H + 2.0 and vel.dot(n) <= 0.0:
		_land(n)
		return
	var min_d := RIDE_H * 0.8
	if p.dist < min_d:
		pos += n * (min_d - p.dist)
		var vn := vel.dot(n)
		if vn < 0.0:
			vel -= n * vn


func _land(n: Vector2) -> void:
	clinging = true
	up = n
	speed_along = clampf(vel.dot(_tangent()), -WALK_SPEED, WALK_SPEED)
	if absf(speed_along) > 1.0:
		facing = signf(speed_along)
	vel = Vector2.ZERO
	feet_short = 0.0


func _drop() -> void:
	clinging = false
	vel = _tangent() * speed_along
	speed_along = 0.0
	no_cling = NO_CLING_TIME
	_unplant()


func _jump() -> void:
	clinging = false
	vel = up * JUMP_SPEED + _tangent() * speed_along
	speed_along = 0.0
	no_cling = NO_CLING_TIME
	_unplant()


func _unplant() -> void:
	for f in feet:
		f.planted = false
		f.stepping = false


# Moves pos by delta in 1 px sub-steps and stops at the first step that
# would bring the body centre within BODY_R of rock. Stuck beats
# tunnelling: the gecko never passes through ground. A body already
# inside rock (buried by the brush) is let move so it can be pushed out.
func _move(delta: Vector2) -> bool:
	var length := delta.length()
	if length < 0.001:
		return true
	if map.solid_within(pos, BODY_R):
		pos += delta
		return true
	var dir := delta / length
	var moved := 0.0
	while moved < length:
		var step := minf(1.0, length - moved)
		var next: Vector2 = pos + dir * step
		if map.solid_within(next, BODY_R):
			return false
		pos = next
		moved += step
	return true


# Normal of the rock that blocked the move: away from the nearest solid.
# An overhang leaning back over the body (more than about 100 degrees
# from up) is not climbed into; the gecko just stops there.
func _obstacle_normal(p: Dictionary) -> Vector2:
	var n: Vector2 = (pos - p.nearest).normalized()
	if n.dot(up) < -0.2:
		return Vector2.ZERO
	return n


# Surface normal from two rays cast down from ahead of and behind the
# body: the slope between their hits, so a bump beside the gecko does not
# tilt it. Falls back to the probe's centroid normal when a ray misses or
# starts inside rock, which happens at corners, where the centroid is
# what swings the gecko round smoothly.
func _surface_normal(p: Dictionary) -> Vector2:
	var t := _tangent()
	var sa := pos + t * RAY_HALF
	var sb := pos - t * RAY_HALF
	var a = map.ray_hit(sa, -up, RAY_LEN)
	var b = map.ray_hit(sb, -up, RAY_LEN)
	if a != null and a.distance_to(sa) < 1.0:
		a = null
	if b != null and b.distance_to(sb) < 1.0:
		b = null
	if a != null and b != null:
		var along: Vector2 = a - b
		if along.length() > 1.0:
			var n := Vector2(along.y, -along.x).normalized()
			if n.dot(up) < 0.0:
				n = -n
			return n
	return p.normal


static func _turn_toward(a: Vector2, b: Vector2, max_angle: float) -> Vector2:
	var ang := a.angle_to(b)
	return a.rotated(clampf(ang, -max_angle, max_angle)).normalized()


# The head leads the chain. Clinging, it sits ahead of the body centre in
# the facing direction, and slides round to the other side on a turn so
# the body folds into a U behind it. Airborne, it points along the
# velocity. Chain points that end up inside rock get pushed out.
func _update_chain(dt: float) -> void:
	var target: Vector2
	if clinging:
		target = pos + _tangent() * facing * HEAD_LEAD
	else:
		var dir := vel.normalized() if vel.length() > 20.0 else Vector2(facing, 0.0)
		target = pos + dir * HEAD_LEAD
	var head := chain.head()
	var to := target - head
	var dir := Vector2.ZERO
	var new_head := head
	if to.length() > 0.001:
		new_head = head + to.normalized() * minf(to.length(), HEAD_SPEED * dt)
	if to.length() > 2.0:
		dir = to.normalized()
	elif clinging:
		dir = _tangent() * facing
	chain.set_head(new_head, dir)
	# Points inside rock get pushed out. Clinging, trailing points also get
	# pulled onto the surface, so the body hugs a wall it is climbing
	# instead of hanging in the air along the path the head took.
	for i in chain.size():
		var r: float = chain.radii[i]
		var q: Dictionary = map.probe(chain.points[i], r + BODY_HUG)
		if not q.found:
			continue
		var away: Vector2 = (chain.points[i] - q.nearest).normalized() if q.dist > 0.01 else up
		var want := r + 2.0
		if q.dist < want:
			chain.points[i] += away * (want - q.dist)
		elif clinging and i > 0:
			chain.points[i] += away * (want - q.dist) * minf(1.0, HUG_RATE * dt)


func _partner(f: Foot) -> Foot:
	for g in feet:
		if g.end == f.end and g.side != f.side:
			return g
	return f


func _diagonal(f: Foot) -> Foot:
	for g in feet:
		if g.end != f.end and g.side != f.side:
			return g
	return f


func _update_feet(dt: float) -> void:
	var tangent := _tangent()
	var stepping := 0
	for f in feet:
		if f.stepping:
			stepping += 1
	for f in feet:
		var hip: Vector2 = chain.points[f.hip]
		if f.stepping:
			f.step_t += dt / STEP_TIME
			if f.step_t >= 1.0:
				f.stepping = false
				f.planted = true
				f.anchor = f.step_to
				f.pos = f.anchor
			else:
				f.pos = f.step_from.lerp(f.step_to, f.step_t) + up * STEP_HEIGHT * sin(PI * f.step_t)
			continue
		if f.planted:
			if map.solid_near(f.anchor, 1) and f.anchor.distance_to(hip) < MAX_LEG:
				f.pos = f.anchor
			else:
				f.planted = false
		if not clinging:
			f.planted = false
			var hang := hip + Vector2(f.end * facing * 5.0, 9.0)
			f.pos = f.pos.lerp(hang, minf(1.0, 12.0 * dt))
			continue
		var lead := speed_along / WALK_SPEED * FOOT_LEAD
		var rest := hip + tangent * (f.end * facing * FOOT_SPREAD + lead) - up * RIDE_H
		var q: Dictionary = map.probe(rest, LEG_REACH)
		if q.found and q.nearest.distance_to(hip) > MAX_LEG:
			q.found = false
		if not q.found:
			if not f.planted:
				f.pos = f.pos.lerp(rest, minf(1.0, 12.0 * dt))
			continue
		var threshold := STEP_LEN * (0.5 if _diagonal(f).stepping else 1.0)
		if f.planted and f.anchor.distance_to(q.nearest) <= threshold:
			continue
		if _partner(f).stepping:
			continue
		if f.planted and stepping >= 2:
			continue
		f.stepping = true
		f.planted = false
		f.step_from = f.pos
		f.step_to = q.nearest
		f.step_t = 0.0
		stepping += 1


func _push_blobs() -> void:
	var list: Array = []
	for i in chain.size():
		list.append([chain.points[i], chain.radii[i], BODY_COLOR])
	blobs.set_blobs(list)


func _draw() -> void:
	_draw_legs(1.0)
	var head: Vector2 = chain.points[0]
	var eye := head + chain.heading * 3.0 + up * 3.5
	draw_circle(eye, 2.2, Color(0.08, 0.07, 0.06))
	draw_circle(eye + chain.heading * 0.7, 0.9, Color(0.95, 0.95, 0.9))
	if chewing:
		draw_arc(_bite, CHEW_R, 0.0, TAU, 20, Color(1.0, 0.8, 0.5, 0.6), 1.5)


func _draw_legs(side: float) -> void:
	var canvas: CanvasItem = self if side > 0.0 else _far
	var col := LEG_COLOR if side > 0.0 else FAR_LEG_COLOR
	var width := 3.0 if side > 0.0 else 2.5
	var tangent := _tangent()
	for f in feet:
		if f.side != side:
			continue
		var hip: Vector2 = chain.points[f.hip] + up * (2.0 if side < 0.0 else -1.0)
		var foot := f.pos + (up * 1.5 if f.planted else Vector2.ZERO)
		var knee := (hip + foot) * 0.5 + up * 4.0 - tangent * f.end * facing * 2.0
		canvas.draw_line(hip, knee, col, width)
		canvas.draw_line(knee, foot, col, width)
		canvas.draw_circle(foot, width * 0.7, col)


func _draw_debug() -> void:
	if not debug:
		return
	var c := _debug_layer
	c.draw_line(pos, pos + up * 30.0, Color(0.3, 0.9, 1.0), 1.5)
	c.draw_arc(pos, PROBE_R, 0.0, TAU, 32, Color(0.3, 0.9, 1.0, 0.25), 1.0)
	if _last_probe.get("found", false):
		c.draw_circle(_last_probe.nearest, 2.5, Color(1.0, 0.5, 0.2))
	for f in feet:
		var col := Color(0.2, 1.0, 0.3) if f.planted else (Color(1.0, 0.9, 0.2) if f.stepping else Color(1.0, 0.2, 0.2))
		c.draw_rect(Rect2(f.pos - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), col, false, 1.0)


func debug_text() -> String:
	var planted := 0
	for f in feet:
		if f.planted:
			planted += 1
	return "%s%s  feet %d/4  up (%.2f, %.2f)  speed %.0f  vel (%.0f, %.0f)" % [
		"cling" if clinging else "air", " chew" if chewing else "", planted, up.x, up.y, speed_along, vel.x, vel.y]
