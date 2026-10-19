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
# same-end partner is mid-step waits, so two feet stay planted. Body and
# legs are all metaballs in the blob layer, so the legs read as soft
# appendages of one slug-like body.
extends Node2D

const Chain = preload("res://chain.gd")

const WALK_SPEED := 130.0
const WALK_ACCEL := 1600.0
const RIDE_H := 16.0           # Body centre height above the nearest solid
const BODY_R := 9.0            # Clearance the body centre always keeps from rock
const CHEW_R := 11.0           # Mean radius of one bite; each bite varies around it
const CHEW_REACH := 19.0       # Bite centre distance ahead of the body centre
const PROBE_R := 32.0          # Reach of the body's surface search
const SURF_TURN := 14.0        # Up vector turn rate toward the surface normal (rad/s)
const LOSE_SURFACE_D := 26.0   # Nearest solid farther than this = nothing to hold
const RAY_HALF := 12.0         # Half the span between the two surface rays
const RAY_LEN := 34.0          # How far down each surface ray looks
const BRIDGE := 36.0           # A gap with ground this far ahead at the same level is crossed, not entered
const JUMP_SPEED := 340.0
const GRAVITY := 900.0
const AIR_ACCEL := 600.0
const AIR_MAX := 220.0
const NO_CLING_TIME := 0.18    # Grace after a jump or a drop before clinging again
const FEET_GRACE := 0.2        # Time with too few feet planted before dropping
const MIN_FEET := 2
const HEAD_LEAD := 15.0        # Head sits this far ahead of the body centre
const BOB_SMOOTH := 0.15       # Per-tick blend of the drawn body's across-surface bounce
const BOB_MAX := 12.0          # Largest across-surface lag the drawn body may carry
const HEAD_SPEED := 420.0      # How fast the head swings round on a turn
const RADII := [7.0, 8.5, 8.5, 7.5, 5.5, 4.0, 3.2, 2.6, 2.2, 1.9]
const LINK := 8.0
const MAX_BEND := 1.0
const BODY_GAP := 2.0          # Clearance a chain point keeps past its radius
const BODY_HUG := 20.0         # How far past its radius a chain point looks for the surface
const HUG_K := 0.5             # Fraction of the way a trailing point is pulled onto the surface per tick
const SNOUT := 4.0             # Snout blob offset ahead of the head along the look direction
const LOOK_LIMIT := 1.8        # Radians the head can turn off the body line to look at the mouse
const FRONT_HIP := 1
const BACK_HIP := 3
const FOOT_SPREAD := 11.0      # Foot rest distance from its hip along the tangent
const FOOT_LEAD := 10.0        # Extra rest offset in the walking direction at full speed
const LEG_REACH := 16.0        # Farthest a foot searches for an anchor from its rest spot
const MAX_LEG := 28.0          # Hip to anchor distance that forces a planted foot to let go (rest spot is ~26 at full speed)
const STEP_LEN := 20.0         # Anchor drift from the rest spot that triggers a step
const STEP_TIME := 0.1
const STEP_HEIGHT := 7.0
const KNEE_OUT := 5.0          # Knee lift away from the surface
const KNEE_BACK := 3.0         # Knee set back against the leg's end (front legs bend back)
const LEG_R := 3.4             # Upper leg blob radius; the lower leg tapers from it
const REACH := 24.0            # How far past the body clearance a wall beside the gecko can be grabbed
const GRAB_PULL := 90.0        # Speed the body closes on a wall it is turning onto (px/s)
const MAX_TURN_DOT := -0.35    # No turn onto a surface more than ~110 degrees from up (no flips)
const SQUEEZE_D := 20.0        # Rock this close on both sides along the tangent = wedged in a crevice
const NORMAL_SMOOTH := 0.35    # Per-tick blend of the surface normal target (jagged ground flickers)
const HOLD_TIME := 0.12        # Mouse held longer than this shoots the tongue; a shorter press spits
const TONGUE_SPEED := 900.0
const TONGUE_MAX := 160.0
const PULL_SPEED := 360.0
const PULL_ACCEL := 2400.0
const SPIT_SPEED := 520.0
const SPIT_GRAVITY := 500.0
const SPIT_R := 20.0           # Crater radius of a spit burst
const SPIT_COOLDOWN := 0.25
const SWIM_SPEED := 120.0      # Mean speed; the kick peaks above it, the glide falls below
const SWIM_ACCEL := 700.0
const SWIM_DRAG := 300.0
const SWIM_PERIOD := 0.7       # One kick and glide
const SWIM_KICK := 0.35        # Fraction of the period the legs push
const BODY_COLOR := Color(0.56, 0.63, 0.40)
const TONGUE_COLOR := Color(0.80, 0.42, 0.48)
const SPIT_COLOR := Color(0.85, 0.95, 0.45)
const FAR_LEG_COLOR := Color(0.34, 0.40, 0.24)


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
var look := Vector2.RIGHT      # Where the head points: toward the mouse, within LOOK_LIMIT of the body line
var _pos_s := Vector2.ZERO     # Body centre with its across-surface bounce filtered out, for the drawn body
var input_override = null      # Vector2 from the demo pilot, null for real input
var jump_override := false
var chew_override := false
var lmb_override := false      # Demo pilot's left button
var aim_override := Vector2.ZERO  # Demo pilot's cursor, relative to the body
var chewing := false
var _bite := Vector2.ZERO
var swimming := false
var _swim_phase := 0.0         # 0..1 through the kick cycle
var tongue_out := false
var tongue_anchored := false
var tongue_retracting := false
var tongue_tip := Vector2.ZERO
var tongue_dir := Vector2.ZERO
var spits: Array = []          # [position, velocity] per spit in flight
var debug := false             # F1: overlay with up vector, probe reach, feet and bite
var _mouse_held := -1.0        # Seconds the left button has been held, -1 when it is up
var _tongue_spent := false     # A tongue that missed or let go stays in until the button is released
var _spit_cd := 0.0
var _n_target := Vector2.UP    # Smoothed surface normal the up vector turns toward
var _grab_n := Vector2.ZERO    # Normal of the surface the gecko is turning onto, zero when none
var _dbg := ""

