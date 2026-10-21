# The pose editor (F3 in the game, tools/pose_editor.sh on its own): a
# scene of its own with one gecko, drawn by the blob layer as in the
# game, at a pose made by hand. The chain's points, the feet and the
# look are handles to drag: a dragged point pulls the body after it
# like a rope (every link keeps its length), Shift moves the one point,
# Ctrl drags the whole pose. Frames of poses run along the top, each a
# card drawn as the chain in small with its seconds: a click picks one
# to edit, + adds a copy after it, - takes it away, < and > move it,
# Play runs them blended in link space (pose_anim.gd), the slider
# scrubs, Reverse previews the curl. The frames are kept under poses/
# as versions with a head the game loads (PoseAnim): New, Load and Save
# as the map editor's, an auto version a minute while there are edits.
# The file named wake is the gecko's wake-up (main.gd play_anim), and
# backwards its curl to sleep. GECKO_POSE=name opens another file.
extends Node2D

const Gecko = preload("res://gecko.gd")
const BlobLayer = preload("res://blob_layer.gd")
const PoseAnim = preload("res://pose_anim.gd")

const BASE := Vector2(960.0, 640.0)   # Where the pose's surface point sits in the blob layer's world (it covers 1920 by 1080)
const ZOOM_DEFAULT := 4.0
const ZOOM_MIN := 2.0
const ZOOM_MAX := 12.0
const ZOOM_STEP := 1.25
const STRIP_H := 150.0                # The frames strip across the top
const PANEL_W := 300.0                # The panel down the left
const PICK_PX := 11.0                 # Screen px round a handle that picks it
const LOOK_HANDLE := 16.0             # Px from the head the look's handle sits
const AUTOSAVE_S := 60.0
const UNDO_MAX := 60
const TOAST_S := 4.0
const DUR_MIN := 0.02
const DUR_MAX := 5.0
const PANEL_BG := Color("15161a")
const CARD_BG := Color("1d1e24")
const BOX_BG := Color("22232b")
const EDGE := Color("3a3b45")
const INK := Color("d8d6cf")
const DIM := Color("9a978f")
const BRIGHT := Color("f0eee6")
const ACCENT := Color("c9b28a")
const DARK := Color("15161a")
const BACKDROP := Color(0.11, 0.115, 0.13)
const FLOOR_COL := Color(0.55, 0.5, 0.42, 0.9)
const TICK_COL := Color(0.55, 0.5, 0.42, 0.35)
const LINK_COL := Color(1.0, 1.0, 1.0, 0.55)
const RING_COL := Color(1.0, 1.0, 1.0, 0.16)
const HANDLE_COL := Color(0.92, 0.9, 0.84)
const HIP_COL := Color(0.6, 0.85, 1.0)
const FOOT_COL := Color(0.45, 1.0, 0.55)
const LOOK_COL := Color(1.0, 0.72, 0.3)
const HOVER_COL := Color(1.0, 0.95, 0.3)
const DRAG_COL := Color(1.0, 0.55, 0.2)
const PREV_COL := Color(0.4, 0.6, 1.0, 0.4)
const NEXT_COL := Color(1.0, 0.6, 0.3, 0.4)
const EYE_COL := Color(0.1, 0.1, 0.12)
const POINT_NAMES := ["head", "neck (front hip)", "chest", "belly (back hip)", "rump", "tail root", "tail", "tail", "tail", "tail tip"]
const FOOT_NAMES := ["front near foot", "front far foot", "back near foot", "back far foot"]

const CHEAT := [
	["Frames", [
		["click a card", "edit that frame; Left, Right pick the one before or after"],
		["+ Add, Insert", "a copy of the frame after it"],
		["- Remove, Delete", "the frame taken away (the last one stays)"],
		["< >, Ctrl+Left/Right", "move the frame along"],
		["Seconds, Ease", "how long the frame blends into the next, and how"]]],
	["Handles", [
		["drag a point", "the body follows like a rope, every link its length"],
		["Shift+drag", "that one point alone, the links stretching"],
		["Ctrl+drag", "the whole pose"],
		["drag a foot", "where it is drawn (its anchor sits under)"],
		["drag the look", "the orange handle off the head"],
		["drag the eye", "the dark handle on the head, kept on its disc; Eye to look hands it back to the look"]]],
	["Play", [
		["Space, Play", "the frames blended; Loop, Reverse (the curl), Speed"],
		["slider", "scrubs; a click in the world edits again"],
		["onion skin", "the frame before in blue, after in orange"]]],
	["View", [
		["wheel", "zoom about the cursor"],
		["MMB drag", "pan; Home: back to the gecko"],
		["Pixel grid", "1 px as the game, or 2 px like the rock"]]],
	["Files", [
		["Save, Ctrl+S", "a saved version and the head the game plays (poses/<name>.json)"],
		["autosave", "a version a minute while there are edits, the last 10 kept"],
		["New, Load", "a name; the animations and their versions"],
		["Ctrl+Z, Ctrl+Y", "undo, redo"],
		["Esc, F3", "back to the game (an auto version written first)"]]],
]


