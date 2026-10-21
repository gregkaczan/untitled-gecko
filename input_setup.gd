# Input actions, registered at runtime so the bindings live in one
# readable place instead of project.godot. Rain World layout: WASD, the
# arrows or the left stick move, Space or the south face button jumps,
# E, Shift or the west face button chews. 1 and 2 pick the gecko's pixel
# grid: 2 px like the rock, or the default 1 px. Tab or F2 opens and
# leaves the map editor, Ctrl+Tab loads the next test scene from
# tests/scenes.json, Shift+Tab goes back to the first cave, F3 opens the
# pose editor (pose_editor.gd) and leaves it.
# B, C and N drop a boulder, a clump of clay or a heap of sand at the
# cursor. In the map editor Ctrl+Z and Ctrl+Y undo and redo, Home
# brings the camera back, [ and ] size the brush. The mouse is
# the gecko's tongue and chew (see gecko.gd), with the brush on Ctrl and
# the middle button.
class_name InputSetup
extends RefCounted


static func ensure_actions() -> void:
	if InputMap.has_action("jump"):
		return
	_key_axis("move_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_key_axis("move_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_key_axis("move_up", [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0)
	_key_axis("move_down", [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add("jump", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add("chew", [_key(KEY_E), _key(KEY_SHIFT), _button(JOY_BUTTON_X)])
	_add("regenerate", [_key(KEY_R)])
	_add("debug_toggle", [_key(KEY_F1)])
	_add("edit_toggle", [_key(KEY_F2), _key(KEY_TAB)])
	_add("pose_editor", [_key(KEY_F3)])
	_add("render_coarse", [_key(KEY_1)])
	_add("render_fine", [_key(KEY_2)])
	_add("scene_next", [_key(KEY_TAB, false, true)])
	_add("scene_main", [_key(KEY_TAB, true)])
	_add("drop_boulder", [_key(KEY_B)])
	_add("drop_clay", [_key(KEY_C)])
	_add("drop_sand", [_key(KEY_N)])
	# The map editor (editor.gd): undo and redo, the camera home, the brush.
	_add("edit_undo", [_key(KEY_Z, false, true)])
	_add("edit_redo", [_key(KEY_Y, false, true)])
	_add("edit_home", [_key(KEY_HOME)])
	_add("brush_up", [_key(KEY_BRACKETRIGHT)])
	_add("brush_down", [_key(KEY_BRACKETLEFT)])


static func _add(action: String, events: Array, deadzone := 0.4) -> void:
	InputMap.add_action(action, deadzone)
	for ev in events:
		InputMap.action_add_event(action, ev)


static func _key_axis(action: String, keys: Array, axis: JoyAxis, value: float) -> void:
	var events: Array = []
	for k in keys:
		events.append(_key(k))
	events.append(_axis(axis, value))
	_add(action, events, 0.25)


static func _key(key: Key, shift := false, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.command_or_control_autoremap = ctrl
	return ev


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev
