# The sound ripples' look (waves.gd), a column left of the debug panel,
# shown with it on F1: a slider for each of the look's numbers, the
# chew's and the hum's, their tints, and Save to keep them in
# waves.json. A tuning tool, so it sets the waves node straight rather
# than emitting like the debug panel.
extends PanelContainer

const Waves = preload("res://waves.gd")
const WIDTH := 290.0
const GAP := 8.0                 # Between it and the debug panel

var waves: Node2D
var _sliders: Array = [{}, {}]   # Per kind, name -> HSlider
var _tints: Array = []
var _snap: CheckButton
var _cave: CheckButton
var _cave_sliders := {}
var _status: Label


func setup(w: Node2D, right_of: float) -> void:
	waves = w
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_right = -right_of - GAP
	offset_left = offset_right - WIDTH
	offset_top = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 0.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	scroll.add_child(col)

	col.add_child(_heading("Sound waves"))
	var keys := _label("Q held: listen (the hum shows).  G: a chew wave at the mouse.  J: the hum from the mouse, Shift+J from the exit.")
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size = Vector2(WIDTH - 20.0, 0.0)
	col.add_child(keys)
	_cave = _check(col, "Follow the cave (off: straight circles)", waves.cave, func(on: bool) -> void: waves.cave = on)
	_snap = _check(col, "Snap shifts to rock cells", waves.snap, func(on: bool) -> void:
		waves.snap = on
		waves.apply_look())
	_check(col, "Bites make waves", waves.bites, func(on: bool) -> void: waves.bites = on)
	_check(col, "Hum without listening", waves.hum_always, func(on: bool) -> void: waves.hum_always = on)
	_check(col, "Heard lines", waves.show_marks, func(on: bool) -> void: waves.show_marks = on)
	for k in 2:
		col.add_child(HSeparator.new())
		col.add_child(_heading("Chew" if k == Waves.CHEW else "Hum"))
		for p in Waves.PARAMS:
			if p[0] == "period" and k == Waves.CHEW:
				continue
			_slider(col, k, p)
		var row := HBoxContainer.new()
		col.add_child(row)
		row.add_child(_name_label("tint"))
		var pick := ColorPickerButton.new()
		pick.color = waves.look[k].tint
		pick.edit_alpha = false
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(0.0, 20.0)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.color_changed.connect(func(c: Color) -> void:
			waves.look[k].tint = c
			waves.apply_look())
		row.add_child(pick)
		_tints.append(pick)
	col.add_child(HSeparator.new())
	col.add_child(_heading("Cave"))
	for p in Waves.CAVE_PARAMS:
		_slider_on(col, waves.cave_look, p, _cave_sliders)
	col.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	buttons.add_child(_button("Save look", func() -> void: _status.text = waves.save_look()))
	buttons.add_child(_button("Defaults", func() -> void:
		waves.reset_look()
		_refresh()
		_status.text = "defaults (not saved)"))
	_status = _label("")
	col.add_child(_status)
	# Tall enough for the lot, no taller than the screen.
	scroll.custom_minimum_size.y = minf(col.get_combined_minimum_size().y + 8.0, 1000.0)


func _slider(col: VBoxContainer, k: int, p: Array) -> void:
	_slider_on(col, waves.look[k], p, _sliders[k])


# A slider row for one number of a look dictionary.
func _slider_on(col: VBoxContainer, look: Dictionary, p: Array, into: Dictionary) -> void:
	var n: String = p[0]
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(_name_label(n))
	var s := HSlider.new()
	s.min_value = p[1]
	s.max_value = p[2]
	s.step = p[3]
	s.value = look[n]
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0.0, 20.0)
	row.add_child(s)
	var v := _label(_fmt(s.value))
	v.custom_minimum_size = Vector2(46.0, 0.0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		look[n] = x
		v.text = _fmt(x)
		waves.apply_look())
	into[n] = s


# The sliders back in step with the look (after Defaults).
func _refresh() -> void:
	for k in 2:
		for n in _sliders[k]:
			_sliders[k][n].value = waves.look[k][n]
		_tints[k].color = waves.look[k].tint
	for n in _cave_sliders:
		_cave_sliders[n].value = waves.cave_look[n]
	_snap.set_pressed_no_signal(waves.snap)
	_cave.set_pressed_no_signal(waves.cave)


func has_mouse(p: Vector2) -> bool:
	return visible and get_global_rect().has_point(p)


func _fmt(x: float) -> String:
	return "%.2f" % x if x < 10.0 else "%d" % int(x)


func _check(col: VBoxContainer, text: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(cb)
	col.add_child(c)
	return c


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


func _name_label(text: String) -> Label:
	var l := _label(text)
	l.custom_minimum_size = Vector2(72.0, 0.0)
	return l


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b