# A frame's card in the strip: the chain in small over a floor line,
# the feet as dots, the frame's number and its seconds.
class FrameCard extends Control:
	signal picked(index: int)
	const W := 104.0
	const H := 66.0
	const S := 0.72                   # Card px a pose px
	const BG := Color("1d1e24")
	const SEL := Color("c9b28a")
	const LIVE := Color("6fd0ff")
	const EDGE_C := Color("3a3b45")
	const BODY := Color(0.56, 0.63, 0.40)
	const FOOT := Color(0.45, 1.0, 0.55)
	const FLOOR := Color(0.55, 0.5, 0.42, 0.7)
	const TXT := Color("d8d6cf")
	const TXT_DIM := Color("9a978f")
	var index := 0
	var frame: Dictionary = {}
	var radii: Array = []
	var selected := false
	var live := false

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(index)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, BG)
		var o := Vector2(size.x * 0.64, size.y - 13.0)
		draw_line(Vector2(0.0, o.y), Vector2(size.x, o.y), FLOOR, 1.0)
		if not frame.is_empty():
			var pts: PackedVector2Array = frame.points
			for i in range(pts.size() - 1, -1, -1):
				var rad: float = float(radii[i]) if i < radii.size() else 3.0
				draw_circle(o + pts[i] * S, maxf(rad * S, 1.2), BODY)
			var feet: PackedVector2Array = frame.feet
			for p in feet:
				draw_circle(o + p * S, 1.6, FOOT)
			var look: Vector2 = frame.look
			draw_line(o + pts[0] * S, o + (pts[0] + look * 9.0) * S, Color(1.0, 0.72, 0.3, 0.9), 1.0)
			var eye: Vector2 = frame.get("eye", look * 3.5 + Vector2(0.0, -1.0))
			draw_circle(o + (pts[0] + eye) * S, 1.5, Color(0.1, 0.1, 0.12))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(6.0, 14.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TXT)
		draw_string(font, Vector2(size.x - 40.0, size.y - 4.0), "%.2fs" % float(frame.get("dur", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TXT_DIM)
		if live:
			draw_rect(Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0)), LIVE, false, 2.0)
		draw_rect(r, SEL if selected else EDGE_C, false, 2.0 if selected else 1.0)


var _blobs: BlobLayer
var _gecko: Gecko
var _overlay: Node2D
var _camera: Camera2D
var _ui: CanvasLayer
var _strip_panel: PanelContainer
var _strip: HBoxContainer
var _scroll: ScrollContainer
var _frames_label: Label
var _scrub: HSlider
var _time_label: Label
var _play_b: Button
var _loop_c: CheckButton
var _rev_c: CheckButton
var _speed_label: Label
var _panel: PanelContainer
var _name_label: Label
var _frame_title: Label
var _dur_spin: SpinBox
var _ease_opt: OptionButton
var _shut_c: CheckButton
var _lock_c: CheckButton
var _onion_c: CheckButton
var _zoom_label: Label
var _file_label: Label
var _file_note: Label
var _status: Label
var _toast: Label
var _toast_t := 0.0
var _dim: ColorRect
var _new_box: PanelContainer
var _new_name: LineEdit
var _new_info: Label
var _load_box: PanelContainer
var _load_list: ItemList
var _load_versions: ItemList
var _load_vlabel: Label
var _load_b: Button
var _load_entries: Array = []
var _load_vdata: Array = []
var _cheat_box: PanelContainer
var _cards: Array = []

var _frames: Array = []        # The animation: PoseAnim frames
var _sel := 0                  # The frame being edited
var _shown: Dictionary = {}    # The pose on the gecko now (the frame, or a blend while playing or scrubbing)
var _handles_on := true        # The selected frame is shown, its handles live (off while playing or scrubbing)
var _playing := false
var _play_t := 0.0
var _loop := true
var _reverse := false
var _speed := 1.0
var _onion := true
var _lock := true              # A dragged point pulls the chain after it
var _zoom := ZOOM_DEFAULT
var _cam := BASE               # The world point shown in the middle of the free part of the screen
var _panning := false
var _drag_kind := ""           # point | foot | look | body, while the left button drags one
var _drag_i := -1
var _drag_last := Vector2.ZERO
var _drag_armed := false       # The undo snapshot waits for the first motion
var _hover: Dictionary = {}
var _undo: Array = []
var _redo: Array = []
var _name := PoseAnim.WAKE
var _dirty := false            # Edits since the last saved version or load
var _dirty_v := false          # Edits since any version: what autosave waits for
var _autosave_t := 0.0
var _version := 0
var _version_kind := ""


func _ready() -> void:
	InputSetup.ensure_actions()
	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.position = Vector2(-4000.0, -4000.0)
	bg.size = Vector2(10000.0, 10000.0)
	bg.z_index = -10
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_blobs = BlobLayer.new()
	add_child(_blobs)
	_gecko = Gecko.new()
	_gecko.blobs = _blobs
	add_child(_gecko)
	_gecko.set_physics_process(false)
	_gecko.pos = BASE + Vector2.UP * Gecko.RIDE_H
	_overlay = Node2D.new()
	_overlay.z_index = 14
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	_cam = BASE + Vector2(0.0, -24.0)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_build_strip()
	_build_panel()
	_build_dialogs()
	_build_cheat()
	_place_camera()
	_fit_to_panel.call_deferred()
	var want := OS.get_environment("GECKO_POSE")
	_open(want if want != "" else PoseAnim.WAKE)


# --- The animation in hand ---

func _frame() -> Dictionary:
	return _frames[_sel]


# Opens the head of an animation, or starts one of a standing frame
# under that name when there is no file yet.
func _open(name: String) -> void:
	_name = name
	var frames := PoseAnim.load_head(name)
	var vs := PoseAnim.versions(name)
	if frames.is_empty() and not vs.is_empty():
		frames = PoseAnim.load_version(name, String(vs[0].file))
	if frames.is_empty():
		frames = [PoseAnim.standing()]
		say("new animation %s: one standing frame, nothing written until Save" % name)
	else:
		say("loaded %s, %d frames" % [name, frames.size()])
	_take(frames, vs)


func _take(frames: Array, vs: Array) -> void:
	_frames = frames
	_sel = 0
	_undo.clear()
	_redo.clear()
	_dirty = false
	_dirty_v = false
	_autosave_t = 0.0
	_version = int(vs[0].n) if not vs.is_empty() else 0
	_version_kind = String(vs[0].kind) if not vs.is_empty() else ""
	_stop_play()
	_rebuild_cards()
	_show_pose()
	_refresh_file()


