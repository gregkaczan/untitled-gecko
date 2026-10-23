# Scene driver for the gecko game: a generated cave (seed OPEN_SEED)
# built in the particle sim, or in the bitmap stand-in with
# GECKO_WORLD=bitmap; the main cave (the scene named LEVEL, levels/cave5.json
# for now, Shift+Tab) with its loose lumps and its exit, which pulls the
# camera back over the whole cave when the gecko gets there; one gecko; a
# mouse brush for carving (Ctrl+right erases, middle fills, wheel sizes),
# R to start the cave again (a fresh chamber when in a generated one),
# F1 for debug mode (the state readout and a
# panel down the right: scenes, seed, brush, clock, pixel grid, and the
# gecko's overlay behind the panel's Overlay check; a hand-played run
# starts in debug mode, OPEN_DEBUG, with the overlay off, OPEN_OVERLAY), 1 and 2
# for the gecko's pixel grid (2 px like the rock, or 1 px), Tab or F2 for
# the map editor (editor.gd), Ctrl+Tab for the next test scene
# from tests/scenes.json and Shift+Tab back to the first cave (the
# keys drive the gecko in a scene loaded this way), F3 for the pose
# editor (pose_editor.gd, a scene of its own); the panel's New cave
# builds a generated chamber from its seed. GECKO_DUMP_MAP=file.png
# writes the bitmap world's cells as a PNG and quits. The mouse buttons are
# the gecko's: a left press shoots the tongue, which strikes what it
# hits on a tap, grapples on a hold, and sticks and drags it in when the
# right button is held too; right alone chews toward the cursor, and
# with no key held the gecko
# tunnels after the bite, a bite every CHEW_PERIOD. B, C and N drop a
# boulder, a clump of clay or a heap of sand at the cursor, half the
# brush's size, and N held pours sand there. The generated cave gets a
# few lumps and heaps of its own (_scatter_chunks).
# GECKO_LEVEL=name opens the game on a level from levels/.
# GECKO_DEMO=1 in the environment replaces the keyboard with a scripted
# walk so movie-mode frames show the gecko moving without anyone at the keys.
# GECKO_SCENE=name[:script] runs a test scene from tests/scenes.json the
# same way and quits when the script ends; GECKO_SEED fixes the random
# bites and steps so a run repeats exactly. GECKO_SENSE=4 puts the
# gecko's senses on the 4 px fold and GECKO_CRUMB=n sets the crumb
# threshold, both the debug panel's. The sound is muted unless
# GECKO_SOUND=1 or the panel's Sound is on.
extends Node2D

const CAMERA_ZOOM := 2.0
const CAMERA_EASE := 16.0      # How fast the camera closes on the gecko (per second), once it has fallen behind
const CAM_LOCK_SPEED := 220.0  # Up to this speed (px/s) the camera scrolls exactly with the drawn body, so an ordinary walk or climb keeps the body on the same screen pixels
const CAM_GRID := 1.0 / CAMERA_ZOOM  # The camera sits on whole screen pixels: half a world pixel at this zoom
const UNDO_MAX := 40           # Strokes the editor keeps for undo (each a copy of the authored cells)
const EDIT_ZOOM_STEP := 1.25   # The editor's wheel: the zoom multiplied or divided by this a notch
const GLOW_COLOR := Color(1.0, 0.82, 0.58)   # The gecko's own light, warm and small (the sim's light pass)
const GLOW_R := 14.0                         # Px round the head seeded at full glow; the spread carries it on
const DAYLIGHT := Color(0.85, 0.92, 1.0)     # The light at the exit's crack
const VINE_HOLD := 1.2                       # Seconds the gecko may hang on a vine before its anchor gives
const VINE_TEAR := false                     # Off for now: a vine holds the gecko as long as it hangs (a bite through it still drops what is below)
const BLAST_SPEED := 480.0                   # px/s a gas burst throws the gecko
const BLAST_R := 45.0                        # The sim's blast round a burst pocket's centre
const CaveMap = preload("res://cave_map.gd")
const SimMap = preload("res://sim_map.gd")
const Sim = preload("res://sim.gd")
const SoundBank = preload("res://sound.gd")
const Ambience = preload("res://ambience.gd")
const Backdrop = preload("res://backdrop.gd")
const Slug = preload("res://slug.gd")
const Critters = preload("res://critters.gd")
const Shroom = preload("res://shroom.gd")
const Editor = preload("res://editor.gd")
const DecorBrush = preload("res://decor_brush.gd")
const Gecko = preload("res://gecko.gd")
const BlobLayer = preload("res://blob_layer.gd")
const SceneBuilder = preload("res://tests/scene_builder.gd")
const DebugPanel = preload("res://debug_panel.gd")
const PoseAnim = preload("res://pose_anim.gd")
const Gut = preload("res://gut.gd")
const Waves = preload("res://waves.gd")
const WavePanel = preload("res://wave_panel.gd")
const SCENE_SETTLE := 0.5      # Seconds a test scene runs on after its script
var _stay := OS.get_environment("GECKO_STAY") != ""   # GECKO_STAY=1: a test scene hands the keys over when its script ends instead of quitting, to play on from where it left the gecko
const LEVEL := "cave5"         # The main cave: the scene Shift+Tab goes to (and the game opens on when OPEN_SEED is 0); cave 5 as edited (levels/cave5.json) for now, the clutch before
const OPEN_SEED := 5           # The game opens in the generated cave with this seed; 0 opens on LEVEL instead
const OPEN_DEBUG := true       # A hand-played run (no GECKO_SCENE or GECKO_DEMO) starts in debug mode, as after F1
const OPEN_OVERLAY := false    # The panel's Overlay check at the start: the gecko's overlay (up, probe, feet, bite)
const WIN_ZOOM := 0.85         # The camera's zoom once the gecko is out, the whole cave in view
const WIN_PULL := 0.6          # How fast it pulls back (per second)
const CAM_LIMIT := 1000000     # No camera limit, while the pull-back shows the rock round the cave
const LAB_FLOOR := 800.0       # The tongue demos' flat room: its floor line
const LAB_CEIL := 680.0        # and its ceiling, within the tongue's reach of the floor

# Demo steps: seconds, input vector, jump on the first frame, chew held
# (the right button), then optionally the left button held and the
# cursor offset from the body. GECKO_DEMO=climb walks into the boulder
# and over it, tunnel chews through it and walks the tunnel both ways,
# swim drops into the pool, tongue grapples the ceiling on a held left
# button, then strikes the floor from it with taps, pull drags a stone
# in with both buttons and swallows it, then
# drags a boulder to the mouth and walks it along, strike dents the
# floor and breaks the boulder, dig chews after the cursor with no key
# held: down-right, up-right, straight down, back left.
const DEMOS := {
	"pull": [
		[0.6, Vector2.ZERO, false, false],
		[2.4, Vector2.ZERO, false, true, true, Vector2(90, 9)],
		[0.6, Vector2.ZERO, false, false],
		[4.0, Vector2.ZERO, false, true, true, Vector2(190, 1)],
		[0.6, Vector2.ZERO, false, false],
		[3.5, Vector2.RIGHT, false, false],
		[2.0, Vector2.LEFT, false, false],
	],
	"strike": [
		[0.6, Vector2.ZERO, false, false],
		[0.05, Vector2.ZERO, false, false, true, Vector2(70, 30)],
		[1.2, Vector2.ZERO, false, false, false, Vector2(70, 30)],
		[0.05, Vector2.ZERO, false, false, true, Vector2(150, 1)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(150, 1)],
		[0.05, Vector2.ZERO, false, false, true, Vector2(150, 1)],
		[2.5, Vector2.ZERO, false, false, false, Vector2(150, 1)],
	],
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
		[1.0, Vector2.ZERO, false, false, false, Vector2(60, -110)],
		[2.5, Vector2.ZERO, false, false, true, Vector2(60, -110)],
		[1.0, Vector2.ZERO, false, false, false, Vector2(40, 100)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(40, 100)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(40, 100)],
		[0.08, Vector2.ZERO, false, false, true, Vector2(-60, 100)],
		[1.5, Vector2.ZERO, false, false, false, Vector2(-60, 100)],
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
var seed_value := OPEN_SEED if OPEN_SEED > 0 else 7
var _label: Label
var _camera: Camera2D
var _cam := Vector2.ZERO       # The camera's eased position before pixel snapping
var _cam_target := Vector2.ZERO  # The drawn body's base the camera last followed, for its move this tick
var _cam_seat := Vector2.ZERO  # The base's place on the screen's pixels: where the blob layer's grid is anchored
var _seat_off := Vector2.ZERO  # That place as an offset from the camera, kept until the lag has left it by a screen pixel
var _demo: Array = []
var _hint_t := 0.0
var _trace := OS.get_environment("GECKO_TRACE") != ""
var _demo_name := OS.get_environment("GECKO_DEMO")
var _timing := OS.get_environment("GECKO_TIMING") != ""  # T lines every 60 ticks: the sim tick, the gecko's tick and the render readback in ms, mean and max
var _t_sim: Array[int] = []
var _t_gecko: Array[int] = []
var _t_render: Array[int] = []
var _fps_label: Label           # Bottom left, always on: fps, the frame, the gecko's tick and the sim's tick in ms, each with its worst over the last half second (the player's frame drops)
var _gut: Gut                   # Bottom left, always on: the stomach the chewed rock drops into (gut.gd)
var _fps_t := 0.0               # Seconds since the readout was last refreshed
var _frame_peak := 0.0          # Worst frame (ms) since then
var _gecko_us := 0
var _gecko_peak := 0
var _sim_us := 0
var _sim_peak := 0
var _read_us := 0
var _read_peak := 0
var _demo_step := -1
var _demo_t := 0.0
var _scene: Dictionary = {}    # The test scene being run, empty outside the suite
var _scene_bases: Dictionary = {}
var _scene_done := -1.0        # Seconds since the scene script ended, -1 while it runs
var _scene_all: Dictionary = {}  # tests/scenes.json, loaded on the first Tab
var _scene_i := -1             # Index of the scene Tab loaded, -1 in the generated cave
var _hint := ""                # Label text while the hint timer runs; empty for the controls hint
var _panel: DebugPanel
var _debug := false            # F1: the panel and the state readout, with the gecko's overlay if the panel's check is on
var _step_ticks := 0           # Physics ticks left to run before pausing again (the panel's step)
var _exit := Rect2()           # The level's exit, empty in a scene without one
var _sound: Node2D              # sound.gd: the one-shots on the gecko's events, the drone and the hum
var _sound_on := OS.get_environment("GECKO_SOUND") == "1"  # Muted unless asked: GECKO_SOUND=1, or the debug panel's Sound
var _ambience: Node2D           # ambience.gd: drips, bite dust, bubbles
var critters: Node2D             # critters.gd: the shrooms that bend, the vines that swing, the slimes and the long slugs
var _backdrop: Node2D           # backdrop.gd: the far wall and the near dripstone, particle world only
var _slugs: Array = []          # slug.gd: the glow slugs in the level
var _gas: Array = []            # Rect2 of each sealed gas pocket still to burst (the scene's gas ops)
var _editor: CanvasLayer        # editor.gd: the map editor's panel (Tab or F2)
var _editing := false
var _cam_grid := CAM_GRID       # The camera's grid, 1 / zoom: CAM_GRID at the game's zoom, finer or coarser once the editor zooms
var _edit_cam := false          # The editor zoomed or panned: the camera stays put, no follow, until Home
var _author: CaveMap            # The terrain as authored, the paints alone: the bitmap map itself, or a CPU map the sim's world is baked from (_bake), kept for the editor
var _gen_spawn := Vector2.ZERO  # The generated cave's spawn (its flattest floor) and the lumps scattered on it, [kind, x, y, r] each: a save of the cave keeps them
var _gen_lumps: Array = []
var _fills: Array = []          # Editor paints waiting for the sim's erase to land: [p, r, kind]
var _won := false              # The gecko reached the exit: the camera pulls back
var waves: Node2D                # waves.gd: sound as ripples on the world, the chew's and the hum's
var _wave_panel: WavePanel       # wave_panel.gd: their look, beside the debug panel on F1
var _listening := false         # Q held: the meerkat stand, the hum's ripples shown
var _listen_up := 0.0           # s into the meerkat where it stands tallest, and where it starts down
var _listen_down := 0.0
var _listen_end := 0.0


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
	# The camera follows after the gecko's tick, so the pixel grid it
	# anchors is the one the body is drawn on this tick (main ticks
	# before its children).
	gecko.ticked.connect(_follow)
	_sound = SoundBank.new()
	add_child(_sound)
	AudioServer.set_bus_mute(0, not _sound_on)
	_sound.listen(gecko)
	_ambience = Ambience.new()
	add_child(_ambience)
	_ambience.setup(map, gecko, _sound)
	gecko.bit.connect(func(_at: Vector2) -> void: _check_gas())
	gecko.tongue_hit.connect(func(_at: Vector2) -> void: _check_gas())
	_editor = Editor.new()
	_editor.setup(self)
	add_child(_editor)
	_marks = LightMarks.new()
	_marks.z_as_relative = false
	_marks.z_index = 60
	_marks.visible = false
	add_child(_marks)
	_ghost = EditGhost.new()
	_ghost.z_as_relative = false
	_ghost.z_index = 61
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.visible = false
	add_child(_ghost)
	if not sim:
		_author = map
		_baked = map
	if sim:
		_backdrop = Backdrop.new()
		_backdrop.set_grid(CAM_GRID)
		add_child(_backdrop)
		_backdrop.attach_far(sim)
	gecko.blobs = blobs
	critters = Critters.new()
	add_child(critters)
	critters.setup(sim, map, gecko)
	waves = Waves.new()
	waves.sim = sim
	add_child(waves)
	gecko.bit.connect(waves.bite)
	add_child(gecko)
	_anim = Sprite2D.new()
	_anim.centered = false
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim.scale = Vector2(2.0, 2.0)   # A frame's pixel is a gecko pixel, 2 world px
	_anim.z_index = 6                 # Over the blob layer, unlit like the gecko
	_anim.visible = false
	add_child(_anim)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(CaveMap.W_FULL * CaveMap.CELL_FULL)
	_camera.limit_bottom = int(CaveMap.H_FULL * CaveMap.CELL_FULL)
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 20)
	hud.add_child(_label)
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 970)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.modulate = Color(1.0, 0.95, 0.7)
	hud.add_child(_fps_label)
	_gut = Gut.new()
	_gut.position = Vector2(12.0, 964.0 - Gut.VIEW.y * Gut.SCALE)
	_gut.gecko = gecko
	_gut.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.add_child(_gut)
	gecko.chewed.connect(_feed_gut)
	gecko.ate.connect(func(area: float, glow: bool) -> void: _gut.feed_lump(area, glow))
	gecko.spawned.connect(_gut.clear)
	# The panel keeps working while the world is paused: this node runs
	# always and guards its own ticks, the world's nodes pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	map.process_mode = Node.PROCESS_MODE_PAUSABLE
	gecko.process_mode = Node.PROCESS_MODE_PAUSABLE
	if sim:
		sim.process_mode = Node.PROCESS_MODE_PAUSABLE
	_panel = DebugPanel.new()
	_panel.visible = false
	hud.add_child(_panel)
	_wave_panel = WavePanel.new()
	_wave_panel.visible = false
	hud.add_child(_wave_panel)
	_wave_panel.setup(waves, DebugPanel.WIDTH)
	_ensure_scenes()
	_panel.set_scenes(_scene_all.get("scenes", {}).keys())
	_panel.set_seed(seed_value)
	_panel.set_brush(brush_r)
	_panel.set_pixel_size(blobs.pixel_sz)
	if sim and OS.get_environment("GECKO_SENSE") == "4":
		map.call("set_sense", 4.0)
	if sim and OS.get_environment("GECKO_CRUMB") != "":
		sim.crumb_cells = int(OS.get_environment("GECKO_CRUMB"))
	_panel.set_sense(map.CELL)
	_panel.set_sound(_sound_on)
	_panel.set_crumb(sim.crumb_cells if sim else 0)
	_panel.scene_picked.connect(_load_scene)
	_panel.main_cave.connect(_main_cave)
	_panel.reload.connect(_reset)
	_panel.regenerate.connect(func(sv: int) -> void:
		seed_value = sv
		_scene = {}
		_scene_i = -1
		_panel.select_scene(-1)
		_reset())
	_panel.brush_changed.connect(func(v: float) -> void: brush_r = v)
	_panel.time_scale_changed.connect(func(v: float) -> void: Engine.time_scale = v)
	_panel.paused.connect(func(on: bool) -> void: get_tree().paused = on)
	_panel.step.connect(func() -> void:
		_step_ticks = 1
		get_tree().paused = false)
	_panel.pixel_size_changed.connect(func(v: float) -> void: blobs.set_pixel_size(v))
	_panel.sense_changed.connect(func(v: float) -> void:
		if map.has_method("set_sense"):
			map.call("set_sense", v))
	_panel.crumb_changed.connect(func(n: int) -> void:
		if sim:
			sim.crumb_cells = n)
	_panel.overlay_changed.connect(func(on: bool) -> void: gecko.debug = on)
	_panel.sound_changed.connect(func(on: bool) -> void: AudioServer.set_bus_mute(0, not on))
	_panel.light_changed.connect(set_light)
	_panel.anim_requested.connect(play_anim)
	_panel.pose_editor_requested.connect(_open_pose_editor)
	_panel.set_poses(PoseAnim.names())
	_panel.set_overlay(OPEN_OVERLAY or OS.get_environment("GECKO_OVERLAY") == "1")   # GECKO_OVERLAY=1: the gecko's overlay on from the start (a headless look at it)
	if picked.is_empty() and _demo_name == "":
		if OPEN_SEED <= 0:
			_pick_level()
		if OPEN_DEBUG:
			_set_debug(true)
	_reset()
	if OS.get_environment("GECKO_LEVEL") != "":
		# The game opens on a level from levels/ (the showcase cave).
		print(load_level(OS.get_environment("GECKO_LEVEL")))
	if OS.get_environment("GECKO_ANIM") != "":
		play_anim(OS.get_environment("GECKO_ANIM"))   # A look at an animation without a hand on the panel
	if OS.get_environment("GECKO_EDIT") != "":
		# Straight into the map editor (a look at its panel without a hand on Tab).
		_set_editing(true)
	if OS.get_environment("GECKO_EDIT_TEST") != "":
		# The editor's save and load, headless: paint, stamp, save, load,
		# count the kinds, quit (tools and the memory notes).
		_edit_self_test.call_deferred()
	var probe := OS.get_environment("GECKO_PROBE")
	if probe != "":
		# A script run inside the game with this node as its `main`:
		# tests/save_test.gd (the editor's save and load, pixel for
		# pixel, tools/save_test.sh) and one-off probes of the sim.
		var script = load(probe)
		if script == null:
			push_error("no probe at " + probe)
		else:
			var t: Node = script.new()
			t.set("main", self)
			add_child(t)
	var dump := OS.get_environment("GECKO_DUMP_MAP")
	if dump != "":
		if not sim:
			map.save_png(dump)
		get_tree().quit()
		return
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
	_anim_stop()
	critters.clear()
	if not _scene.is_empty():
		# The scene's lists are the level in hand: the editor moves and
		# saves them.
		_edit_lights = (_scene.get("lights", []) as Array).duplicate(true)
		_edit_lumps = (_scene.get("lumps", []) as Array).duplicate(true)
		_edit_slugs = (_scene.get("slugs", []) as Array).duplicate(true)
		if sim:
			# The terrain is built on a CPU map, kept as the authoring map
			# (what Save writes), and the particles are made from it with
			# the decor baked on (_bake), as the generated cave's are.
			var gen := CaveMap.new()
			SceneBuilder.build(gen, _scene, _scene_bases, true)
			_strip_decor(gen)
			if _author and _author != map:
				_author.free()
			_author = gen
			_build_seed = 0
			_edit_decor = _decor_entries(SceneBuilder.ops_of(_scene, _scene_bases, "decor").map(func(op: Array) -> Array: return op.slice(1)))
			_edit_decor.append_array(_decor_entries(_scene.get("decor", [])))
			map.generate_cells(_build_seed, _bake())
			_backdrop.build(_baked.solid, CaveMap.W_FULL, CaveMap.H_FULL, seed_value)
		else:
			SceneBuilder.build(map, _scene, _scene_bases)
			_edit_decor = _decor_entries(_scene.get("decor", []))
		_dress_world()
		var sp := SceneBuilder.spawn_point(map, _scene, Gecko.RIDE_H)
		gecko.spawn(sp.pos, sp.up)
		_camera_home()
		_cam_reset()
		return
	_exit = Rect2()
	_clear_slugs()
	waves.clear()
	_gas.clear()
	map.clear_currents()
	if sim:
		sim.set_daylight(_exit, DAYLIGHT)
	_sound.set_exit(_exit)
	waves.set_exit(_exit)
	_ambience.reset()
	_camera_home()
	if sim and _demo_name in ["pull", "strike", "tongue"]:
		_lab()
		return
	_edit_decor.clear()
	_edit_lights.clear()
	_edit_slugs.clear()
	_relight()
	if sim:
		# The generated cave's cells on a CaveMap, kept as the authoring
		# map, so the editor paints and saves a generated cave like a
		# level from a file.
		var gen := CaveMap.new()
		gen.generate(seed_value)
		map.generate_cells(seed_value, gen.solid)
		if _author and _author != map:
			_author.free()
		_author = gen
		_build_seed = seed_value
		_bake()
		if _backdrop:
			_backdrop.build(gen.solid, CaveMap.W_FULL, CaveMap.H_FULL, seed_value)
	else:
		map.generate(seed_value)
	var spawn := _flat_spawn()
	_gen_spawn = spawn
	_gen_lumps.clear()
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
	if sim and _demo_name == "":
		_scatter_chunks(spawn)
	# The scattered lumps are the level's lumps now: the editor's rebuild
	# spawns them again and Save writes them.
	_edit_lumps = _gen_lumps.duplicate(true)
	gecko.spawn(spawn - Vector2(0.0, Gecko.RIDE_H))
	_cam_reset()


