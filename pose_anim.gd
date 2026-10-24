# Pose animations for the gecko. A frame is the chain's ten points, the
# four feet (where they are drawn) and the look, in the gecko's own
# frame: the surface line at y = 0, up along -y, the walk's facing along
# +x; the eye as an offset from the head (EYE_MAX at most: on the head's
# disc), riding with the look (EYE_LOOK along it, a pixel up) until the
# editor places it by hand; with the seconds to the next frame, a
# tension and a bias, and how far the eye is open (lid: 0 shut to a
# line a pixel high, 1 the open disc, the pixels between a lid half
# down; a file's old shut flag reads as 0 or 1), and how far the jaw is
# open (jaw: 0 shut, 1 the yawn's widest; gecko.gd _jaw_geom). Playback
# runs a spline through the frames in link space, each link's angle and
# length, so a curled body unrolls instead of shrinking as blended
# points would; the head, the feet, the look and the eye run on the same
# spline as points. The spline is a Kochanek-Bartels one: the body keeps
# its speed through a frame of tension 0 and stops on a frame of tension
# 1 (the old smooth ease); a bias above 0 carries the move on past the
# frame, below 0 turns it early. A
# link that turns more than FOLD_ANGLE between two frames (a tail tucked
# forward along the flank, laid out behind in the next) is pulled
# through instead of swung round: its length shrinks to nothing and
# grows back the other way, the side view of a tail curling round
# sideways, as the body folds on a turn-around. The
# files live under poses/ as the levels do under levels/: versions
# poses/<name>/vNNNN.json (kind saved or auto, the last AUTOSAVE_KEEP
# autos kept) and the head poses/<name>.json, what the game loads. The
# pose editor (pose_editor.gd) writes them; the gecko plays them
# (gecko.gd play_pose): the file named wake is the wake-up, and played
# backwards the curl to sleep (main.gd play_anim).
class_name PoseAnim
extends RefCounted

const DIR := "res://poses/"
const WAKE := "wake"
const N_POINTS := 10
const N_FEET := 4
const DUR_DEFAULT := 0.3
const TENSION_DEFAULT := 0.0   # A new frame: the body moves through it
const TENSION_OLD := 1.0       # A frame from before tensions (all smooth eases): the body stops on it
const AUTOSAVE_KEEP := 10
const FOOT_DRAWN_Y := -4.5     # A standing foot as drawn: FOOT_LIFT over its anchor on the surface line
const EYE_LOOK := 3.5          # The eye's place along the look when it rides with it (gecko.gd _face)
const EYE_UP := Vector2(0.0, -1.0)   # and a pixel up
const EYE_MAX := 5.0           # Farthest the eye's centre may sit from the head's (its 4 px disc stays on the 7 px head)
const LID_OPEN := 1.0
const JAW_SHUT := 0.0
const SPINE_LAST := 4          # The rump: points 1 to 4 are the spine the editor's lock holds still
const STEP_LIFT := 3.0         # Most a foot lifts stepping along the floor between two frames
const STEP_FLOOR := -5.0       # A foot drawn lower than this (y down) stands on the floor
const LEG_MAX := 18.0          # Farthest a foot as drawn sits from its hip in the editor (the standing pose's legs are 15.3)
const SHORT_LINK := 0.25      # A link under this part of its length at the other frame runs as a vector, never turning
const FOLD_ANGLE := 2.6        # Radians (150 degrees) a link turns between two frames beyond which it is pulled through, not swung
# The gecko at rest on a floor, read off a settled run (the suite's
# flat:idle trace): the head 15 px ahead of the body centre and 18 up,
# the body sagging to a tail tip 5 px over the ground; the feet as drawn.
# The feet are in the gecko's order: front near, front far, back near,
# back far.
const STANDING_POINTS := [[15.0, -18.0], [7.0, -15.1], [-1.0, -12.5], [-9.0, -11.5], [-17.0, -9.2], [-25.0, -7.4], [-33.0, -6.4], [-41.0, -5.7], [-49.0, -5.2], [-57.0, -4.9]]
const STANDING_FEET := [[18.0, -4.5], [16.0, -4.5], [-22.0, -4.5], [-18.0, -4.5]]


