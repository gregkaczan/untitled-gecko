# The in-game map editor (Tab or F2): a panel down the left, the world painted
# with the mouse. Paints are the cell kinds (air, rock, hard rock,
# bedrock, copper, sand, clay, water, lava, glowshroom, moss, crumbling
# rock, gas, thorn), each a box in its colour. Decor is the stamps drawn
# as PNGs in decor/stamps (tools/decor_split.py cuts them into pieces),
# one icon a group, laid by the brush (decor_brush.gd): dragged along a
# surface it lays a run of the group edge to edge, the variants picked
# by its rules, mirrored at random when asked; the wheel picks a variant
# to pin the brush to ("any" hands the pick back to the rules). Set
# free, a click places the variant anywhere. The stamps under them are
# the procedural ones: dripstone cones, a vine, a thorn bush and a slug,
# sized 1 to 5 with the up and down arrows, the wheel picking a cone's
# shape. Whatever is picked rides the cursor as a ghost, drawn where a
# click would set it (main.gd edit_ghost), with a tag naming it. Lights
# are glow sources in five colours and three shapes: a point, a cone
# dragged from its source to its aim, a strip dragged along a surface.
# The light picked is seeded at the cursor before the click, so the
# world shows it, the wheel sizing its radius and Shift+wheel its
# strength; the right button takes a light away; a check turns the
# light pass off, the whole cave lit flat. Select (the Tools card, V
# or Esc: nothing picked) is the hand: every stamp, cone, run, critter, lump, slug and
# light placed shows a box, a drag moves it, the wheel, the arrows and H
# change it, Del or the right button takes it away. Everything goes
# through main.gd, which keeps the paints as terrain on an authoring
# cell map and the rest as entries baked on it into the live world (the
# particle sim or the bitmap), makes that world again from the level
# when the editor opens and, after edits, when it closes, keeps every
# stroke for undo (Ctrl+Z, Ctrl+Y), autosaves versions of the level and
# loads them.
# Ctrl+wheel zooms about the cursor with no limit, the middle button
# pans, Home brings the camera back to the gecko, [ and ] size the
# brush, Esc drops the pick, ? shows the cheat sheet of all of it. New
# and Load open dialogs: a name for a new level; the levels and their
# versions to load from.
extends CanvasLayer

const SceneBuilder = preload("res://tests/scene_builder.gd")
const CaveMap = preload("res://cave_map.gd")
const Critters = preload("res://critters.gd")
const WIDTH := 300.0           # The panel's least width; it grows to its text
const PAINTS := [
	["Air", 0], ["Rock", 1], ["Hard", 7], ["Bedrock", 8],
	["Copper", 3], ["Sand", 4], ["Clay", 5], ["Water", 2],
	["Lava", 6], ["Shroom", 9], ["Moss", 10], ["Crumble", 11],
	["Gas", 12], ["Thorn", 13],
]
const STAMPS := [["Stalactite", "stalactite"], ["Stalagmite", "stalagmite"], ["Vine", "vine"], ["Thorn", "thorn"], ["Slug", "slug"],
	["Shroom", "shroom"], ["Slime", "slime"], ["Long slug", "longslug"], ["Worm", "worm"], ["Jellyfish", "jelly"]]
const STAMP_SIZES := {"stalactite": 5, "stalagmite": 5, "vine": 5, "thorn": 2, "slug": 1, "shroom": 5, "slime": 5, "longslug": 5, "worm": 5, "jelly": 1}
const STAMP_VARIANTS := {"stalactite": 4, "stalagmite": 4, "shroom": 2}
const SHAPES := [["Point", "point"], ["Cone", "cone"], ["Strip", "strip"]]
const ANCHORS := ["nearest", "floor", "ceiling", "wall_left", "wall_right"]
const BRUSH_MIN := 4.0
const BRUSH_MAX := 48.0
const RADIUS_MIN := 4.0
const RADIUS_MAX := 64.0
const STRENGTH_MIN := 0.2
const STRENGTH_MAX := 2.0
const ICON := 36               # The icon grids' icons, px square: a stamp at 2x when it fits, else at 1x, else shrunk
const TOAST_S := 4.0           # Seconds a status line shows
const PANEL_BG := Color("15161a")
const CARD_BG := Color("1d1e24")
const BOX_BG := Color("22232b")
const EDGE := Color("3a3b45")
const INK := Color("d8d6cf")
const DIM := Color("9a978f")
const BRIGHT := Color("f0eee6")
const ACCENT := Color("c9b28a")
const DARK := Color("15161a")

const CHEAT := [
	["Everywhere", [
		["Ctrl+wheel", "zoom about the cursor"],
		["MMB drag", "pan; Home: back to the gecko"],
		["Ctrl+Z, Ctrl+Y", "undo, redo"],
		["Esc", "let go of the item; drop the pick; close a dialog"],
		["?", "this sheet; Tab or F2 leaves the editor"],
		["Tab", "in: the world as the level has it; out: baked, play on"]]],
	["Select (V, Esc, or Tools)", [
		["hover", "an item's box and what it is"],
		["LMB drag", "moves it; it finds its surface where it lands"],
		["wheel", "next variant; a run: another pick of its rules"],
		["up, down", "size: cones, vines, critters, lumps, thorns"],
		["H", "mirror a stamp; a run's random mirroring"],
		["Del, RMB", "takes it away"]]],
	["Paints", [
		["LMB, RMB", "paint the kind, erase to air"],
		["wheel, [ ]", "brush radius 4 to 48 px"]]],
	["Decor", [
		["pick", "a ghost rides the cursor on the surface the anchor finds"],
		["wheel", "next variant, pinning the brush; any is first"],
		["LMB click, drag", "lays it; a drag lays a run along the surface"],
		["RMB", "takes away the stamp or run under it"],
		["Free", "each click places the variant anywhere"]]],
	["Stamps", [
		["up, down", "size 1 to 5: a cone's height, a vine's length, the bush"],
		["wheel", "a cone's shape, 4 of them"],
		["LMB click", "sets it where the ghost stands"],
		["RMB", "takes away what is under it"]]],
	["Lights", [
		["pick", "the light is live on the cursor"],
		["wheel", "radius 4 to 64; Shift+wheel strength 0.2 to 2.0"],
		["Point", "click sets it"],
		["Cone", "press at the source, drag to the aim, release"],
		["Strip", "press, drag along the surface, release"],
		["RMB", "takes the nearest light away"],
		["Lighting", "off: the whole cave lit flat, every stamp in view"]]],
	["Bands (palettes)", [
		["P, Shift+P", "the band under the cursor: next palette, the one before"],
		["K", "a new band from the cursor's height down"],
		["Shift+K", "the band border nearest the cursor removed"]]],
	["Files", [
		["Save", "a saved version and the head the game loads"],
		["autosave", "a version a minute while there are strokes, the last 10 kept"],
		["New, Load", "a name; the levels and their versions"]]],
]