# What stands in the built cells: the scene's vines and lumps and the
# editor's, the slugs, the exit and its daylight, the drip zones, the
# gas pockets and the currents. The scene's reset and the editor's
# rebuild after an undo share it.
func _dress_world() -> void:
	critters.clear()
	for c in SceneBuilder.spawn_lumps(map, {"lumps": _edit_lumps}):
		_add_critter(c)
	for pl in _decor_plans:
		critters.add_shroom_plan(pl)
	_clear_slugs()
	var k := 0
	for at in SceneBuilder.slug_points({"slugs": _edit_slugs}):
		var s := Slug.new()
		s.setup(map, at, 31 + k)
		add_child(s)
		_slugs.append(s)
		k += 1
	_relight()
	_exit = _edit_exit if _edit_exit.has_area() else SceneBuilder.exit_rect(_scene)
	if sim:
		sim.set_daylight(_exit, DAYLIGHT)
	_sound.set_exit(_exit)
	waves.set_exit(_exit)
	_ambience.reset()
	_ambience.set_drip_zones(SceneBuilder.ops_of(_scene, _scene_bases, "drips"))
	_gas.clear()
	for op in SceneBuilder.ops_of(_scene, _scene_bases, "gas"):
		_gas.append(Rect2(float(op[1]), float(op[2]), float(op[3]), float(op[4])))
	_gas_from_cells()
	map.clear_currents()
	for op in SceneBuilder.ops_of(_scene, _scene_bases, "current"):
		map.add_current(Rect2(float(op[1]), float(op[2]), float(op[3]), float(op[4])), Vector2(float(op[5]), float(op[6])), float(op[7]))


# A flat room for the tongue demos (particle world only): a stone small
# enough to swallow and a boulder the tongue can drag but not swallow
# for pull, a boulder for strike, the ceiling in reach for tongue.
func _lab() -> void:
	var gen := CaveMap.new()
	gen.blank()
	gen.erase_rect(Rect2(0.0, LAB_CEIL, 1920.0, LAB_FLOOR - LAB_CEIL))
	map.build_cells(gen.solid)
	gen.free()
	var x := 900.0
	if _demo_name == "pull":
		_lump_on_floor(x + 90.0, 5.0, false, LAB_CEIL + 8.0)
		_lump_on_floor(x + 190.0, 13.0, false, LAB_CEIL + 8.0)
	elif _demo_name == "strike":
		_lump_on_floor(x + 150.0, 12.0, false, LAB_CEIL + 8.0)
	gecko.spawn(Vector2(x, LAB_FLOOR - Gecko.RIDE_H))
	_cam_reset()


# A lump resting on the first floor below (x, from_y): a boulder (or a
# stone, when small) or a clump of clay. Returns its chunk id, 0 when
# it did not fit.
func _lump_on_floor(x: float, radius: float, clay: bool, from_y := 540.0) -> int:
	var fl: Vector2 = map.floor_below(Vector2(x, from_y))
	var p := Vector2(x, fl.y - radius - 2.0)
	if map.solid_within(p, radius + 2.0):
		return 0
	return map.spawn_clay(p, radius) if clay else map.spawn_boulder(p, radius)


