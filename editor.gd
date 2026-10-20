# The in-game map editor (F2): a panel down the left, the world painted
# with the mouse. Paints are the cell kinds (air, rock, hard rock,
# bedrock, copper, sand, clay, water, lava, glowshroom, moss, crumbling
# rock, gas). Decor is the stamps drawn as PNGs in decor/stamps
# (tools/decor_split.py cuts them into pieces), shown as icons and laid
# by a brush: dragged along a surface it sets one wherever the next
# stands clear of every placed one by the spacing, picking among the
# stamp's group at random and mirroring at random when asked; set free,
# a click places one anywhere, overlapping or not. Stamps are the table
# glowshrooms, dripstone cones, a vine and a slug; the level tools set
# the spawn and the exit. Everything goes through main.gd, which paints
# the live world (the particle sim or the bitmap) and an authoring cell
# map alike, keeps every stroke for undo (Ctrl+Z, Ctrl+Y), and saves and
# loads levels/<name>.json with its cells (levels/<name>.cells.png).
# The wheel zooms about the cursor with no limit, the middle button
# pans, Home brings the camera back to the gecko; [ and ] size the brush.
extends CanvasLayer

const SceneBuilder = preload("res://tests/scene_builder.gd")
const WIDTH := 236.0
const PAINTS := [
	["Air", 0], ["Rock", 1], ["Hard rock", 7], ["Bedrock", 8], ["Copper", 3],
	["Sand", 4], ["Clay", 5], ["Water", 2], ["Lava", 6],
	["Glowshroom", 9], ["Moss", 10], ["Crumble", 11], ["Gas", 12],
]
const STAMPS := [
	["Shroom small", "shroom_s"], ["Shroom", "shroom_m"], ["Shroom cluster", "shroom_cluster"],
	["Stalactite", "stalactite"], ["Stalagmite", "stalagmite"], ["Vine", "vine"], ["Slug", "slug"],
]
const TOOLS := [["Spawn", "spawn"], ["Exit (drag)", "exit"]]
const ANCHORS := ["nearest", "floor", "ceiling"]
const BRUSH_MIN := 4.0
const BRUSH_MAX := 48.0
const ICON := 36               # The decor grid's icons, px square: a stamp at 2x when it fits, else at 1x, else shrunk

var _main: Node2D
var _panel: PanelContainer
var _title: Label
var _paints: ItemList
var _decor: ItemList
var _stamps: ItemList
var _tools: ItemList
var _files: ItemList
var _brush: HSlider
var _spacing: HSlider
var _random: CheckButton
var _mirror: CheckButton
var _free: CheckButton
var _anchor: OptionButton
var _undo_b: Button
var _redo_b: Button
var _name: LineEdit
var _status: Label
var _mode := "paint"           # paint | decor | stamp | tool
var _pick := 1                 # Kind, stamp index, or tool index
var _decor_name := ""          # The decor stamp picked
var _decor_names: Array = []   # Every PNG stamp, in the grid's order
var _groups := {}              # Group -> its stamps' names (SceneBuilder.stamp_group)
var _radius := 12.0
var _drag_from := Vector2.INF  # The exit rect's first corner while dragging
var _was_down := false
var _panning := false
var _confirm := ""             # The button pressed once while the level has unsaved strokes: pressed again, it goes ahead
var _rng := RandomNumberGenerator.new()   # The brush's picks, apart from the global RNG the suite seeds


func setup(main_node: Node2D) -> void:
	_main = main_node


