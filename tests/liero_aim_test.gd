# Liero aim (gecko.gd liero_aim, L in main.gd): Up and Down raise and
# lower a crosshair on the screen, in the half circle from the gecko's
# up through ahead to into the floor, instead of moving it; Left and Right still walk; the chew bites where it points. Run on the critters_lab scene:
#
#   GECKO_PROBE=res://tests/liero_aim_test.gd GECKO_SCENE=critters_lab:hold godot --path .
# Prints LIERO lines and LIERO TEST OK or LIERO TEST FAILS.
extends Node

var main: Node2D
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


func _check(name: String, ok: bool, detail: String) -> void:
	print("LIERO %s %s: %s" % ["ok  " if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1


func _run() -> void:
	await _ticks(60)
	main._demo_step = -1
	var g: Node2D = main.gecko
	g.input_override = null
	await _ticks(20)
	_key(KEY_L, true)
	await _ticks(2)
	_key(KEY_L, false)
	await _ticks(2)
	_check("toggle", g.liero_aim, "L turns Liero aim on")
	# Up held: the aim rises to straight up over the head, and the gecko
	# stays put
	var p0: Vector2 = g.pos
	_key(KEY_UP, true)
	await _ticks(60)
	_key(KEY_UP, false)
	var above: Vector2 = g._cursor() - g.chain.head()
	_check("aim up", above.normalized().dot(Vector2.UP) > 0.99, "the crosshair %s from the head" % above)
	_check("up still", g.pos.distance_to(p0) < 3.0, "the gecko moved %.1f px while Up was held" % g.pos.distance_to(p0))
	# Left still walks
	_key(KEY_LEFT, true)
	await _ticks(20)
	_key(KEY_LEFT, false)
	await _ticks(5)
	_check("left walks", g.pos.x < p0.x - 4.0, "the gecko went from x %.0f to %.0f" % [p0.x, g.pos.x])
	# Turned round, the aim mirrored to the left side; then Down from up
	# sweeps it ahead (left) on its way down, never behind
	_key(KEY_DOWN, true)
	await _ticks(12)
	_key(KEY_DOWN, false)
	var swept: Vector2 = g._cursor() - g.chain.head()
	_check("arc ahead", swept.x < -4.0, "partway down the crosshair is %s from the head (ahead is left)" % swept)
	# Down held: into the floor; a chew bites below the body
	_key(KEY_DOWN, true)
	await _ticks(90)
	_key(KEY_DOWN, false)
	var below: Vector2 = g._cursor() - g.chain.head()
	_check("aim down", below.normalized().dot(Vector2.DOWN) > 0.99, "the crosshair %s from the head" % below)
	# Through the dig (the body tips nose down into the shaft) the tunnel
	# goes on straight down
	var up0 := Vector2.UP
	var start: Vector2 = g.pos
	_key(KEY_E, true)
	await _ticks(60)
	var bite: Vector2 = g._bite
	_key(KEY_E, false)
	var into: float = (bite - start).dot(-up0)
	var sideways: float = absf((g.pos - start).dot(Vector2(-up0.y, up0.x)))
	_check("dig holds its line", into > 8.0 and sideways < 6.0, "the bite %.1f px below where the gecko stood, the body %.1f px off the line" % [into, sideways])
	main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://runs/liero_aim.png"))
	_key(KEY_L, true)
	await _ticks(2)
	_key(KEY_L, false)
	await _ticks(2)
	_check("toggle off", not g.liero_aim and InputMap.action_has_event("move_up", _arrow(KEY_UP)), "L gives Up and Down back to moving")
	print("LIERO TEST %s %d" % ["OK" if _fails == 0 else "FAILS", _fails])
	get_tree().quit()


func _arrow(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	return ev
