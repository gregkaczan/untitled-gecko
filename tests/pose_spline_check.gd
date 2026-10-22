# Headless check of the pose spline (pose_anim.gd between): the poses
# set to tension 1 match the old smooth-eased blend, at tension 0 the body
# keeps moving through the inner frames, no link changes length beyond
# its ends, and no head or foot dips below both its ends. The editor's
# spine lock leaves the spine and the link lengths alone and reaches the
# target, and the leg limit holds the feet to LEG_MAX.
# godot --headless --path . --script res://tests/pose_spline_check.gd
extends SceneTree

const PoseAnim = preload("res://pose_anim.gd")


# The blend before the spline: link space, smoothstep; folds as vectors.
func old_blend(a: Dictionary, b: Dictionary, k: float) -> PackedVector2Array:
	k = k * k * (3.0 - 2.0 * k)
	var pa: PackedVector2Array = a.points
	var pb: PackedVector2Array = b.points
	var pts := PackedVector2Array()
	pts.resize(pa.size())
	pts[0] = pa[0].lerp(pb[0], k)
	for i in range(1, pa.size()):
		var va := pa[i] - pa[i - 1]
		var vb := pb[i] - pb[i - 1]
		var turn := angle_difference(va.angle(), vb.angle())
		var long := maxf(va.length(), vb.length())
		if absf(turn) > PoseAnim.FOLD_ANGLE or minf(va.length(), vb.length()) < PoseAnim.SHORT_LINK * long:
			# Since the uncurl rework a fold runs as a vector, through nothing.
			pts[i] = pts[i - 1] + va.lerp(vb, k).limit_length(long)
			continue
		var len := lerpf(va.length(), vb.length(), k)
		var ang := va.angle() + turn * k
		pts[i] = pts[i - 1] + Vector2.from_angle(ang) * len
	return pts


func speed_at_keys(frames: Array) -> Array:
	# The head's and the chain's mean speed (px/s) just around each inner key.
	var out: Array = []
	var t := 0.0
	for i in range(frames.size() - 1):
		t += float(frames[i].dur)
		if i == frames.size() - 2:
			break
		var e := 0.004
		var p0: PackedVector2Array = PoseAnim.sample(frames, t - e).points
		var p1: PackedVector2Array = PoseAnim.sample(frames, t + e).points
		var v := 0.0
		for j in p0.size():
			v += p0[j].distance_to(p1[j])
		out.append(snappedf(v / p0.size() / (2.0 * e), 0.1))
	return out


func _init() -> void:
	var ok := true
	for name in ["wake", "meerkat"]:
		var saved := PoseAnim.load_head(name)
		var frames := PoseAnim.dup_all(saved)
		for f in frames:
			f.tension = 1.0
			f.bias = 0.0
		var worst := 0.0
		var t := 0.0
		for i in range(frames.size() - 1):
			for s in 20:
				var k := s / 20.0
				var got: PackedVector2Array = PoseAnim.sample(frames, t + k * float(frames[i].dur)).points
				var want := old_blend(frames[i], frames[i + 1], k)
				for j in got.size():
					worst = maxf(worst, got[j].distance_to(want[j]))
			t += float(frames[i].dur)
		print("%s at tension 1: worst gap to the old blend %.5f px" % [name, worst])
		if worst > 0.001:
			ok = false
		print("  chain speed at inner keys, tension 1: ", speed_at_keys(frames))
		print("  chain speed at inner keys, as saved:  ", speed_at_keys(saved))
		var flow := PoseAnim.dup_all(frames)
		for f in flow:
			f.tension = 0.0
		print("  chain speed at inner keys, tension 0: ", speed_at_keys(flow))
		# Overshoot: link lengths and the floor.
		var tot := PoseAnim.total(flow)
		var lo_y := 1e9
		var key_lo := 1e9
		for f in flow:
			for p in f.feet:
				key_lo = minf(key_lo, -p.y)
		var bad_len := 0.0
		for s in 400:
			var tt := tot * s / 400.0
			var i := PoseAnim.frame_at(flow, tt)
			var f := PoseAnim.sample(flow, tt)
			for p in f.feet:
				lo_y = minf(lo_y, -p.y)
			if i < flow.size() - 1:
				var pa: PackedVector2Array = flow[i].points
				var pb: PackedVector2Array = flow[i + 1].points
				var pf: PackedVector2Array = f.points
				for j in range(1, pf.size()):
					var l := pf[j].distance_to(pf[j - 1])
					var hi := maxf(pa[j].distance_to(pa[j - 1]), pb[j].distance_to(pb[j - 1]))
					bad_len = maxf(bad_len, l - hi)
		print("  tension 0: lowest foot %.2f px up (keys' lowest %.2f), worst link over its ends %.4f px" % [lo_y, key_lo, bad_len])
		if lo_y < key_lo - 0.001 or bad_len > 0.001:
			ok = false
	var st := PoseAnim.standing()
	var spine: PackedVector2Array = st.points.duplicate()
	for target in [Vector2(-40.0, -20.0), Vector2(-20.0, 0.0), Vector2(-90.0, -6.0), Vector2(30.0, -40.0)]:
		for i in [0, 6, 9]:
			var f := PoseAnim.dup(st)
			PoseAnim.follow_locked(f, i, target)
			var pts: PackedVector2Array = f.points
			var moved := 0.0
			for j in range(1, PoseAnim.SPINE_LAST + 1):
				moved = maxf(moved, pts[j].distance_to(spine[j]))
			var stretch := 0.0
			for j in range(1, pts.size()):
				stretch = maxf(stretch, absf(pts[j].distance_to(pts[j - 1]) - spine[j].distance_to(spine[j - 1])))
			if moved > 0.001 or stretch > 0.01:
				print("spine lock: point %d to %s moved the spine %.3f, a link by %.3f" % [i, target, moved, stretch])
				ok = false
	var f2 := PoseAnim.dup(st)
	PoseAnim.follow_locked(f2, 8, Vector2(-40.0, -20.0))
	var miss: float = f2.points[8].distance_to(Vector2(-40.0, -20.0))
	print("spine lock: tail point 9 to (-40, -20) lands %.3f px off" % miss)
	if miss > 0.05:
		ok = false
	if PoseAnim.follow_locked(PoseAnim.dup(st), 2, Vector2.ZERO):
		ok = false
	var f3 := PoseAnim.dup(st)
	f3.feet = PackedVector2Array([Vector2(80, 0), Vector2(16, -4.5), Vector2(-22, 60), Vector2(-18, -4.5)])
	PoseAnim.keep_legs(f3)
	var longest := 0.0
	for k in 4:
		longest = maxf(longest, f3.feet[k].distance_to(f3.points[PoseAnim.hip_of(k)]))
	print("legs: longest after the limit %.2f px (LEG_MAX %.0f), the standing feet kept: %s" % [longest, PoseAnim.LEG_MAX, f3.feet[1] == Vector2(16, -4.5)])
	if longest > PoseAnim.LEG_MAX + 0.001 or f3.feet[1] != Vector2(16, -4.5):
		ok = false
	print("POSE SPLINE OK" if ok else "POSE SPLINE FAILS")
	quit()