func _ready() -> void:
	layer = 20
	visible = false
	_rng.randomize()
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 0.0
	_panel.offset_right = WIDTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	_title = _heading("Edit   (F2 leaves)")
	col.add_child(_title)
	col.add_child(_label("LMB paints, RMB erases, wheel zooms,\nMMB pans, Home resets, [ ] size the brush,\nCtrl+Z undo, Ctrl+Y redo"))
	col.add_child(_heading("Paints"))
	_paints = _list(PAINTS, func(i: int) -> void: _choose("paint", int(PAINTS[i][1])))
	_paints.select(1)
	col.add_child(_paints)
	col.add_child(_heading("Decor"))
	_decor = _decor_grid()
	col.add_child(_decor)
	_random = _check("Random in group", true)
	col.add_child(_random)
	_mirror = _check("Mirror at random", true)
	col.add_child(_mirror)
	_free = _check("Free: click places, overlaps", false)
	col.add_child(_free)
	var arow := HBoxContainer.new()
	col.add_child(arow)
	arow.add_child(_label("Anchor"))
	_anchor = OptionButton.new()
	for a in ANCHORS:
		_anchor.add_item(a)
	_anchor.focus_mode = Control.FOCUS_NONE
	arow.add_child(_anchor)
	col.add_child(_label("Spacing"))
	_spacing = HSlider.new()
	_spacing.min_value = 0.0
	_spacing.max_value = 64.0
	_spacing.step = 2.0
	_spacing.value = 8.0
	_spacing.focus_mode = Control.FOCUS_NONE
	col.add_child(_spacing)
	col.add_child(_heading("Stamps"))
	_stamps = _list(STAMPS, func(i: int) -> void: _choose("stamp", i))
	col.add_child(_stamps)
	col.add_child(_heading("Level"))
	_tools = _list(TOOLS, func(i: int) -> void: _choose("tool", i))
	col.add_child(_tools)
	col.add_child(_label("Brush"))
	_brush = HSlider.new()
	_brush.min_value = BRUSH_MIN
	_brush.max_value = BRUSH_MAX
	_brush.step = 2.0
	_brush.value = _radius
	_brush.focus_mode = Control.FOCUS_NONE
	_brush.value_changed.connect(func(v: float) -> void: _radius = v)
	col.add_child(_brush)
	var urow := HBoxContainer.new()
	col.add_child(urow)
	_undo_b = _button("Undo", func() -> void: _say(_main.edit_undo()))
	urow.add_child(_undo_b)
	_redo_b = _button("Redo", func() -> void: _say(_main.edit_redo()))
	urow.add_child(_redo_b)
	col.add_child(_heading("Files"))
	_files = ItemList.new()
	_files.auto_height = true
	_files.allow_search = false
	_files.focus_mode = Control.FOCUS_NONE
	_files.item_selected.connect(func(i: int) -> void:
		_name.text = _files.get_item_text(i)
		_confirm = "")
	col.add_child(_files)
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(_label("Name"))
	_name = LineEdit.new()
	_name.text = "edit"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	var row2 := HBoxContainer.new()
	col.add_child(row2)
	row2.add_child(_button("Load", _load))
	row2.add_child(_button("New", _new))
	row2.add_child(_button("Save", _save))
	row2.add_child(_button("Save as", _save_as))
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)


# The decor stamps as a grid of icons, a tooltip naming each.
func _decor_grid() -> ItemList:
	var l := ItemList.new()
	l.icon_mode = ItemList.ICON_MODE_TOP
	l.max_columns = 5
	l.same_column_width = true
	l.fixed_icon_size = Vector2i(ICON, ICON)
	l.fixed_column_width = 42
	l.auto_height = true
	l.allow_search = false
	l.focus_mode = Control.FOCUS_NONE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var stamps: Dictionary = SceneBuilder.png_stamps()
	_decor_names = stamps.keys()
	_decor_names.sort()
	for name in _decor_names:
		var group: String = SceneBuilder.stamp_group(name)
		if not _groups.has(group):
			_groups[group] = []
		_groups[group].append(name)
		var i := l.add_item("", _icon(stamps[name].img))
		l.set_item_tooltip(i, name)
	l.item_selected.connect(func(i: int) -> void:
		_choose("decor", i)
		_decor_name = _decor_names[i]
		_say(_decor_name))
	return l


static func _icon(img: Image) -> ImageTexture:
	var src := img.duplicate() as Image
	if src.get_width() * 2 <= ICON and src.get_height() * 2 <= ICON:
		src.resize(src.get_width() * 2, src.get_height() * 2, Image.INTERPOLATE_NEAREST)
	elif src.get_width() > ICON or src.get_height() > ICON:
		var f := minf(float(ICON) / src.get_width(), float(ICON) / src.get_height())
		src.resize(maxi(int(src.get_width() * f), 1), maxi(int(src.get_height() * f), 1), Image.INTERPOLATE_NEAREST)
	var out := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i((ICON - src.get_width()) / 2, (ICON - src.get_height()) / 2))
	return ImageTexture.create_from_image(out)


func _list(items: Array, on_pick: Callable) -> ItemList:
	var l := ItemList.new()
	for it in items:
		l.add_item(it[0])
	l.custom_minimum_size = Vector2(0.0, 27.0 * items.size() + 6.0)
	l.allow_search = false
	l.focus_mode = Control.FOCUS_NONE
	l.item_selected.connect(on_pick)
	return l


func _choose(mode: String, pick: int) -> void:
	_mode = mode
	_pick = pick
	var lists := {"paint": _paints, "decor": _decor, "stamp": _stamps, "tool": _tools}
	for m in lists:
		if m != mode:
			lists[m].deselect_all()


# The stamp the brush sets next: the one picked, or any of its group.
func _variant() -> String:
	if _random.button_pressed:
		var group: Array = _groups.get(SceneBuilder.stamp_group(_decor_name), [_decor_name])
		return group[_rng.randi_range(0, group.size() - 1)]
	return _decor_name


