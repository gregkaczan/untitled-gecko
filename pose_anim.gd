# Pose animations for the gecko. A frame is the chain's ten points, the
# four feet (where they are drawn) and the look, in the gecko's own
# frame: the surface line at y = 0, up along -y, the walk's facing along
# +x; the eye as an offset from the head (EYE_MAX at most: on the head's
# disc), riding with the look (EYE_LOOK along it, a pixel up) until the
# editor places it by hand; with the seconds to the next frame, an ease
# and whether the eye is shut (asleep). Playback blends
# frame to frame in link space, each link's angle and length (lerp_angle),
# so a curled body unrolls through a blend instead of shrinking through
# it as blended points would; the head and the feet blend as points. A
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
const EASES := ["smooth", "linear", "in", "out"]
const DUR_DEFAULT := 0.3
const AUTOSAVE_KEEP := 10
const FOOT_DRAWN_Y := -4.5     # A standing foot as drawn: FOOT_LIFT over its anchor on the surface line
const EYE_LOOK := 3.5          # The eye's place along the look when it rides with it (gecko.gd _face)
const EYE_UP := Vector2(0.0, -1.0)   # and a pixel up
const EYE_MAX := 5.0           # Farthest the eye's centre may sit from the head's (its 4 px disc stays on the 7 px head)
const FOLD_ANGLE := 2.6        # Radians (150 degrees) a link turns between two frames beyond which it is pulled through, not swung
# The gecko at rest on a floor, read off a settled run (the suite's
# flat:idle trace): the head 15 px ahead of the body centre and 18 up,
# the body sagging to a tail tip 5 px over the ground; the feet as drawn.
# The feet are in the gecko's order: front near, front far, back near,
# back far.
const STANDING_POINTS := [[15.0, -18.0], [7.0, -15.1], [-1.0, -12.5], [-9.0, -11.5], [-17.0, -9.2], [-25.0, -7.4], [-33.0, -6.4], [-41.0, -5.7], [-49.0, -5.2], [-57.0, -4.9]]
const STANDING_FEET := [[18.0, -4.5], [16.0, -4.5], [-22.0, -4.5], [-18.0, -4.5]]


static func standing() -> Dictionary:
	return from_json_frame({"points": STANDING_POINTS, "feet": STANDING_FEET, "look": [1.0, 0.0], "dur": DUR_DEFAULT, "ease": "smooth"})


static func dup(f: Dictionary) -> Dictionary:
	var pts: PackedVector2Array = f.points
	var feet: PackedVector2Array = f.feet
	return {"points": pts.duplicate(), "feet": feet.duplicate(), "look": f.look, "eye": f.get("eye", eye_for(f.look)), "eye_free": f.get("eye_free", false), "dur": f.dur, "ease": f.ease, "shut": f.get("shut", false)}


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


# The pose t seconds in: frame i blends to frame i + 1 over frame i's
# seconds; the last frame holds for its seconds, or looping blends back
# to the first. Past the end, the last frame.
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
			return blend(frames[i], frames[(i + 1) % n], eased(k, String(frames[i].ease)))
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


static func eased(k: float, ease: String) -> float:
	match ease:
		"linear":
			return k
		"in":
			return k * k
		"out":
			return 1.0 - (1.0 - k) * (1.0 - k)
	return k * k * (3.0 - 2.0 * k)


# a toward b by k, the chain in link space.
static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := dup(a)
	var pa: PackedVector2Array = a.points
	var pb: PackedVector2Array = b.points
	var pts := PackedVector2Array()
	pts.resize(pa.size())
	pts[0] = pa[0].lerp(pb[0], k)
	for i in range(1, pa.size()):
		var va := pa[i] - pa[i - 1]
		var vb := pb[i] - pb[i - 1]
		var turn := angle_difference(va.angle(), vb.angle())
		var ang: float
		var len := lerpf(va.length(), vb.length(), k)
		if absf(turn) > FOLD_ANGLE:
			# Pulled through: seen from the side, a link swinging round
			# sideways shortens to nothing and comes back the other way.
			ang = va.angle() if k < 0.5 else vb.angle()
			len *= absf(cos(PI * k))
		else:
			ang = va.angle() + turn * k
		pts[i] = pts[i - 1] + Vector2.from_angle(ang) * len
	out.points = pts
	var fa: PackedVector2Array = a.feet
	var fb: PackedVector2Array = b.feet
	var feet := PackedVector2Array()
	feet.resize(fa.size())
	for i in fa.size():
		feet[i] = fa[i].lerp(fb[i], k)
	out.feet = feet
	var la: Vector2 = a.look
	var lb: Vector2 = b.look
	out.look = Vector2.from_angle(lerp_angle(la.angle(), lb.angle(), k))
	var ea: Vector2 = a.get("eye", eye_for(la))
	var eb: Vector2 = b.get("eye", eye_for(lb))
	out.eye = ea.lerp(eb, k)
	out.shut = a.get("shut", false) if k < 0.5 else b.get("shut", false)
	return out


# --- The gecko's frame ---
#
# base is the point on the surface under the body centre, up the
# surface normal, facing the walk's: +1 along the tangent, -1 against it.

static func to_world(local: Vector2, base: Vector2, up: Vector2, facing: float) -> Vector2:
	var t := Vector2(-up.y, up.x)
	return base + t * (local.x * facing) - up * local.y


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
	var ease := String(d.get("ease", "smooth"))
	if not EASES.has(ease):
		ease = "smooth"
	look = look.normalized()
	var eye := eye_for(look)
	var eye_free := false
	var ey = d.get("eye", null)
	if ey is Array and ey.size() >= 2:
		eye = Vector2(float(ey[0]), float(ey[1])).limit_length(EYE_MAX)
		eye_free = true
	return {"points": pts, "feet": feet, "look": look, "eye": eye, "eye_free": eye_free, "dur": maxf(float(d.get("dur", DUR_DEFAULT)), 0.0), "ease": ease, "shut": bool(d.get("shut", false))}


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
		var item := {"points": pts, "feet": feet, "look": [snappedf(look.x, 0.001), snappedf(look.y, 0.001)], "dur": snappedf(float(f.dur), 0.001), "ease": f.ease, "shut": bool(f.get("shut", false))}
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
