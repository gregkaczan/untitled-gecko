# Scene driver for the gecko movement spike: one chamber (the particle
# sim, or the bitmap stand-in with GECKO_WORLD=bitmap), one gecko, a
# mouse brush for carving (Ctrl+right erases, middle fills, wheel sizes),
# R for a fresh chamber, F1 for the debug overlay, 1 and 2 for the gecko's
# pixel grid (4 px like the rock, or 2 px), Tab for the next test scene
# from tests/scenes.json and Shift+Tab back to the generated cave (the
# keys drive the gecko in a scene loaded this way). The mouse buttons are
# the gecko's: left tap spits, left hold is the tongue, right chews toward
# the cursor, and with no key held the gecko tunnels after the bite.
# GECKO_DEMO=1 in the environment replaces the keyboard with a scripted
# walk so movie-mode frames show the gecko moving without anyone at the keys.
# GECKO_SCENE=name[:script] runs a test scene from tests/scenes.json the
# same way and quits when the script ends; GECKO_SEED fixes the random
# bites and steps so a run repeats exactly.
extends Node2D

const CAMERA_ZOOM := 2.0
const CaveMap = preload("res://cave_map.gd")
const SimMap = preload("res://sim_map.gd")
const Sim = preload("res://sim.gd")
const Gecko = preload("res://gecko.gd")
const BlobLayer = preload("res://blob_layer.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const SCENE_SETTLE := 0.5      # Seconds a test scene runs on after its script

# Demo steps: seconds, input vector, jump on the first frame, chew held,
# then optionally the left button held and the cursor offset from the
# body. GECKO_DEMO=climb walks into the boulder and over it, tunnel chews
# through it and walks the tunnel both ways, swim drops into the pool,
# tongue grapples the ceiling and spits at the floor, dig chews after the
# cursor with no key held: down-right, up-right, straight down, back left.
const DEMOS := {
	"dig": [
		[0.5, Vector2.ZERO, false, false],
		[2.5, Vector2.ZERO, false, true, false, Vector2(120, 120)],
		[2.5, Vector2.ZERO, false, true, false, Vector2(140, -60)],
		[2.0, Vector2.ZERO, false, true, false, Vector2(0, 140)],
		[2.5, Vector2.ZERO, false, true, false, Vector2(-140, 0)],
	],
	"swim": [
		[0.3, Vector2.ZERO, false, false],
		[2.6, Vector2.LEFT, false, false],
		[0.6, Vector2.LEFT, true, false],
		[1.5, Vector2.DOWN, false, false],
		[1.5, Vector2.LEFT, false, false],
		[2.0, Vector2.UP, false, false],
		[1.5, Vector2.RIGHT, false, false],
		[2.5, Vector2.UP, false, false],
	],
	"gap": [
		[3.5, Vector2.RIGHT, false, false],
		[3.5, Vector2.LEFT, false, false],
	],
	"traverse": [
		[9.0, Vector2.RIGHT, false, false],
		[9.0, Vector2.LEFT, false, false],
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
var sim: Sim
var gecko: Gecko
var blobs: BlobLayer
var brush_r := 24.0
var seed_value := 7
var _label: Label
var _camera: Camera2D
var _demo: Array = []
var _hint_t := 0.0
var _trace := OS.get_environment("GECKO_TRACE") != ""
var _demo_name := OS.get_environment("GECKO_DEMO")
var _demo_step := -1
var _demo_t := 0.0
var _scene: Dictionary = {}    # The test scene being run, empty outside the suite
var _scene_bases: Dictionary = {}
var _scene_done := -1.0        # Seconds since the scene script ended, -1 while it runs
var _scene_all: Dictionary = {}  # tests/scenes.json, loaded on the first Tab
var _scene_i := -1             # Index of the scene Tab loaded, -1 in the generated cave
var _hint := ""                # Label text while the hint timer runs; empty for the controls hint


func _ready() -> void:
	InputSetup.ensure_actions()
	var seed_env := OS.get_environment("GECKO_SEED")
	if seed_env != "":
		seed(int(seed_env))
	var scene_spec := OS.get_environment("GECKO_SCENE")
	var picked: Dictionary = {}
	if scene_spec != "":
		picked = SceneBuilder.pick(scene_spec)
		if picked.is_empty():
			get_tree().quit(2)
			return
		_scene = picked.scene
		_scene_bases = picked.bases
	# The particle sim is the world unless GECKO_WORLD=bitmap asks for the
	# static stand-in (faster to start, and what the demo strips were tuned on).
	if OS.get_environment("GECKO_WORLD") == "bitmap":
		map = CaveMap.new()
	else:
		sim = Sim.new()
		add_child(sim)
		var sm := SimMap.new()
		sm.sim = sim
		map = sm
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
	if not picked.is_empty():
		_demo = picked.steps
		_demo_step = 0
		_demo_t = 0.0
		gecko.input_override = Vector2.ZERO
	elif _demo_name != "":
		_demo = DEMOS.get(_demo_name, DEMOS["climb"])
		_demo_step = 0
		_demo_t = 0.0
		gecko.input_override = Vector2.ZERO


func _reset() -> void:
	if not _scene.is_empty():
		if sim:
			# The scene is built on a CPU map and the particles are made
			# from it, as the generated cave's are.
			var gen := CaveMap.new()
			SceneBuilder.build(gen, _scene, _scene_bases)
			map.build_cells(gen.solid)
			gen.free()
		else:
			SceneBuilder.build(map, _scene, _scene_bases)
		var sp := SceneBuilder.spawn_point(map, _scene, Gecko.RIDE_H)
		gecko.spawn(sp.pos, sp.up)
		_camera.position = gecko.pos
		_camera.reset_smoothing()
		return
	map.generate(seed_value)
	var spawn := _flat_spawn()
	if _demo_name == "climb":
		# A straight pillar to the right of the spawn: the wall test
		map.fill_rect(Rect2(spawn.x + 110.0, spawn.y - 170.0, 32.0, 200.0))
	elif _demo_name == "gap":
		# A hole the body can span, then one it cannot
		map.erase_circle(Vector2(spawn.x + 80.0, spawn.y + 6.0), 15.0)
		map.erase_circle(Vector2(spawn.x + 220.0, spawn.y + 10.0), 26.0)
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
	if sim:
		sim.tick()
	_camera.position = gecko.pos
	if _demo_step >= 0:
		_run_demo(dt)
	# The state readout only with the debug overlay; the controls hint for
	# the first seconds of a run.
	_hint_t += dt
	if gecko.debug:
		_label.text = gecko.debug_text() + "   brush %.0f   [LMB tap spit, hold tongue, RMB chew, Space jump, Ctrl+RMB erase, MMB fill, wheel size, R new cave, F1 debug, 1/2 gecko px]" % brush_r
	elif _hint_t < 10.0:
		_label.text = _hint if _hint != "" else "WASD move   Space jump   LMB tap spit, hold tongue   RMB chew at cursor   R new cave   Tab test scene   F1 debug"
	else:
		_label.text = ""


# Tab: the next test scene from tests/scenes.json, built in this world,
# with the keys driving the gecko instead of the scene's script.
func _next_scene() -> void:
	if _scene_all.is_empty():
		_scene_all = SceneBuilder.load_all()
	var names: Array = _scene_all.scenes.keys()
	if names.is_empty():
		return
	_scene_i = (_scene_i + 1) % names.size()
	var name: String = names[_scene_i]
	_scene = _scene_all.scenes[name]
	_scene_bases = _scene_all.bases
	_demo_step = -1
	gecko.input_override = null
	gecko.chew_override = false
	gecko.lmb_override = false
	_reset()
	_hint = "scene %d/%d  %s   (Tab next, Shift+Tab main cave)" % [_scene_i + 1, names.size(), name]
	_hint_t = 5.0


# Shift+Tab: back to the generated cave.
func _main_cave() -> void:
	_scene = {}
	_scene_i = -1
	_reset()
	_hint = "main cave"
	_hint_t = 7.0


func _run_demo(dt: float) -> void:
	if _demo_step >= _demo.size():
		gecko.input_override = Vector2.ZERO
		gecko.chew_override = false
		gecko.lmb_override = false
		gecko.aim_override = Vector2.ZERO
		if not _scene.is_empty():
			_scene_done = maxf(_scene_done, 0.0) + dt
			if _scene_done >= SCENE_SETTLE:
				get_tree().quit()
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
	if sim:
		sim.read_render()
	if _trace:
		# Screen position in the movie frame. The window is unstretched
		# (project.godot), so the frame is the window's size, one pixel
		# per pixel, whatever size the compositor gave it.
		var half := get_viewport().get_visible_rect().size * 0.5
		var screen := (gecko.pos - _camera.get_screen_center_position()) * CAMERA_ZOOM + half
		print("F%d %d %d %d" % [Engine.get_frames_drawn(), int(screen.x), int(screen.y), gecko._tick])
	var m := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.is_key_pressed(KEY_CTRL):
		map.erase_circle(m, brush_r)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		map.fill_circle(m, brush_r)
	if Input.is_action_just_pressed("regenerate"):
		seed_value += 1
		_scene = {}
		_scene_i = -1
		_reset()
	# Exact matches, so Tab with Shift held is only the one action.
	if Input.is_action_just_pressed("scene_next", true):
		_next_scene()
	if Input.is_action_just_pressed("scene_main", true):
		_main_cave()
	if Input.is_action_just_pressed("debug_toggle"):
		gecko.debug = not gecko.debug
	if Input.is_action_just_pressed("render_coarse"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_COARSE)
	if Input.is_action_just_pressed("render_fine"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_FINE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_r = minf(brush_r + 4.0, 80.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_r = maxf(brush_r - 4.0, 8.0)