# Loose lumps about the chamber's floor: a boulder too heavy for the
# tongue, two it can drag, some stones and clumps of clay, and two heaps
# of sand, clear of the spawn so the gecko starts on plain ground and
# clear of the pool.
func _scatter_chunks(spawn: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var lumps := [[18.0, false], [13.0, false], [10.0, false], [4.0, false], [5.0, false],
		[3.5, false], [4.5, false], [11.0, true], [8.0, true]]
	for lump in lumps:
		for _try in 8:
			var x := rng.randf_range(720.0, 1400.0)
			if absf(x - spawn.x) < 140.0:
				continue
			if _lump_on_floor(x, lump[0], lump[1]) > 0:
				_gen_lumps.append(["clay" if lump[1] else "boulder", x, 540.0, lump[0]])
				break
	for r in [26.0, 18.0]:
		for _try in 8:
			var x := rng.randf_range(720.0, 1400.0)
			if absf(x - spawn.x) < 160.0:
				continue
			var fl: Vector2 = map.floor_below(Vector2(x, 540.0))
			var p := Vector2(x, fl.y - r - 2.0)
			if map.solid_within(p, r + 2.0):
				continue
			map.spawn_sand(p, r)
			_gen_lumps.append(["sand", p.x, p.y, r])
			break


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
	if get_tree().paused and _step_ticks == 0:
		return
	if _step_ticks > 0:
		# One tick for the panel's step button, then paused again after
		# the frame, so the world's nodes get their tick too.
		_step_ticks -= 1
		if _step_ticks == 0:
			get_tree().set_deferred("paused", true)
			_panel.set_paused(true)
	_update_slugs(dt)
	_autosave(dt)
	_anim_tick(dt)
	_listen_tick()
	waves.tick(dt, _slugs + critters.long_slugs)
	if sim:
		var glows: Array = []
		if gecko.glow_snuff <= 0.0:
			glows.append([gecko.chain.head(), GLOW_COLOR.lerp(Color(0.8, 1.0, 0.6), 0.5 if gecko.glow_boost > 0.0 else 0.0),
					GLOW_R * (1.8 if gecko.glow_boost > 0.0 else 1.0)])
		if not _light_preview.is_empty():
			glows.append(_light_preview)
		for s in _slugs:
			glows.append(s.glow())
		glows.append_array(critters.glows())
		glows.append_array(_lights)
		sim.set_glows(_nearest_glows(glows))
		critters.pre_tick(dt)
		var t0 := Time.get_ticks_usec()
		sim.tick()
		_sim_us = Time.get_ticks_usec() - t0
		_sim_peak = maxi(_sim_peak, _sim_us)
		if _timing:
			_t_sim.append(_sim_us)
			_t_gecko.append(gecko.tick_us)
			if _t_sim.size() >= 60:
				_print_timing()
		if not _fills.is_empty():
			# Editor paints and stamps: the tick just run took the paint's
			# erase (a melt is on for one tick, sim.gd tick), so the
			# fill spawns into empty cells now and is drawn next tick.
			# Spawned before the tick, it would be melted with the rest.
			for f in _fills:
				map.material_circle(f[0], f[1], f[2])
			_fills.clear()
		critters.post_tick()
		_update_vines(dt)
	else:
		critters.pre_tick(dt)
	if not _won and _exit.has_area() and _exit.has_point(gecko.pos):
		_win()
	if _demo_step >= 0:
		_run_demo(dt)
	# The state readout only with the debug overlay; the controls hint for
	# the first seconds of a run.
	_hint_t += dt
	if _debug:
		_label.text = gecko.debug_text()
		_panel.set_status(gecko.debug_text())
	elif _hint_t < 10.0 and not _editing:
		_label.text = _hint if _hint != "" else "WASD move   Space jump   LMB tap strike, hold grapple   LMB+RMB drag, eat   RMB chew at cursor   B boulder  C clay  N sand (hold: pour)   R again   Tab editor   F1 debug"
	else:
		_label.text = ""


func _edit_self_test() -> void:
	print("EDIT: " + blank_level("edtest"))
	edit_paint(Vector2(600.0, 700.0), 40.0, CaveMap.CELL_ROCK)
	edit_paint(Vector2(700.0, 790.0), 30.0, CaveMap.CELL_WATER)
	edit_paint(Vector2(900.0, 780.0), 20.0, CaveMap.CELL_MOSS)
	edit_paint(Vector2(1000.0, 500.0), 24.0, CaveMap.CELL_GAS)
	edit_stamp("shroom_cluster", Vector2(1200.0, 790.0), 12.0)
	edit_stamp("stalactite", Vector2(1300.0, 170.0), 12.0)
	edit_stamp("stalagmite", Vector2(1350.0, 790.0), 12.0, "nearest", "", {"size": 4, "variant": 2})
	edit_stamp("thorn", Vector2(1100.0, 790.0), 12.0, "floor", "", {"size": 2})
	edit_stamp("vine", Vector2(1400.0, 300.0), 12.0)
	edit_stamp("slug", Vector2(1500.0, 790.0), 12.0)
	# A PNG stamp as one stroke, undone and redone: the decor cells go and come back.
	var n0 := _count_kinds_from(CaveMap.CELL_DECOR)
	edit_begin()
	edit_stamp("cluster_0", Vector2(800.0, 790.0), 12.0, "floor", "h")
	var placed := edit_can_place("cluster_0", Vector2(800.0, 790.0), "floor", 4.0)
	edit_end()
	var n1 := _count_kinds_from(CaveMap.CELL_DECOR)
	print("EDIT: " + edit_undo())
	var n2 := _count_kinds_from(CaveMap.CELL_DECOR)
	print("EDIT: " + edit_redo())
	var n3 := _count_kinds_from(CaveMap.CELL_DECOR)
	print("EDIT: decor cells %d, after stamp %d, after undo %d, after redo %d, spot taken %s, entries %d, terrain decor %d" % [n0, n1, n2, n3, str(not placed), _edit_decor.size(), _count_kinds_from(CaveMap.CELL_DECOR, _author)])
	# Stamped decor is in the baked map, never in the terrain; the
	# entries: the cluster, two cones, the thorn bush, cluster_0.
	var undo_ok := n0 == 0 and n1 > 100 and n2 == 0 and n3 == n1 and not placed and _edit_decor.size() == 5 and _count_kinds_from(CaveMap.CELL_DECOR, _author) == 0
	print("EDIT: " + edit_spawn(Vector2(500.0, 780.0)))
	print("EDIT: " + edit_exit(Rect2(1700.0, 700.0, 60.0, 60.0)))
	print("EDIT: " + edit_light(Vector2(600.0, 500.0), Vector2(700.0, 560.0), "torch", 20.0, 1.2, "cone"))
	print("EDIT: " + edit_light(Vector2(300.0, 500.0), Vector2(300.0, 500.0), "glow", 12.0, 1.0))
	print("EDIT: " + edit_light_remove(Vector2(302.0, 503.0)))
	print("EDIT: " + save_level())
	print("EDIT: " + write_version("auto"))
	print("EDIT: ghost on " + edit_ghost({"name": "cluster_0", "p": Vector2(800.0, 700.0), "where": "nearest"}) + ", " + edit_ghost({"name": "thorn", "p": Vector2(900.0, 700.0), "size": 1}))
	edit_ghost({})
	var counts := {}
	for v in _author.solid:
		counts[v] = counts.get(v, 0) + 1
	var baked := {}
	for v in _baked.solid:
		baked[v] = baked.get(v, 0) + 1
	print("EDIT: kinds before load ", counts, " baked ", baked)
	var versions := level_versions("edtest")
	print("EDIT: versions ", versions.size(), " ", versions.map(func(v): return "v%d %s" % [v.n, v.kind]), " entries ", level_entries().size())
	print("EDIT: " + load_version("edtest"))
	var files_ok: bool = versions.size() == 3 and versions[0].kind == "auto" and _version == 3
	var counts2 := {}
	for v in _author.solid:
		counts2[v] = counts2.get(v, 0) + 1
	var baked2 := {}
	for v in _baked.solid:
		baked2[v] = baked2.get(v, 0) + 1
	print("EDIT: baked after load ", baked2)
	print("EDIT: kinds after load ", counts2, " gas pockets ", _gas.size(), " slugs ", _slugs.size(), " spawn ", gecko.pos, " exit ", _exit, " decor entries ", _edit_decor.size())
	var lights_ok: bool = _edit_lights.size() == 1 and _lights.size() == 1 and _lights[0][2] < 0.0
	print("EDIT: lights after load ", _edit_lights, " undo_ok ", undo_ok, " files_ok ", files_ok, " lights_ok ", lights_ok)
	# A move and a removal: the stamp's cells go with it, the terrain stays.
	var before := _count_kinds_from(CaveMap.CELL_DECOR)
	var it := edit_item_at(Vector2(800.0, _edit_decor[4].rect.get_center().y))
	print("EDIT: item at the cluster ", it, " ", edit_item_text(it))
	print("EDIT: " + edit_move(it, Vector2(200.0, 0.0)))
	var moved_x: float = _edit_decor[4].x
	var moved_n := _count_kinds_from(CaveMap.CELL_DECOR)
	var left := edit_item_at(Vector2(800.0, _edit_decor[4].rect.get_center().y))
	var moved_ok: bool = absf(moved_x - 1000.0) < 0.01 and absi(moved_n - before) < 40 and left.is_empty()
	print("EDIT: " + edit_remove({"list": "decor", "i": 4}))
	var removed_ok: bool = _edit_decor.size() == 4 and _count_kinds_from(CaveMap.CELL_DECOR) < before - 100 and _author.solid == _undo[_undo.size() - 1].cells
	print("EDIT: moved_ok ", moved_ok, " removed_ok ", removed_ok, " x ", moved_x, " decor ", before, " -> ", moved_n, " left at 800 ", left)
	print("EDIT TEST " + ("OK" if counts == counts2 and baked == baked2 and undo_ok and moved_ok and removed_ok and _edit_decor.size() == 4 and files_ok and lights_ok else "DIFFERS"))
	_remove_level_files("edtest")
	get_tree().quit()


# The editor in or out. In: the live world made again from the level in
# hand, whatever the play did to it, the entries with their handles.
# Out: made again once more when the editor changed anything, so the
# play starts on the level as edited, the gecko where it stood.
func _set_editing(on: bool) -> void:
	if on == _editing:
		return
	_editing = on
	_editor.visible = on
	_marks.visible = on
	_ghost.visible = on
	_label.position.x = (_editor.panel_width() + 12.0) if on else 12.0
	if on:
		_edits_at_open = _edits
		_rebuild_world()
		_editor.refresh()
	else:
		edit_ghost({})
		edit_light_preview([])
		edit_marks({}, {}, Vector2.ZERO)
		if _edits != _edits_at_open:
			_rebuild_world()
		edit_home()


var _edits := 0                # Strokes, undos and redos so far
var _edits_at_open := 0        # _edits when the editor opened: what tells its close that something changed


func _count_kinds_from(kind: int, m: CaveMap = null) -> int:
	var n := 0
	for v in (m if m else _baked).solid:
		if v >= kind:
			n += 1
	return n


# --- The editor's hands on the world (editor.gd) ---

# The level in hand is the terrain (_author, the cells png of a save)
# and these lists. The decor, the dripstone cones and the brush's runs
# are entries baked on the terrain (_bake) into _baked, which the live
# world is made from: never part of the terrain, so the editor can move
# them, change them and take them away. Opening the editor makes the
# live world again from the level (whatever the play did to it), and so
# does leaving it after an edit, and an undo.
var _edit_lumps: Array = []     # The lumps and the critters, [kind, x, y, size...] each (tests/scene_builder.gd spawn_lumps): the scene's on a reset, then the editor's
var _edit_slugs: Array = []     # [x, y] each
var _decor_plans: Array = []    # The decor mushrooms the particle world makes shrooms that bend (_bake_stamp), _dress_world makes them
var _edit_decor: Array = []     # The entries baked on the terrain in order, each a Dictionary with a type: stamp {name, x, y, where, flags, anchor}, cone {name, x, y, h, variant}, run {names, path, where, spacing, mirror, pin, seed}; rects (what the bake set) and rect (their bounds) are the bake's
var _baked: CaveMap             # The terrain with the entries baked on: the live world's cells, the surfaces new stamps find
var _build_seed := 0            # The sim's seed for the particles (sim.gd build): the generated cave's, 0 for a scene
var _stroke_area := Rect2()     # The ground a stroke painted, so its end can bake the entries on it again
var _edit_lights: Array = []    # The lights, [x, y, kind] or [x, y, kind, radius, strength, shape, x2, y2] each (tests/scene_builder.gd light_point): the level's on a reset, then the editor's; the level file lists them
var _lights: Array = []         # The same as the light pass takes them, [position, colour, radius, end]
var _light_preview: Array = []  # The editor's light on the cursor before the click, in the light pass's form, empty for none
var _ghost_tex := {}            # Stamp name -> ImageTexture, the ghost's
var _brush = null               # The decor brush of the stroke in hand (decor_brush.gd)
var _marks: Node2D              # The lights drawn as marks while the editor is open
var _ghost: Node2D              # The editor's ghost: the stamp picked, drawn where a click would set it
var _edit_spawn := Vector2.INF
var _edit_exit := Rect2()
var _undo: Array = []           # Strokes, oldest first: the authored cells and the editor's lists before each
var _redo: Array = []
var _stroke: Dictionary = {}    # The state when the button went down, until it comes up


# A stroke: from the button going down to its coming up. What changed
# in between is one undo step: a copy of the authored cells (518 KB at
# 2 px cells, UNDO_MAX of them at most) and the editor's lists.
func edit_begin() -> void:
	if _author == null or not _stroke.is_empty():
		return
	_stroke = _edit_state()
	_stroke_area = Rect2()


func edit_end() -> void:
	if _stroke.is_empty():
		return
	var before := _stroke
	_stroke = {}
	var now := _edit_state()
	if _edit_changed(before, now):
		if before.cells != now.cells and sim and _entries_meet(_stroke_area.grow(8.0)):
			# Ground painted under or over an entry: the world made
			# again, so the entry finds its surface anew.
			_rebuild_world()
		elif (before.cells != now.cells or before.decor != now.decor) and _backdrop:
			# The dripstone silhouettes hang from the baked cells, cones
			# and all: made again now, so the view is what a load shows.
			_backdrop.rebuild_near(_baked.solid)
		_undo.append(before)
		_edits += 1
		while _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_redo.clear()
		_dirty = true
		_dirty_v = true
		if _level_name == "":
			_level_name = _default_level_name()


func _edit_state() -> Dictionary:
	return {"cells": _author.solid.duplicate(), "decor": _edit_decor.duplicate(true), "lumps": _edit_lumps.duplicate(true),
			"slugs": _edit_slugs.duplicate(true), "lights": _edit_lights.duplicate(true), "spawn": _edit_spawn, "exit": _edit_exit}


func _edit_changed(a: Dictionary, b: Dictionary) -> bool:
	return a.cells != b.cells or a.decor != b.decor or a.lumps != b.lumps or a.slugs != b.slugs or a.lights != b.lights or a.spawn != b.spawn or a.exit != b.exit


func edit_undo() -> String:
	if _undo.is_empty():
		return "nothing to undo"
	_redo.append(_edit_state())
	_edit_restore(_undo.pop_back())
	_edits += 1
	return "undone, %d left" % _undo.size()


func edit_redo() -> String:
	if _redo.is_empty():
		return "nothing to redo"
	_undo.append(_edit_state())
	_edit_restore(_redo.pop_back())
	_edits += 1
	return "redone"


func edit_can_undo() -> bool:
	return not _undo.is_empty()


func edit_can_redo() -> bool:
	return not _redo.is_empty()


# The world as it was: the authored cells back, the live world rebuilt
# from them (the sim's particles made anew, as at a reset), the vines,
# slugs and exit set again from the lists. The gecko stays where it is.
func _edit_restore(st: Dictionary) -> void:
	_edit_decor = st.decor.duplicate(true)
	_edit_lumps = st.lumps.duplicate(true)
	_edit_slugs = st.slugs.duplicate(true)
	_edit_lights = st.lights.duplicate(true)
	_edit_spawn = st.spawn
	_edit_exit = st.exit
	_author.solid = st.cells.duplicate()
	_rebuild_world()
	_relight()
	_dirty = true
	_dirty_v = true


# The live world made again from the level in hand: the terrain with
# the entries baked on, the lumps, critters and slugs set again. The
# editor's way in and out (Tab), an undo, a move, and a stroke that
# painted ground under an entry. The gecko stays where it is unless the
# ground is back over it, then it goes to the spawn.
func _rebuild_world() -> void:
	if _author == null:
		return
	_fills.clear()
	if sim:
		map.generate_cells(_build_seed, _bake())
		if _backdrop:
			_backdrop.rebuild_near(_baked.solid)
	else:
		_author.repaint_all()
	_dress_world()
	if _baked and _baked.solid_within(gecko.pos, 3.0):
		gecko.spawn(_spawn_at(), Vector2.UP)
		_cam_reset()


# Where the gecko starts: the editor's spawn, the scene's, or the
# generated cave's.
# A bite about to land: the gut gets what it will take, by kind. The sim
# says only whether a cell is solid; what it is comes from the baked
# terrain, and a solid cell the terrain has as open is grains or a lump
# that moved there. Bedrock gives nothing and hard rock HARD_GIVE of its
# cells, as the bite does.
func _feed_gut(at: Vector2, radius: float) -> void:
	var step := CaveMap.CELL_FULL
	var reach := radius + CaveMap.CARVE_PAD
	var n := int(ceil(reach / step))
	var counts := {}
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := at + Vector2(i, j) * step
			if p.distance_to(at) >= reach or not map.is_solid_world(p):
				continue
			var k: int = _baked._kind_world(p) if _baked else CaveMap.CELL_ROCK
			if k == CaveMap.CELL_BEDROCK:
				continue
			if k == CaveMap.CELL_AIR or k == CaveMap.CELL_WATER or k == CaveMap.CELL_LAVA or k == CaveMap.CELL_GAS:
				k = CaveMap.CELL_SAND if map.loose_at_world(p) else CaveMap.CELL_ROCK
			var w := CaveMap.HARD_GIVE if k == CaveMap.CELL_HARD else 1.0
			counts[k] = counts.get(k, 0.0) + w
	for k in counts:
		_gut.feed(k, counts[k] * step * step)


func _spawn_at() -> Vector2:
	if _edit_spawn != Vector2.INF:
		return _edit_spawn
	if not _scene.is_empty():
		return SceneBuilder.spawn_point(map, _scene, Gecko.RIDE_H).pos
	return _gen_spawn - Vector2(0.0, Gecko.RIDE_H)


# The baked map made again: the terrain, then every entry stamped on it
# in order, each finding its surface on what the ones before it left.
# Returns the cells the particles are made from: the baked ones with
# the decor mushrooms lifted out (each a shroom that bends, planned in
# _decor_plans for _dress_world). The bitmap world has no bake: its map
# is the authoring map and stamps go straight on it.
func _bake() -> PackedByteArray:
	_decor_plans = []
	if not sim:
		_baked = _author
		return _author.solid
	if _baked == null or _baked == _author:
		_baked = CaveMap.new()
	_baked.solid = _author.solid.duplicate()
	for e in _edit_decor:
		e.rects = []
		e.rect = Rect2()
	for e in _edit_decor:
		_bake_entry(e, false)
	var kinds := _baked.solid.duplicate()
	for pl in _decor_plans:
		for c in pl.cells:
			kinds[c[1] * _baked.W + c[0]] = CaveMap.CELL_AIR
	return kinds


# One entry stamped on the baked map, its rects kept (the handles, the
# brush's spacing). live: into the running world as well, the cells
# filled after the next tick and the mushrooms made shrooms that bend
# at once, as a click in the editor wants.
func _bake_entry(e: Dictionary, live: bool) -> void:
	e.rects = []
	match String(e.type):
		"cone":
			var down: bool = e.name == "stalactite"
			var p := Vector2(e.x, e.y)
			var line: Vector2 = _baked.ceiling_above(p) if down else _baked.floor_below(p)
			var h: float = e.h
			SceneBuilder.cone(_baked, Vector2(p.x, line.y), h, down, int(e.variant))
			if live and sim:
				SceneBuilder.cone(map, Vector2(p.x, line.y), h, down, int(e.variant))
			e.rects.append(Rect2(p.x - h * 0.3, line.y if down else line.y - h, h * 0.6, h))
		"run":
			# The brush's run laid again along its path, with its seed:
			# the same pieces on the same ground, refitted where the
			# ground or the entries before it changed.
			var path: Array = e.path
			if path.is_empty():
				return
			var b := _run_brush(e, live)
			b.begin(e.names, _v(path[0]), String(e.where))
			for i in range(1, path.size()):
				b.drag(_v(path[i]))
			b.end(_v(path[path.size() - 1]))
		_:
			_bake_stamp(e, String(e.name), Vector2(e.x, e.y), String(e.where), String(e.flags), live)
	var r := Rect2()
	for rr in e.rects:
		r = rr if r.size == Vector2.ZERO else r.merge(rr)
	e.rect = r


# A decor brush (decor_brush.gd) laying the run e on the baked map.
func _run_brush(e: Dictionary, live: bool) -> RefCounted:
	var b := DecorBrush.new()
	b.map = _baked
	b.place = func(name: String, at: Vector2, w: String, flags: String) -> Rect2: return _bake_stamp(e, name, at, w, flags, live)
	b.taken = _edit_taken
	b.rng.seed = int(e.seed)
	b.spacing = float(e.spacing)
	b.mirror = bool(e.mirror)
	b.pin = String(e.pin)
	return b


static func _v(a) -> Vector2:
	return a if a is Vector2 else Vector2(float(a[0]), float(a[1]))


# A stamp of the entry e on the baked map: its rect added to e's. A
# decor mushroom is planned as a shroom that bends, what of it has no
# stem to bend left as cells. Returns the rect, empty when nothing was
# set.
func _bake_stamp(e: Dictionary, name: String, at: Vector2, where: String, flags: String, live: bool) -> Rect2:
	var rect := SceneBuilder.stamp_rect(_baked, name, at, where)
	var cells: Array = SceneBuilder.stamp(_baked, name, at, where, flags)
	if cells.is_empty():
		return Rect2()
	e.rects.append(rect)
	if sim and SceneBuilder.is_shroom_stamp(name):
		var res: Array = Critters.plan_decor(cells, SceneBuilder.frame_up(where), CaveMap.CELL_FULL, SceneBuilder.png_stamps()[name].part_n)
		for pl in res[0]:
			if not live:
				_decor_plans.append(pl)
			elif critters.add_shroom_plan(pl):
				_decor_plans.append(pl)
			else:
				res[1].append_array(pl.cells)
		cells = res[1]
	if live and sim:
		# Into the live sim: each cell set is filled on the next tick
		# (fill_circle at a cell's centre with the cell's radius takes
		# that cell alone).
		var cell := CaveMap.CELL_FULL
		for c in cells:
			_fills.append([Vector2((c[0] + 0.5) * cell, (c[1] + 0.5) * cell), cell, c[2]])
	return rect


# Whether an entry's rect meets r.
func _entries_meet(r: Rect2) -> bool:
	if r.size == Vector2.ZERO:
		return false
	for e in _edit_decor:
		if (e.rect as Rect2).intersects(r):
			return true
	return false


# Decor cells out of a terrain: a level saved before the split had its
# stamps baked into the cells png, and the entries are their only source
# now.
static func _strip_decor(m: CaveMap) -> void:
	for i in m.solid.size():
		if m.solid[i] >= CaveMap.CELL_DECOR:
			m.solid[i] = CaveMap.CELL_AIR


# A circle of kind at p: the live world and the authoring map alike.
# In the sim the circle is melted this tick and filled after it
# (_physics_process). A melt reaches CARVE_PAD past its radius, as a
# bite does, and so does the map's erase: a paint of a kind melts that
# much less, so it takes exactly the circle it fills, as the map does,
# and leaves no ring of air round it. A paint is terrain only: the
# entries over it are baked again at the stroke's end (edit_end), on
# the ground as painted.
func edit_paint(p: Vector2, r: float, kind: int) -> void:
	if _author == null:
		return
	for m in ([_author, _baked] if _baked and _baked != _author else [_author]):
		if kind == CaveMap.CELL_AIR:
			m.erase_circle(p, r, true)
		else:
			m.material_circle(p, r, kind)
	var area := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
	_stroke_area = area if _stroke_area.size == Vector2.ZERO else _stroke_area.merge(area)
	if sim:
		map.erase_circle(p, r if kind == CaveMap.CELL_AIR else r - CaveMap.CARVE_PAD, true)
		if kind != CaveMap.CELL_AIR:
			_fills.append([p, r, kind])
	if kind == CaveMap.CELL_GAS:
		_gas_from_cells()


# The surface a stamp at p goes on: the nearest of the floor below, the
# ceiling above and the walls beside when the editor says "nearest".
# Read off the authoring map, which has this tick's paints already.
func edit_where(p: Vector2, where: String) -> String:
	if where != "nearest":
		return where
	var m: CaveMap = _surf()
	var d := {"floor": m.floor_below(p).y - p.y, "ceiling": p.y - m.ceiling_above(p).y,
			"wall_right": m.wall_beside(p, 1).x - p.x, "wall_left": p.x - m.wall_beside(p, -1).x}
	var best := "floor"
	for k in d:
		if d[k] < d[best]:
			best = k
	return best


# Whether a stamp at p would stand clear of every placed one by spacing
# px (the brush's rule, unless it is set free).
func edit_can_place(name: String, p: Vector2, where: String, spacing: float) -> bool:
	var r := SceneBuilder.stamp_rect(_surf(), name, p, edit_where(p, where)).grow(spacing)
	return not _edit_taken(r)


func _edit_taken(r: Rect2) -> bool:
	for d in _edit_decor:
		for rr in d.get("rects", []):
			if r.intersects(rr):
				return true
	return false


# The map stamps find their surfaces on: the baked one, so a stamp goes
# on the decor before it as it will at the next bake.
func _surf() -> CaveMap:
	if _baked:
		return _baked
	return _author if _author else map


# The decor brush (decor_brush.gd) over a stroke: begun where the button
# went down with the group's stamps and the editor's settings, dragged
# each frame, ended where it came up. The stroke is one entry, a run:
# the path the cursor took and the brush's seed, so the bake lays the
# same pieces again, and a move of it lays them along the moved path.
func edit_brush_begin(names: Array, p: Vector2, where: String, spacing: float, mirror: bool, pin: String) -> void:
	if _author == null:
		return
	p = _snap(p)
	var e := {"type": "run", "names": names.duplicate(), "path": [p], "where": edit_where(p, where), "spacing": spacing,
			"mirror": mirror, "pin": pin, "seed": randi() & 0x7fffffff, "rects": [], "rect": Rect2()}
	_edit_decor.append(e)
	_brush = _run_brush(e, true)
	_brush.begin(e.names, p, e.where)


func edit_brush_drag(p: Vector2) -> void:
	if _brush == null:
		return
	p = _snap(p)
	var e: Dictionary = _edit_decor[_edit_decor.size() - 1]
	if p == e.path[e.path.size() - 1]:
		return
	e.path.append(p)
	_brush.drag(p)
	_bounds(e)


func edit_brush_end(_p: Vector2) -> void:
	if _brush == null:
		return
	var e: Dictionary = _edit_decor[_edit_decor.size() - 1]
	_brush.end(e.path[e.path.size() - 1])
	_brush = null
	_bounds(e)
	if e.rects.is_empty():
		_edit_decor.pop_back()


# An entry's rect: the bounds of what it set.
static func _bounds(e: Dictionary) -> void:
	var r := Rect2()
	for rr in e.rects:
		r = rr if r.size == Vector2.ZERO else r.merge(rr)
	e.rect = r


# A point as the level file keeps it: on a quarter px, which the json
# writes exactly, so a run's path bakes the same after a load.
static func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(0.25, 0.25))