static func standing() -> Dictionary:
	return from_json_frame({"points": STANDING_POINTS, "feet": STANDING_FEET, "look": [1.0, 0.0], "dur": DUR_DEFAULT, "tension": TENSION_DEFAULT, "lid": LID_OPEN, "jaw": JAW_SHUT})


static func dup(f: Dictionary) -> Dictionary:
	var pts: PackedVector2Array = f.points
	var feet: PackedVector2Array = f.feet
	return {"points": pts.duplicate(), "feet": feet.duplicate(), "look": f.look, "eye": f.get("eye", eye_for(f.look)), "eye_free": f.get("eye_free", false), "dur": f.dur, "tension": f.tension, "bias": f.get("bias", 0.0), "lid": f.get("lid", LID_OPEN), "jaw": f.get("jaw", JAW_SHUT)}


# Where the eye sits when it rides with the look.
static func eye_for(look: Vector2) -> Vector2:
	return look * EYE_LOOK + EYE_UP


static func dup_all(frames: Array) -> Array:
	var out: Array = []
	for f in frames:
		out.append(dup(f))
	return out


static func total(frames: Array) -> float:
	var t := 0.0
	for f in frames:
		t += float(f.dur)
	return t


# The pose t seconds in: the spline from frame i to frame i + 1 over
# frame i's seconds; the last frame holds for its seconds, or looping
# runs on to the first. Past the end, the last frame.
static func sample(frames: Array, t: float, loop := false) -> Dictionary:
	var n := frames.size()
	if n == 0:
		return standing()
	if n == 1:
		return dup(frames[0])
	var tot := total(frames)
	if loop and tot > 0.0:
		t = fposmod(t, tot)
	for i in n:
		var d := float(frames[i].dur)
		if t < d or i == n - 1:
			if i == n - 1 and not loop:
				return dup(frames[i])
			var k := clampf(t / d, 0.0, 1.0) if d > 0.0 else 1.0
			return between(frames, i, k, loop)
		t -= d
	return dup(frames[n - 1])


# Which frame t seconds in is in (blending toward the next).
static func frame_at(frames: Array, t: float) -> int:
	for i in frames.size():
		var d := float(frames[i].dur)
		if t < d:
			return i
		t -= d
	return frames.size() - 1