var _debug_layer: Node2D
var _under: Node2D             # Drawn beneath the body: the tongue, so it emerges from the snout
var _last_probe := {}
var _block_normal := Vector2.ZERO
var _bridging := false         # Crossing a gap shorter than the body: keep the line, no nudge, no drop
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
	_under = Node2D.new()
	_under.z_index = -2
	_under.draw.connect(_draw_under)
	add_child(_under)
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
	look = Vector2.RIGHT
	_pos_s = at
	swimming = false
	tongue_out = false
	tongue_anchored = false
	tongue_retracting = false
	spits.clear()
	_n_target = Vector2.UP
	_grab_n = Vector2.ZERO
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
	_update_mouse(dt)
	_update_spits(dt)
	var in_water: bool = map.water_near(pos, 1)
	if in_water and not clinging and not swimming and not tongue_anchored:
		swimming = true
		vel *= 0.4
	elif swimming and not in_water:
		swimming = false
	if tongue_anchored:
		_update_pull(dt)
	elif swimming:
		_update_swimming(inp, dt)
	elif clinging:
		_update_clinging(inp, jump, dt)
	else:
		_update_airborne(inp, dt)
	_update_tongue(dt)
	_update_chain(dt)
	_update_look(dt)
	_update_feet(dt)
	_tick += 1
	if _trace:
		var hd := chain.head()
		print("t%d pos(%.0f,%.0f) head(%.0f,%.0f) hip(%.0f,%.0f) up(%.2f,%.2f) dist %.1f spd %.0f %s " % [
			_tick, pos.x, pos.y, hd.x, hd.y, chain.points[FRONT_HIP].x, chain.points[FRONT_HIP].y,
			up.x, up.y, _last_probe.get("dist", -1.0), speed_along, "cling" if clinging else ("swim" if swimming else "air")], _dbg)
	_push_blobs()
	queue_redraw()
	_under.queue_redraw()
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
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not Input.is_key_pressed(KEY_CTRL):
		return true
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
	# Each bite lands a little off and a little different in size, so a
	# tunnel comes out ragged like something chewed, not drilled.
	var jitter := Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	map.erase_circle(_bite + jitter, randf_range(CHEW_R - 2.5, CHEW_R + 0.5))