func _snapshot() -> void:
	_undo.append(PoseAnim.dup_all(_frames))
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


func _mark() -> void:
	_dirty = true
	_dirty_v = true
	_refresh_file()


func _undo_step() -> void:
	if _undo.is_empty():
		say("nothing to undo")
		return
	_redo.append(PoseAnim.dup_all(_frames))
	_frames = _undo.pop_back()
	_sel = clampi(_sel, 0, _frames.size() - 1)
	_mark()
	_rebuild_cards()
	_show_pose()
	say("undone")


func _redo_step() -> void:
	if _redo.is_empty():
		say("nothing to redo")
		return
	_undo.append(PoseAnim.dup_all(_frames))
	_frames = _redo.pop_back()
	_sel = clampi(_sel, 0, _frames.size() - 1)
	_mark()
	_rebuild_cards()
	_show_pose()
	say("redone")


# The selected frame on the gecko, its handles live.
func _show_pose() -> void:
	_shown = _frame()
	_handles_on = true
	_gecko.pose_show(_shown, BASE, Vector2.UP, 1.0)
	_set_live(-1)
	var start := 0.0
	for i in _sel:
		start += float(_frames[i].dur)
	var tot := PoseAnim.total(_frames)
	_scrub.set_value_no_signal(start / tot if tot > 0.0 else 0.0)
	_time_label.text = "%.2f / %.2f s" % [start, tot]
	_refresh_frame_card()
	_overlay.queue_redraw()


# A blend on the gecko, at t seconds of the forward animation, the
# handles away.
func _preview_at(t: float) -> void:
	var tot := PoseAnim.total(_frames)
	var tf := tot - t if _reverse else t
	_shown = PoseAnim.sample(_frames, tf, _loop)
	_handles_on = false
	_gecko.pose_show(_shown, BASE, Vector2.UP, 1.0)
	_set_live(PoseAnim.frame_at(_frames, tf))
	_time_label.text = "%.2f / %.2f s" % [t, tot]
	_overlay.queue_redraw()


func _changed() -> void:
	_mark()
	_show_pose()
	if _sel < _cards.size():
		_cards[_sel].queue_redraw()
	_frames_label.text = _frames_text()


func _select(i: int) -> void:
	_sel = clampi(i, 0, _frames.size() - 1)
	for c in _cards:
		c.selected = c.index == _sel
		c.queue_redraw()
	if _sel < _cards.size():
		_scroll.ensure_control_visible(_cards[_sel])
	_show_pose()


func _add_frame() -> void:
	_snapshot()
	_frames.insert(_sel + 1, PoseAnim.dup(_frame()))
	_sel += 1
	_mark()
	_rebuild_cards()
	_show_pose()
	say("frame %d added, a copy of %d" % [_sel + 1, _sel])


func _remove_frame() -> void:
	if _frames.size() <= 1:
		say("the last frame stays")
		return
	_snapshot()
	_frames.remove_at(_sel)
	_sel = clampi(_sel, 0, _frames.size() - 1)
	_mark()
	_rebuild_cards()
	_show_pose()
	say("frame taken away, %d left" % _frames.size())


func _move_frame(d: int) -> void:
	var j := _sel + d
	if j < 0 or j >= _frames.size():
		return
	_snapshot()
	var f: Dictionary = _frames[_sel]
	_frames[_sel] = _frames[j]
	_frames[j] = f
	_sel = j
	_mark()
	_rebuild_cards()
	_show_pose()


func _set_dur(v: float) -> void:
	if absf(float(_frame().dur) - v) < 0.0005:
		return
	_snapshot()
	_frame().dur = v
	_changed()


func _set_ease(e: String) -> void:
	if String(_frame().ease) == e:
		return
	_snapshot()
	_frame().ease = e
	_changed()


# The tools: the frame's pose replaced, its seconds and ease kept.
func _tool(what: String) -> void:
	var f := _frame()
	_snapshot()
	match what:
		"standing":
			var s := PoseAnim.standing()
			f.points = s.points
			f.feet = s.feet
			f.look = s.look
			f.eye = s.eye
			f.eye_free = false
		"mirror":
			_frames[_sel] = PoseAnim.mirrored(f)
		"even":
			PoseAnim.even_links(f, Gecko.LINK)
		"eye":
			f.eye = PoseAnim.eye_for(f.look)
			f.eye_free = false
		"feet":
			var feet: PackedVector2Array = f.feet
			for k in feet.size():
				feet[k] = Vector2(feet[k].x, PoseAnim.FOOT_DRAWN_Y)
			f.feet = feet
		"prev", "next":
			var j := _sel - 1 if what == "prev" else _sel + 1
			if j < 0 or j >= _frames.size():
				_undo.pop_back()
				say("no frame there")
				return
			var src := PoseAnim.dup(_frames[j])
			f.points = src.points
			f.feet = src.feet
			f.look = src.look
			f.eye = src.eye
			f.eye_free = src.eye_free
	_changed()


# --- Playback ---

func _toggle_play() -> void:
	if _playing:
		_stop_play()
		say("stopped: click a frame, or in the world, to edit")
	else:
		_start_play()


func _start_play() -> void:
	if _frames.size() < 2:
		say("two frames at least to play")
		return
	_playing = true
	_play_t = _scrub.value * PoseAnim.total(_frames) if not _handles_on else 0.0
	_play_b.text = "Stop"
	_preview_at(_play_t)


func _stop_play() -> void:
	_playing = false
	if _play_b:
		_play_b.text = "Play"


func _on_scrub(v: float) -> void:
	_stop_play()
	_preview_at(v * PoseAnim.total(_frames))


func _set_live(i: int) -> void:
	for c in _cards:
		var on: bool = c.index == i
		if c.live != on:
			c.live = on
			c.queue_redraw()