# A stamp at p: a decor stamp (a PNG or a table) on the surface, a
# dripstone cone, a vine hanging from the ceiling above, a thorn bush,
# a slug on the nearest surface. opts "size", 1 to 5, is a cone's
# height, a vine's length or a thorn's bush (small up to 2), "variant"
# a cone's shape; with no size the brush radius r sizes a cone (2 r)
# and a vine (4 r). flags: "h" mirrors a PNG stamp, "v" flips it, "d"
# drapes it. Returns the rect a decor stamp covers, empty for the rest.
func edit_stamp(name: String, p: Vector2, r: float, where := "nearest", flags := "", opts := {}) -> Rect2:
	if _author == null:
		return Rect2()
	p = _snap(p)
	var size: int = int(opts.get("size", 0))
	var variant: int = int(opts.get("variant", 0))
	match name:
		"vine":
			var length := vine_length(size) if size > 0 else r * 4.0
			critters.add_vine(p, length)
			_edit_lumps.append(["vine", p.x, p.y, length])
		"shroom":
			var sz := size if size > 0 else 3
			critters.add_shroom(p, sz, variant)
			_edit_lumps.append(["shroom", p.x, p.y, float(sz), float(variant)])
		"slime":
			var rad := slime_radius(size) if size > 0 else 10.0
			critters.add_slime(p, rad)
			_edit_lumps.append(["slime", p.x, p.y, rad])
		"longslug":
			var ln := long_slug_length(size) if size > 0 else 40.0
			critters.add_long_slug(p, ln)
			_edit_lumps.append(["longslug", p.x, p.y, ln])
		"slug":
			var sl := Slug.new()
			sl.setup(map, p, 31 + _slugs.size())
			add_child(sl)
			_slugs.append(sl)
			_edit_slugs.append([p.x, p.y])
		"stalactite", "stalagmite":
			var h := cone_height(size) if size > 0 else maxf(r * 2.0, 8.0)
			var e := {"type": "cone", "name": name, "x": p.x, "y": p.y, "h": h, "variant": variant, "size": size}
			_bake_entry(e, true)
			_edit_decor.append(e)
			return e.rect
		_:
			var table := stamp_table(name, size)
			var e := {"type": "stamp", "name": table, "x": p.x, "y": p.y, "where": edit_where(p, where), "flags": flags, "anchor": where}
			_bake_entry(e, true)
			if e.rects.is_empty():
				return Rect2()
			_edit_decor.append(e)
			return e.rect
	return Rect2()


# A cone's height and a vine's length for a stamp size, 1 to 5.
static func cone_height(size: int) -> float:
	return 12.0 + 12.0 * clampi(size, 1, 5)


static func vine_length(size: int) -> float:
	return 24.0 * clampi(size, 1, 5)


static func slime_radius(size: int) -> float:
	return 5.0 + 3.0 * clampi(size, 1, 5)


static func long_slug_length(size: int) -> float:
	return 20.0 + 14.0 * clampi(size, 1, 5)


# A critter from the scene's lumps (tests/scene_builder.gd spawn_lumps):
# [kind, position, size, variant].
func _add_critter(c: Array) -> void:
	match String(c[0]):
		"vine":
			critters.add_vine(c[1], c[2])
		"shroom":
			critters.add_shroom(c[1], int(c[2]), int(c[3]))
		"slime":
			critters.add_slime(c[1], c[2])
		"longslug":
			critters.add_long_slug(c[1], c[2])


# The light pass takes MAX_GLOWS: past that the gecko's own and those
# nearest it.
func _nearest_glows(glows: Array) -> Array:
	if glows.size() <= Sim.MAX_GLOWS or glows.is_empty():
		return glows
	var first: Array = glows[0]
	var rest := glows.slice(1)
	var at: Vector2 = gecko.pos
	rest.sort_custom(func(a: Array, b: Array) -> bool: return at.distance_squared_to(a[0]) < at.distance_squared_to(b[0]))
	var out: Array = [first]
	out.append_array(rest.slice(0, Sim.MAX_GLOWS - 1))
	return out


# The table a stamp name and size pick: the thorn bush is small up to 2.
static func stamp_table(name: String, size: int) -> String:
	if name == "thorn" and size > 0 and size <= 2:
		return "thorn_s"
	return name


# A light from a to b (tests/scene_builder.gd LIGHTS, light_point): a
# point at a, a strip of light along the segment to b, or a cone from
# the source a to the aim b; the radius in px, the strength a factor on
# the kind's colour. Drawn as a mark while editing; air painted over it
# or the editor's right button takes it away.
func edit_light(a: Vector2, b: Vector2, kind: String, radius: float, strength: float, shape := "point") -> String:
	if not SceneBuilder.LIGHTS.has(kind):
		return "no light " + kind
	if shape == "point":
		b = a
	_edit_lights.append([a.x, a.y, kind, radius, strength, shape, b.x, b.y])
	_relight()
	if shape == "point":
		return "%s light at %d, %d, r %d" % [kind, int(a.x), int(a.y), int(radius)]
	return "%s %s %d px long, r %d" % [kind, shape, int(a.distance_to(b)), int(radius)]


# The light nearest p, within its radius or 10 px, taken away.
func edit_light_remove(p: Vector2) -> String:
	var best := -1
	var bd := INF
	for i in _edit_lights.size():
		var lp: Array = SceneBuilder.light_point(_edit_lights[i])
		var d := _seg_dist(p, lp[0], lp[3])
		if d <= maxf(absf(lp[2]), 10.0) and d < bd:
			bd = d
			best = i
	if best < 0:
		return "no light there"
	var gone: Array = _edit_lights[best]
	_edit_lights.remove_at(best)
	_relight()
	return "%s light removed" % String(gone[2])