# Frame i toward the next by k (0 to 1 of frame i's seconds) on the
# spline. Each value v runs as a cubic Hermite curve from frame a to
# frame b, its slope at either end set from the chords to the frames
# around: v = v_a + c_in * (v_a - v_prev) + c_ab * (v_b - v_a) + c_out
# * (v_next - v_b). Without a frame before (the start, not looping) or
# after (the end) the slope there is nil: the body sets off from rest
# and comes to rest. The slopes are scaled by the seconds on either
# side, so the speed carries through a frame where a long blend meets a
# short one. A link that folds between a and b (turns past FOLD_ANGLE),
# or is all but gone at one end, runs as a vector instead, through
# nothing along one line; chords across those carry no turn. A
# foot on the floor at a and at b that moves steps (STEP_LIFT).
static func between(frames: Array, i: int, k: float, loop := false) -> Dictionary:
	var n := frames.size()
	var a: Dictionary = frames[i]
	var b: Dictionary = frames[(i + 1) % n]
	var ip := i - 1 if i > 0 else (n - 1 if loop else -1)
	var inx := i + 2 if i + 2 < n else ((i + 2) % n if loop else -1)
	var p: Dictionary = frames[ip] if ip >= 0 else a
	var q: Dictionary = frames[inx] if inx >= 0 else b
	var d_ab := float(a.dur)
	var w_in := 0.0
	var w_a := 0.0
	var w_b := 0.0
	var w_out := 0.0
	if ip >= 0:
		var d_in := float(p.dur)
		var f := 2.0 * d_ab / (d_in + d_ab) if d_in + d_ab > 0.0 else 0.0
		var ta := 1.0 - float(a.tension)
		var ba := float(a.get("bias", 0.0))
		w_in = f * ta * (1.0 + ba) * 0.5
		w_a = f * ta * (1.0 - ba) * 0.5
	if inx >= 0:
		var d_out := float(b.dur)
		var f := 2.0 * d_ab / (d_ab + d_out) if d_ab + d_out > 0.0 else 0.0
		var tb := 1.0 - float(b.tension)
		var bb := float(b.get("bias", 0.0))
		w_b = f * tb * (1.0 + bb) * 0.5
		w_out = f * tb * (1.0 - bb) * 0.5
	var k2 := k * k
	var k3 := k2 * k
	var h01 := 3.0 * k2 - 2.0 * k3
	var h10 := k3 - 2.0 * k2 + k
	var h11 := k3 - k2
	var c_in := h10 * w_in
	var c_ab := h01 + h10 * w_a + h11 * w_b
	var c_out := h11 * w_out

	var out := dup(a)
	var pp: PackedVector2Array = p.points
	var pa: PackedVector2Array = a.points
	var pb: PackedVector2Array = b.points
	var pq: PackedVector2Array = q.points
	var pts := PackedVector2Array()
	pts.resize(pa.size())
	pts[0] = _low(pa[0] + (pa[0] - pp[0]) * c_in + (pb[0] - pa[0]) * c_ab + (pq[0] - pb[0]) * c_out, pa[0], pb[0])
	for j in range(1, pa.size()):
		var vp := pp[j] - pp[j - 1]
		var va := pa[j] - pa[j - 1]
		var vb := pb[j] - pb[j - 1]
		var vq := pq[j] - pq[j - 1]
		var turn := angle_difference(va.angle(), vb.angle())
		var long := maxf(va.length(), vb.length())
		if absf(turn) > FOLD_ANGLE or minf(va.length(), vb.length()) < SHORT_LINK * long:
			# Pulled through: seen from the side, a link swinging round
			# sideways shortens to nothing and comes back the other way;
			# or a link all but gone at one end (mid-fold), with no
			# direction there worth turning from. The link runs as a
			# vector on the spline, through nothing along one line, its
			# speed carried through the frames like the rest.
			var v := va + (va - vp) * c_in + (vb - va) * c_ab + (vq - vb) * c_out
			pts[j] = pts[j - 1] + v.limit_length(long)
			continue
		var t_in := angle_difference(vp.angle(), va.angle())
		var t_out := angle_difference(vb.angle(), vq.angle())
		var l_in := va.length() - vp.length()
		var l_out := vq.length() - vb.length()
		# A chord across a fold, or from a link all but gone, has no
		# turn to carry.
		if absf(t_in) > FOLD_ANGLE or vp.length() < SHORT_LINK * va.length():
			t_in = 0.0
			l_in = 0.0
		if absf(t_out) > FOLD_ANGLE or vq.length() < SHORT_LINK * vb.length():
			t_out = 0.0
			l_out = 0.0
		var ang := va.angle() + t_in * c_in + turn * c_ab + t_out * c_out
		var len := va.length() + l_in * c_in + (vb.length() - va.length()) * c_ab + l_out * c_out
		# A link never longer or shorter than at either end.
		len = clampf(len, minf(va.length(), vb.length()), long)
		pts[j] = pts[j - 1] + Vector2.from_angle(ang) * len
	out.points = pts
	var fp: PackedVector2Array = p.feet
	var fa: PackedVector2Array = a.feet
	var fb: PackedVector2Array = b.feet
	var fq: PackedVector2Array = q.feet
	var feet := PackedVector2Array()
	feet.resize(fa.size())
	for j in fa.size():
		feet[j] = _low(fa[j] + (fa[j] - fp[j]) * c_in + (fb[j] - fa[j]) * c_ab + (fq[j] - fb[j]) * c_out, fa[j], fb[j])
		# A foot standing on the floor at both frames that moves between
		# them steps: it lifts on the way instead of sliding.
		var stride := absf(fb[j].x - fa[j].x)
		if fa[j].y > STEP_FLOOR and fb[j].y > STEP_FLOOR and stride > 1.0:
			feet[j].y -= minf(STEP_LIFT, stride * 0.5) * sin(PI * k)
	out.feet = feet
	var lp: Vector2 = p.look
	var la: Vector2 = a.look
	var lb: Vector2 = b.look
	var lq: Vector2 = q.look
	out.look = Vector2.from_angle(la.angle() + angle_difference(lp.angle(), la.angle()) * c_in + angle_difference(la.angle(), lb.angle()) * c_ab + angle_difference(lb.angle(), lq.angle()) * c_out)
	var ep: Vector2 = p.get("eye", eye_for(lp))
	var ea: Vector2 = a.get("eye", eye_for(la))
	var eb: Vector2 = b.get("eye", eye_for(lb))
	var eq: Vector2 = q.get("eye", eye_for(lq))
	out.eye = (ea + (ea - ep) * c_in + (eb - ea) * c_ab + (eq - eb) * c_out).limit_length(EYE_MAX)
	var dp := float(p.get("lid", LID_OPEN))
	var da := float(a.get("lid", LID_OPEN))
	var db := float(b.get("lid", LID_OPEN))
	var dq := float(q.get("lid", LID_OPEN))
	out.lid = clampf(da + (da - dp) * c_in + (db - da) * c_ab + (dq - db) * c_out, 0.0, 1.0)
	var jp := float(p.get("jaw", JAW_SHUT))
	var ja := float(a.get("jaw", JAW_SHUT))
	var jb := float(b.get("jaw", JAW_SHUT))
	var jq := float(q.get("jaw", JAW_SHUT))
	out.jaw = clampf(ja + (ja - jp) * c_in + (jb - ja) * c_ab + (jq - jb) * c_out, 0.0, 1.0)
	return out


