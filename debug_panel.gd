# Debug panel: a column down the right of the screen, shown with F1,
# to drive the world by hand: the suite's scenes at the top, then the
# cave seed, the brush, the clock, and the gecko's pixel grid and
# overlay. main.gd owns the actions; the panel only emits.
class_name DebugPanel
extends PanelContainer

signal scene_picked(index: int)
signal main_cave
signal reload
signal regenerate(seed_value: int)
signal brush_changed(radius: float)
signal time_scale_changed(scale: float)
signal paused(on: bool)
signal step
signal pixel_size_changed(size: float)
signal sound_changed(on: bool)      # The master bus unmuted
signal sense_changed(cell: float)   # The senses' grid: 2 px (the sim's cells) or 4 px (folded), particle world only
signal crumb_changed(n: int)        # Crumbs of up to n cells are air to the senses and loosened by the body's touch; 0 for none
signal overlay_changed(on: bool)
signal light_changed(on: bool)
signal shading_changed(on: bool)   # The bodies' lit crescent and shade (metaball.gdshader)
signal shading_param_changed(param: String, v: float)   # One of its uniforms, from the Shading sliders
signal anim_requested(name: String)   # The gecko's animations: "curl" to sleep, "wake" up (main.gd play_anim: poses/wake.json, or the sprites in decor/gecko/wake)
signal pose_editor_requested          # The pose editor scene (pose_editor.gd, F3)

const WIDTH := 300.0

