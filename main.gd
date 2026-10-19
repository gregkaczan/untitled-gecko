# Scene driver for the gecko movement spike: one chamber, one gecko, a
# mouse brush for carving (right erases, middle fills, wheel sizes), R
# for a fresh chamber, F1 for the debug overlay. The left button is the
# gecko's: tap to spit, hold for the tongue. GECKO_DEMO=1 in the
# environment replaces the keyboard with a scripted walk so movie-mode
# frames show the gecko moving without anyone at the keys.
extends Node2D

const CAMERA_ZOOM := 2.0
const CaveMap = preload("res://cave_map.gd")
const Gecko = preload("res://gecko.gd")
const BlobLayer = preload("res://blob_layer.gd")

# Demo steps: seconds, input vector, jump on the first frame, chew held,
# then optionally the left button held and the cursor offset from the
# body. GECKO_DEMO=climb walks into the boulder and over it, tunnel chews
# through it and walks the tunnel both ways, swim drops into the pool,
# tongue grapples the ceiling and spits at the floor.
const DEMOS := {
	"swim": [
		[0.3, Vector2.ZERO, false, false],
		[4.5, Vector2.LEFT, false, false],
		[1.5, Vector2.DOWN, false, false],
		[1.5, Vector2.LEFT, false, false],
		[2.0, Vector2.UP, false, false],
		[1.5, Vector2.RIGHT, false, false],
		[2.5, Vector2.UP, false, false],
	],
	"notch": [
		[4.5, Vector2.RIGHT, false, false],
		[1.5, Vector2.UP, false, false],
		[1.5, Vector2.RIGHT, false, false],
		[1.5, Vector2(1, -1), false, false],
	],
	"crevice": [
		[1.2, Vector2.RIGHT, false, false],
		[1.5, Vector2(1, 1), false, false],
		[1.0, Vector2.DOWN, false, false],
		[1.0, Vector2.LEFT, false, false],
		[2.0, Vector2.UP, false, false],
		[1.5, Vector2(-1, -1), false, false],
	],
	"tongue": [
		[1.5, Vector2.RIGHT, false, false, false, Vector2(160, -160)],
		[0.3, Vector2.ZERO, false, false, false, Vector2(160, -160)],
		[2.5, Vector2.ZERO, false, false, true, Vector2(160, -160)],
		[1.0, Vector2.ZERO, false, false, false, Vector2(60, 200)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(60, 200)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(60, 200)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(-80, 200)],
		[2.0, Vector2.ZERO, false, false, false, Vector2(-80, 200)],
	],
	"climb": [
		[1.3, Vector2.RIGHT, false, false],
		[3.0, Vector2.UP, false, false],
		[1.5, Vector2(1, -1), false, false],
		[2.5, Vector2.LEFT, false, false],
		[1.0, Vector2.ZERO, false, false],
		[1.5, Vector2.ZERO, true, false],
		[2.0, Vector2.LEFT, false, false],
		[1.0, Vector2.RIGHT, true, false],
		[2.0, Vector2.RIGHT, false, false],
	],
	"tunnel": [
		[0.3, Vector2.ZERO, false, false],
		[3.6, Vector2.RIGHT, false, true],
		[0.5, Vector2.ZERO, false, false],
		[3.0, Vector2.LEFT, false, false],
		[0.5, Vector2.ZERO, false, false],
		[3.0, Vector2.RIGHT, false, false],
		[2.5, Vector2.LEFT, false, false],
	],
}

var map: CaveMap
var gecko: Gecko
var blobs: BlobLayer
var brush_r := 24.0
var seed_value := 7
var _label: Label
var _camera: Camera2D
var _demo: Array = []
var _trace := OS.get_environment("GECKO_TRACE") != ""
var _demo_name := OS.get_environment("GECKO_DEMO")
var _demo_step := -1
var _demo_t := 0.0


func _ready() -> void:
	InputSetup.ensure_actions()
	map = CaveMap.new()
	add_child(map)
	blobs = BlobLayer.new()
	add_child(blobs)
	gecko = Gecko.new()
	gecko.map = map
	gecko.blobs = blobs
	add_child(gecko)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(CaveMap.W * CaveMap.CELL)
	_camera.limit_bottom = int(CaveMap.H * CaveMap.CELL)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 6.0
	add_child(_camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 20)
	hud.add_child(_label)
	_reset()
	if _demo_name != "":
		_demo = DEMOS.get(_demo_name, DEMOS["climb"])
		_demo_step = 0
		_demo_t = 0.0
		gecko.input_override = Vector2.ZERO


func _reset() -> void:
	map.generate(seed_value)
	var spawn := _flat_spawn()
	if _demo_name == "climb":
		# A straight pillar to the right of the spawn: the wall test
		map.fill_rect(Rect2(spawn.x + 110.0, spawn.y - 170.0, 32.0, 200.0))
	elif _demo_name == "crevice":
		# A funnel in the floor, 44 px wide at the top narrowing to nothing
		for i in range(9):
			map.erase_circle(Vector2(spawn.x + 90.0, spawn.y + 6.0 + i * 8.0), 22.0 - i * 2.0)
	gecko.spawn(spawn - Vector2(0.0, Gecko.RIDE_H))
	_camera.position = gecko.pos
	_camera.reset_smoothing()


# The floor point near the middle of the chamber with the least slope
# across a body length, so the gecko starts level.
func _flat_spawn() -> Vector2:
	var best := Vector2.ZERO
	var best_slope := INF
	for x in range(800, 1121, 8):
		var y0 := map.floor_below(Vector2(x - 24.0, 540.0)).y
		var y1 := map.floor_below(Vector2(x + 24.0, 540.0)).y
		var slope := absf(y1 - y0)
		if slope < best_slope:
			best_slope = slope
			best = map.floor_below(Vector2(x, 540.0))
	return best


func _physics_process(dt: float) -> void:
	_camera.position = gecko.pos
	if _demo_step >= 0:
		_run_demo(dt)
	_label.text = gecko.debug_text() + "   brush %.0f   [LMB tap spit, hold tongue, E chew, Space jump, RMB erase, MMB fill, wheel size, R new cave, F1 debug]" % brush_r


func _run_demo(dt: float) -> void:
	if _demo_step >= _demo.size():
		gecko.input_override = Vector2.ZERO
		gecko.chew_override = false
		gecko.lmb_override = false
		return
	var step: Array = _demo[_demo_step]
	if _demo_t == 0.0 and step[2]:
		gecko.jump_override = true
	gecko.input_override = step[1]
	gecko.chew_override = step[3]
	gecko.lmb_override = step[4] if step.size() > 4 else false
	gecko.aim_override = step[5] if step.size() > 5 else Vector2.ZERO
	_demo_t += dt
	if _demo_t >= step[0]:
		_demo_step += 1
		_demo_t = 0.0


func _process(_dt: float) -> void:
	if _trace:
		var screen := (gecko.pos - _camera.get_screen_center_position()) * CAMERA_ZOOM + Vector2(960.0, 540.0)
		print("F%d %d %d" % [Engine.get_frames_drawn(), int(screen.x), int(screen.y)])
	var m := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		map.erase_circle(m, brush_r)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		map.fill_circle(m, brush_r)
	if Input.is_action_just_pressed("regenerate"):
		seed_value += 1
		_reset()
	if Input.is_action_just_pressed("debug_toggle"):
		gecko.debug = not gecko.debug


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_r = minf(brush_r + 4.0, 80.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_r = maxf(brush_r - 4.0, 8.0)