func _process(dt: float) -> void:
	if _playing:
		var tot := PoseAnim.total(_frames)
		_play_t += dt * _speed
		if _play_t >= tot:
			if _loop and tot > 0.0:
				_play_t = fposmod(_play_t, tot)
			else:
				_play_t = tot
				_stop_play()
		_scrub.set_value_no_signal(_play_t / tot if tot > 0.0 else 0.0)
		_preview_at(_play_t)
	if _toast_t > 0.0:
		_toast_t -= dt
		if _toast_t <= 0.0:
			_toast.visible = false
	if _dirty_v:
		_autosave_t += dt
		if _autosave_t >= AUTOSAVE_S:
			say(PoseAnim.write(_name, _frames, "auto"))
			_dirty_v = false
			_autosave_t = 0.0
			_version += 1
			_version_kind = "auto"
			_refresh_file()
	# The hover: the handle under the cursor, named in the status line.
	if _drag_kind == "" and not _dialog_open():
		var h := _pick(get_global_mouse_position()) if _handles_on else {}
		if h != _hover:
			_hover = h
			_overlay.queue_redraw()
		if _handles_on:
			_status.text = _handle_name(h) + ("   drag: the chain follows · Shift one point · Ctrl the whole pose" if not h.is_empty() else "")
		else:
			_status.text = "preview: click a frame, or in the world, to edit"


# --- The world: handles, dragging, the view ---

func _to_world(p: Vector2) -> Vector2:
	return PoseAnim.to_world(p, BASE, Vector2.UP, 1.0)


func _to_local(w: Vector2) -> Vector2:
	return PoseAnim.to_local(w, BASE, Vector2.UP, 1.0)


# The handle under a world point: {kind, i}, or empty.
func _pick(m: Vector2) -> Dictionary:
	if _frames.is_empty():
		return {}
	var f := _frame()
	var best := {}
	var best_d := PICK_PX / _zoom
	var pts: PackedVector2Array = f.points
	var look: Vector2 = f.look
	var eye: Vector2 = f.eye
	var d := m.distance_to(_to_world(pts[0] + eye))
	if d < best_d * 0.8:
		best = {"kind": "eye", "i": 0}
		best_d = d
	d = m.distance_to(_to_world(pts[0] + look * LOOK_HANDLE))
	if d < best_d:
		best = {"kind": "look", "i": 0}
		best_d = d
	var feet: PackedVector2Array = f.feet
	for k in feet.size():
		d = m.distance_to(_to_world(feet[k]))
		if d < best_d:
			best = {"kind": "foot", "i": k}
			best_d = d
	for i in pts.size():
		d = m.distance_to(_to_world(pts[i]))
		if d < best_d:
			best = {"kind": "point", "i": i}
			best_d = d
	return best


func _handle_name(h: Dictionary) -> String:
	if h.is_empty():
		return ""
	match String(h.kind):
		"point":
			return "point %d: %s" % [int(h.i) + 1, POINT_NAMES[int(h.i)]]
		"foot":
			return FOOT_NAMES[int(h.i)]
		"look":
			return "the look" + ("" if bool(_frame().get("eye_free", false)) else " (the eye rides with it)")
		"eye":
			return "the eye, on the head's disc"
	return "the whole pose"


func _begin_drag(m: Vector2, ctrl: bool) -> void:
	if _playing:
		_stop_play()
	if not _handles_on:
		_show_pose()
		return
	var hit := _pick(m)
	if ctrl:
		hit = {"kind": "body", "i": -1}
	if hit.is_empty():
		return
	_drag_kind = String(hit.kind)
	_drag_i = int(hit.i)
	_drag_last = _to_local(m)
	_drag_armed = true
	_hover = hit
	_overlay.queue_redraw()


func _drag_to(m: Vector2, shift: bool) -> void:
	var local := _to_local(m)
	var f := _frame()
	if _drag_armed:
		_snapshot()
		_drag_armed = false
	match _drag_kind:
		"point":
			if shift or not _lock:
				var pts: PackedVector2Array = f.points
				pts[_drag_i] = local
				f.points = pts
			else:
				PoseAnim.follow(f, _drag_i, local)
		"foot":
			var feet: PackedVector2Array = f.feet
			feet[_drag_i] = local
			f.feet = feet
		"look":
			var pts: PackedVector2Array = f.points
			var d := local - pts[0]
			if d.length() > 0.5:
				f.look = d.normalized()
				if not bool(f.get("eye_free", false)):
					f.eye = PoseAnim.eye_for(f.look)
		"eye":
			var pts: PackedVector2Array = f.points
			f.eye = (local - pts[0]).limit_length(PoseAnim.EYE_MAX)
			f.eye_free = true
		"body":
			PoseAnim.moved(f, local - _drag_last)
			_drag_last = local
	_changed()


func _end_drag() -> void:
	_drag_kind = ""
	_drag_i = -1
	_drag_armed = false
	_overlay.queue_redraw()


func _place_camera() -> void:
	_camera.zoom = Vector2(_zoom, _zoom)
	# The base sits in the middle of the screen's free part, right of
	# the panel and under the strip.
	var off := Vector2(PANEL_W, STRIP_H) * 0.5 / _zoom
	_camera.position = (_cam - off).round()
	if _zoom_label:
		_zoom_label.text = "zoom %.1fx" % _zoom
	_overlay.queue_redraw()


func _zoom_at(m: Vector2, factor: float) -> void:
	var nz := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if nz == _zoom:
		return
	_cam = m + (_cam - m) * (_zoom / nz)
	_zoom = nz
	_place_camera()


func _home() -> void:
	_zoom = ZOOM_DEFAULT
	_cam = BASE + Vector2(0.0, -24.0)
	_place_camera()