func _tangent() -> Vector2:
	return Vector2(-up.y, up.x)


func _update_clinging(inp: Vector2, jump: bool, dt: float) -> void:
	var tangent := _tangent()
	var s := 0.0
	if inp.length() > 0.2:
		s = clampf(inp.dot(tangent) * sqrt(2.0), -1.0, 1.0)
		if absf(s) < 0.3:
			s = 0.0
		# Pressing away from a steep surface walks down it: left on a
		# right-hand wall takes the gecko back to the floor, not nowhere.
		if s == 0.0 and inp.dot(up) > 0.5 and absf(tangent.y) > 0.5:
			s = signf(tangent.y)
	if absf(s) > 0.3:
		facing = signf(s)
	speed_along = move_toward(speed_along, s * WALK_SPEED, WALK_ACCEL * dt)
	var blocked := not _step(tangent * speed_along * dt)
	if blocked:
		speed_along = 0.0
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	_bridging = _gap_ahead()
	if (not p.found or p.dist > LOSE_SURFACE_D) and not _bridging:
		_drop()
		return
	# Blocked by rock ahead: turn up toward that rock's normal, so walking
	# into a wall ends standing on the wall, and up means climb. Chewing
	# through it instead, the gecko holds still and waits for the hole.
	# A turn onto another surface (a wall that blocked the move, or one
	# within reach that the input points along) is a commitment: up keeps
	# turning toward that surface's normal until it gets there, so a
	# tilted body half way round cannot talk itself out of it.
	# Wedged in a crevice, with rock close on both sides: no new grabs and
	# no nudge. The nearest rock flips sides every tick there, and anything
	# that follows it makes the gecko dance. It still follows the surface
	# under it and slides along its tangent, so it sits still or backs out.
	var squeezed := _squeezed()
	var n: Vector2
	if _grab_n != Vector2.ZERO and absf(up.angle_to(_grab_n)) < 0.12:
		_grab_n = Vector2.ZERO
	if _grab_n != Vector2.ZERO:
		n = _grab_n
		speed_along = 0.0
		_move(-_grab_n * GRAB_PULL * dt)
	elif blocked and chewing:
		n = Vector2.ZERO
	elif blocked:
		n = _obstacle_normal(inp)
		_grab_n = n
	else:
		n = _reach_for_wall(inp) if (not chewing and not squeezed and inp.length() > 0.2) else Vector2.ZERO
		if n != Vector2.ZERO:
			_grab_n = n
			speed_along = 0.0
		else:
			n = _surface_normal(p)
	_dbg = ("blk" if blocked else "surf") + (" grab" if _grab_n != Vector2.ZERO else "") + (" squeezed" if squeezed else "")
	_dbg += " n(%.2f,%.2f) s %.2f" % [n.x, n.y, s]
	if n != Vector2.ZERO:
		if _grab_n != Vector2.ZERO or n.dot(_n_target) < 0.5:
			_n_target = n
		else:
			_n_target = _n_target.slerp(n, NORMAL_SMOOTH).normalized()
		up = _turn_toward(up, _n_target, SURF_TURN * dt)
	# Ride-height nudge, away from (or toward) the nearest rock rather
	# than along up, so a body squeezed against a side wall can get clear.
	# Ride-height nudge against the surface under the body only. Side
	# rock never pushes the body (the collision check already stops it
	# there), so a notch does not shove the gecko back and forth. Over an
	# edge, where no surface is under it, it pulls toward the nearest
	# rock instead, which is what wraps it round the corner.
	if not squeezed and not _bridging:
		var floor_pt = map.ray_hit(pos, -up, RAY_LEN)
		if floor_pt != null:
			var d: float = (pos - floor_pt).dot(up)
			_move(up * (RIDE_H - 1.5 - d) * minf(1.0, 20.0 * dt))
		else:
			var away: Vector2 = (pos - p.nearest).normalized() if p.dist > 0.01 else up
			_move(away * (RIDE_H - p.dist) * minf(1.0, 20.0 * dt))
	if jump:
		_jump()
		return
	var planted := 0
	for f in feet:
		if f.planted:
			planted += 1
	if planted < MIN_FEET and not _bridging:
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