# A point on the spline kept from dipping below both its ends (y down):
# an overshoot never puts the head or a foot into the floor.
static func _low(v: Vector2, a: Vector2, b: Vector2) -> Vector2:
	return Vector2(v.x, minf(v.y, maxf(a.y, b.y)))


# --- The gecko's frame ---
#
# base is the point on the surface under the body centre, up the
# surface normal, facing the walk's: +1 along the tangent, -1 against it.

static func to_world(local: Vector2, base: Vector2, up: Vector2, facing: float) -> Vector2:
	var t := Vector2(-up.y, up.x)
	return base + t * (local.x * facing) - up * local.y


# The jaw, in the gecko's frame with the head at the origin: it hinges
# at the mouth's corner under the eye and swings down from the look,
# toward the chin's side (the look turned a quarter toward +y: under the
# snout looking ahead, forward looking up), by up to JAW_MAX at jaw 1.
const JAW_HINGE_ALONG := -0.5  # The hinge's place along the look from the head's centre
const JAW_HINGE_DOWN := 4.0    # and toward the chin
const JAW_LEN := 9.5           # Hinge to the lips' front: the shut mouth's tip at the snout's (gecko.gd _mouth)
const JAW_MAX := 0.6           # Radians the jaw turns at jaw 1 (about 34 degrees)


static func chin_side(look: Vector2) -> Vector2:
	return Vector2(-look.y, look.x)


static func jaw_hinge(look: Vector2) -> Vector2:
	return look * JAW_HINGE_ALONG + chin_side(look) * JAW_HINGE_DOWN