# The editor's light on the cursor: seeded each tick like a placed one,
# so the world shows it before the click. Empty for none.
func edit_light_preview(entry: Array) -> void:
	_light_preview = SceneBuilder.light_point(entry) if not entry.is_empty() else []
	if _marks:
		_marks.preview = _light_preview
		_marks.queue_redraw()


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# The lights as the light pass takes them, from the list, and the marks.
func _relight() -> void:
	_lights = SceneBuilder.light_points({"lights": _edit_lights})
	if _marks:
		_marks.lights = _lights
		_marks.queue_redraw()


# The editor's ghost: the stamp picked, drawn where a click would set it
# (editor.gd). spec: name, p (the cursor), where (the anchor rule), size,
# variant; empty hides it. Returns the surface it would go on.
func edit_ghost(spec: Dictionary) -> String:
	if spec.is_empty() or _author == null:
		_ghost.items = []
		_ghost.queue_redraw()
		return ""
	var name: String = spec.name
	var p: Vector2 = spec.p
	var size: int = int(spec.get("size", 3))
	var items: Array = []
	var where := ""
	var cell := CaveMap.CELL_FULL
	match name:
		"stalactite", "stalagmite":
			var down := name == "stalactite"
			var line: Vector2 = map.ceiling_above(p) if down else map.floor_below(p)
			var h := cone_height(size)
			var tip := Vector2(p.x, line.y + (h if down else -h))
			var w := h * 0.5
			items.append(["poly", PackedVector2Array([Vector2(p.x - w * 0.5, line.y), Vector2(p.x + w * 0.5, line.y), tip]), Color(0.85, 0.78, 0.68)])
			where = "ceiling" if down else "floor"
		"vine":
			var c: Vector2 = map.ceiling_above(p)
			var top := Vector2(p.x, c.y + 2.0)
			items.append(["line", top, top + Vector2(0.0, vine_length(size)), Color(0.75, 0.62, 0.45), 3.0])
			where = "ceiling"
		"slug":
			items.append(["disc", p, 4.0, Color(0.62, 0.85, 0.42)])
			where = "surface"
		"shroom":
			# The sprite's size (shroom.gd sprite_for): a stem of most of
			# its height, a cap of its width.
			var fl: Vector2 = map.floor_below(p)
			var pick: Array = Shroom.sprite_for(size, int(spec.get("variant", 0)))
			var st: Dictionary = SceneBuilder.png_stamps().get(pick[0], {"w": 16, "h": 20})
			var cw: float = sim.PIXEL_SZ * pick[1] if sim else 2.0 * pick[1]
			var h: float = st.h * cw
			items.append(["line", Vector2(p.x, fl.y), Vector2(p.x, fl.y - h * 0.6), Color(0.94, 0.93, 0.79), 4.0])
			items.append(["disc", Vector2(p.x, fl.y - h * 0.8), st.w * cw * 0.5, Color(0.71, 0.80, 0.61)])
			where = "floor"
		"slime":
			items.append(["disc", p, slime_radius(size), Color(0.42, 0.82, 0.36)])
			where = "surface"
		"longslug":
			var ln := long_slug_length(size)
			items.append(["line", p - Vector2(ln * 0.5, 0.0), p + Vector2(ln * 0.5, 0.0), Color(0.86, 0.62, 0.74), 6.0])
			where = "surface"
		_:
			var table := stamp_table(name, size)
			where = edit_where(p, String(spec.get("where", "nearest")))
			var png: Dictionary = SceneBuilder.png_stamps().get(table, {})
			if not png.is_empty():
				if not _ghost_tex.has(table):
					_ghost_tex[table] = ImageTexture.create_from_image(png.img)
				items.append(["tex", _ghost_tex[table], SceneBuilder.frame(_surf(), p, where), png.w, png.h])
			else:
				for c in SceneBuilder.table_cells(_surf(), table, p, where):
					items.append(["cell", Rect2(c[0] * cell, c[1] * cell, cell, cell), CaveMap.THORN])
			items.append(["box", SceneBuilder.stamp_rect(_surf(), table, p, where)])
	_ghost.items = items
	_ghost.queue_redraw()
	return where


# The level file's decor list to entries, and back. A stamp is [name,
# x, y, where, flags] as before the split; a cone {"cone": name, x, y,
# h, variant}; a run {"run": names, path, where, spacing, mirror, pin,
# seed}, its path [x, y] pairs.
func _decor_entries(list: Array) -> Array:
	var out: Array = []
	for d in list:
		if d is Dictionary:
			if d.has("cone"):
				out.append({"type": "cone", "name": String(d.cone), "x": float(d.x), "y": float(d.y), "h": float(d.h),
						"variant": int(d.get("variant", 0)), "size": int(d.get("size", 0)), "rects": [], "rect": Rect2()})
			elif d.has("run"):
				var path: Array = []
				for q in d.path:
					path.append(Vector2(float(q[0]), float(q[1])))
				out.append({"type": "run", "names": (d.run as Array).map(func(n) -> String: return String(n)), "path": path,
						"where": String(d.where), "spacing": float(d.get("spacing", 0.0)), "mirror": bool(d.get("mirror", true)),
						"pin": String(d.get("pin", "")), "seed": int(d.seed), "rects": [], "rect": Rect2()})
			continue
		if d.size() < 4:
			continue
		out.append({"type": "stamp", "name": String(d[0]), "x": float(d[1]), "y": float(d[2]), "where": String(d[3]),
				"flags": String(d[4]) if d.size() > 4 else "", "anchor": String(d[5]) if d.size() > 5 else String(d[3]), "rects": [], "rect": Rect2()})
	return out


static func _decor_json(e: Dictionary) -> Variant:
	match String(e.type):
		"cone":
			return {"cone": e.name, "x": e.x, "y": e.y, "h": e.h, "variant": e.variant, "size": e.get("size", 0)}
		"run":
			return {"run": e.names, "path": (e.path as Array).map(func(q: Vector2) -> Array: return [q.x, q.y]), "where": e.where,
					"spacing": e.spacing, "mirror": e.mirror, "pin": e.pin, "seed": e.seed}
	return [e.name, e.x, e.y, e.where, e.flags, e.get("anchor", e.where)]


# --- The handles: what the editor takes hold of (editor.gd) ---
#
# An item is {list, i}: "decor" (a stamp, a cone, a run), "lumps" (a
# lump or a critter), "slugs" or "lights", and its index there. A move,
# a change or a removal is a stroke of its own, undone as one, and the
# world is made again from the level after it (a light only relights).

func edit_items() -> Array:
	var out: Array = []
	for list in ["decor", "lumps", "slugs", "lights"]:
		for i in _item_list(list).size():
			out.append({"list": list, "i": i, "rect": _item_rect(list, i)})
	return out


func _item_list(list: String) -> Array:
	match list:
		"decor":
			return _edit_decor
		"lumps":
			return _edit_lumps
		"slugs":
			return _edit_slugs
	return _edit_lights


func _item(it: Dictionary) -> Variant:
	if it.is_empty():
		return null
	var l := _item_list(String(it.list))
	return l[it.i] if int(it.i) < l.size() else null


# The box a handle is drawn as and taken by: what a decor entry set, a
# critter's or a lump's body about its point, a light's source and aim.
func _item_rect(list: String, i: int) -> Rect2:
	var m := _surf()
	match list:
		"decor":
			var e: Dictionary = _edit_decor[i]
			if (e.rect as Rect2).size != Vector2.ZERO:
				return e.rect
			var at := _v(e.path[0]) if e.type == "run" else Vector2(e.x, e.y)
			return Rect2(at - Vector2(4.0, 4.0), Vector2(8.0, 8.0))
		"lumps":
			var l: Array = _edit_lumps[i]
			var p := Vector2(float(l[1]), float(l[2]))
			var r := float(l[3])
			match String(l[0]):
				"vine":
					var c: Vector2 = m.ceiling_above(p)
					return Rect2(p.x - 5.0, c.y, 10.0, r)
				"shroom":
					var f: Vector2 = m.floor_below(p)
					return Rect2(p.x - 3.0 - 2.0 * r, f.y - 8.0 - 6.0 * r, 6.0 + 4.0 * r, 8.0 + 6.0 * r)
				"longslug":
					return Rect2(p.x - r * 0.5, p.y - 5.0, r, 10.0)
				"boulder", "clay":
					var f: Vector2 = m.floor_below(p)
					return Rect2(p.x - r, f.y - 2.0 * r - 2.0, 2.0 * r, 2.0 * r)
			return Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		"slugs":
			var s: Array = _edit_slugs[i]
			return Rect2(float(s[0]) - 5.0, float(s[1]) - 5.0, 10.0, 10.0)
	var lp: Array = SceneBuilder.light_point(_edit_lights[i])
	var a: Vector2 = lp[0]
	var b: Vector2 = lp[3]
	return Rect2(a, Vector2.ZERO).expand(b).grow(6.0)


# The item under p: the smallest box that holds it, so a mushroom on a
# run of moss is taken before the run.
func edit_item_at(p: Vector2) -> Dictionary:
	var best := {}
	var area := INF
	for it in edit_items():
		var r: Rect2 = (it.rect as Rect2).grow(2.0)
		if r.has_point(p) and r.get_area() < area:
			area = r.get_area()
			best = {"list": it.list, "i": it.i}
	return best


# What an item is, for the tag under the cursor.
func edit_item_text(it: Dictionary) -> String:
	var x = _item(it)
	if x == null:
		return ""
	match String(it.list):
		"decor":
			match String(x.type):
				"run":
					return "run of %s · %d pieces · %s" % [SceneBuilder.stamp_group(String(x.names[0])), x.rects.size(), x.where]
				"cone":
					return "%s · size %d · shape %d" % [x.name, _cone_size(x), int(x.variant) + 1]
			return "%s · %s%s" % [x.name, x.where, " · mirrored" if String(x.flags).contains("h") else ""]
		"lumps":
			return "%s · %d" % [String(x[0]), int(x[3])]
		"slugs":
			return "slug"
	return "%s light · r %d · strength %.1f" % [String(x[2]), int(_light_full(x)[3]), float(_light_full(x)[4])]


static func _cone_size(e: Dictionary) -> int:
	return clampi(int(round((float(e.h) - 12.0) / 12.0)), 1, 5)


# A light entry in its long form, [x, y, kind, radius, strength, shape, x2, y2].
static func _light_full(l: Array) -> Array:
	if l.size() >= 8:
		return l
	var k: Array = SceneBuilder.LIGHTS.get(String(l[2]), SceneBuilder.LIGHTS["torch"])
	return [l[0], l[1], l[2], l[3] if l.size() > 3 else k[1], l[4] if l.size() > 4 else 1.0, "point", l[0], l[1]]


# An item moved by d px: a stamp or a cone finds its surface from the
# moved point (a stamp set to the nearest surface takes the nearest
# there), a run's whole path moves and its pieces are laid again.
func edit_move(it: Dictionary, d: Vector2) -> String:
	var x = _item(it)
	if x == null or d.length() < 0.5:
		return ""
	d = _snap(d)
	edit_begin()
	match String(it.list):
		"decor":
			if x.type == "run":
				x.path = (x.path as Array).map(func(q) -> Vector2: return _v(q) + d)
			else:
				x.x += d.x
				x.y += d.y
				if x.type == "stamp" and String(x.get("anchor", "")) == "nearest":
					x.where = edit_where(Vector2(x.x, x.y), "nearest")
		"lumps":
			x[1] = float(x[1]) + d.x
			x[2] = float(x[2]) + d.y
		"slugs":
			x[0] = float(x[0]) + d.x
			x[1] = float(x[1]) + d.y
		"lights":
			var l := _light_full(x)
			l[0] = float(l[0]) + d.x
			l[1] = float(l[1]) + d.y
			l[6] = float(l[6]) + d.x
			l[7] = float(l[7]) + d.y
			_edit_lights[it.i] = l
	_item_changed(it)
	return "moved %d, %d" % [int(d.x), int(d.y)]


func edit_remove(it: Dictionary) -> String:
	if _item(it) == null:
		return "nothing there"
	var what := edit_item_text(it)
	edit_begin()
	_item_list(String(it.list)).remove_at(it.i)
	_item_changed(it)
	return what.get_slice(" · ", 0) + " removed"


# The wheel on an item: the next variant of a stamp's group (the same
# role, an end for an end), another pick of a run's rules (its seed), a
# cone's or a shroom's next shape, a light's radius (Shift: strength).
func edit_turn(it: Dictionary, dir: int, shift: bool) -> String:
	var x = _item(it)
	if x == null:
		return ""
	edit_begin()
	match String(it.list):
		"decor":
			match String(x.type):
				"run":
					x.seed = (int(x.seed) + dir) & 0x7fffffff
				"cone":
					x.variant = posmod(int(x.variant) + dir, 4)
				_:
					var names: Array = []
					var group := SceneBuilder.stamp_group(String(x.name))
					var role := SceneBuilder.stamp_role(String(x.name))
					for n in SceneBuilder.png_stamps():
						if SceneBuilder.stamp_group(n) == group and SceneBuilder.stamp_role(n) == role:
							names.append(n)
					names.sort()
					if names.size() > 1:
						x.name = names[posmod(names.find(x.name) + dir, names.size())]
		"lumps":
			if String(x[0]) == "shroom":
				while x.size() < 5:
					x.append(0.0)
				x[4] = float(posmod(int(x[4]) + dir, 2))
		"lights":
			var l := _light_full(x)
			if shift:
				l[4] = clampf(snappedf(float(l[4]) + 0.1 * dir, 0.1), 0.2, 2.0)
			else:
				l[3] = clampf(float(l[3]) + 2.0 * dir, 4.0, 64.0)
			_edit_lights[it.i] = l
	_item_changed(it)
	return edit_item_text(it)


# Up and down on an item: a cone's height, a vine's length, a shroom's,
# a slime's or a long slug's size 1 to 5, a lump's radius, the thorn
# bush small or big.
func edit_resize(it: Dictionary, dir: int) -> String:
	var x = _item(it)
	if x == null:
		return ""
	edit_begin()
	match String(it.list):
		"decor":
			if x.type == "cone":
				x.size = clampi(_cone_size(x) + dir, 1, 5)
				x.h = cone_height(x.size)
			elif x.type == "stamp" and String(x.name).begins_with("thorn"):
				x.name = "thorn" if dir > 0 else "thorn_s"
		"lumps":
			match String(x[0]):
				"vine":
					x[3] = vine_length(clampi(int(round(float(x[3]) / 24.0)) + dir, 1, 5))
				"shroom":
					x[3] = float(clampi(int(x[3]) + dir, 1, 5))
				"slime":
					x[3] = slime_radius(clampi(int(round((float(x[3]) - 5.0) / 3.0)) + dir, 1, 5))
				"longslug":
					x[3] = long_slug_length(clampi(int(round((float(x[3]) - 20.0) / 14.0)) + dir, 1, 5))
				_:
					x[3] = clampf(float(x[3]) + dir, 3.0, 30.0)
	_item_changed(it)
	return edit_item_text(it)