var _scenes: ItemList
var _seed: SpinBox
var _brush: HSlider
var _time: HSlider
var _pause: CheckButton
var _overlay: CheckButton
var _pixel: OptionButton
var _sense: OptionButton
var _sound: CheckButton
var _light: CheckButton
var _shading: CheckButton
var _shading_sliders := {}   # Uniform name: its slider
var _crumb: SpinBox
var _poses: OptionButton
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -WIDTH
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The column scrolls when it runs past the screen's foot (the
	# Shading sliders open).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(_heading("Scene   (Tab next, Shift+Tab cave)"))
	_scenes = ItemList.new()
	_scenes.custom_minimum_size = Vector2(0.0, 300.0)
	_scenes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Mouse only: the keys belong to the gecko. With focus, the list's
	# type-ahead search would jump to a scene on any letter (W, A, S, D).
	_scenes.allow_search = false
	_scenes.focus_mode = Control.FOCUS_NONE
	_scenes.item_selected.connect(func(i: int) -> void: scene_picked.emit(i))
	col.add_child(_scenes)
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(_button("Main cave", func() -> void: main_cave.emit()))
	row.add_child(_button("Reload", func() -> void: reload.emit()))
	var anim_row := HBoxContainer.new()
	col.add_child(anim_row)
	anim_row.add_child(_label("Anim"))
	anim_row.add_child(_button("Curl", func() -> void: anim_requested.emit("curl")))
	anim_row.add_child(_button("Wake", func() -> void: anim_requested.emit("wake")))
	anim_row.add_child(_button("Poses (F3)", func() -> void: pose_editor_requested.emit()))
	var pose_row := HBoxContainer.new()
	col.add_child(pose_row)
	pose_row.add_child(_label("Pose file"))
	_poses = OptionButton.new()
	_poses.focus_mode = Control.FOCUS_NONE
	_poses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pose_row.add_child(_poses)
	pose_row.add_child(_button("Play", func() -> void:
		if _poses.selected >= 0:
			anim_requested.emit(_poses.get_item_text(_poses.selected))))

	col.add_child(HSeparator.new())
	col.add_child(_heading("World"))
	var seed_row := HBoxContainer.new()
	col.add_child(seed_row)
	seed_row.add_child(_label("Seed"))
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 9999
	_seed.value = 7
	seed_row.add_child(_seed)
	seed_row.add_child(_button("New cave", func() -> void: regenerate.emit(int(_seed.value))))
	col.add_child(_label("Brush radius   (Ctrl+RMB erase, MMB fill)"))
	_brush = HSlider.new()
	_brush.min_value = 8.0
	_brush.max_value = 80.0
	_brush.step = 4.0
	_brush.value = 24.0
	_brush.focus_mode = Control.FOCUS_NONE
	_brush.value_changed.connect(func(v: float) -> void: brush_changed.emit(v))
	col.add_child(_brush)
	col.add_child(_label("Time scale"))
	_time = HSlider.new()
	_time.min_value = 0.1
	_time.max_value = 2.0
	_time.step = 0.1
	_time.value = 1.0
	_time.focus_mode = Control.FOCUS_NONE
	_time.value_changed.connect(func(v: float) -> void: time_scale_changed.emit(v))
	col.add_child(_time)
	var clock := HBoxContainer.new()
	col.add_child(clock)
	_pause = CheckButton.new()
	_pause.text = "Pause"
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.toggled.connect(func(on: bool) -> void: paused.emit(on))
	clock.add_child(_pause)
	clock.add_child(_button("Step one tick", func() -> void: step.emit()))
	_sound = CheckButton.new()
	_sound.text = "Sound"
	_sound.focus_mode = Control.FOCUS_NONE
	_sound.toggled.connect(func(on: bool) -> void: sound_changed.emit(on))
	col.add_child(_sound)

	col.add_child(HSeparator.new())
	col.add_child(_heading("Gecko"))
	var px_row := HBoxContainer.new()
	col.add_child(px_row)
	px_row.add_child(_label("Pixel grid"))
	_pixel = OptionButton.new()
	_pixel.add_item("1 px", 1)
	_pixel.add_item("2 px", 2)
	_pixel.focus_mode = Control.FOCUS_NONE
	_pixel.item_selected.connect(func(i: int) -> void: pixel_size_changed.emit(float(_pixel.get_item_id(i))))
	px_row.add_child(_pixel)
	var sense_row := HBoxContainer.new()
	col.add_child(sense_row)
	sense_row.add_child(_label("Senses"))
	_sense = OptionButton.new()
	_sense.add_item("2 px", 2)
	_sense.add_item("4 px", 4)
	_sense.focus_mode = Control.FOCUS_NONE
	_sense.item_selected.connect(func(i: int) -> void: sense_changed.emit(float(_sense.get_item_id(i))))
	sense_row.add_child(_sense)
	var crumb_row := HBoxContainer.new()
	col.add_child(crumb_row)
	crumb_row.add_child(_label("Crumbs pushed, up to (cells)"))
	_crumb = SpinBox.new()
	_crumb.min_value = 0
	_crumb.max_value = 25
	_crumb.value = 4
	_crumb.focus_mode = Control.FOCUS_NONE
	_crumb.value_changed.connect(func(v: float) -> void: crumb_changed.emit(int(v)))
	crumb_row.add_child(_crumb)
	_overlay = CheckButton.new()
	_overlay.text = "Overlay (up, probe, feet, bite)"
	_overlay.button_pressed = true
	_overlay.focus_mode = Control.FOCUS_NONE
	_overlay.toggled.connect(func(on: bool) -> void: overlay_changed.emit(on))
	col.add_child(_overlay)
	_light = CheckButton.new()
	_light.text = "Light (off: the whole cave lit)"
	_light.button_pressed = OS.get_environment("GECKO_LIGHT") == "1"   # Off by default, as sim.gd light_on
	_light.focus_mode = Control.FOCUS_NONE
	_light.toggled.connect(func(on: bool) -> void: light_changed.emit(on))
	col.add_child(_light)
	_shading = CheckButton.new()
	_shading.text = "Body shading (lit crescent, shade)"
	_shading.button_pressed = OS.get_environment("GECKO_SHADE") == "1"
	_shading.focus_mode = Control.FOCUS_NONE
	_shading.toggled.connect(func(on: bool) -> void: shading_changed.emit(on))
	col.add_child(_shading)
	_add_shading(col)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	col.add_child(_status)


func set_scenes(names: Array) -> void:
	_scenes.clear()
	for n in names:
		_scenes.add_item(String(n))


func select_scene(i: int) -> void:
	if i < 0:
		_scenes.deselect_all()
		return
	_scenes.select(i)
	_scenes.ensure_current_is_visible()


# The pose files in poses/ for the Pose row (main.gd play_anim plays one by name).
func set_poses(names: Array) -> void:
	_poses.clear()
	for n in names:
		_poses.add_item(String(n))