func _draw_overlay() -> void:
	var c := _overlay
	var w := 1.0 / _zoom
	# The surface line, ticks every 10 px (a longer one every 50), the
	# body centre's column.
	c.draw_line(BASE + Vector2(-600.0, 0.0), BASE + Vector2(600.0, 0.0), FLOOR_COL, 2.0 * w)
	for x in range(-600, 601, 10):
		var h := 4.0 if x % 50 == 0 else 2.0
		c.draw_line(BASE + Vector2(x, 0.0), BASE + Vector2(x, h), TICK_COL, w)
	c.draw_line(BASE + Vector2(0.0, 0.0), BASE + Vector2(0.0, -80.0), TICK_COL, w)
	if _frames.is_empty() or _shown.is_empty():
		return
	if _onion and _handles_on:
		if _sel > 0:
			_draw_ghost(_frames[_sel - 1], PREV_COL, w)
		if _sel < _frames.size() - 1:
			_draw_ghost(_frames[_sel + 1], NEXT_COL, w)
	var pts: PackedVector2Array = _shown.points
	var wp := PackedVector2Array()
	wp.resize(pts.size())
	for i in pts.size():
		wp[i] = _to_world(pts[i])
	for i in range(1, wp.size()):
		c.draw_line(wp[i - 1], wp[i], LINK_COL, 1.5 * w)
	for i in wp.size():
		c.draw_arc(wp[i], float(Gecko.RADII[i]), 0.0, TAU, 28, RING_COL, w)
	var head := wp[0]
	var look: Vector2 = _shown.look
	c.draw_line(head, head + look * LOOK_HANDLE, LOOK_COL, 1.5 * w)
	if not _handles_on:
		return
	var hr := 5.0 * w
	for i in wp.size():
		var col := HIP_COL if (i == Gecko.FRONT_HIP or i == Gecko.BACK_HIP) else HANDLE_COL
		if _is(_hover, "point", i):
			col = DRAG_COL if _drag_kind != "" else HOVER_COL
		c.draw_circle(wp[i], hr * (1.3 if _is(_hover, "point", i) else 1.0), col)
	var feet: PackedVector2Array = _shown.feet
	for k in feet.size():
		var fw := _to_world(feet[k])
		var col := FOOT_COL
		if _is(_hover, "foot", k):
			col = DRAG_COL if _drag_kind != "" else HOVER_COL
		c.draw_rect(Rect2(fw - Vector2(hr, hr), Vector2(hr, hr) * 2.0), col)
	var eye: Vector2 = _shown.get("eye", PoseAnim.eye_for(look))
	var ew := head + eye
	c.draw_arc(head, PoseAnim.EYE_MAX, 0.0, TAU, 24, Color(EYE_COL, 0.35), w)
	c.draw_circle(ew, hr * 0.9, HOVER_COL if _is(_hover, "eye", 0) else Color(0.95, 0.93, 0.85))
	c.draw_circle(ew, hr * 0.55, DRAG_COL if (_is(_hover, "eye", 0) and _drag_kind != "") else EYE_COL)
	var lk := head + look * LOOK_HANDLE
	var lcol := LOOK_COL
	if _is(_hover, "look", 0):
		lcol = DRAG_COL if _drag_kind != "" else HOVER_COL
	c.draw_colored_polygon(PackedVector2Array([lk + Vector2(0.0, -hr * 1.3), lk + Vector2(hr * 1.3, 0.0), lk + Vector2(0.0, hr * 1.3), lk + Vector2(-hr * 1.3, 0.0)]), lcol)


func _is(h: Dictionary, kind: String, i: int) -> bool:
	return not h.is_empty() and String(h.kind) == kind and int(h.i) == i