# The lower jaw's direction from the hinge.
static func jaw_dir(look: Vector2, jaw: float) -> Vector2:
	var a := clampf(jaw, 0.0, 1.0) * JAW_MAX
	return look * cos(a) + chin_side(look) * sin(a)


# The jaw a point dragged to from the hinge asks for (the editor's chin handle).
static func jaw_for(look: Vector2, hinge_to: Vector2) -> float:
	if hinge_to.length() < 0.5:
		return 0.0
	var a := atan2(hinge_to.dot(chin_side(look)), hinge_to.dot(look))
	return clampf(a / JAW_MAX, 0.0, 1.0)


# An offset (not normalised) in the gecko's frame as a world vector.
static func vec_to_world(v: Vector2, up: Vector2, facing: float) -> Vector2:
	var t := Vector2(-up.y, up.x)
	return t * (v.x * facing) - up * v.y


static func dir_to_world(d: Vector2, up: Vector2, facing: float) -> Vector2:
	var t := Vector2(-up.y, up.x)
	var w := t * (d.x * facing) - up * d.y
	return w.normalized() if w.length() > 0.001 else t * facing


static func to_local(world: Vector2, base: Vector2, up: Vector2, facing: float) -> Vector2:
	var t := Vector2(-up.y, up.x)
	var d := world - base
	return Vector2(d.dot(t) * facing, -d.dot(up))


# --- Editing ---

# Drags point i of a pose to a spot, the chain following like a rope:
# every link keeps its length, the points beyond i on both sides
# swinging after it.
static func follow(f: Dictionary, i: int, to: Vector2) -> void:
	var src: PackedVector2Array = f.points
	var pts := src.duplicate()
	var n := pts.size()
	var lens := PackedFloat32Array()
	lens.resize(n)
	for j in range(1, n):
		lens[j] = pts[j].distance_to(pts[j - 1])
	pts[i] = to
	for j in range(i + 1, n):
		var d := pts[j] - pts[j - 1]
		pts[j] = pts[j - 1] + (d.normalized() if d.length() > 0.001 else Vector2.LEFT) * lens[j]
	for j in range(i - 1, -1, -1):
		var d := pts[j] - pts[j + 1]
		pts[j] = pts[j + 1] + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * lens[j + 1]
	f.points = pts


# The drag with the spine locked: points 1 to SPINE_LAST stay. The head
# swings round the neck; a tail point bends the tail between the rump
# and it (FABRIK, the rump held), the points past it following like a
# rope. False for a spine point, which does not move.
static func follow_locked(f: Dictionary, i: int, to: Vector2) -> bool:
	if i >= 1 and i <= SPINE_LAST:
		return false
	var src: PackedVector2Array = f.points
	var pts := src.duplicate()
	var n := pts.size()
	var lens := PackedFloat32Array()
	lens.resize(n)
	for j in range(1, n):
		lens[j] = pts[j].distance_to(pts[j - 1])
	if i == 0:
		var d := to - pts[1]
		pts[0] = pts[1] + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * lens[1]
		f.points = pts
		return true
	var root := pts[SPINE_LAST]
	var reach := 0.0
	for j in range(SPINE_LAST + 1, i + 1):
		reach += lens[j]
	if root.distance_to(to) >= reach:
		var dir := (to - root).normalized()
		for j in range(SPINE_LAST + 1, i + 1):
			pts[j] = pts[j - 1] + dir * lens[j]
	else:
		for it in 12:
			pts[i] = to
			for j in range(i - 1, SPINE_LAST, -1):
				var d := pts[j] - pts[j + 1]
				pts[j] = pts[j + 1] + (d.normalized() if d.length() > 0.001 else Vector2.LEFT) * lens[j + 1]
			for j in range(SPINE_LAST + 1, i + 1):
				var d := pts[j] - pts[j - 1]
				pts[j] = pts[j - 1] + (d.normalized() if d.length() > 0.001 else Vector2.LEFT) * lens[j]
	for j in range(i + 1, n):
		var d := pts[j] - pts[j - 1]
		pts[j] = pts[j - 1] + (d.normalized() if d.length() > 0.001 else Vector2.LEFT) * lens[j]
	f.points = pts
	return true