# In water the gecko swims like a frog: a kick that pushes it the way the
# input points, then a glide under drag, no gravity. It cannot rise
# through the surface; it leaves the water by pushing into rock and
# clinging to it, or on the tongue.
func _update_swimming(inp: Vector2, dt: float) -> void:
	if inp.length() > 0.2:
		_swim_phase = fmod(_swim_phase + dt / SWIM_PERIOD, 1.0)
		if _swim_phase < SWIM_KICK:
			vel = vel.move_toward(inp.normalized() * SWIM_SPEED * 1.7, SWIM_ACCEL * 2.0 * dt)
		else:
			vel = vel.move_toward(Vector2.ZERO, SWIM_DRAG * 0.4 * dt)
		if absf(inp.x) > 0.3:
			facing = signf(inp.x)
	else:
		vel = vel.move_toward(Vector2.ZERO, SWIM_DRAG * dt)
		if _swim_phase > 0.0:
			_swim_phase = minf(_swim_phase + dt / SWIM_PERIOD, 1.0)
			if _swim_phase >= 1.0:
				_swim_phase = 0.0
	if vel.y < 0.0 and not map.water_near(pos + Vector2(0.0, -RIDE_H), 1):
		vel.y = 0.0
	if not _move(vel * dt):
		vel = Vector2.ZERO
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	up = _turn_toward(up, Vector2.UP, 6.0 * dt)
	if p.found and p.dist <= RIDE_H + 2.0 and inp.length() > 0.2:
		var n: Vector2 = (pos - p.nearest).normalized()
		if inp.normalized().dot(-n) > 0.3:
			swimming = false
			_land(n)


# The mouth is at the snout's tip, on its underside, well away from the eye.
func _mouth() -> Vector2:
	return chain.head() + look * (SNOUT + 4.0) - up * 2.5


func _cursor() -> Vector2:
	if input_override != null:
		return pos + aim_override
	return get_global_mouse_position()


# Left mouse: held past HOLD_TIME shoots the tongue at the cursor and
# keeps it until release; a shorter press spits.
func _update_mouse(dt: float) -> void:
	_spit_cd = maxf(_spit_cd - dt, 0.0)
	var held := lmb_override if input_override != null else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held:
		_mouse_held = 0.0 if _mouse_held < 0.0 else _mouse_held + dt
		if not tongue_out and not _tongue_spent and _mouse_held >= HOLD_TIME:
			_shoot_tongue()
	else:
		if _mouse_held >= 0.0 and _mouse_held < HOLD_TIME and not tongue_out:
			_spit()
		_mouse_held = -1.0
		_tongue_spent = false
		if tongue_out and not tongue_retracting:
			_release_tongue()


func _shoot_tongue() -> void:
	tongue_out = true
	tongue_anchored = false
	tongue_retracting = false
	tongue_tip = _mouth()
	tongue_dir = (_cursor() - tongue_tip).normalized()
	if tongue_dir == Vector2.ZERO:
		tongue_dir = look


# Letting go: the tip flies back to the mouth before the tongue is gone.
func _release_tongue() -> void:
	tongue_anchored = false
	tongue_retracting = tongue_out
	_tongue_spent = true