func _flags() -> String:
	return "h" if _mirror.button_pressed and _rng.randf() < 0.5 else ""


func has_mouse(p: Vector2) -> bool:
	return visible and _panel.get_global_rect().has_point(p)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _main == null:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_main.edit_zoom(_main.EDIT_ZOOM_STEP, event.position)
			_say(_main.edit_zoom_text())
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_main.edit_zoom(1.0 / _main.EDIT_ZOOM_STEP, event.position)
			_say(_main.edit_zoom_text())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		_main.edit_pan(event.relative)
		get_viewport().set_input_as_handled()


func _keys() -> void:
	if _name.has_focus():
		return
	if Input.is_action_just_pressed("edit_undo"):
		_say(_main.edit_undo())
	if Input.is_action_just_pressed("edit_redo"):
		_say(_main.edit_redo())
	if Input.is_action_just_pressed("edit_home"):
		_main.edit_home()
		_say(_main.edit_zoom_text())
	if Input.is_action_just_pressed("brush_up"):
		_brush.value = minf(_brush.value + 2.0, BRUSH_MAX)
	if Input.is_action_just_pressed("brush_down"):
		_brush.value = maxf(_brush.value - 2.0, BRUSH_MIN)


func _process(_dt: float) -> void:
	if not visible or _main == null:
		return
	_keys()
	var over := has_mouse(_main.get_viewport().get_mouse_position())
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not over
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not over
	var down := lmb or rmb
	var pressed := lmb and not _was_down
	if down and not _was_down:
		_main.edit_begin()
		if _name.has_focus():
			_name.release_focus()
	elif _was_down and not down:
		_main.edit_end()
		_refresh_title()
	_was_down = down
	if over:
		return
	var world: Vector2 = _main.get_global_mouse_position()
	if rmb:
		_main.edit_paint(world, _radius, 0)
		return
	match _mode:
		"paint":
			if lmb:
				_main.edit_paint(world, _radius, _pick)
		"decor":
			if lmb and _decor_name != "":
				var name := _variant()
				var anchor: String = ANCHORS[_anchor.selected]
				if _free.button_pressed:
					if pressed:
						_main.edit_stamp(name, world, _radius, anchor, _flags())
				elif _main.edit_can_place(name, world, anchor, _spacing.value):
					_main.edit_stamp(name, world, _radius, anchor, _flags())
		"stamp":
			if pressed:
				_main.edit_stamp(String(STAMPS[_pick][1]), world, _radius)
		"tool":
			var tool := String(TOOLS[_pick][1])
			if tool == "spawn" and pressed:
				_say(_main.edit_spawn(world))
			elif tool == "exit":
				if pressed:
					_drag_from = world
				elif not lmb and _drag_from != Vector2.INF:
					_say(_main.edit_exit(Rect2(_drag_from, Vector2.ZERO).expand(world).abs()))
					_drag_from = Vector2.INF


# --- Files ---

# On opening (main.gd F2) and after a save or load: the level list, the
# name, the title.
func refresh() -> void:
	_files.clear()
	var names: Array = _main.level_names()
	for n in names:
		_files.add_item(String(n))
	var current: String = _main.level_name()
	if current != "":
		_name.text = current
		var i: int = names.find(current)
		if i >= 0:
			_files.select(i)
	_refresh_title()


func _refresh_title() -> void:
	var current: String = _main.level_name()
	_title.text = "Edit   %s%s   (F2 leaves)" % [current if current != "" else "(unsaved)", "*" if _main.level_dirty() else ""]
	_undo_b.disabled = not _main.edit_can_undo()
	_redo_b.disabled = not _main.edit_can_redo()


# A level with strokes since its save is dropped only on a second press.
func _guard(what: String) -> bool:
	if _main.level_dirty() and _confirm != what:
		_confirm = what
		_say("unsaved strokes: press %s again to drop them" % what)
		return false
	_confirm = ""
	return true


func _load() -> void:
	var name := _name.text.strip_edges()
	if _files.is_anything_selected():
		name = _files.get_item_text(_files.get_selected_items()[0])
	if name == "" or not _guard("Load"):
		return
	_say(_main.load_level(name))
	refresh()


func _new() -> void:
	if not _guard("New"):
		return
	var name := _name.text.strip_edges()
	_say(_main.blank_level(name))
	refresh()


func _save() -> void:
	var name: String = _main.level_name()
	if name == "":
		name = _name.text.strip_edges()
	if name == "":
		_say("a name first")
		return
	_say(_main.save_level(name))
	refresh()


func _save_as() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		_say("a name first")
		return
	_say(_main.save_level(name))
	refresh()


func _say(text: String) -> void:
	_status.text = text
	_refresh_title()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


func _check(text: String, on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 12)
	return c


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b