func _draw_ghost(f: Dictionary, col: Color, w: float) -> void:
	var pts: PackedVector2Array = f.points
	for i in range(1, pts.size()):
		_overlay.draw_line(_to_world(pts[i - 1]), _to_world(pts[i]), col, 2.0 * w)
	for i in pts.size():
		_overlay.draw_circle(_to_world(pts[i]), 2.0 * w, col)
	var feet: PackedVector2Array = f.feet
	for p in feet:
		_overlay.draw_circle(_to_world(p), 2.0 * w, col)


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _dialog_open():
		return
	if event is InputEventMouseButton:
		var m := get_global_mouse_position()
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(m, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(m, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_begin_drag(m, event.ctrl_pressed)
				else:
					_end_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _panning:
			_cam -= event.relative / _zoom
			_place_camera()
		elif _drag_kind != "":
			_drag_to(get_global_mouse_position(), event.shift_pressed)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k: Key = event.physical_keycode
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		# Typing a name or a number: only Esc and Enter are the editor's.
		if _dialog_open() and not event.echo:
			if k == KEY_ESCAPE:
				_close_dialogs()
				get_viewport().set_input_as_handled()
			elif k == KEY_ENTER or k == KEY_KP_ENTER:
				_create()
				get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE or k == KEY_ENTER or k == KEY_KP_ENTER:
			focus.release_focus()
			get_viewport().set_input_as_handled()
		return
	if event.echo:
		return
	if _dialog_open():
		if k == KEY_ESCAPE:
			_close_dialogs()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			if _new_box.visible:
				_create()
			elif _load_box.visible:
				_load_pick()
		get_viewport().set_input_as_handled()
		return
	if event.unicode == 63 or (k == KEY_SLASH and event.shift_pressed):
		_cheat_box.visible = not _cheat_box.visible
		get_viewport().set_input_as_handled()
		return
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	match k:
		KEY_ESCAPE:
			if _cheat_box.visible:
				_cheat_box.visible = false
			elif _playing:
				_toggle_play()
			else:
				_back()
		KEY_F3:
			_back()
		KEY_SPACE:
			_toggle_play()
		KEY_LEFT:
			if ctrl:
				_move_frame(-1)
			else:
				_select(_sel - 1)
		KEY_RIGHT:
			if ctrl:
				_move_frame(1)
			else:
				_select(_sel + 1)
		KEY_DELETE, KEY_BACKSPACE, KEY_MINUS, KEY_KP_SUBTRACT:
			_remove_frame()
		KEY_INSERT, KEY_EQUAL, KEY_KP_ADD:
			_add_frame()
		KEY_M:
			_tool("mirror")
		KEY_HOME:
			_home()
		KEY_Z:
			if ctrl:
				_undo_step()
		KEY_Y:
			if ctrl:
				_redo_step()
		KEY_S:
			if ctrl:
				_save()
		_:
			return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty_v and not _frames.is_empty():
		PoseAnim.write(_name, _frames, "auto")


# Back to the game: an auto version first, so nothing in hand is lost.
func _back() -> void:
	if _dirty_v and not _frames.is_empty():
		print(PoseAnim.write(_name, _frames, "auto"))
	get_tree().change_scene_to_file("res://main.tscn")


# --- Files ---

func _save() -> void:
	say(PoseAnim.write(_name, _frames, "saved"))
	_dirty = false
	_dirty_v = false
	_autosave_t = 0.0
	var vs := PoseAnim.versions(_name)
	_version = int(vs[0].n) if not vs.is_empty() else 0
	_version_kind = "saved"
	_refresh_file()


func _refresh_file() -> void:
	if _file_label == null:
		return
	_name_label.text = _name + ("*" if _dirty else "")
	var v := ("v%d %s" % [_version, _version_kind]) if _version > 0 else "no version yet"
	_file_label.text = "%s · %s" % [_name, v]
	var head := PoseAnim.exists(_name)
	_file_note.text = ("the game plays poses/%s.json" % _name if head else "no head yet: Save writes poses/%s.json for the game" % _name) \
			+ (" · edits unsaved" if _dirty else "")
	if _frames_label:
		_frames_label.text = _frames_text()


func _frames_text() -> String:
	return "%d frames · %.2f s" % [_frames.size(), PoseAnim.total(_frames)]


# --- Building the strip ---

func _build_strip() -> void:
	_strip_panel = PanelContainer.new()
	_strip_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_strip_panel.offset_bottom = STRIP_H
	_strip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip_panel.add_theme_stylebox_override("panel", _flat(PANEL_BG, EDGE, 0, 0, 14, 8))
	_ui.add_child(_strip_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_strip_panel.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	head.add_child(_label("FRAMES", 11, DIM))
	_frames_label = _label("", 11, ACCENT)
	head.add_child(_frames_label)
	var hint := _label("click a card to edit it · + adds a copy after · Space plays · ? keys", 11, DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(hint)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(0.0, FrameCard.H + 12.0)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_scroll)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 6)
	_scroll.add_child(_strip)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	left.add_child(srow)
	_scrub = _slider(0.0, 1.0, 0.001, 0.0)
	_scrub.value_changed.connect(_on_scrub)
	srow.add_child(_scrub)
	_time_label = _label("0.00 / 0.00 s", 11, INK)
	_time_label.custom_minimum_size = Vector2(100.0, 0.0)
	srow.add_child(_time_label)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 4)
	right.add_child(r1)
	r1.add_child(_button("+ Add", _add_frame))
	r1.add_child(_button("- Remove", _remove_frame))
	r1.add_child(_button("<", func() -> void: _move_frame(-1)))
	r1.add_child(_button(">", func() -> void: _move_frame(1)))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	right.add_child(r2)
	_play_b = _button("Play", _toggle_play)
	_play_b.custom_minimum_size = Vector2(80.0, 30.0)
	_play_b.add_theme_stylebox_override("normal", _flat(ACCENT, ACCENT, 1))
	_play_b.add_theme_stylebox_override("hover", _flat(ACCENT.lightened(0.1), ACCENT, 1))
	_play_b.add_theme_stylebox_override("pressed", _flat(ACCENT.darkened(0.1), ACCENT, 1))
	_play_b.add_theme_color_override("font_color", DARK)
	_play_b.add_theme_color_override("font_hover_color", DARK)
	_play_b.add_theme_color_override("font_pressed_color", DARK)
	r2.add_child(_play_b)
	_loop_c = _check("Loop", true)
	_loop_c.toggled.connect(func(on: bool) -> void: _loop = on)
	r2.add_child(_loop_c)
	_rev_c = _check("Reverse (the curl)", false)
	_rev_c.toggled.connect(func(on: bool) -> void: _reverse = on)
	r2.add_child(_rev_c)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 8)
	right.add_child(r3)
	r3.add_child(_label("Speed", 11, DIM))
	var speed := _slider(0.1, 2.0, 0.1, 1.0)
	speed.custom_minimum_size = Vector2(140.0, 0.0)
	speed.value_changed.connect(func(v: float) -> void:
		_speed = v
		_speed_label.text = "%.1fx" % v)
	r3.add_child(speed)
	_speed_label = _label("1.0x", 11, INK)
	r3.add_child(_speed_label)


func _rebuild_cards() -> void:
	for c in _cards:
		_strip.remove_child(c)
		c.queue_free()
	_cards.clear()
	for i in _frames.size():
		var c := FrameCard.new()
		c.index = i
		c.frame = _frames[i]
		c.radii = Gecko.RADII
		c.selected = i == _sel
		c.picked.connect(_select)
		_strip.add_child(c)
		_cards.append(c)
	_frames_label.text = _frames_text()
	if _sel < _cards.size():
		_scroll.ensure_control_visible.call_deferred(_cards[_sel])


func _refresh_frame_card() -> void:
	if _frame_title == null or _frames.is_empty():
		return
	var f := _frame()
	_frame_title.text = "Frame %d of %d" % [_sel + 1, _frames.size()]
	_dur_spin.set_value_no_signal(float(f.dur))
	_ease_opt.select(PoseAnim.EASES.find(String(f.ease)))
	_shut_c.set_pressed_no_signal(bool(f.get("shut", false)))