var _main: Node2D
var _panel: PanelContainer
var _name_label: Label
var _hint: Label
var _paint_group := ButtonGroup.new()
var _light_group := ButtonGroup.new()
var _shape_group := ButtonGroup.new()
var _select_b: Button          # The Tools card's Select: the hand, nothing picked
var _paint_buttons: Array = []
var _light_buttons: Array = []
var _shape_buttons: Array = []
var _lighting: CheckButton
var _decor: ItemList
var _variants: ItemList
var _stamps: ItemList
var _size_label: Label
var _brush: HSlider
var _brush_label: Label
var _spacing: HSlider
var _spacing_label: Label
var _mirror: CheckButton
var _free: CheckButton
var _anchor: OptionButton
var _undo_b: Button
var _redo_b: Button
var _card_right := {}          # Card title -> the label at its right
var _file_name: Label
var _toast: Label
var _toast_t := 0.0
var _tag: Label
var _file_t := 0.0
var _dim: ColorRect
var _new_box: PanelContainer
var _new_name: LineEdit
var _new_info: Label
var _load_box: PanelContainer
var _load_levels: ItemList
var _load_versions: ItemList
var _load_vlabel: Label
var _load_note: Label
var _load_b: Button
var _load_entries: Array = []
var _load_vdata: Array = []
var _cheat_box: PanelContainer
var _mode := "none"            # none | paint | decor | stamp | light
var _pick := -1                # Kind, stamp index or light index
var _group := ""               # The decor group picked
var _group_names: Array = []   # Every group, in the grid's order
var _groups := {}              # Group -> its stamps' names, sorted (SceneBuilder.stamp_group)
var _variant_names: Array = [] # The picked group's stamps in the variants grid's order, "" first for any
var _pin := ""                 # The variant the brush is pinned to, or "" for its rules' pick
var _stamp_size := 3
var _stamp_var := 0
var _lights_items: Array = []  # The light kinds, [label, kind, colour]
var _shape := "point"
var _radius := 12.0            # The brush
var _lradius := 16.0           # A light's radius
var _strength := 1.0
var _drag_from := Vector2.INF  # A cone's source or a strip's start while dragging
var _hover := {}               # The item under the cursor with nothing picked (main.gd edit_item_at)
var _sel := {}                 # The item taken: what the wheel, the arrows, H and Delete change
var _grab := Vector2.INF       # Where the taken item was pressed, while it is dragged
var _was_down := false
var _was_rmb := false
var _panning := false
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
	_panel.add_theme_stylebox_override("panel", _flat(PANEL_BG, EDGE, 0, 0))
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	scroll.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# The header: the title, the level's name, undo and redo.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_label("Edit", 15, BRIGHT))
	_name_label = _label("", 13, ACCENT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_undo_b = _button("Undo", func() -> void: say(_main.edit_undo()))
	head.add_child(_undo_b)
	_redo_b = _button("Redo", func() -> void: say(_main.edit_redo()))
	head.add_child(_redo_b)
	_hint = _label("Tab leaves · ? keys · V or Esc: Select · Ctrl+wheel zoom · MMB pan", 11, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_hint)

	# Tools: Select, the hand on what is placed (V or Esc).
	var tools := _card(col, "Tools", "V")
	_select_b = _swatch("Select", BOX_BG, func() -> void: _choose("none", -1))
	_select_b.button_pressed = true
	tools.add_child(_select_b)
	var thint := _label("click takes · drag moves · wheel variant · up, down size · H mirror · Del or RMB removes", 11, DIM)
	thint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tools.add_child(thint)

	# Paints: a box a kind, and the brush.
	var paints := _card(col, "Paints")
	var pgrid := GridContainer.new()
	pgrid.columns = 4
	pgrid.add_theme_constant_override("h_separation", 4)
	pgrid.add_theme_constant_override("v_separation", 4)
	paints.add_child(pgrid)
	for i in PAINTS.size():
		var kind: int = PAINTS[i][1]
		var b := _swatch(PAINTS[i][0], _paint_colour(kind), func() -> void: _choose("paint", kind))
		b.button_group = _paint_group
		pgrid.add_child(b)
		_paint_buttons.append(b)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	paints.add_child(brow)
	brow.add_child(_label("Brush", 11, DIM))
	_brush = _slider(BRUSH_MIN, BRUSH_MAX, 2.0, _radius)
	_brush.value_changed.connect(func(v: float) -> void:
		_radius = v
		_brush_label.text = "%d px" % int(v))
	brow.add_child(_brush)
	_brush_label = _label("%d px" % int(_radius), 11, INK)
	brow.add_child(_brush_label)

	# Decor: the groups, the variants, the stamps, the brush's settings.
	var decor := _card(col, "Decor", "ghost under the cursor")
	_decor = _decor_grid()
	decor.add_child(_decor)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 4)
	decor.add_child(vrow)
	var vl := _label("Variant", 11, DIM)
	vl.custom_minimum_size = Vector2(52.0, 0.0)
	vrow.add_child(vl)
	_variants = _grid(6, 40)
	_variants.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variants.item_selected.connect(func(i: int) -> void:
		_pin = _variant_names[i]
		say("variant: " + (_pin if _pin != "" else "any")))
	vrow.add_child(_variants)
	var srow := HBoxContainer.new()
	decor.add_child(srow)
	var sl := _label("Stamps", 11, DIM)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sl)
	_size_label = _label("", 11, DIM)
	srow.add_child(_size_label)
	_stamps = _grid(5, 44)
	for st in STAMPS:
		var i := _stamps.add_item("", _stamp_icon(String(st[1])))
		_stamps.set_item_tooltip(i, String(st[0]))
	_stamps.item_selected.connect(func(i: int) -> void:
		_choose("stamp", i)
		var n: int = STAMP_SIZES.get(String(STAMPS[i][1]), 1)
		_stamp_size = clampi(_stamp_size, 1, n)
		_stamp_var = 0
		_refresh_size())
	decor.add_child(_stamps)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 10)
	decor.add_child(orow)
	_mirror = _check("Mirror", true)
	orow.add_child(_mirror)
	_free = _check("Free", false)
	orow.add_child(_free)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orow.add_child(spacer)
	orow.add_child(_label("Anchor", 11, DIM))
	_anchor = OptionButton.new()
	for a in ANCHORS:
		_anchor.add_item(a)
	_anchor.focus_mode = Control.FOCUS_NONE
	_anchor.add_theme_font_size_override("font_size", 11)
	orow.add_child(_anchor)
	var sprow := HBoxContainer.new()
	sprow.add_theme_constant_override("separation", 8)
	decor.add_child(sprow)
	sprow.add_child(_label("Spacing", 11, DIM))
	_spacing = _slider(0.0, 64.0, 2.0, 8.0)
	_spacing.value_changed.connect(func(v: float) -> void: _spacing_label.text = "%d px" % int(v))
	sprow.add_child(_spacing)
	_spacing_label = _label("8 px", 11, INK)
	sprow.add_child(_spacing_label)

	# Lights: a box a colour, the three shapes, the dials.
	var lights := _card(col, "Lights", "")
	var lgrid := GridContainer.new()
	lgrid.columns = 5
	lgrid.add_theme_constant_override("h_separation", 4)
	lights.add_child(lgrid)
	for k in SceneBuilder.LIGHTS:
		var i := _lights_items.size()
		_lights_items.append([String(k).capitalize(), k, SceneBuilder.LIGHTS[k][0]])
		var b := _swatch(String(k).capitalize(), SceneBuilder.LIGHTS[k][0], func() -> void: _choose("light", i))
		b.button_group = _light_group
		lgrid.add_child(b)
		_light_buttons.append(b)
	var shrow := HBoxContainer.new()
	shrow.add_theme_constant_override("separation", 4)
	lights.add_child(shrow)
	for sh in SHAPES:
		var shape := String(sh[1])
		var b := _swatch(String(sh[0]), BOX_BG, func() -> void:
			_shape = shape
			_drag_from = Vector2.INF
			if _mode != "light" and _pick >= 0 and _pick < _lights_items.size() and _light_group.get_pressed_button() != null:
				_choose("light", _pick))
		b.button_group = _shape_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shrow.add_child(b)
		_shape_buttons.append(b)
	_shape_buttons[0].set_pressed_no_signal(true)
	var lhint := _label("wheel radius · Shift+wheel strength · RMB removes", 11, DIM)
	lhint.autowrap_mode = TextServer.AUTOWRAP_WORD
	lights.add_child(lhint)
	# The light pass itself: off, the whole cave is lit flat, so every
	# stamp and paint shows while dressing a dark corner.
	_lighting = _check("Lighting (off: all lit)", _main.light_on())
	_lighting.disabled = _main.sim == null
	_lighting.toggled.connect(func(on: bool) -> void:
		_main.set_light(on)
		say("lighting " + ("on" if on else "off: the whole cave lit")))
	lights.add_child(_lighting)
	_refresh_light_readout()

	# The file: the level's name and version, New, Load, Save.
	var file := _card(col, "File", "")
	_file_name = _label("", 13, BRIGHT)
	file.add_child(_file_name)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	file.add_child(frow)
	for pair in [["New", _open_new], ["Load", _open_load], ["Save", _save]]:
		var b := _button(String(pair[0]), pair[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if pair[0] == "Save":
			b.add_theme_stylebox_override("normal", _flat(ACCENT, ACCENT, 1))
			b.add_theme_stylebox_override("hover", _flat(ACCENT.lightened(0.1), ACCENT, 1))
			b.add_theme_stylebox_override("pressed", _flat(ACCENT.darkened(0.1), ACCENT, 1))
			b.add_theme_color_override("font_color", DARK)
			b.add_theme_color_override("font_hover_color", DARK)
			b.add_theme_color_override("font_pressed_color", DARK)
		frow.add_child(b)

	# The toast and the ghost's tag, over the world.
	_toast = _label("", 12, INK)
	_toast.position = Vector2(WIDTH + 16.0, 40.0)
	_toast.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.09, 0.1, 0.92), EDGE, 1, 4, 10, 6))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	_tag = _label("", 11, INK)
	_tag.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.09, 0.1, 0.92), EDGE, 1, 4, 8, 6))
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	add_child(_tag)

	_build_dialogs()
	_build_cheat()