# The hip a foot hangs from: the front feet the front hip's, the back
# feet the back one's.
static func hip_of(foot: int) -> int:
	return 1 if foot < 2 else 3


# Every foot pulled in to LEG_MAX of its hip.
static func keep_legs(f: Dictionary) -> void:
	var pts: PackedVector2Array = f.points
	var src: PackedVector2Array = f.feet
	var feet := src.duplicate()
	for k in feet.size():
		var hip := pts[hip_of(k)]
		feet[k] = hip + (feet[k] - hip).limit_length(LEG_MAX)
	f.feet = feet


# Every link set to one length from the head back, each keeping its direction.
static func even_links(f: Dictionary, link: float) -> void:
	var src: PackedVector2Array = f.points
	var pts := src.duplicate()
	for j in range(1, pts.size()):
		var d := pts[j] - pts[j - 1]
		pts[j] = pts[j - 1] + (d.normalized() if d.length() > 0.001 else Vector2.LEFT) * link
	f.points = pts


static func mirrored(f: Dictionary) -> Dictionary:
	var out := dup(f)
	var pts: PackedVector2Array = out.points
	for j in pts.size():
		pts[j] = Vector2(-pts[j].x, pts[j].y)
	out.points = pts
	var feet: PackedVector2Array = out.feet
	for j in feet.size():
		feet[j] = Vector2(-feet[j].x, feet[j].y)
	out.feet = feet
	var look: Vector2 = out.look
	out.look = Vector2(-look.x, look.y)
	var eye: Vector2 = out.eye
	out.eye = Vector2(-eye.x, eye.y)
	return out


static func moved(f: Dictionary, by: Vector2) -> void:
	var pts: PackedVector2Array = f.points
	for j in pts.size():
		pts[j] = pts[j] + by
	f.points = pts
	var feet: PackedVector2Array = f.feet
	for j in feet.size():
		feet[j] = feet[j] + by
	f.feet = feet


# --- Files ---

static func exists(name: String) -> bool:
	return FileAccess.file_exists(DIR + name + ".json")


# The heads in poses/, by name.
static func names() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(String(f).trim_suffix(".json"))
	out.sort()
	return out


# Every animation for the Load dialog: [{name, versions, head}], the
# ones with versions first.
static func entries() -> Array:
	var out: Array = []
	var seen := {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var folders: Array = Array(dir.get_directories())
	folders.sort()
	for f in folders:
		var n := versions(String(f)).size()
		if n > 0:
			out.append({"name": String(f), "versions": n, "head": exists(String(f))})
			seen[String(f)] = true
	for name in names():
		if not seen.has(name):
			out.append({"name": name, "versions": 0, "head": true})
	return out


# An animation's versions, the latest first: [{n, file, kind, saved_at}].
static func versions(name: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR + name)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("v") and f.ends_with(".json"):
			var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + name + "/" + f))
			if data is Dictionary:
				out.append({"n": int(String(f).substr(1, 4)), "file": String(f), "kind": String(data.get("kind", "saved")), "saved_at": String(data.get("saved_at", ""))})
	out.sort_custom(func(a, b) -> bool: return a.n > b.n)
	return out


# The frames of the head poses/<name>.json; empty when there is none.
static func load_head(name: String) -> Array:
	return load_file(DIR + name + ".json")


static func load_version(name: String, file: String) -> Array:
	return load_file(DIR + name + "/" + file)


static func load_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not (data.get("frames") is Array):
		return []
	return from_json(data.frames)