func set_seed(v: int) -> void:
	_seed.set_value_no_signal(v)


func set_brush(v: float) -> void:
	_brush.set_value_no_signal(v)


func set_overlay(on: bool) -> void:
	_overlay.set_pressed_no_signal(on)


func overlay_on() -> bool:
	return _overlay.button_pressed


func set_paused(on: bool) -> void:
	_pause.set_pressed_no_signal(on)


func set_pixel_size(v: float) -> void:
	_pixel.select(_pixel.get_item_index(int(v)))


func set_light(on: bool) -> void:
	_light.set_pressed_no_signal(on)


func set_sound(on: bool) -> void:
	_sound.set_pressed_no_signal(on)


func set_sense(v: float) -> void:
	_sense.select(_sense.get_item_index(int(v)))


func set_crumb(n: int) -> void:
	_crumb.set_value_no_signal(n)


# The Shading sliders: [uniform, label, min, max, step, default], the
# defaults as metaball.gdshader's (light_angle 217: up and to the left).
const SHADING := [
	["light_angle", "Light angle", 0.0, 360.0, 1.0, 217.0],
	["lit_mix", "Lit strength", 0.0, 1.0, 0.05, 0.5],
	["lit_width", "Lit width", 0.0, 6.0, 0.5, 2.0],
	["lit_from", "Lit wrap (low: wider)", -0.5, 0.95, 0.05, 0.3],
	["gleam_mix", "Gleam", 0.0, 1.0, 0.05, 0.35],
	["gleam_from", "Gleam wrap", 0.5, 1.0, 0.01, 0.85],
	["shade_darken", "Shade strength", 0.0, 0.8, 0.02, 0.22],
	["shade_width", "Shade width", 0.0, 6.0, 0.5, 3.0],
	["shade_from", "Shade wrap (low: wider)", -0.5, 0.95, 0.05, 0.2],
	["core_darken", "Core darken", 0.0, 0.6, 0.02, 0.0],
	["core_depth", "Core depth", 2.0, 8.0, 0.5, 5.0],
	["smoothness", "Bands to smooth", 0.0, 1.0, 0.05, 0.0],
	["rim_darken", "Outline darken", 0.0, 1.0, 0.05, 0.5],
	["core_lighten", "Core lift", 0.0, 0.4, 0.02, 0.12],
]


# A fold under the Body shading switch: a slider a row for each of
# SHADING, Print (the values to the log, to bake in) and Reset.
func _add_shading(col: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var fold := _button("Shading settings", func() -> void: pass)
	fold.toggle_mode = true
	fold.button_pressed = true
	fold.toggled.connect(func(on: bool) -> void: box.visible = on)
	var row := HBoxContainer.new()
	row.add_child(fold)
	row.add_child(_button("Print", func() -> void:
		var parts: Array[String] = []
		for s in SHADING:
			parts.append("%s=%s" % [s[0], _shading_sliders[s[0]].value])
		print("shading: ", " ".join(parts))))
	row.add_child(_button("Reset", func() -> void:
		for s in SHADING:
			_shading_sliders[s[0]].value = s[5]))
	col.add_child(row)
	col.add_child(box)
	for s in SHADING:
		var r := HBoxContainer.new()
		var name_l := _label(s[1])
		name_l.custom_minimum_size = Vector2(130.0, 0.0)
		r.add_child(name_l)
		var sl := HSlider.new()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = s[4]
		sl.value = s[5]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		var val_l := _label(str(s[5]))
		val_l.custom_minimum_size = Vector2(36.0, 0.0)
		var param: String = s[0]
		sl.value_changed.connect(func(v: float) -> void:
			val_l.text = str(v)
			shading_param_changed.emit(param, v))
		r.add_child(sl)
		r.add_child(val_l)
		box.add_child(r)
		_shading_sliders[param] = sl


func set_status(text: String) -> void:
	_status.text = text


# Whether a screen point is over the panel: the world's own mouse
# handling (brush, tongue, chew) stays out of it.
func has_mouse(p: Vector2) -> bool:
	return visible and get_global_rect().has_point(p)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b