# The tip flies out in 2 px steps until it meets rock or runs out of
# tongue. An anchor whose rock gets destroyed lets go.
func _update_tongue(dt: float) -> void:
	if not tongue_out:
		return
	if tongue_retracting:
		var mouth := _mouth()
		var step := TONGUE_SPEED * dt
		if tongue_tip.distance_to(mouth) <= step + 3.0:
			tongue_out = false
			tongue_retracting = false
		else:
			tongue_tip += (mouth - tongue_tip).normalized() * step
		return
	if tongue_anchored:
		if not map.solid_near(tongue_tip, 1):
			_release_tongue()
		return
	var travelled := 0.0
	var step := TONGUE_SPEED * dt
	while travelled < step:
		var inc := minf(2.0, step - travelled)
		var next := tongue_tip + tongue_dir * inc
		if map.is_solid_world(next):
			tongue_tip = next
			tongue_anchored = true
			if clinging:
				clinging = false
				_unplant()
			swimming = false
			return
		tongue_tip = next
		travelled += inc
		if tongue_tip.distance_to(_mouth()) > TONGUE_MAX:
			_release_tongue()
			return


# Reeling in: the body flies at the anchor and clings where it arrives.
func _update_pull(dt: float) -> void:
	var to := tongue_tip - pos
	var d := to.length()
	var p: Dictionary = map.probe(pos, PROBE_R)
	_last_probe = p
	if d <= RIDE_H + 3.0 and p.found:
		_land((pos - p.nearest).normalized())
		_release_tongue()
		return
	vel = vel.move_toward(to / maxf(d, 0.001) * PULL_SPEED, PULL_ACCEL * dt)
	if not _move(vel * dt):
		if p.found:
			_land((pos - p.nearest).normalized())
			_release_tongue()
			return
		vel = Vector2.ZERO
	no_cling = 0.1
	up = _turn_toward(up, Vector2.UP, 4.0 * dt)


func _spit() -> void:
	if _spit_cd > 0.0:
		return
	_spit_cd = SPIT_COOLDOWN
	var dir := (_cursor() - _mouth()).normalized()
	if dir == Vector2.ZERO:
		dir = look
	spits.append([_mouth(), dir * SPIT_SPEED])


func _update_spits(dt: float) -> void:
	for i in range(spits.size() - 1, -1, -1):
		var sp: Array = spits[i]
		sp[1].y += SPIT_GRAVITY * dt
		var from: Vector2 = sp[0]
		var delta: Vector2 = sp[1] * dt
		var hit = map.ray_hit(from, delta.normalized(), delta.length())
		if hit != null:
			map.blast(hit, SPIT_R)
			spits.remove_at(i)
			continue
		sp[0] = from + delta
		if sp[0].y > 1300.0 or sp[0].x < -200.0 or sp[0].x > 2200.0 or sp[0].y < -300.0:
			spits.remove_at(i)


func _land(n: Vector2) -> void:
	clinging = true
	up = n
	_n_target = n
	_grab_n = Vector2.ZERO
	speed_along = clampf(vel.dot(_tangent()), -WALK_SPEED, WALK_SPEED)
	if absf(speed_along) > 1.0:
		facing = signf(speed_along)
	vel = Vector2.ZERO
	feet_short = 0.0


func _drop() -> void:
	clinging = false
	_grab_n = Vector2.ZERO
	vel = _tangent() * speed_along
	speed_along = 0.0
	no_cling = NO_CLING_TIME
	_unplant()


func _jump() -> void:
	clinging = false
	_grab_n = Vector2.ZERO
	vel = up * JUMP_SPEED + _tangent() * speed_along
	speed_along = 0.0
	no_cling = NO_CLING_TIME
	_unplant()


func _unplant() -> void:
	for f in feet:
		f.planted = false
		f.stepping = false


# A walking move: when the way is blocked, tries again from up to
# STEP_UP higher, so a loose pixel or a small ledge is stepped over
# instead of stopping the gecko. The ride-height nudge settles it after.
func _step(delta: Vector2) -> bool:
	if _move(delta):
		return true
	if delta.length() < 0.01:
		return false
	for k in [3.0, 6.0, 9.0]:
		var save := pos
		if _move(up * k) and _move(delta):
			# Only a real step: the ground must still be right under the body.
			var floor_pt = map.ray_hit(pos, -up, RIDE_H + k + 4.0)
			if floor_pt != null:
				return true
		pos = save
	return false


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
			var cell = map.blocking_cell(pos, next, BODY_R)
			_block_normal = (next - cell).normalized() if cell != null else -dir
			return false
		pos = next
		moved += step
	return true