static func from_json(list: Array) -> Array:
	var out: Array = []
	for item in list:
		if item is Dictionary:
			var f := from_json_frame(item)
			if not f.is_empty():
				out.append(f)
	return out


static func from_json_frame(d: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	for p in d.get("points", []):
		if p is Array and p.size() >= 2:
			pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() != N_POINTS:
		return {}
	var feet := PackedVector2Array()
	for p in d.get("feet", []):
		if p is Array and p.size() >= 2:
			feet.append(Vector2(float(p[0]), float(p[1])))
	while feet.size() < N_FEET:
		var s: Array = STANDING_FEET[feet.size()]
		feet.append(Vector2(float(s[0]), float(s[1])))
	feet.resize(N_FEET)
	var look := Vector2.RIGHT
	var lk = d.get("look", null)
	if lk is Array and lk.size() >= 2:
		look = Vector2(float(lk[0]), float(lk[1]))
	if look.length() < 0.001:
		look = Vector2.RIGHT
	look = look.normalized()
	var eye := eye_for(look)
	var eye_free := false
	var ey = d.get("eye", null)
	if ey is Array and ey.size() >= 2:
		eye = Vector2(float(ey[0]), float(ey[1])).limit_length(EYE_MAX)
		eye_free = true
	var lid := float(d.get("lid", 0.0 if bool(d.get("shut", false)) else LID_OPEN))
	return {"points": pts, "feet": feet, "look": look, "eye": eye, "eye_free": eye_free, "dur": maxf(float(d.get("dur", DUR_DEFAULT)), 0.0), "tension": clampf(float(d.get("tension", TENSION_OLD)), 0.0, 1.0), "bias": clampf(float(d.get("bias", 0.0)), -1.0, 1.0), "lid": clampf(lid, 0.0, 1.0), "jaw": clampf(float(d.get("jaw", JAW_SHUT)), 0.0, 1.0)}


static func to_json(frames: Array) -> Array:
	var out: Array = []
	for f in frames:
		var pts: Array = []
		for p in f.points:
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		var feet: Array = []
		for p in f.feet:
			feet.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		var look: Vector2 = f.look
		var item := {"points": pts, "feet": feet, "look": [snappedf(look.x, 0.001), snappedf(look.y, 0.001)], "dur": snappedf(float(f.dur), 0.001), "tension": snappedf(float(f.tension), 0.01), "bias": snappedf(float(f.get("bias", 0.0)), 0.01), "lid": snappedf(float(f.get("lid", LID_OPEN)), 0.01), "jaw": snappedf(float(f.get("jaw", JAW_SHUT)), 0.01)}
		if f.get("eye_free", false):
			var eye: Vector2 = f.eye
			item["eye"] = [snappedf(eye.x, 0.01), snappedf(eye.y, 0.01)]
		out.append(item)
	return out


# Writes a version of the frames under the name, and the head as well
# when kind is saved; an auto version prunes the autos past
# AUTOSAVE_KEEP. Returns a line for the status, or the error.
static func write(name: String, frames: Array, kind: String) -> String:
	var dir := DIR + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := 1
	var vs := versions(name)
	if not vs.is_empty():
		n = int(vs[0].n) + 1
	var doc := {"name": name, "saved_at": Time.get_datetime_string_from_system(false, true), "kind": kind, "frames": to_json(frames)}
	var stem := dir + "v%04d" % n
	if not _write_json(stem + ".json", doc):
		return "cannot write " + stem + ".json"
	if kind == "saved":
		if not _write_json(DIR + name + ".json", doc):
			return "cannot write the head " + DIR + name + ".json"
	else:
		var autos := 0
		for v in versions(name):
			if v.kind == "auto":
				autos += 1
				if autos > AUTOSAVE_KEEP:
					DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + v.file))
	return "%s v%d of %s" % ["saved" if kind == "saved" else "auto-saved", n, name]


static func _write_json(path: String, doc: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(doc, " "))
	f.close()
	return true