# H on an item: a stamp mirrored along its surface, a run's random
# mirroring on or off.
func edit_flip(it: Dictionary) -> String:
	var x = _item(it)
	if x == null or String(it.list) != "decor" or x.type == "cone":
		return ""
	edit_begin()
	if x.type == "run":
		x.mirror = not bool(x.mirror)
	else:
		x.flags = String(x.flags).replace("h", "") if String(x.flags).contains("h") else String(x.flags) + "h"
	_item_changed(it)
	return edit_item_text(it)


# After a change to an item: the world made again (a light only lit
# again), and the change one undo step.
func _item_changed(it: Dictionary) -> void:
	if String(it.list) == "lights":
		_relight()
	else:
		_rebuild_world()
	edit_end()


# The handles drawn (LightMarks): every item's box faint, the one under
# the cursor and the one taken brighter, the taken one at the drag's
# offset while it is dragged.
func edit_marks(hover: Dictionary, sel: Dictionary, offset: Vector2) -> void:
	if _marks == null:
		return
	var boxes: Array = []
	if _editing:
		for it in edit_items():
			var st := 0
			if not sel.is_empty() and it.list == sel.list and it.i == sel.i:
				st = 2
			elif not hover.is_empty() and it.list == hover.list and it.i == hover.i:
				st = 1
			boxes.append([it.rect, st])
	_marks.boxes = boxes
	_marks.offset = offset
	_marks.queue_redraw()


func edit_spawn(p: Vector2) -> String:
	_edit_spawn = p
	gecko.spawn(p, Vector2.UP)
	_cam_reset()
	return "spawn at %d, %d" % [int(p.x), int(p.y)]


func edit_exit(r: Rect2) -> String:
	_edit_exit = r
	_exit = r
	if sim:
		sim.set_daylight(_exit, DAYLIGHT)
	_sound.set_exit(_exit)
	waves.set_exit(_exit)
	return "exit %d, %d, %d x %d" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


# The editor's camera: the wheel zooms about the cursor, without a
# limit either way, the middle button pans; Home (edit_home) brings
# it back to the gecko at the game's zoom. The camera's grid follows
# the zoom, so the view still moves by whole screen pixels.
func edit_zoom(factor: float, screen: Vector2) -> void:
	var half := get_viewport().get_visible_rect().size * 0.5
	var under := _camera.get_screen_center_position() + (screen - half) / _camera.zoom.x
	var z := clampf(_camera.zoom.x * factor, 0.02, 64.0)
	_camera.zoom = Vector2(z, z)
	_edit_take_camera()
	_cam = under - (screen - half) / z
	_cam_target = _cam
	_follow()


func edit_pan(screen_delta: Vector2) -> void:
	_edit_take_camera()
	_cam -= screen_delta / _camera.zoom.x
	_cam_target = _cam
	_follow()


func _edit_take_camera() -> void:
	if not _edit_cam:
		_cam = _camera.get_screen_center_position()
		_edit_cam = true
		_camera.limit_left = -CAM_LIMIT
		_camera.limit_top = -CAM_LIMIT
		_camera.limit_right = CAM_LIMIT
		_camera.limit_bottom = CAM_LIMIT
	_cam_grid = 1.0 / _camera.zoom.x
	if _backdrop:
		_backdrop.set_grid(_cam_grid)


func edit_home() -> void:
	if _won:
		return
	_camera_home()
	_cam_reset()


func edit_zoom_text() -> String:
	return "zoom %.2f" % _camera.zoom.x


# --- Level files ---
#
# A level the editor works on lives as versions: levels/<name>/vNNNN.json
# with vNNNN.cells.png beside it, one pair a version, numbered up, the
# json carrying saved_at and kind (auto or saved). Autosave writes an
# auto version every AUTOSAVE_S seconds while there are strokes since
# the last version, keeping the last AUTOSAVE_KEEP of them; Save writes
# a saved version, kept for good, and the head pair levels/<name>.json
# and levels/<name>.cells.png, what the game and the suite load
# (tests/scene_builder.gd level_files). A level generated by tools (the
# clutch) has a head and no folder: its edits go under <name>-edit, a
# generated cave's under cave<seed>.

const AUTOSAVE_S := 60.0
const AUTOSAVE_KEEP := 10
const LEVELS := "res://levels/"

var _level_name := ""           # The level the strokes belong to: what the versions are written under
var _dirty := false             # Strokes since the last saved version or load
var _dirty_v := false           # Strokes since the last version of any kind: what autosave waits for
var _version := 0               # The last version written or loaded, 0 for none
var _version_kind := ""         # Its kind, auto or saved
var _version_at := 0.0          # When it was written or loaded, seconds on the clock
var _autosave_t := 0.0


# The levels in levels/, by name: the heads.
func level_names() -> Array:
	var out: Array = []
	for path in SceneBuilder.level_files():
		out.append(String(path).get_file().trim_suffix(".json"))
	return out


# Every level for the Load dialog: a folder of versions, or a head with
# none (generated by tools, read only). [{name, versions, generated}],
# the edited ones first.
func level_entries() -> Array:
	var out: Array = []
	var seen := {}
	var dir := DirAccess.open(LEVELS)
	if dir == null:
		return out
	var folders: Array = Array(dir.get_directories())
	folders.sort()
	for f in folders:
		var n := level_versions(String(f)).size()
		if n > 0:
			out.append({"name": String(f), "versions": n, "generated": false})
			seen[String(f)] = true
	for name in level_names():
		if not seen.has(name):
			out.append({"name": name, "versions": 0, "generated": true})
	return out


# A level's versions, the latest first: [{n, file, kind, saved_at}].
func level_versions(name: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(LEVELS + name)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("v") and f.ends_with(".json"):
			var data = JSON.parse_string(FileAccess.get_file_as_string(LEVELS + name + "/" + f))
			if data is Dictionary:
				out.append({"n": int(String(f).substr(1, 4)), "file": String(f), "kind": String(data.get("kind", "saved")), "saved_at": String(data.get("saved_at", ""))})
	out.sort_custom(func(a, b) -> bool: return a.n > b.n)
	return out


func level_name() -> String:
	return _level_name


func level_dirty() -> bool:
	return _dirty


# The last version written or loaded: [n, kind, seconds ago], n 0 for none.
func level_version_info() -> Array:
	return [_version, _version_kind, (Time.get_ticks_msec() / 1000.0 - _version_at) if _version > 0 else 0.0]


# Whether Save may write levels/<name>.json: a new name, or a level the
# editor wrote (a cells file). A generated level keeps its generator.
func level_writable(name: String) -> bool:
	_ensure_scenes()
	var bases: Dictionary = _scene_all.get("bases", {})
	if not bases.has(name):
		return true
	for op in bases[name]:
		if String(op[0]) == "cells":
			return true
	return false


# The name the strokes go under when the level has none: cave<seed> for
# a generated cave, <scene>-edit for a scene from a file that tools wrote.
func _default_level_name() -> String:
	if _scene.is_empty():
		return "cave%d" % seed_value
	if _scene_i >= 0:
		var n := String(_scene_all.get("scenes", {}).keys()[_scene_i])
		return n if level_writable(n) else n + "-edit"
	return "edit"


# The level as a file: a base of the cells png, the terrain alone, and
# one scene on it with the spawn, the exit, the vines and lumps, the
# slugs, the decor entries and the lights. The game and the suite load
# it like the clutch. A generated cave saves its own spawn and the
# lumps it scattered, so a load of it starts where it started, with
# the same boulders and heaps.
func _level_dict(name: String, png: String) -> Dictionary:
	var spawn: Array = ["at", _edit_spawn.x, _edit_spawn.y, 0, -1] if _edit_spawn != Vector2.INF else _scene.get("spawn", ["floor", _gen_spawn.x, _gen_spawn.y - 20.0])
	var decor: Array = []
	for e in _edit_decor:
		decor.append(_decor_json(e))
	var sc := {"base": name, "spawn": spawn, "lumps": _edit_lumps.duplicate(true), "slugs": _edit_slugs.duplicate(true), "decor": decor, "lights": _edit_lights.duplicate(true)}
	var ex := _edit_exit if _edit_exit.has_area() else _exit
	if ex.has_area():
		sc["exit"] = [ex.position.x, ex.position.y, ex.size.x, ex.size.y]
	return {"bases": {name: [["blank"], ["cells", png]]}, "scripts": {}, "scenes": {name: sc}}


# A version of the level in hand: the next number under levels/<name>/,
# the cells png and the json. A saved one rewrites the head pair too and
# clears the dirty flag; an auto one prunes the autos before it past
# AUTOSAVE_KEEP.
func write_version(kind: String) -> String:
	if _author == null:
		return "nothing to save"
	if _level_name == "":
		_level_name = _default_level_name()
	var name := _level_name
	var dir := LEVELS + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := 1
	var versions := level_versions(name)
	if not versions.is_empty():
		n = int(versions[0].n) + 1
	var stem := dir + "v%04d" % n
	if not _write_pair(name, stem, kind):
		return "cannot write " + stem + ".json"
	if kind == "saved":
		if not _write_pair(name, LEVELS + name, kind):
			return "cannot write the head " + LEVELS + name + ".json"
		_dirty = false
		_scene_all = {}
	else:
		var autos := 0
		for v in level_versions(name):
			if v.kind == "auto":
				autos += 1
				if autos > AUTOSAVE_KEEP:
					DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + v.file))
					DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + String(v.file).trim_suffix(".json") + ".cells.png"))
	_dirty_v = false
	_autosave_t = 0.0
	_version = n
	_version_kind = kind
	_version_at = Time.get_ticks_msec() / 1000.0
	return "%s v%d of %s" % ["saved" if kind == "saved" else "auto-saved", n, name]


func _write_pair(name: String, stem: String, kind: String) -> bool:
	var png := stem + ".cells.png"
	_author.save_cells_png(ProjectSettings.globalize_path(png))
	var level := _level_dict(name, png)
	level["saved_at"] = Time.get_datetime_string_from_system(false, true)
	level["kind"] = kind
	var f := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(level, " "))
	f.close()
	return true


# Save: a saved version and the head, under the name given or the one in hand.
func save_level(name := "") -> String:
	if name != "":
		_level_name = name
	return write_version("saved")


# Autosave: an auto version once AUTOSAVE_S have passed with strokes
# since the last version.
func _autosave(dt: float) -> void:
	if not _dirty_v:
		return
	_autosave_t += dt
	if _autosave_t >= AUTOSAVE_S:
		_editor.call("say", write_version("auto"))


# Loads a version of a level: its json as the scene (the cells png of
# that version), built like the clutch. file "" takes the latest, and
# the head when the level has no versions.
func load_version(name: String, file := "") -> String:
	if file == "":
		var versions := level_versions(name)
		if versions.is_empty():
			return load_level(name)
		file = String(versions[0].file)
	var data = JSON.parse_string(FileAccess.get_file_as_string(LEVELS + name + "/" + file))
	if not (data is Dictionary) or not data.get("scenes", {}).has(name):
		return "cannot read " + file
	_scene = data.scenes[name]
	_scene_bases = data.get("bases", {})
	_scene_i = -1
	_demo_step = -1
	gecko.input_override = null
	_edit_clear()
	_level_name = name
	_version = int(file.substr(1, 4))
	_version_kind = String(data.get("kind", "saved"))
	_version_at = Time.get_ticks_msec() / 1000.0
	_reset()
	return "loaded %s v%d" % [name, _version]


# Loads levels/<name>.json, the head, as the scene and builds it.
func load_level(name: String) -> String:
	_scene_all = {}
	_ensure_scenes()
	var scenes: Dictionary = _scene_all.get("scenes", {})
	if not scenes.has(name):
		return "no level " + name
	_scene = scenes[name]
	_scene_bases = _scene_all.get("bases", {})
	_scene_i = scenes.keys().find(name)
	_demo_step = -1
	gecko.input_override = null
	_edit_clear()
	_level_name = name if level_writable(name) else name + "-edit"
	_version = 0
	_version_kind = ""
	_reset()
	return "loaded " + name


# An empty rock world to paint in: a blank scene with a room to stand
# in, under the name given, its first version written at once.
func blank_level(name := "") -> String:
	_scene = {"base": "room", "terrain": [], "spawn": ["floor", 960, 700], "lumps": [], "slugs": []}
	_scene_bases = {"room": [["blank"], ["room", 0, 160, 1920, 640]]}
	_scene_i = -1
	_demo_step = -1
	gecko.input_override = null
	_edit_clear()
	_level_name = name
	_version = 0
	_version_kind = ""
	_reset()
	if name != "":
		return "new level %s: %s" % [name, write_version("saved")]
	return "blank"


# A level's files gone: the head pair and the versions (the self test).
func _remove_level_files(name: String) -> void:
	var g := ProjectSettings.globalize_path(LEVELS)
	DirAccess.remove_absolute(g + name + ".json")
	DirAccess.remove_absolute(g + name + ".cells.png")
	var dir := DirAccess.open(LEVELS + name)
	if dir:
		for f in dir.get_files():
			DirAccess.remove_absolute(g + name + "/" + f)
		DirAccess.remove_absolute(g + name)


func _edit_clear() -> void:
	_edit_lumps.clear()
	_edit_slugs.clear()
	_edit_decor.clear()
	_edit_lights.clear()
	_edit_spawn = Vector2.INF
	_edit_exit = Rect2()
	_undo.clear()
	_redo.clear()
	_stroke = {}
	_dirty = false
	_dirty_v = false


# --- The gecko's animations (the debug panel's Curl and Wake) ---
#
# The wake-up and the curl are the pose animation poses/wake.json made
# in the pose editor (pose_anim.gd, pose_editor.gd), played on the
# gecko's own body: forwards to wake, backwards and held to sleep, a
# key waking it. Without that file the sprite frames from
# decor/gecko/wake play over the hidden body instead.

const ANIM_DIR := "res://decor/gecko/wake"
const ANIM_FRAMES := 17        # wake_1x_00 (curled asleep) to wake_1x_16 (the standing sprite)
const ANIM_STEP := 0.16        # Seconds a frame shows
var _anim: Sprite2D
var _anim_tex: Array = []
var _anim_name := ""           # "" none, "wake" curled to standing, "curl" the reverse, held asleep at its end
var _anim_t := 0.0
var _anim_input = null         # The gecko's input override before the animation froze it
var _anim_pose := false        # The animation playing is the pose one (the gecko's play_pose), not the sprites


func _anim_load() -> void:
	if not _anim_tex.is_empty():
		return
	for i in ANIM_FRAMES:
		var bytes := FileAccess.get_file_as_bytes("%s/wake_1x_%02d.png" % [ANIM_DIR, i])
		var img := Image.new()
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			push_error("no animation frame %d in %s" % [i, ANIM_DIR])
			_anim_tex.clear()
			return
		_anim_tex.append(ImageTexture.create_from_image(img))