# Normal of the rock that blocked the move, as the new up, but only when
# the held input, read on that rock's surface, would carry the body away
# from the surface it is on now: up into a wall or an overhang turns and
# climbs; right into a wall stops at it (right would point into the
# rock), right into an overhang stays too (it would lead back down into
# the floor, and the gecko would rock between the two for ever).
func _obstacle_normal(inp: Vector2) -> Vector2:
	var n := _block_normal
	if n == Vector2.ZERO or n.dot(up) < MAX_TURN_DOT:
		return Vector2.ZERO
	var t_new := Vector2(-n.y, n.x)
	var s_new := inp.dot(t_new)
	if absf(s_new) < 0.3:
		return Vector2.ZERO
	if (t_new * signf(s_new)).dot(up) < -0.2:
		return Vector2.ZERO
	return n


func _squeezed() -> bool:
	var t := _tangent()
	var a = map.ray_hit(pos, t, SQUEEZE_D)
	var b = map.ray_hit(pos, -t, SQUEEZE_D)
	return a != null and b != null


# A wall within reach on either side of the body, as a new up, under the
# same rule as a blocking wall: only when the held input would then move
# the body along it and away from the surface it is on now. Without this
# a floor dipping toward a wall walks the gecko backward on up, since up
# projects on the slope as uphill.
func _reach_for_wall(inp: Vector2) -> Vector2:
	var t := _tangent()
	for side in [1.0, -1.0]:
		var hit = map.ray_hit(pos, t * side, BODY_R + REACH)
		if hit == null:
			continue
		var q: Dictionary = map.probe(hit - t * side * 3.0, 10.0)
		var n: Vector2 = q.normal if q.found and q.normal != Vector2.ZERO else -t * side
		if n.dot(up) > 0.75 or n.dot(up) < MAX_TURN_DOT:
			continue
		var t_new := Vector2(-n.y, n.x)
		var s_new := inp.dot(t_new)
		if absf(s_new) < 0.3:
			continue
		if (t_new * signf(s_new)).dot(up) < -0.2:
			continue
		return n
	return Vector2.ZERO


# Surface normal from two rays cast down from ahead of and behind the
# body: the slope between their hits, so a bump beside the gecko does not
# tilt it. Falls back to the probe's centroid normal when a ray misses or
# starts inside rock, which happens at corners, where the centroid is
# what swings the gecko round smoothly.
func _surface_normal(p: Dictionary) -> Vector2:
	if _bridging:
		return up
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


# A gap shorter than the body: no ground under the front ray, ground
# under the back ray, and ground again BRIDGE ahead at about the same
# level. The gecko spans it instead of following the surface down into it.
func _gap_ahead() -> bool:
	var t := _tangent() * facing
	var front = map.ray_hit(pos + t * RAY_HALF, -up, RAY_LEN)
	if front != null:
		return false
	var back = map.ray_hit(pos - t * RAY_HALF, -up, RAY_LEN)
	if back == null:
		return false
	var far = map.ray_hit(pos + t * BRIDGE, -up, RAY_LEN)
	return far != null


static func _turn_toward(a: Vector2, b: Vector2, max_angle: float) -> Vector2:
	var ang := a.angle_to(b)
	return a.rotated(clampf(ang, -max_angle, max_angle)).normalized()