# --- Building the panel ---

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_top = STRIP_H
	_panel.offset_right = PANEL_W
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _flat(PANEL_BG, EDGE, 0, 0))
	_ui.add_child(_panel)
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

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_label("Poses", 15, BRIGHT))
	_name_label = _label("", 13, ACCENT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	head.add_child(_button("Undo", _undo_step))
	head.add_child(_button("Redo", _redo_step))
	var hint := _label("F3 or Esc back to the game · ? keys · wheel zoom · MMB pan", 11, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(hint)

	var fc := _card(col, "Frame")
	_frame_title = _label("", 13, BRIGHT)
	fc.add_child(_frame_title)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	fc.add_child(drow)
	var dl := _label("Seconds to the next", 11, DIM)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(dl)
	_dur_spin = SpinBox.new()
	_dur_spin.min_value = DUR_MIN
	_dur_spin.max_value = DUR_MAX
	_dur_spin.step = 0.02
	_dur_spin.value = PoseAnim.DUR_DEFAULT
	_dur_spin.custom_minimum_size = Vector2(90.0, 0.0)
	_dur_spin.add_theme_font_size_override("font_size", 12)
	_dur_spin.value_changed.connect(_set_dur)
	drow.add_child(_dur_spin)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 8)
	fc.add_child(erow)
	var el := _label("Ease into the next", 11, DIM)
	el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	erow.add_child(el)
	_ease_opt = OptionButton.new()
	for e in PoseAnim.EASES:
		_ease_opt.add_item(String(e))
	_ease_opt.focus_mode = Control.FOCUS_NONE
	_ease_opt.add_theme_font_size_override("font_size", 12)
	_ease_opt.item_selected.connect(func(i: int) -> void: _set_ease(String(PoseAnim.EASES[i])))
	erow.add_child(_ease_opt)
	_shut_c = _check("Eye shut (asleep)", false)
	_shut_c.toggled.connect(func(on: bool) -> void:
		if bool(_frame().get("shut", false)) != on:
			_snapshot()
			_frame().shut = on
			_changed())
	fc.add_child(_shut_c)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	fc.add_child(grid)
	for pair in [["Standing", "standing"], ["Mirror (M)", "mirror"], ["Even links", "even"], ["Feet down", "feet"], ["Copy previous", "prev"], ["Copy next", "next"], ["Eye to look", "eye"]]:
		var what: String = pair[1]
		var b := _button(String(pair[0]), func() -> void: _tool(what))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	var tnote := _label("Standing: the rest pose from the game. Even links: every link back to 8 px. Feet down: the feet onto the floor where they are. Eye to look: the eye rides with the look again.", 11, DIM)
	tnote.autowrap_mode = TextServer.AUTOWRAP_WORD
	fc.add_child(tnote)

	var hc := _card(col, "Handles")
	_lock_c = _check("A dragged point pulls the chain (Shift: alone)", true)
	_lock_c.toggled.connect(func(on: bool) -> void: _lock = on)
	hc.add_child(_lock_c)
	_onion_c = _check("Onion skin: before blue, after orange", true)
	_onion_c.toggled.connect(func(on: bool) -> void:
		_onion = on
		_overlay.queue_redraw())
	hc.add_child(_onion_c)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	hc.add_child(prow)
	var pl := _label("Pixel grid", 11, DIM)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(pl)
	var px := OptionButton.new()
	px.add_item("1 px (the game)", 1)
	px.add_item("2 px (the rock's)", 2)
	px.focus_mode = Control.FOCUS_NONE
	px.add_theme_font_size_override("font_size", 12)
	px.item_selected.connect(func(i: int) -> void: _blobs.set_pixel_size(float(px.get_item_id(i))))
	prow.add_child(px)
	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 8)
	hc.add_child(zrow)
	_zoom_label = _label("zoom %.1fx" % _zoom, 11, INK)
	_zoom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zrow.add_child(_zoom_label)
	zrow.add_child(_button("Home", _home))

	var file := _card(col, "File")
	_file_label = _label("", 13, BRIGHT)
	file.add_child(_file_label)
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
	_file_note = _label("", 11, DIM)
	_file_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	file.add_child(_file_note)

	var gc := _card(col, "Game")
	var gnote := _label("The file named wake is the wake-up: the panel's Wake plays it forwards, Curl backwards and holds the first frame asleep, a key wakes it. The last frame should be the standing pose: the physics takes the body from there.", 11, DIM)
	gnote.autowrap_mode = TextServer.AUTOWRAP_WORD
	gc.add_child(gnote)
	gc.add_child(_button("Back to the game (F3)", _back))

	_status = _label("", 12, INK)
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = PANEL_W + 16.0
	_status.offset_right = -16.0
	_status.offset_top = -30.0
	_status.offset_bottom = -8.0
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_status)
	_toast = _label("", 12, INK)
	_toast.position = Vector2(PANEL_W + 16.0, STRIP_H + 12.0)
	_toast.add_theme_stylebox_override("normal", _flat(Color(0.08, 0.09, 0.1, 0.92), EDGE, 1, 4, 10, 6))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_ui.add_child(_toast)


# The panel grows past PANEL_W to its content: the toast and the status
# line start clear of it (after the first layout).
func _fit_to_panel() -> void:
	var w := maxf(_panel.size.x, PANEL_W) + 16.0
	_toast.position.x = w
	_status.offset_left = w


func say(text: String) -> void:
	if text == "":
		return
	_toast.text = text
	_toast.visible = true
	_toast_t = TOAST_S
	print("POSE: " + text)


func _card(col: VBoxContainer, title: String) -> VBoxContainer:
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
	v.add_child(_label(title.to_upper(), 11, DIM))
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


# --- The dialogs: New, Load, the cheat sheet ---