# Plays the wake-up (curled asleep to standing, then the gecko draws
# itself again) or the curl (the same backwards, held asleep until a
# wake or a reset) at the gecko's place on the floor, the sprite on the
# gecko's 2 px grid and facing its way; the gecko is hidden and takes no
# input meanwhile.
func play_anim(name: String) -> void:
	# wake and curl are the wake file forwards and backwards; any other
	# name is a pose file of its own, played forwards (the panel's Pose
	# row, GECKO_ANIM): its last frame should be the standing pose.
	var file := PoseAnim.WAKE if (name == "wake" or name == "curl") else name
	if PoseAnim.exists(file):
		var frames := PoseAnim.load_head(file)
		if not frames.is_empty():
			_anim_stop()
			_anim_name = name
			_anim_pose = true
			gecko.play_pose(frames, name == "curl", name == "curl")
			return
	if name != "wake" and name != "curl":
		push_warning("no pose file poses/%s.json" % name)
		return
	_anim_load()
	if _anim_tex.is_empty() or _anim == null:
		return
	if _anim_name == "":
		_anim_input = gecko.input_override
		gecko.input_override = Vector2.ZERO
	_anim_name = name
	_anim_t = 0.0
	gecko.body_hidden = true
	_anim.visible = true
	_anim_place()
	_anim_show()


func _anim_place() -> void:
	var fl: Vector2 = map.floor_below(gecko.pos)
	# The canvas is 48 by 24 at 2 px a pixel, the feet on its row 22.
	var top := Vector2(gecko.pos.x - 48.0, fl.y - 44.0)
	_anim.position = (top / 2.0).floor() * 2.0
	_anim.flip_h = gecko.facing > 0.0   # Drawn facing left


func _anim_show() -> void:
	var i := clampi(int(_anim_t / ANIM_STEP), 0, ANIM_FRAMES - 1)
	_anim.texture = _anim_tex[i if _anim_name == "wake" else ANIM_FRAMES - 1 - i]


func _anim_tick(dt: float) -> void:
	if _anim_name == "":
		return
	if _anim_pose:
		if not gecko.posing:
			_anim_stop()   # The wake-up ran out: the gecko has its body back
		elif gecko.pose_held() and gecko.input_override == null and (Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.2 or Input.is_action_just_pressed("jump")):
			play_anim("wake")   # Asleep: a key wakes it
		return
	_anim_t += dt
	if _anim_t >= ANIM_FRAMES * ANIM_STEP:
		if _anim_name == "wake":
			_anim_stop()
			return
		_anim_t = (ANIM_FRAMES - 1) * ANIM_STEP   # Asleep: the curled frame held
	_anim_show()


func _anim_stop() -> void:
	if _anim_name == "":
		return
	_anim_name = ""
	_anim.visible = false
	gecko.body_hidden = false
	if _anim_pose:
		_anim_pose = false
		gecko.stop_pose()
	else:
		gecko.input_override = _anim_input
		_anim_input = null


# Q held: the gecko stands up like a meerkat (poses/meerkat.json) and
# holds there, and the hum's ripples show as it rises; let go, it gets
# down and they fade. Only from the gecko's own stance: not mid-air,
# not in another animation, not in the editor.
func _listen_tick() -> void:
	var held := Input.is_action_pressed("listen") and not _editing and gecko.input_override == null
	if held and not _listening and _anim_name == "" and not gecko.posing and gecko.clinging and not gecko.swimming:
		var frames: Array = PoseAnim.load_head("meerkat") if PoseAnim.exists("meerkat") else []
		if not frames.is_empty():
			_listen_marks(frames)
			play_anim("meerkat")
			gecko.pose_stop_t = _listen_up
			_listening = true
	if _listening and (not gecko.posing or _anim_name != "meerkat"):
		_listening = false
	if _listening and not held and gecko.pose_stop_t < INF:
		gecko.pose_stop_t = INF
		gecko.pose_seek(_listen_down)
	var t: float = gecko.pose_time() if _listening else 0.0
	if not _listening:
		waves.listen = 0.0
	elif t <= _listen_up:
		waves.listen = clampf(t / maxf(_listen_up, 0.01), 0.0, 1.0)
	elif t < _listen_down:
		waves.listen = 1.0
	else:
		waves.listen = clampf(1.0 - (t - _listen_down) / maxf(_listen_end - _listen_down, 0.01), 0.0, 1.0)


# The meerkat's times: where the head first stands tallest and where it
# last does (the hold between), from the frames themselves.
func _listen_marks(frames: Array) -> void:
	var top := INF
	for f in frames:
		top = minf(top, (f.points as PackedVector2Array)[0].y)
	var at := 0.0
	_listen_up = -1.0
	for f in frames:
		if (f.points as PackedVector2Array)[0].y <= top + 0.5:
			if _listen_up < 0.0:
				_listen_up = at
			_listen_down = at
		at += float(f.dur)
	_listen_end = PoseAnim.total(frames)


# The pose editor (pose_editor.gd), a scene of its own: F3 or the
# panel's Poses button. F3 or Esc there comes back to a fresh game.
func _open_pose_editor() -> void:
	get_tree().change_scene_to_file.call_deferred("res://pose_editor.tscn")


# Gas pockets from the authored cells (painted ones have no op): each
# connected patch of gas cells as its bounding rect.
func _gas_from_cells() -> void:
	if _author == null:
		return
	var W: int = CaveMap.W_FULL
	var H: int = CaveMap.H_FULL
	var seen := {}
	for i in _author.solid.size():
		if _author.solid[i] != CaveMap.CELL_GAS or seen.has(i):
			continue
		var queue := [i]
		seen[i] = true
		var x0 := W
		var y0 := H
		var x1 := -1
		var y1 := -1
		while not queue.is_empty():
			var c: int = queue.pop_back()
			var x := c % W
			var y := c / W
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			for d in [c - 1, c + 1, c - W, c + W]:
				if d >= 0 and d < W * H and not seen.has(d) and _author.solid[d] == CaveMap.CELL_GAS:
					seen[d] = true
					queue.append(d)
		var r := Rect2(x0 * CaveMap.CELL_FULL, y0 * CaveMap.CELL_FULL, (x1 - x0 + 1) * CaveMap.CELL_FULL, (y1 - y0 + 1) * CaveMap.CELL_FULL)
		var known := false
		for g in _gas:
			if g.intersects(r):
				known = true
		if not known:
			_gas.append(r)


# A gas pocket whose wall has been opened (a cell on the ring just
# outside it reads open after a bite or a strike) bursts: the gecko is
# thrown from its centre with its glow out, the pocket is plain air, the
# sim gets a blast and a puff.
func _check_gas() -> void:
	for i in range(_gas.size() - 1, -1, -1):
		var r: Rect2 = _gas[i]
		if not _gas_opened(r):
			continue
		var c := r.get_center()
		_gas.remove_at(i)
		if _author and not sim:
			# The pocket is plain air in the bitmap world's map, which is
			# its authoring map too. The sim's shows air there already
			# and its authored cells keep the pocket for the next build.
			_author.clear_gas(r)
		gecko.blast(c, BLAST_SPEED)
		if sim:
			sim.trigger_explosion_at(c, BLAST_R)
		map.spawn_puff(c, 14, Vector2(0.0, -40.0), 70.0, 0.004)


func _gas_opened(r: Rect2) -> bool:
	var cell: float = map.CELL
	var x0 := int(floor(r.position.x / cell)) - 1
	var y0 := int(floor(r.position.y / cell)) - 1
	var x1 := int(ceil(r.end.x / cell))
	var y1 := int(ceil(r.end.y / cell))
	for x in range(x0, x1 + 1):
		if not map.is_solid(x, y0) or not map.is_solid(x, y1):
			return true
	for y in range(y0 + 1, y1):
		if not map.is_solid(x0, y) or not map.is_solid(x1, y):
			return true
	return false


# The slugs creep (slug.gd), one swallowed at the mouth is gone and the
# gecko's glow brightens, and their blobs go to the gecko's drawing.
func _update_slugs(dt: float) -> void:
	var blobs_out: Array = []
	for i in range(_slugs.size() - 1, -1, -1):
		var s: Node2D = _slugs[i]
		s.tick(dt, gecko)
		if s.eaten:
			gecko.gulp_slug()
			_slugs.remove_at(i)
			s.queue_free()
			continue
		for b in s.blobs():
			blobs_out.append(b)
	gecko.extra_blobs = blobs_out


func _clear_slugs() -> void:
	for s in _slugs:
		s.queue_free()
	_slugs.clear()
	gecko.extra_blobs = []


# A vine the gecko hangs on (a planted foot on its cells) takes the
# load for VINE_HOLD (when VINE_TEAR is on), then its anchor's bonds are broken and it comes
# down, gecko and all; the load eases off a vine let go of.
func _update_vines(dt: float) -> void:
	var held: RefCounted = critters.held_vine()
	for v in critters.vines:
		if v.gone:
			continue
		v.hang = v.hang + dt if v == held else maxf(v.hang - dt * 2.0, 0.0)
		if VINE_TEAR and v.hang >= VINE_HOLD:
			v.tear()


# The camera, after the gecko's tick (its ticked signal). Out of the
# cave it lets go of the gecko and pulls back over the whole cave, the
# rock round it in view. Otherwise it follows the drawn body's base:
# it scrolls exactly with the base's own move up to CAM_LOCK_SPEED, so
# an ordinary walk keeps the body on the same screen pixels and the
# small unevenness of its speed goes into the scroll, where the eye
# does not see it, rather than into the body's place on the screen;
# whatever lag is left (a fall, a landing's jolt, a long move in one
# tick) eases out at CAMERA_EASE. It sits on whole screen pixels
# (CAM_GRID), held inside the world's edges, so the world scrolls a
# screen pixel at a time and every edge stays crisp. The body's own
# pixel grid is anchored on the base's place on the screen's pixels
# (the blob layer's origin), so the body is drawn with the same pixels
# tick after tick and moves on the screen only as the camera's lag
# changes, a screen pixel at a time. Before, the camera was rounded to
# the body's 2 px grid and the body to the world's: the two crossed
# pixel boundaries at different moments and the body shook a pixel
# back and forth as it walked, while the world scrolled in 2 px steps.
func _follow() -> void:
	var dt := get_physics_process_delta_time()
	if _won:
		var k := 1.0 - exp(-WIN_PULL * dt)
		_cam = _cam.lerp(Vector2(CaveMap.W_FULL * CaveMap.CELL_FULL, CaveMap.H_FULL * CaveMap.CELL_FULL) * 0.5, k)
		_camera.position = _cam
		_camera.zoom = _camera.zoom.lerp(Vector2(WIN_ZOOM, WIN_ZOOM), k)
		return
	if _editing and _edit_cam:
		# The editor's camera: where the wheel and the middle button put it.
		_camera.position = _cam_clamped((_cam / _cam_grid).round() * _cam_grid)
		_cam_target = gecko.draw_pos()
		_seat_off = Vector2.ZERO
		_cam_seat = _camera.position
		blobs.set_origin(_cam_seat.posmodv(Vector2(blobs.pixel_sz, blobs.pixel_sz)))
		if _backdrop:
			_backdrop.follow(_camera.position)
		return
	var target := gecko.draw_pos()
	_cam += (target - _cam_target).limit_length(CAM_LOCK_SPEED * dt)
	_cam_target = target
	_cam = _cam.lerp(target, 1.0 - exp(-CAMERA_EASE * dt))
	_camera.position = _cam_clamped((_cam / _cam_grid).round() * _cam_grid)
	# The seat moves to the lag's nearest screen pixel only once the lag
	# has left the seat by a whole one: the camera's own rounding to the
	# grid puts a quarter pixel of noise on the lag, which would rock a
	# seat at a boundary between two pixels.
	var lag := target - _camera.position
	for k in 2:
		if absf(lag[k] - _seat_off[k]) >= _cam_grid:
			_seat_off[k] = roundf(lag[k] / _cam_grid) * _cam_grid
	_cam_seat = _camera.position + _seat_off
	blobs.set_origin(_cam_seat.posmodv(Vector2(blobs.pixel_sz, blobs.pixel_sz)))
	if _backdrop:
		_backdrop.follow(_camera.position)


# The camera straight onto the gecko, as at a spawn.
func _cam_reset() -> void:
	_cam = gecko.draw_pos()
	_cam_target = _cam
	_camera.position = _cam_clamped((_cam / _cam_grid).round() * _cam_grid)
	_seat_off = Vector2.ZERO
	_cam_seat = _camera.position
	blobs.set_origin(_cam_seat.posmodv(Vector2(blobs.pixel_sz, blobs.pixel_sz)))


# The camera centre held inside its limits, as Camera2D itself would
# hold it, so the position set is the position shown and the blob grid
# can be anchored to it; on the camera's grid, so the view at an edge
# stays on whole screen pixels.
func _cam_clamped(p: Vector2) -> Vector2:
	var half := get_viewport().get_visible_rect().size * 0.5 / _camera.zoom
	half = (half / _cam_grid).ceil() * _cam_grid
	if _editing and _edit_cam:
		# The editor's view may be wider than the world: then it is centred on it.
		var world := Vector2(CaveMap.W_FULL * CaveMap.CELL_FULL, CaveMap.H_FULL * CaveMap.CELL_FULL)
		var out := p
		for k in 2:
			out[k] = world[k] * 0.5 if half[k] * 2.0 >= world[k] else clampf(p[k], half[k], world[k] - half[k])
		return out
	return Vector2(clampf(p.x, _camera.limit_left + half.x, _camera.limit_right - half.x),
			clampf(p.y, _camera.limit_top + half.y, _camera.limit_bottom - half.y))


# The gecko is out of the cave. Input stays with the player; the camera
# pulls back (see _physics_process) and R starts the cave again.
func _win() -> void:
	_won = true
	_camera.limit_left = -CAM_LIMIT
	_camera.limit_top = -CAM_LIMIT
	_camera.limit_right = CAM_LIMIT
	_camera.limit_bottom = CAM_LIMIT
	_hint = "out, into the light.   R hatches again"
	_hint_t = 0.0


# The camera back on the gecko at the game's zoom, held to the world.
func _camera_home() -> void:
	_won = false
	_edit_cam = false
	_cam_grid = CAM_GRID
	if _backdrop:
		_backdrop.set_grid(_cam_grid)
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(CaveMap.W_FULL * CaveMap.CELL_FULL)
	_camera.limit_bottom = int(CaveMap.H_FULL * CaveMap.CELL_FULL)


# F1 and the start: the panel and the state readout, and the gecko's
# overlay only while the panel's Overlay check is on (the check keeps
# its state across F1).
func _set_debug(on: bool) -> void:
	_debug = on
	_panel.visible = on
	_wave_panel.visible = on
	waves.show_marks = on
	gecko.debug = on and _panel.overlay_on()


