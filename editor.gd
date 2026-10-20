# The in-game map editor (F2): a panel of paints down the left, the
# world painted with the mouse. Paints are the cell kinds (air, rock,
# hard rock, bedrock, copper, sand, clay, water, lava, glowshroom,
# moss, crumbling rock, gas), stamps (the decor table's glowshrooms,
# dripstone cones, a vine, a slug), and the level's spawn and exit.
# Everything goes through main.gd, which paints the live world (the
# particle sim or the bitmap) and an authoring cell map alike, so Save
# writes the cells exactly (levels/<name>.cells.png) with a level file
# (levels/<name>.json) the game and the suite load like any other.
extends CanvasLayer

const WIDTH := 190.0
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
const BRUSH_MIN := 4.0
const BRUSH_MAX := 48.0

var _main: Node2D
var _panel: PanelContainer
var _paints: ItemList
var _stamps: ItemList
var _tools: ItemList
var _brush: HSlider
var _name: LineEdit
var _status: Label
var _mode := "paint"           # paint | stamp | tool
var _pick := 1                 # Kind, stamp index, or tool index
var _radius := 12.0
var _drag_from := Vector2.INF  # The exit rect's first corner while dragging
var _was_down := false


func setup(main_node: Node2D) -> void:
	_main = main_node


func _ready() -> void:
	layer = 20
	visible = false
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 0.0
	_panel.offset_right = WIDTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)
	col.add_child(_heading("Edit   (F2 leaves)"))
	col.add_child(_label("LMB paints, RMB erases, wheel sizes"))
	col.add_child(_heading("Paints"))
	_paints = _list(PAINTS, func(i: int) -> void: _choose("paint", int(PAINTS[i][1])))
	_paints.select(1)
	col.add_child(_paints)
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
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(_label("Name"))
	_name = LineEdit.new()
	_name.text = "edit"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	var row2 := HBoxContainer.new()
	col.add_child(row2)
	row2.add_child(_button("Save", func() -> void: _status.text = _main.save_level(_name.text)))
	row2.add_child(_button("Load", func() -> void: _status.text = _main.load_level(_name.text)))
	row2.add_child(_button("Blank", func() -> void: _status.text = _main.blank_level()))
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)


func _list(items: Array, on_pick: Callable) -> ItemList:
	var l := ItemList.new()
	for it in items:
		l.add_item(it[0])
	l.custom_minimum_size = Vector2(0.0, 22.0 * items.size() + 6.0)
	l.allow_search = false
	l.focus_mode = Control.FOCUS_NONE
	l.item_selected.connect(on_pick)
	return l


func _choose(mode: String, pick: int) -> void:
	_mode = mode
	_pick = pick
	for l in [_paints, _stamps, _tools]:
		if (l == _paints and mode != "paint") or (l == _stamps and mode != "stamp") or (l == _tools and mode != "tool"):
			l.deselect_all()


func has_mouse(p: Vector2) -> bool:
	return visible and _panel.get_global_rect().has_point(p)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_brush.value = minf(_brush.value + 2.0, BRUSH_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_brush.value = maxf(_brush.value - 2.0, BRUSH_MIN)


func _process(_dt: float) -> void:
	if not visible or _main == null:
		return
	if has_mouse(_main.get_viewport().get_mouse_position()):
		_was_down = false
		return
	var world: Vector2 = _main.get_global_mouse_position()
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var pressed := lmb and not _was_down
	_was_down = lmb
	if rmb:
		_main.edit_paint(world, _radius, 0)
		return
	match _mode:
		"paint":
			if lmb:
				_main.edit_paint(world, _radius, _pick)
		"stamp":
			if pressed:
				_main.edit_stamp(String(STAMPS[_pick][1]), world, _radius)
		"tool":
			var tool := String(TOOLS[_pick][1])
			if tool == "spawn" and pressed:
				_status.text = _main.edit_spawn(world)
			elif tool == "exit":
				if pressed:
					_drag_from = world
				elif not lmb and _drag_from != Vector2.INF:
					_status.text = _main.edit_exit(Rect2(_drag_from, Vector2.ZERO).expand(world).abs())
					_drag_from = Vector2.INF


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


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	return b
