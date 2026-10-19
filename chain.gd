# Procedural animation chain. A head point leads, every body point trails
# it at a fixed link length, and each joint bends at most max_bend from
# the joint before it. Moving the head drags the body behind it, so a
# turning creature bends its spine and a straight run with a wiggle on
# the heading swims. The radii give the silhouette the blob layer draws.
class_name Chain
extends RefCounted

var points := PackedVector2Array()
var radii := PackedFloat32Array()
var link := 8.0
var max_bend := 0.6     # Radians per joint
var heading := Vector2.RIGHT


func _init(head: Vector2, radii_in: Array, link_len: float, bend: float, dir := Vector2.RIGHT) -> void:
	link = link_len
	max_bend = bend
	heading = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	points.resize(radii_in.size())
	radii.resize(radii_in.size())
	for i in radii_in.size():
		radii[i] = float(radii_in[i])
		points[i] = head - heading * link * i


func size() -> int:
	return points.size()


func head() -> Vector2:
	return points[0]


# Moves the head and resolves the body. The trailing direction of each
# link is clamped to max_bend from the link ahead of it, which keeps the
# spine from folding over itself.
func set_head(p: Vector2, dir: Vector2) -> void:
	if dir.length() > 0.001:
		heading = dir.normalized()
	points[0] = p
	var prev_trail := -heading
	for i in range(1, points.size()):
		var anchor := points[i - 1]
		var trail := points[i] - anchor
		var desired: Vector2 = trail.normalized() if trail.length() > 0.001 else prev_trail
		var ang := prev_trail.angle_to(desired)
		if absf(ang) > max_bend:
			desired = prev_trail.rotated(signf(ang) * max_bend)
		points[i] = anchor + desired * link
		prev_trail = desired


# Teleports the whole chain, laid out straight behind the head.
func reset(head_pos: Vector2, dir: Vector2) -> void:
	heading = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	for i in points.size():
		points[i] = head_pos - heading * link * i


# Closest distance from a world point to any segment circle edge.
# Negative means inside a circle.
func distance_to(p: Vector2) -> float:
	var best := INF
	for i in points.size():
		best = minf(best, p.distance_to(points[i]) - radii[i])
	return best


# True when any segment circle touches the capsule from a to b with the
# given radius.
func hits_capsule(a: Vector2, b: Vector2, radius: float) -> bool:
	var ab := b - a
	var ab_len2 := maxf(ab.length_squared(), 0.001)
	for i in points.size():
		var t := clampf((points[i] - a).dot(ab) / ab_len2, 0.0, 1.0)
		var closest := a + ab * t
		if points[i].distance_to(closest) < radius + radii[i]:
			return true
	return false