# The head leads the chain. Clinging, it sits ahead of the body centre in
# the facing direction, and slides round to the other side on a turn so
# the body folds into a U behind it; the body is then laid along the
# surface behind it. Airborne, it points along the velocity and the body
# trails freely, only pushed out of rock.
func _update_chain(dt: float) -> void:
	# The drawn body hangs off a base that follows the body centre exactly
	# along the surface but only slowly across it, so bumps in the ground
	# do not bob the head: a chicken's head on its gyro.
	var target: Vector2
	if clinging:
		var t := _tangent()
		var d := pos - _pos_s
		var across := d.dot(up)
		_pos_s += t * d.dot(t) + up * across * BOB_SMOOTH
		across = (pos - _pos_s).dot(up)
		if absf(across) > BOB_MAX:
			_pos_s += up * (across - signf(across) * BOB_MAX)
		target = _pos_s + t * facing * HEAD_LEAD
	else:
		_pos_s = pos
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
	if clinging:
		_resolve_body(new_head, dir)
		return
	chain.set_head(new_head, dir)
	for i in chain.size():
		var r: float = chain.radii[i]
		var q: Dictionary = map.probe(chain.points[i], r + BODY_GAP)
		if q.found and q.dist < r + BODY_GAP:
			var away: Vector2 = (chain.points[i] - q.nearest).normalized() if q.dist > 0.01 else up
			chain.points[i] += away * (r + BODY_GAP - q.dist)


# Lays the body behind the head along the surface, one link at a time.
# Each link keeps the direction it trailed in last tick (so the body
# folds into a U on a turn), bent at most MAX_BEND from the link before;
# then the point is kept BODY_GAP off the nearest rock and the link
# length restored, before the next link starts from it. Link by link,
# the body turns an inside corner as an L instead of bunching up in it.
func _resolve_body(new_head: Vector2, dir: Vector2) -> void:
	if dir.length() > 0.001:
		chain.heading = dir.normalized()
	var old := chain.points.duplicate()
	var q0: Dictionary = map.probe(new_head, chain.radii[0] + BODY_GAP)
	if q0.found and q0.dist < chain.radii[0] + BODY_GAP:
		var away0: Vector2 = (new_head - q0.nearest).normalized() if q0.dist > 0.01 else up
		new_head += away0 * (chain.radii[0] + BODY_GAP - q0.dist)
	chain.points[0] = new_head
	var prev_dir := -chain.heading
	for i in range(1, chain.size()):
		var anchor: Vector2 = chain.points[i - 1]
		var trail: Vector2 = old[i] - anchor
		var desired: Vector2 = trail.normalized() if trail.length() > 0.001 else prev_dir
		var ang := prev_dir.angle_to(desired)
		if absf(ang) > MAX_BEND:
			desired = prev_dir.rotated(signf(ang) * MAX_BEND)
		var p: Vector2 = anchor + desired * LINK
		var r: float = chain.radii[i]
		var q: Dictionary = map.probe(p, r + BODY_HUG)
		if q.found:
			var away: Vector2 = (p - q.nearest).normalized() if q.dist > 0.01 else up
			var want := r + BODY_GAP
			if q.dist < want:
				p += away * (want - q.dist)
			else:
				p += away * (want - q.dist) * HUG_K
			p = anchor + (p - anchor).normalized() * LINK
		chain.points[i] = p
		prev_dir = (p - anchor).normalized()


# The head looks at the mouse, within LOOK_LIMIT of the body line, so the
# gecko never looks back through itself. The demo pilot has no mouse and
# looks where it goes.
func _update_look(dt: float) -> void:
	var want := chain.heading
	if input_override == null or aim_override != Vector2.ZERO:
		var to_mouse := _cursor() - chain.head()
		if to_mouse.length() > 4.0:
			want = to_mouse.normalized()
			var off := chain.heading.angle_to(want)
			if absf(off) > LOOK_LIMIT:
				want = chain.heading.rotated(signf(off) * LOOK_LIMIT)
	look = _turn_toward(look, want, 16.0 * dt)


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
		if swimming:
			# Frog kick: legs sweep back and out fast, then tuck slowly.
			f.planted = false
			var fwd := vel.normalized() if vel.length() > 10.0 else chain.heading
			var perp := Vector2(-fwd.y, fwd.x)
			var k: float
			if _swim_phase < SWIM_KICK:
				var u := _swim_phase / SWIM_KICK
				k = 1.0 - (1.0 - u) * (1.0 - u)
			else:
				k = 1.0 - (_swim_phase - SWIM_KICK) / (1.0 - SWIM_KICK)
			var tucked := hip + fwd * 2.0 + perp * f.end * 2.0
			var extended := hip - fwd * 12.0 + perp * (f.end * 7.0 + f.side * 2.0)
			f.pos = f.pos.lerp(tucked.lerp(extended, k), minf(1.0, 25.0 * dt))
			continue
		if not clinging:
			f.planted = false
			var hang := hip - up * 6.0 + tangent * f.end * facing * 4.0
			if f.pos.distance_to(hang) > 20.0:
				f.pos = hang
			else:
				f.pos = f.pos.lerp(hang, minf(1.0, 30.0 * dt))
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