# --- Building the panel ---

# A section: a card with its title at the left and a note at the right.
func _card(col: VBoxContainer, title: String, right := "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _flat(CARD_BG, CARD_BG, 0, 6))
	col.add_child(pc)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 12)
	pc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	var t := _label(title.to_upper(), 11, DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var r := _label(right, 11, DIM)
	row.add_child(r)
	_card_right[title] = r
	return v


static func _flat(bg: Color, edge: Color, edge_w: int, radius := 4, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(edge_w)
	s.set_corner_radius_all(radius)
	if pad_x > 0 or pad_y > 0:
		s.content_margin_left = pad_x
		s.content_margin_right = pad_x
		s.content_margin_top = pad_y
		s.content_margin_bottom = pad_y
	return s


# A palette box: a toggle in its colour with the name inside, a white
# edge when picked.
func _swatch(text: String, bg: Color, on_pick: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 30.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	var ink := DARK if bg.get_luminance() > 0.4 else BRIGHT
	for n in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(n, ink)
	var edge := EDGE if bg.get_luminance() > 0.03 else Color("5a5b66")
	b.add_theme_stylebox_override("normal", _flat(bg, edge, 1))
	b.add_theme_stylebox_override("hover", _flat(bg, Color("8a8b95"), 1))
	b.add_theme_stylebox_override("pressed", _flat(bg, BRIGHT, 2))
	b.add_theme_stylebox_override("hover_pressed", _flat(bg, BRIGHT, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_pick)
	return b


static func _paint_colour(kind: int) -> Color:
	match kind:
		0: return CaveMap.CAVE
		1: return CaveMap.ROCK
		2: return CaveMap.WATER
		3: return CaveMap.COPPER
		4: return CaveMap.SAND
		5: return CaveMap.CLAY
		6: return CaveMap.LAVA
		7: return CaveMap.HARD
		8: return CaveMap.BEDROCK
		9: return CaveMap.SHROOM
		10: return CaveMap.MOSS
		11: return CaveMap.CRUMBLE
		12: return CaveMap.GAS
		13: return CaveMap.THORN
	return CaveMap.ROCK


# The decor groups as a grid of icons (a group's first whole take), a
# tooltip naming each.
func _decor_grid() -> ItemList:
	var l := _grid(4, 56)
	var stamps: Dictionary = SceneBuilder.png_stamps()
	var names: Array = stamps.keys()
	names.sort()
	for name in names:
		var group: String = SceneBuilder.stamp_group(name)
		if not _groups.has(group):
			_groups[group] = []
			_group_names.append(group)
		_groups[group].append(name)
	for group in _group_names:
		var i := l.add_item("", _icon(stamps[_face(group)].img))
		l.set_item_tooltip(i, group)
	l.item_selected.connect(func(i: int) -> void:
		_choose("decor", i)
		_group = _group_names[i]
		_pin = ""
		_fill_variants()
		say(_group + ": " + str(_groups[_group].size()) + " variants, the wheel picks one"))
	return l


# A group's face: its first whole take.
func _face(group: String) -> String:
	for n in _groups.get(group, []):
		if SceneBuilder.stamp_role(n) == "":
			return n
	var all: Array = _groups.get(group, [])
	return all[0] if not all.is_empty() else ""


# The picked group's variants beside the grid: "any" first, then every
# take and piece, the tooltip naming each.
func _fill_variants() -> void:
	_variants.clear()
	_variant_names = [""]
	_variants.add_item("any")
	_variants.set_item_tooltip(0, "any: the brush's rules pick")
	var stamps: Dictionary = SceneBuilder.png_stamps()
	for n in _groups.get(_group, []):
		_variant_names.append(n)
		var i := _variants.add_item("", _icon(stamps[n].img))
		_variants.set_item_tooltip(i, n)
	_variants.select(0)


func _grid(columns: int, column_w: int) -> ItemList:
	var l := ItemList.new()
	l.icon_mode = ItemList.ICON_MODE_TOP
	l.max_columns = columns
	l.same_column_width = true
	l.fixed_icon_size = Vector2i(ICON, ICON)
	l.fixed_column_width = column_w
	l.auto_height = true
	l.allow_search = false
	l.focus_mode = Control.FOCUS_NONE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.04, 0.06), EDGE, 1))
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


# The procedural stamps' icons, drawn as pixels: a cone down, a cone
# up, a vine with leaves, a thorn bush, a slug, a shroom that bends, a
# slime, a long slug.
static func _stamp_icon(name: String) -> ImageTexture:
	var img := Image.create(ICON, ICON, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rock := CaveMap.RIM
	var leaf := Color(0.45, 0.64, 0.29)
	var stem := Color(0.33, 0.48, 0.2)
	match name:
		"stalactite", "stalagmite":
			var down := name == "stalactite"
			for r in 30:
				var t := float(r) / 29.0
				var w := maxi(int(round(14.0 * pow(1.0 - t, 0.75))), 1)
				var y := 3 + r if down else ICON - 4 - r
				for x in range(18 - (w + 1) / 2, 18 + w / 2 + 1):
					img.set_pixel(x, y, rock)
		"vine":
			for y in range(2, 34):
				var x := 18 + int(round(3.0 * sin(y * 0.45)))
				img.set_pixel(x, y, stem)
				img.set_pixel(x + 1, y, stem)
				if y % 8 == 4:
					var side := 1 if (y / 8) % 2 == 0 else -1
					for k in range(2, 6):
						img.set_pixel(x + 1 + side * k, y, leaf)
						img.set_pixel(x + 1 + side * k, y - 1, leaf)
		"thorn":
			var pale := CaveMap.THORN
			_line(img, Vector2(5.0, 32.0), Vector2(9.0, 10.0), pale)
			_line(img, Vector2(9.0, 32.0), Vector2(13.0, 18.0), pale)
			_line(img, Vector2(13.0, 32.0), Vector2(18.0, 3.0), pale)
			_line(img, Vector2(20.0, 32.0), Vector2(24.0, 12.0), pale)
			_line(img, Vector2(25.0, 32.0), Vector2(30.0, 20.0), pale)
			_line(img, Vector2(4.0, 32.0), Vector2(32.0, 32.0), pale)
		"slug":
			var body := Color(0.62, 0.85, 0.42)
			for x in range(5, 31):
				for y in range(18, 30):
					var dx := (x - 18.0) / 12.0
					var dy := (y - 26.0) / 5.0
					if dx * dx + dy * dy <= 1.0 and y <= 26.0 + 2.0:
						img.set_pixel(x, y, body)
			_line(img, Vector2(26.0, 19.0), Vector2(29.0, 13.0), body)
			_line(img, Vector2(29.0, 19.0), Vector2(32.0, 14.0), body)
		"shroom":
			var pale := Color(0.945, 0.933, 0.788)
			var cap := Color(0.71, 0.80, 0.61)
			for y in range(16, 33):
				var x := 18 + int(round(2.0 * sin((y - 16) * 0.2)))
				for k in range(-2, 2):
					img.set_pixel(x + k, y, pale)
			for x in range(5, 31):
				for y in range(5, 17):
					var dx := (x - 18.0) / 13.0
					var dy := (y - 16.0) / 11.0
					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(x, y, pale if (x * 7 + y * 3) % 11 == 0 else cap)
		"slime":
			var goo := Color(0.42, 0.82, 0.36)
			for x in range(4, 33):
				for y in range(14, 33):
					var dx := (x - 18.0) / 14.0
					var dy := (y - 32.0) / 17.0
					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(x, y, goo.lightened(0.35) if dx * dx + dy * dy > 0.7 else goo)
		"worm", "jelly":
			# The creature's own sprite (its first frame), scaled to fit.
			var src: Image = Critters.image(Critters.WORM_SPRITE if name == "worm" else Critters.JELLY_SHEET)
			if src:
				var fr := src.get_region(Rect2i(0, 0, src.get_width(), src.get_height()) if name == "worm" else Rect2i(0, 0, 32, 32))
				return _icon(fr)
		"longslug":
			var flesh := Color(0.86, 0.62, 0.74)
			for x in range(2, 34):
				var r := 1.5 + 2.5 * sin(PI * (x - 2) / 32.0) * (1.0 + 0.25 * sin(x * 0.8))
				for y in range(int(30 - r * 2.0), 31):
					img.set_pixel(x, y, flesh)
	return ImageTexture.create_from_image(img)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var x := int(round(p.x))
		var y := int(round(p.y))
		if x >= 0 and y >= 0 and x < ICON and y < ICON:
			img.set_pixel(x, y, c)


func _slider(lo: float, hi: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _check(text: String, on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	return c


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 30.0)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", _flat(BOX_BG, EDGE, 1))
	b.add_theme_stylebox_override("hover", _flat(BOX_BG.lightened(0.06), Color("8a8b95"), 1))
	b.add_theme_stylebox_override("pressed", _flat(BOX_BG.darkened(0.2), BRIGHT, 1))
	b.add_theme_stylebox_override("disabled", _flat(BOX_BG, EDGE, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))
	b.pressed.connect(on_pressed)
	return b


# --- The pick ---

func _choose(mode: String, pick: int) -> void:
	_mode = mode
	_pick = pick
	_drag_from = Vector2.INF
	_select_b.set_pressed_no_signal(mode == "none")
	if mode != "none":
		_sel = {}
		_hover = {}
		_grab = Vector2.INF
	if mode != "decor":
		_decor.deselect_all()
	if mode != "stamp":
		_stamps.deselect_all()
	if mode != "paint":
		var b := _paint_group.get_pressed_button()
		if b:
			b.set_pressed_no_signal(false)
	if mode != "light":
		var b := _light_group.get_pressed_button()
		if b:
			b.set_pressed_no_signal(false)
		_main.edit_light_preview([])
	_main.edit_ghost({})
	_tag.visible = false
	_refresh_size()


func _drop_pick() -> void:
	_choose("none", -1)
	say("pick dropped")


func _stamp_name() -> String:
	if _mode != "stamp" or _pick < 0 or _pick >= STAMPS.size():
		return ""
	return String(STAMPS[_pick][1])


func _light_kind() -> String:
	if _mode != "light" or _pick < 0 or _pick >= _lights_items.size():
		return ""
	return String(_lights_items[_pick][1])


func _size_step(d: int) -> void:
	var n: int = STAMP_SIZES.get(_stamp_name(), 1)
	_stamp_size = clampi(_stamp_size + d, 1, n)
	_refresh_size()


func _refresh_size() -> void:
	var name := _stamp_name()
	if name == "":
		_size_label.text = ""
		return
	var sizes: int = STAMP_SIZES.get(name, 1)
	var vars: int = STAMP_VARIANTS.get(name, 1)
	var t := "size %d / %d (up, down)" % [_stamp_size, sizes] if sizes > 1 else "one size"
	if vars > 1:
		t += " · shape %d / %d (wheel)" % [_stamp_var + 1, vars]
	_size_label.text = t


func _refresh_light_readout() -> void:
	if _card_right.has("Lights"):
		_card_right["Lights"].text = "r %d · strength %.1f" % [int(_lradius), _strength]


# The wheel as the tool's dial: the brush, the variant, a light's radius
# (its strength with Shift).
func _dial(dir: int, shift: bool) -> void:
	match _mode:
		"paint":
			_brush.value = clampf(_brush.value + 2.0 * dir, BRUSH_MIN, BRUSH_MAX)
		"decor":
			if _variant_names.size() > 1:
				var i := maxi(_variant_names.find(_pin), 0)
				i = posmod(i + dir, _variant_names.size())
				_pin = _variant_names[i]
				_variants.select(i)
		"stamp":
			var n: int = STAMP_VARIANTS.get(_stamp_name(), 1)
			if n > 1:
				_stamp_var = posmod(_stamp_var + dir, n)
				_refresh_size()
		"light":
			if shift:
				_strength = clampf(snappedf(_strength + 0.1 * dir, 0.1), STRENGTH_MIN, STRENGTH_MAX)
			else:
				_lradius = clampf(_lradius + 2.0 * dir, RADIUS_MIN, RADIUS_MAX)
			_refresh_light_readout()


# Whether the group picked is a carpet: one cut into ends and middles.
func _carpet() -> bool:
	for n in _groups.get(_group, []):
		if SceneBuilder.stamp_role(n) == "l":
			return true
	return false


# The stamp a free click places: the variant pinned, or a whole take of
# the group at random.
func _free_variant() -> String:
	if _pin != "":
		return _pin
	var whole: Array = []
	for n in _groups.get(_group, []):
		if SceneBuilder.stamp_role(n) == "":
			whole.append(n)
	if whole.is_empty():
		whole = _groups.get(_group, [])
	return whole[_rng.randi_range(0, whole.size() - 1)]


func _free_flags() -> String:
	var f := "d" if _carpet() else ""
	return f + ("h" if _mirror.button_pressed and _rng.randf() < 0.5 else "")


# --- Input ---

func has_mouse(p: Vector2) -> bool:
	return visible and (_dialog_open() or _cheat_box.visible or _panel.get_global_rect().has_point(p))


func _dialog_open() -> bool:
	return _new_box.visible or _load_box.visible


# Whether a dialog has the keys (main.gd leaves Tab to it then).
func dialog_open() -> bool:
	return _dialog_open()


# The light pass's check kept in step with the debug panel's (main.gd set_light).
func set_light(on: bool) -> void:
	if _lighting:
		_lighting.set_pressed_no_signal(on)


func _input(event: InputEvent) -> void:
	if not visible or _main == null:
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var k: Key = event.physical_keycode
	if _dialog_open():
		if event.echo:
			return
		if k == KEY_ESCAPE:
			_close_dialogs()
			get_viewport().set_input_as_handled()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			if _new_box.visible:
				_create()
			else:
				_load_pick()
			get_viewport().set_input_as_handled()
		return
	if event.unicode == 63 or (k == KEY_SLASH and event.shift_pressed):
		if not event.echo:
			_cheat_box.visible = not _cheat_box.visible
		get_viewport().set_input_as_handled()
		return
	if k == KEY_ESCAPE:
		if not event.echo:
			if _cheat_box.visible:
				_cheat_box.visible = false
			elif not _sel.is_empty():
				_sel = {}
				say("let go")
			else:
				_drop_pick()
		get_viewport().set_input_as_handled()
	elif (k == KEY_P or k == KEY_K) and not event.ctrl_pressed:
		# The bands of decor palettes, at the cursor's height.
		if not event.echo:
			var at: Vector2 = _main.get_global_mouse_position()
			_main.edit_begin()
			if k == KEY_P:
				say(_main.edit_band_palette(at, -1 if event.shift_pressed else 1))
			elif event.shift_pressed:
				say(_main.edit_band_merge(at))
			else:
				say(_main.edit_band_split(at))
			_main.edit_end()
		get_viewport().set_input_as_handled()
	elif k == KEY_V and not event.ctrl_pressed:
		if not event.echo:
			_choose("none", -1)
			say("select")
		get_viewport().set_input_as_handled()
	elif _mode == "none" and not _sel.is_empty() and k in [KEY_UP, KEY_DOWN, KEY_DELETE, KEY_BACKSPACE, KEY_H]:
		# The taken item: the arrows size it, H mirrors it, Delete takes it away.
		if not event.echo or k == KEY_UP or k == KEY_DOWN:
			match k:
				KEY_UP, KEY_DOWN:
					say(_main.edit_resize(_sel, 1 if k == KEY_UP else -1))
				KEY_H:
					say(_main.edit_flip(_sel))
				_:
					say(_main.edit_remove(_sel))
					_sel = {}
					_hover = {}
		Input.action_release("move_up")
		Input.action_release("move_down")
		get_viewport().set_input_as_handled()
	elif (k == KEY_UP or k == KEY_DOWN) and _mode == "stamp":
		# The arrows are the stamp's size here, not the gecko's climb.
		if not event.echo:
			_size_step(1 if k == KEY_UP else -1)
		Input.action_release("move_up")
		Input.action_release("move_down")
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _main == null or _dialog_open():
		return
	if event is InputEventMouseButton:
		if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if event.ctrl_pressed:
				_main.edit_zoom(_main.EDIT_ZOOM_STEP if dir > 0 else 1.0 / _main.EDIT_ZOOM_STEP, event.position)
				say(_main.edit_zoom_text())
			elif _mode == "none":
				# The wheel on the item taken, else on the one under the cursor.
				var it := _sel if not _sel.is_empty() else _hover
				if not it.is_empty():
					say(_main.edit_turn(it, dir, event.shift_pressed))
			else:
				_dial(dir, event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		_main.edit_pan(event.relative)
		get_viewport().set_input_as_handled()


func _keys() -> void:
	if _new_name.has_focus():
		return
	if Input.is_action_just_pressed("edit_undo"):
		say(_main.edit_undo())
		_sel = {}
	if Input.is_action_just_pressed("edit_redo"):
		say(_main.edit_redo())
		_sel = {}
	if Input.is_action_just_pressed("edit_home"):
		_main.edit_home()
		say(_main.edit_zoom_text())
	if Input.is_action_just_pressed("brush_up"):
		_brush.value = minf(_brush.value + 2.0, BRUSH_MAX)
	if Input.is_action_just_pressed("brush_down"):
		_brush.value = maxf(_brush.value - 2.0, BRUSH_MIN)


func _process(dt: float) -> void:
	if not visible or _main == null:
		return
	if _toast_t > 0.0:
		_toast_t -= dt
		if _toast_t <= 0.0:
			_toast.visible = false
	_file_t -= dt
	if _file_t <= 0.0:
		_file_t = 0.5
		_refresh_file()
	if _dialog_open() or _cheat_box.visible:
		_main.edit_ghost({})
		_main.edit_light_preview([])
		_tag.visible = false
		return
	_keys()
	var screen: Vector2 = _main.get_viewport().get_mouse_position()
	var over := has_mouse(screen)
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not over
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not over
	var down := lmb or rmb
	var pressed := lmb and not _was_down
	var rpressed := rmb and not _was_rmb
	var world: Vector2 = _main.get_global_mouse_position()
	if down and not _was_down:
		_main.edit_begin()
	elif _was_down and not down:
		_main.edit_brush_end(world)
		_main.edit_end()
		_refresh_title()
	_was_down = down
	_was_rmb = rmb
	if over:
		_main.edit_ghost({})
		_main.edit_light_preview([])
		_main.edit_marks({}, _sel, Vector2.ZERO)
		_tag.visible = false
		return
	var anchor: String = ANCHORS[_anchor.selected]
	if _mode != "none":
		_main.edit_marks({}, {}, Vector2.ZERO)
		if rpressed and (_mode == "decor" or _mode == "stamp"):
			# The right button takes away what is under it.
			var it: Dictionary = _main.edit_item_at(world)
			if not it.is_empty() and it.list != "lights":
				say(_main.edit_remove(it))
	match _mode:
		"paint":
			if lmb:
				_main.edit_paint(world, _radius, _pick)
			elif rmb:
				_main.edit_paint(world, _radius, 0)
		"decor":
			if lmb and _group != "":
				if _free.button_pressed:
					if pressed:
						_main.edit_stamp(_free_variant(), world, _radius, anchor, _free_flags())
				elif pressed:
					_main.edit_brush_begin(_groups[_group], world, anchor, _spacing.value, _mirror.button_pressed, _pin)
				else:
					_main.edit_brush_drag(world)
			if not down and _group != "":
				var name := _pin if _pin != "" else _face(_group)
				var where: String = _main.edit_ghost({"name": name, "p": world, "where": anchor})
				var which := "any, the rules pick" if _pin == "" else "variant %d / %d" % [_variant_names.find(_pin), _variant_names.size() - 1]
				_show_tag(screen, "%s · %s · %s" % [_group, which, where], "wheel next · click lays it · drag lays a run")
			else:
				_main.edit_ghost({})
				_tag.visible = false
		"stamp":
			var name := _stamp_name()
			if pressed:
				_main.edit_stamp(name, world, _radius, anchor, "", {"size": _stamp_size, "variant": _stamp_var})
				_main.edit_ghost({})
				say("%s set, size %d" % [name, _stamp_size])
			if not down:
				var where: String = _main.edit_ghost({"name": name, "p": world, "where": anchor, "size": _stamp_size, "variant": _stamp_var})
				_show_tag(screen, "%s · %s · %s" % [name, _size_label.text, where], "click sets it")
			else:
				_tag.visible = false
		"light":
			var kind := _light_kind()
			var entry: Array = []
			if _shape == "point" or _drag_from == Vector2.INF:
				entry = [world.x, world.y, kind, _lradius, _strength, "point", world.x, world.y]
			else:
				entry = [_drag_from.x, _drag_from.y, kind, _lradius, _strength, _shape, world.x, world.y]
			_main.edit_light_preview(entry)
			if pressed:
				if _shape == "point":
					say(_main.edit_light(world, world, kind, _lradius, _strength, "point"))
				else:
					_drag_from = world
			elif not lmb and _drag_from != Vector2.INF:
				say(_main.edit_light(_drag_from, world, kind, _lradius, _strength, _shape))
				_drag_from = Vector2.INF
			if rpressed:
				say(_main.edit_light_remove(world))
			var how := "click sets it" if _shape == "point" else ("press at the source, drag to the aim, release" if _shape == "cone" else "press, drag along the surface, release")
			_show_tag(screen, "%s · %s · r %d · strength %.1f" % [kind, _shape, int(_lradius), _strength], how + " · RMB removes")
		_:
			_select(world, screen, lmb, pressed, rpressed)


# Nothing picked: the hand. The item under the cursor shows its box and
# its tag; a press takes it and a drag moves it, laid at the release;
# the right button takes it away. The wheel, the arrows, H and Delete
# work on the one taken (_unhandled_input, _input).
func _select(world: Vector2, screen: Vector2, lmb: bool, pressed: bool, rpressed: bool) -> void:
	_main.edit_ghost({})
	_main.edit_light_preview([])
	if _grab == Vector2.INF:
		_hover = _main.edit_item_at(world)
	if pressed:
		_sel = _hover
		_grab = world if not _sel.is_empty() else Vector2.INF
	elif not lmb and _grab != Vector2.INF:
		var d := world - _grab
		_grab = Vector2.INF
		if d.length() >= 1.0:
			say(_main.edit_move(_sel, d))
	if rpressed and not _hover.is_empty():
		say(_main.edit_remove(_hover))
		_sel = {}
		_hover = {}
	var off := world - _grab if _grab != Vector2.INF else Vector2.ZERO
	_main.edit_marks(_hover, _sel, off)
	var it := _sel if _grab != Vector2.INF else _hover
	if it.is_empty():
		_tag.visible = false
		return
	var line: String = _main.edit_item_text(it)
	var how := "drag moves · wheel variant · up, down size · H mirror · Del or RMB removes"
	if it.list == "lights":
		how = "drag moves · wheel radius · Shift+wheel strength · Del or RMB removes"
	_show_tag(screen, line, how)


func _show_tag(screen: Vector2, line: String, hint: String) -> void:
	_tag.text = line + "\n" + hint
	_tag.position = screen + Vector2(22.0, -10.0)
	_tag.visible = true


# --- Status ---

# A line over the world for a few seconds (main.gd says its autosaves here too).
func say(text: String) -> void:
	_toast.text = text
	_toast.position = Vector2(panel_width() + 16.0, 40.0)
	_toast.visible = text != ""
	_toast_t = TOAST_S
	_refresh_title()


# The panel's width on screen: main.gd keeps its readout clear of it.
func panel_width() -> float:
	return maxf(WIDTH, _panel.size.x)


# On opening (main.gd, Tab or F2) and after a save or load: the name, the title.
# GECKO_EDIT_PICK=decor:<group> | stamp:<name> | light:<kind> makes the
# pick and puts the cursor over the world, for a look at the ghost or
# the light in a recording without a hand on the mouse.
func refresh() -> void:
	_refresh_title()
	_refresh_file()
	var pick := OS.get_environment("GECKO_EDIT_PICK")
	if pick.contains(":"):
		_env_pick(pick.get_slice(":", 0), pick.get_slice(":", 1))


func _env_pick(mode: String, what: String) -> void:
	match mode:
		"decor":
			var i := _group_names.find(what)
			if i >= 0:
				_decor.select(i)
				_decor.item_selected.emit(i)
		"stamp":
			for i in STAMPS.size():
				if STAMPS[i][1] == what:
					_stamps.select(i)
					_stamps.item_selected.emit(i)
		"light":
			for i in _lights_items.size():
				if _lights_items[i][1] == what:
					_light_buttons[i].set_pressed_no_signal(true)
					_choose("light", i)
		"cheat":
			_cheat_box.visible = true
		"load":
			_open_load()
	Input.warp_mouse(Vector2(1100.0, 420.0))


func _refresh_title() -> void:
	var current: String = _main.level_name()
	_name_label.text = "%s%s" % [current if current != "" else "(no level yet)", " *" if _main.level_dirty() else ""]
	_undo_b.disabled = not _main.edit_can_undo()
	_redo_b.disabled = not _main.edit_can_redo()


func _refresh_file() -> void:
	var current: String = _main.level_name()
	_file_name.text = current if current != "" else "(named on the first stroke)"
	var info: Array = _main.level_version_info()
	if _card_right.has("File"):
		if int(info[0]) > 0:
			_card_right["File"].text = "v%d · %s %s ago" % [int(info[0]), "auto-saved" if info[1] == "auto" else "saved", _age(float(info[2]))]
		else:
			_card_right["File"].text = "no version yet"
	_refresh_title()


static func _age(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


# --- Files: the dialogs ---

func _build_dialogs() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_new_box = _dialog(380.0)
	var nv := _new_box.get_child(0) as VBoxContainer
	nv.add_child(_label("New level", 15, BRIGHT))
	nv.add_child(_label("NAME", 11, DIM))
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "a name: letters, digits, - and _"
	_new_name.add_theme_font_size_override("font_size", 13)
	nv.add_child(_new_name)
	_new_info = _label("", 12, DIM)
	_new_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	nv.add_child(_new_info)
	var nrow := HBoxContainer.new()
	nrow.alignment = BoxContainer.ALIGNMENT_END
	nrow.add_theme_constant_override("separation", 6)
	nv.add_child(nrow)
	nrow.add_child(_button("Cancel", _close_dialogs))
	nrow.add_child(_button("Create", _create))

	_load_box = _dialog(560.0)
	var lv := _load_box.get_child(0) as VBoxContainer
	var lhead := HBoxContainer.new()
	lv.add_child(lhead)
	var lt := _label("Load", 15, BRIGHT)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lhead.add_child(lt)
	lhead.add_child(_label("levels/ · a version is a .json and its .cells.png", 11, DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.custom_minimum_size = Vector2(0.0, 240.0)
	lv.add_child(cols)
	var lc := VBoxContainer.new()
	lc.custom_minimum_size = Vector2(200.0, 0.0)
	lc.add_theme_constant_override("separation", 6)
	cols.add_child(lc)
	lc.add_child(_label("LEVELS", 11, DIM))
	_load_levels = _list()
	_load_levels.item_selected.connect(func(_i: int) -> void: _fill_versions())
	lc.add_child(_load_levels)
	var vc := VBoxContainer.new()
	vc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vc.add_theme_constant_override("separation", 6)
	cols.add_child(vc)
	_load_vlabel = _label("VERSIONS", 11, DIM)
	vc.add_child(_load_vlabel)
	_load_versions = _list()
	_load_versions.item_selected.connect(func(i: int) -> void: _load_b.text = "Load v%d" % int(_load_vdata[i].n) if i < _load_vdata.size() else "Load")
	vc.add_child(_load_versions)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 6)
	lv.add_child(lrow)
	_load_note = _label("", 11, DIM)
	_load_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	lrow.add_child(_load_note)
	lrow.add_child(_button("Cancel", _close_dialogs))
	_load_b = _button("Load", _load_pick)
	lrow.add_child(_load_b)


func _dialog(width: float) -> PanelContainer:
	var box := PanelContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(width, 0.0)
	box.add_theme_stylebox_override("panel", _flat(CARD_BG, EDGE, 1, 8, 20, 18))
	box.visible = false
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	return box


func _list() -> ItemList:
	var l := ItemList.new()
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.allow_search = false
	l.focus_mode = Control.FOCUS_NONE
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_stylebox_override("panel", _flat(PANEL_BG, EDGE, 1))
	return l


func _close_dialogs() -> void:
	_new_box.visible = false
	_load_box.visible = false
	_dim.visible = false


func _open_new() -> void:
	_cheat_box.visible = false
	_dim.visible = true
	_new_box.visible = true
	_new_name.text = ""
	var current: String = _main.level_name()
	var info: Array = _main.level_version_info()
	var line := "Opens a blank room under this name, its first version written."
	if _main.level_dirty():
		if int(info[0]) > 0:
			line += " %s keeps its versions; strokes since its last one, %s ago, are dropped." % [current, _age(float(info[2]))]
		else:
			line += " The strokes in hand are dropped."
	_new_info.text = line
	_new_name.grab_focus()


func _create() -> void:
	var name := _new_name.text.strip_edges().to_lower()
	if name == "" or not name.is_valid_filename() or name.contains(" ") or name.contains("."):
		say("a name of letters, digits, - and _ first")
		return
	if not _main.level_versions(name).is_empty():
		say("there is a level %s already: pick another name, or load it" % name)
		return
	_close_dialogs()
	say(_main.blank_level(name))
	refresh()


func _open_load() -> void:
	_cheat_box.visible = false
	_dim.visible = true
	_load_box.visible = true
	_load_entries = _main.level_entries()
	_load_levels.clear()
	var current: String = _main.level_name()
	var sel := 0
	for i in _load_entries.size():
		var e: Dictionary = _load_entries[i]
		_load_levels.add_item("%s   %s" % [e.name, ("%d versions" % int(e.versions)) if not e.generated else "generated"])
		if e.name == current:
			sel = i
	var info: Array = _main.level_version_info()
	_load_note.text = "Loading drops the strokes since the last version, %s ago." % _age(float(info[2])) if _main.level_dirty() else ""
	if _load_entries.is_empty():
		_load_vlabel.text = "VERSIONS"
		_load_versions.clear()
		_load_b.disabled = true
		return
	_load_b.disabled = false
	_load_levels.select(sel)
	_fill_versions()


func _fill_versions() -> void:
	_load_versions.clear()
	_load_vdata = []
	var sel := _load_levels.get_selected_items()
	if sel.is_empty():
		return
	var e: Dictionary = _load_entries[sel[0]]
	_load_vlabel.text = "VERSIONS OF %s · LATEST FIRST" % String(e.name).to_upper()
	if e.generated:
		_load_versions.add_item("the head, generated by tools (read only)")
		_load_b.text = "Load"
		return
	_load_vdata = _main.level_versions(e.name)
	for v in _load_vdata:
		_load_versions.add_item("v%d   %s   %s" % [int(v.n), String(v.saved_at).replace("T", " "), String(v.kind)])
	if not _load_vdata.is_empty():
		_load_versions.select(0)
		_load_b.text = "Load v%d" % int(_load_vdata[0].n)


func _load_pick() -> void:
	var sel := _load_levels.get_selected_items()
	if sel.is_empty():
		return
	var e: Dictionary = _load_entries[sel[0]]
	_close_dialogs()
	if e.generated:
		say(_main.load_level(e.name))
	else:
		var vs := _load_versions.get_selected_items()
		var file: String = String(_load_vdata[vs[0]].file) if not vs.is_empty() and vs[0] < _load_vdata.size() else ""
		say(_main.load_version(e.name, file))
	refresh()


func _save() -> void:
	say(_main.write_version("saved"))
	refresh()


# --- The cheat sheet (?) ---

func _build_cheat() -> void:
	_cheat_box = _dialog(640.0)
	var v := _cheat_box.get_child(0) as VBoxContainer
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label("Mouse and keys", 15, BRIGHT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_label("? or Esc closes", 11, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for section in CHEAT:
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_theme_constant_override("separation", 3)
		grid.add_child(sv)
		sv.add_child(_label(String(section[0]).to_upper(), 11, DIM))
		var rows := GridContainer.new()
		rows.columns = 2
		rows.add_theme_constant_override("h_separation", 10)
		rows.add_theme_constant_override("v_separation", 2)
		sv.add_child(rows)
		for pair in section[1]:
			var k := _label(String(pair[0]), 12, ACCENT)
			k.custom_minimum_size = Vector2(104.0, 0.0)
			rows.add_child(k)
			var d := _label(String(pair[1]), 12, INK)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD
			d.custom_minimum_size = Vector2(180.0, 0.0)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.add_child(d)