func _build_dialogs() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_ui.add_child(_dim)

	_new_box = _dialog(380.0)
	var nv := _new_box.get_child(0) as VBoxContainer
	nv.add_child(_label("New animation", 15, BRIGHT))
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
	lhead.add_child(_label("poses/ · a version is a .json of frames", 11, DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.custom_minimum_size = Vector2(0.0, 240.0)
	lv.add_child(cols)
	var lc := VBoxContainer.new()
	lc.custom_minimum_size = Vector2(200.0, 0.0)
	lc.add_theme_constant_override("separation", 6)
	cols.add_child(lc)
	lc.add_child(_label("ANIMATIONS", 11, DIM))
	_load_list = _list()
	_load_list.item_selected.connect(func(_i: int) -> void: _fill_versions())
	lc.add_child(_load_list)
	var vc := VBoxContainer.new()
	vc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vc.add_theme_constant_override("separation", 6)
	cols.add_child(vc)
	_load_vlabel = _label("VERSIONS", 11, DIM)
	vc.add_child(_load_vlabel)
	_load_versions = _list()
	_load_versions.item_selected.connect(func(i: int) -> void:
		_load_b.text = ("Load v%d" % int(_load_vdata[i].n)) if i < _load_vdata.size() else "Load the head")
	vc.add_child(_load_versions)
	var lrow := HBoxContainer.new()
	lrow.alignment = BoxContainer.ALIGNMENT_END
	lrow.add_theme_constant_override("separation", 6)
	lv.add_child(lrow)
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
	_ui.add_child(box)
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


func _dialog_open() -> bool:
	return _dim != null and _dim.visible


func _close_dialogs() -> void:
	_new_box.visible = false
	_load_box.visible = false
	_dim.visible = false


func _open_new() -> void:
	_stop_play()
	_cheat_box.visible = false
	_dim.visible = true
	_new_box.visible = true
	_new_name.text = ""
	_new_info.text = "Starts an animation of one standing frame under this name, its first version and head written." \
			+ (" The edits in hand to %s are written as an auto version first." % _name if _dirty_v else "")
	_new_name.grab_focus()


func _create() -> void:
	var name := _new_name.text.strip_edges().to_lower()
	if name == "" or not name.is_valid_filename() or name.contains(" ") or name.contains("."):
		say("a name of letters, digits, - and _ first")
		return
	if PoseAnim.exists(name) or not PoseAnim.versions(name).is_empty():
		say("there is an animation %s already: pick another name, or load it" % name)
		return
	_close_dialogs()
	if _dirty_v and not _frames.is_empty():
		print(PoseAnim.write(_name, _frames, "auto"))
	_name = name
	_take([PoseAnim.standing()], [])
	_save()
	say("new animation %s: %s" % [name, _file_label.text])


func _open_load() -> void:
	_stop_play()
	_cheat_box.visible = false
	_dim.visible = true
	_load_box.visible = true
	_load_entries = PoseAnim.entries()
	_load_list.clear()
	var sel := 0
	for i in _load_entries.size():
		var e: Dictionary = _load_entries[i]
		_load_list.add_item("%s   %s%s" % [e.name, ("%d versions" % int(e.versions)) if int(e.versions) > 0 else "", "" if e.head else "   (no head)"])
		if e.name == _name:
			sel = i
	if _load_entries.is_empty():
		_load_vlabel.text = "VERSIONS"
		_load_versions.clear()
		_load_b.disabled = true
		return
	_load_b.disabled = false
	_load_list.select(sel)
	_fill_versions()


func _fill_versions() -> void:
	_load_versions.clear()
	_load_vdata = []
	var sel := _load_list.get_selected_items()
	if sel.is_empty():
		return
	var e: Dictionary = _load_entries[sel[0]]
	_load_vlabel.text = "VERSIONS OF %s · LATEST FIRST" % String(e.name).to_upper()
	_load_vdata = PoseAnim.versions(e.name)
	if e.head:
		_load_versions.add_item("the head, what the game plays")
	for v in _load_vdata:
		_load_versions.add_item("v%d   %s   %s" % [int(v.n), String(v.saved_at).replace("T", " "), String(v.kind)])
	if _load_versions.item_count > 0:
		_load_versions.select(0)
		_load_b.text = "Load the head" if e.head else ("Load v%d" % int(_load_vdata[0].n))


func _load_pick() -> void:
	var sel := _load_list.get_selected_items()
	if sel.is_empty():
		return
	var e: Dictionary = _load_entries[sel[0]]
	_close_dialogs()
	if _dirty_v and not _frames.is_empty():
		print(PoseAnim.write(_name, _frames, "auto"))
	var vs := _load_versions.get_selected_items()
	var row: int = vs[0] if not vs.is_empty() else 0
	var vi := row - (1 if e.head else 0)
	var frames: Array
	var what: String
	if vi < 0 or vi >= _load_vdata.size():
		frames = PoseAnim.load_head(String(e.name))
		what = "the head of %s" % e.name
	else:
		frames = PoseAnim.load_version(String(e.name), String(_load_vdata[vi].file))
		what = "%s v%d" % [e.name, int(_load_vdata[vi].n)]
	if frames.is_empty():
		say("cannot read " + what)
		return
	_name = String(e.name)
	_take(frames, PoseAnim.versions(_name))
	say("loaded %s, %d frames" % [what, frames.size()])


func _build_cheat() -> void:
	_cheat_box = _dialog(640.0)
	var v := _cheat_box.get_child(0) as VBoxContainer
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label("Keys and the mouse", 15, BRIGHT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_label("? or Esc closes", 11, DIM))
	for section in CHEAT:
		v.add_child(_label(String(section[0]).to_upper(), 11, DIM))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 3)
		v.add_child(grid)
		for row in section[1]:
			var k := _label(String(row[0]), 12, ACCENT)
			k.custom_minimum_size = Vector2(170.0, 0.0)
			grid.add_child(k)
			grid.add_child(_label(String(row[1]), 12, INK))