func _knee(f: Foot) -> Vector2:
	var hip: Vector2 = chain.points[f.hip]
	var foot := f.pos + (up * 1.5 if f.planted else Vector2.ZERO)
	return (hip + foot) * 0.5 + up * KNEE_OUT - _tangent() * f.end * facing * KNEE_BACK


# Far legs first, then the body, then the near legs: the colour layer
# keeps the last circle drawn, so far legs come out darker only where
# they show past the body, and near legs are the body's own colour.
func _push_blobs() -> void:
	var list: Array = []
	_leg_blobs(list, -1.0, FAR_LEG_COLOR)
	for i in chain.size():
		list.append([chain.points[i], chain.radii[i], BODY_COLOR])
		# Thin tail segments get a filler blob between them, so the tail
		# renders as a line rather than a row of dots.
		if i > 0 and chain.radii[i] < 4.5:
			var r_mid: float = (chain.radii[i - 1] + chain.radii[i]) * 0.5
			list.append([chain.points[i - 1].lerp(chain.points[i], 0.5), r_mid, BODY_COLOR])
	list.append([chain.head() + look * SNOUT, 5.0, BODY_COLOR])
	_leg_blobs(list, 1.0, BODY_COLOR)
	blobs.set_blobs(list)


func _leg_blobs(list: Array, side: float, color: Color) -> void:
	for f in feet:
		if f.side != side:
			continue
		var hip: Vector2 = chain.points[f.hip]
		var knee := _knee(f)
		var foot := f.pos + (up * 1.5 if f.planted else Vector2.ZERO)
		for k in range(1, 4):
			var t := k / 3.0
			list.append([hip.lerp(knee, t), LEG_R, color])
		for k in range(1, 4):
			var t := k / 3.0
			list.append([knee.lerp(foot, t), lerpf(LEG_R, LEG_R * 0.85, t), color])


func _draw() -> void:
	# The eye is one pixel of the 4 px world grid, snapped to it.
	var head: Vector2 = chain.points[0]
	var eye := (head + look * 3.5 + up * 3.0 + Vector2(-2.0, -2.0)).snapped(Vector2(4.0, 4.0))
	draw_rect(Rect2(eye, Vector2(4.0, 4.0)), Color(0.08, 0.07, 0.06))
	if chewing and debug:
		draw_arc(_bite, CHEW_R, 0.0, TAU, 20, Color(1.0, 0.8, 0.5, 0.6), 1.5)
	for sp in spits:
		draw_circle(sp[0], 3.0, SPIT_COLOR)


func _draw_under() -> void:
	if tongue_out:
		_under.draw_line(_mouth(), tongue_tip, TONGUE_COLOR, 2.5)
		_under.draw_circle(tongue_tip, 2.5, TONGUE_COLOR)


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
	var state := "cling" if clinging else ("swim" if swimming else "air")
	if tongue_anchored:
		state = "pull"
	return "%s%s%s  feet %d/4  up (%.2f, %.2f)  speed %.0f  vel (%.0f, %.0f)" % [
		state, " chew" if chewing else "", " bridge" if _bridging else "", planted, up.x, up.y, speed_along, vel.x, vel.y]