# The sim's light pass on or off (the whole cave lit flat): the debug
# panel's check and the editor's, kept in step.
func set_light(on: bool) -> void:
	if sim:
		sim.set_light(on)
	_panel.set_light(on)
	_editor.set_light(on)


func light_on() -> bool:
	return sim.light_on if sim else false


# The first cave as the scene to build: its index in the scene list, so
# Ctrl+Tab goes on from it.
func _pick_level() -> void:
	_ensure_scenes()
	var scenes: Dictionary = _scene_all.get("scenes", {})
	if not scenes.has(LEVEL):
		push_error("no level named " + LEVEL)
		_scene = {}
		_scene_i = -1
		return
	_scene = scenes[LEVEL]
	_scene_bases = _scene_all.get("bases", {})
	_scene_i = scenes.keys().find(LEVEL)
	_panel.select_scene(_scene_i)


func _in_level() -> bool:
	return not _scene.is_empty() and _scene_i >= 0 and _scene_all.get("scenes", {}).keys()[_scene_i] == LEVEL


func _ensure_scenes() -> void:
	if _scene_all.is_empty():
		_scene_all = SceneBuilder.load_all()


# Ctrl+Tab: the next test scene from tests/scenes.json, built in this
# world, with the keys driving the gecko instead of the scene's script.
func _next_scene() -> void:
	_ensure_scenes()
	var n: int = _scene_all.get("scenes", {}).size()
	if n > 0:
		_load_scene((_scene_i + 1) % n)


func _load_scene(i: int) -> void:
	_ensure_scenes()
	var names: Array = _scene_all.get("scenes", {}).keys()
	if names.is_empty() or i < 0 or i >= names.size():
		return
	_scene_i = i
	var name: String = names[i]
	_scene = _scene_all.scenes[name]
	_scene_bases = _scene_all.bases
	_demo_step = -1
	gecko.input_override = null
	gecko.chew_override = false
	gecko.lmb_override = false
	_reset()
	_panel.select_scene(i)
	_hint = "scene %d/%d  %s   (Ctrl+Tab next, Shift+Tab main cave)" % [i + 1, names.size(), name]
	_hint_t = 5.0


# Shift+Tab: back to the main cave.
func _main_cave() -> void:
	_pick_level()
	_demo_step = -1
	gecko.input_override = null
	gecko.chew_override = false
	gecko.lmb_override = false
	_reset()
	_hint = LEVEL
	_hint_t = 7.0


func _run_demo(dt: float) -> void:
	if _demo_step >= _demo.size():
		gecko.input_override = Vector2.ZERO
		gecko.chew_override = false
		gecko.lmb_override = false
		gecko.aim_override = Vector2.ZERO
		if _stay and not _scene.is_empty():
			_demo_step = -1
			gecko.input_override = null
			_hint = "the script is done: the keys are yours (R rebuilds the scene, Tab the next one)"
			_hint_t = 6.0
			return
		if not _scene.is_empty():
			_scene_done = maxf(_scene_done, 0.0) + dt
			if _scene_done >= SCENE_SETTLE:
				# GECKO_DUMP_END=file.png: the bitmap world's cells as the
				# script left them (a dug tunnel), for a look.
				var dump := OS.get_environment("GECKO_DUMP_END")
				if dump != "" and not sim:
					map.save_png(dump)
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
		var t0 := Time.get_ticks_usec()
		sim.read_render()
		_read_us = Time.get_ticks_usec() - t0
		_read_peak = maxi(_read_peak, _read_us)
		if _timing:
			_t_render.append(_read_us)
	# The frame readout: refreshed twice a second, the worst values since
	# the last refresh beside the current ones, so a dropped frame shows.
	_frame_peak = maxf(_frame_peak, _dt * 1000.0)
	_gecko_us = gecko.tick_us
	_gecko_peak = maxi(_gecko_peak, _gecko_us)
	_fps_t += _dt
	if _fps_t >= 0.5:
		var text := "fps %d   frame %.1f ms (worst %.1f)   gecko tick %.2f ms (worst %.2f)" % [
			Engine.get_frames_per_second(), _dt * 1000.0, _frame_peak, _gecko_us / 1000.0, _gecko_peak / 1000.0]
		if sim:
			text += "   sim tick %.2f ms (worst %.2f)   readback %.2f ms (worst %.2f)" % [_sim_us / 1000.0, _sim_peak / 1000.0, _read_us / 1000.0, _read_peak / 1000.0]
		if critters.last_us > 0:
			text += "   critters %.2f ms" % (critters.last_us / 1000.0)
		_fps_label.text = text
		_fps_t = 0.0
		_frame_peak = 0.0
		_gecko_peak = 0
		_sim_peak = 0
		_read_peak = 0
	if _trace:
		# One line per drawn frame, for tools/analyze.py's camera metrics
		# and the sheet tools: the body centre's screen position in the
		# movie frame (the window is unstretched, project.godot, so the
		# frame is the window's size, one pixel per pixel, whatever size
		# the compositor gave it), the tick, the camera's centre in the
		# world (as shown: held to the world's edges), the drawn body's
		# base on the screen where the blob layer's grid seats it, that
		# base in the world, and 1 once the gecko is out and the camera
		# has let go of it.
		var half := get_viewport().get_visible_rect().size * 0.5
		var cam := _camera.get_screen_center_position()
		var screen := (gecko.pos - cam) * CAMERA_ZOOM + half
		var base := gecko.draw_pos()
		var body := (_cam_seat - cam) * CAMERA_ZOOM + half
		print("F%d %d %d %d %.2f %.2f %.1f %.1f %.2f %.2f %d" % [Engine.get_frames_drawn(), int(screen.x), int(screen.y), gecko._tick,
			cam.x, cam.y, body.x, body.y, base.x, base.y, 1 if _won else 0])
	var m := get_global_mouse_position()
	var over_panel := _panel.has_mouse(get_viewport().get_mouse_position()) or _wave_panel.has_mouse(get_viewport().get_mouse_position()) or _editing
	gecko.mouse_blocked = over_panel
	if over_panel or get_tree().paused:
		pass
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.is_key_pressed(KEY_CTRL):
		map.erase_circle(m, brush_r, true)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		map.fill_circle(m, brush_r)
	if not over_panel and Input.is_action_just_pressed("drop_boulder"):
		map.spawn_boulder(m, maxf(brush_r * 0.5, 4.0))
	if not over_panel and Input.is_action_just_pressed("drop_clay"):
		map.spawn_clay(m, maxf(brush_r * 0.5, 4.0))
	# N held pours: the heap tops itself up every frame as it flows away.
	if not over_panel and Input.is_action_pressed("drop_sand"):
		map.spawn_sand(m, maxf(brush_r * 0.5, 4.0))
	# The sound mockup (waves.gd): a chew wave at the cursor, the hum's
	# source moved to it or back to the exit.
	if not over_panel and Input.is_action_just_pressed("wave_chew"):
		waves.emit_at(m)
	if not over_panel and Input.is_action_just_pressed("wave_hum", true):
		waves.hum_at = m
		waves.hum_set = true
	if Input.is_action_just_pressed("wave_hum_exit", true):
		waves.hum_set = false
	if Input.is_action_just_pressed("regenerate"):
		if not _scene.is_empty() and _dirty and sim:
			# Edits not saved yet: the level in hand again, not the file.
			_rebuild_world()
			gecko.spawn(_spawn_at(), Vector2.UP)
			_cam_reset()
		elif not _scene.is_empty():
			_reset()
		else:
			seed_value += 1
			_scene = {}
			_scene_i = -1
			_panel.select_scene(-1)
			_panel.set_seed(seed_value)
			_reset()
	# Exact matches, so Tab with Shift held is only the one action.
	if Input.is_action_just_pressed("scene_next", true):
		_next_scene()
	if Input.is_action_just_pressed("scene_main", true):
		_main_cave()
	if Input.is_action_just_pressed("edit_toggle", true) and not _editor.dialog_open():
		_set_editing(not _editing)
	if Input.is_action_just_pressed("debug_toggle"):
		_set_debug(not _debug)
	if Input.is_action_just_pressed("pose_editor"):
		_open_pose_editor()
	if Input.is_action_just_pressed("render_coarse"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_COARSE)
		_panel.set_pixel_size(BlobLayer.PIXEL_SZ_COARSE)
	if Input.is_action_just_pressed("render_fine"):
		blobs.set_pixel_size(BlobLayer.PIXEL_SZ_FINE)
		_panel.set_pixel_size(BlobLayer.PIXEL_SZ_FINE)


func _unhandled_input(event: InputEvent) -> void:
	if _editing:
		return   # The editor's wheel zooms (editor.gd)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_r = minf(brush_r + 4.0, 80.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_r = maxf(brush_r - 4.0, 8.0)
		_panel.set_brush(brush_r)


func _print_timing() -> void:
	var line := "T"
	for pair in [["sim", _t_sim], ["gecko", _t_gecko], ["render", _t_render]]:
		var a: Array = pair[1]
		var total := 0
		var mx := 0
		for v in a:
			total += v
			mx = maxi(mx, v)
		var mean := float(total) / maxf(a.size(), 1.0) / 1000.0
		line += " %s %.2f/%.2f" % [pair[0], mean, mx / 1000.0]
		a.clear()
	line += " physics %.2f process %.2f fps %d" % [
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Engine.get_frames_per_second()]
	print(line)
	if sim and OS.get_environment("GECKO_HIST") != "":
		var hist := {}
		var c: PackedByteArray = sim.cells
		for i in range(0, c.size(), 4):
			var k := mini(c.decode_u32(i), 16)
			hist[k] = hist.get(k, 0) + 1
		print("H ", hist, " kinds in author ", _author_hist())


func _author_hist() -> Dictionary:
	var h := {}
	if _author == null:
		return h
	for v in _author.solid:
		h[v] = h.get(v, 0) + 1
	return h


# The lights as rings in their colours, the seed radius each, drawn
# while the editor is open (in the bitmap world nothing else shows
# them).
class LightMarks extends Node2D:
	var lights: Array = []
	var preview: Array = []   # The editor's light on the cursor, faint
	var boxes: Array = []     # The handles (main.gd edit_marks): [rect, 0 idle, 1 under the cursor, 2 taken]
	var offset := Vector2.ZERO   # The taken one's drag

	func _draw() -> void:
		for l in lights:
			_mark(l, 1.0)
		if not preview.is_empty():
			_mark(preview, 0.5)
		for b in boxes:
			var r: Rect2 = b[0]
			match int(b[1]):
				0:
					_corners(r, Color(0.94, 0.93, 0.9, 0.35))
				1:
					draw_rect(r, Color(0.94, 0.93, 0.9, 0.8), false, 1.0)
				2:
					draw_rect(r, Color(0.79, 0.70, 0.54, 0.25), true)
					draw_rect(r, Color(0.79, 0.70, 0.54), false, 1.0)
					if offset != Vector2.ZERO:
						draw_rect(Rect2(r.position + offset, r.size), Color(0.94, 0.93, 0.9, 0.9), false, 1.0)

	# A box's corners, so a dressed wall is not caged in lines.
	func _corners(r: Rect2, col: Color) -> void:
		var k := minf(4.0, minf(r.size.x, r.size.y) * 0.5)
		for c in [[r.position, 1.0, 1.0], [Vector2(r.end.x, r.position.y), -1.0, 1.0], [r.end, -1.0, -1.0], [Vector2(r.position.x, r.end.y), 1.0, -1.0]]:
			var p: Vector2 = c[0]
			draw_line(p, p + Vector2(k * c[1], 0.0), col, 1.0)
			draw_line(p, p + Vector2(0.0, k * c[2]), col, 1.0)

	# A point: a ring of its radius. A strip: the segment and a ring at
	# each end. A cone: the wedge from the source to the aim.
	func _mark(l: Array, alpha: float) -> void:
		var col: Color = l[1]
		col.a = alpha
		var a: Vector2 = l[0]
		var b: Vector2 = l[3] if l.size() > 3 else a
		var r: float = l[2]
		if r < 0.0:
			var d: Vector2 = (b - a).normalized()
			var n := Vector2(-d.y, d.x) * -r
			draw_line(a, b + n, col, 1.0)
			draw_line(a, b - n, col, 1.0)
			draw_line(b + n, b - n, col, 1.0)
			draw_circle(a, 2.0, col)
			return
		draw_arc(a, r, 0.0, TAU, 32, col, 1.0)
		draw_circle(a, 2.0, col)
		if b != a:
			draw_arc(b, r, 0.0, TAU, 32, col, 1.0)
			draw_line(a, b, col, 1.0)


# The editor's ghost (edit_ghost): the stamp picked drawn at half alpha
# where a click would set it, a dashed box round a decor stamp. Items:
# ["tex", texture, frame, w, h] a PNG stamp laid on the surface's frame
# (tests/scene_builder.gd frame: the base cell, the axis along the
# surface and the axis up off it), ["cell", rect, colour], ["poly",
# points, colour], ["line", a, b, colour, width], ["disc", at, r,
# colour], ["box", rect].
class EditGhost extends Node2D:
	var items: Array = []

	func _draw() -> void:
		var cell := CaveMap.CELL_FULL
		for it in items:
			match it[0]:
				"tex":
					var fr: Array = it[2]
					var along: Vector2i = fr[1]
					var up: Vector2i = fr[2]
					var w: int = it[3]
					var h: int = it[4]
					var bx := Vector2(along) * cell
					var by := -Vector2(up) * cell
					var first: Vector2i = fr[0] + along * (-(w / 2)) + up * h   # The cell of the image's first pixel
					var corner := Vector2(1.0 if (bx.x < 0.0 or by.x < 0.0) else 0.0, 1.0 if (bx.y < 0.0 or by.y < 0.0) else 0.0)
					draw_set_transform_matrix(Transform2D(bx, by, (Vector2(first) + corner) * cell))
					draw_texture_rect(it[1], Rect2(0.0, 0.0, w, h), false, Color(1.0, 1.0, 1.0, 0.55))
					draw_set_transform_matrix(Transform2D())
				"cell":
					var c: Color = it[2]
					c.a = 0.55
					draw_rect(it[1], c)
				"poly":
					var c: Color = it[2]
					c.a = 0.55
					draw_colored_polygon(it[1], c)
				"line":
					var c: Color = it[3]
					c.a = 0.55
					draw_line(it[1], it[2], c, it[4])
				"disc":
					var c: Color = it[3]
					c.a = 0.55
					draw_circle(it[1], it[2], c)
				"box":
					var r: Rect2 = it[1]
					var c := Color(0.94, 0.93, 0.9, 0.7)
					draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), c, 1.0, 3.0)
					draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, c, 1.0, 3.0)
					draw_dashed_line(r.end, Vector2(r.position.x, r.end.y), c, 1.0, 3.0)
					draw_dashed_line(Vector2(r.position.x, r.end.y), r.position, c, 1.0, 3.0)
