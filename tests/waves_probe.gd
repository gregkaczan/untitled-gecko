# A look at the sound ripples (waves.gd): a chew wave beside the gecko
# shot as it grows, the hum seen without listening, then Q held (the
# meerkat stand) and let go. Frames to runs/waves/. Run inside the
# game as a probe:
#
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json GECKO_PROBE=res://tests/waves_probe.gd \
#     xvfb-run -a -s "-screen 0 1920x1080x24" \
#     godot --display-driver x11 --rendering-driver vulkan --audio-driver Dummy --path . --fixed-fps 60
#
# GECKO_SCENE=critters_lab:hold checks a creature turns to a chew behind
# it; tunnel_up_bend shows the rings along the cave. WAVES_LOUD=1 shoots
# a loud look (longer rings with light) to judge their shape by,
# WAVES_STRAIGHT=1 with it the straight circles, WAVES_DUMP=1 prints the
# sound field near the first chew.
extends Node
var main: Node2D
var _out := "res://runs/waves"
var _n := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	if OS.get_environment("GECKO_LOOK") != "":
		print("LOOK " + main.load_level(OS.get_environment("GECKO_LOOK")))
	for i in 150:
		await tree.physics_frame
	var w: Node2D = main.waves
	if OS.get_environment("WAVES_LOUD") != "":
		# A loud look to judge the rings' shape by, not the saved one.
		for k in 2:
			w.look[k].wavelength = 14.0
			w.look[k].glow = 0.5
		w.cave = OS.get_environment("WAVES_STRAIGHT") == ""
		w.apply_look()
	var g: Vector2 = main.gecko.pos
	print("WAVES gecko ", g, " hum source ", w.hum_source(), " creatures ", main._slugs.size() + main.critters.long_slugs.size())
	var cr: Array = main._slugs + main.critters.long_slugs
	if not cr.is_empty():
		# A chew 120 px to one side of a creature: it should turn that way.
		var c = cr[0]
		var at: Vector2 = c.ear() + Vector2(120.0 * -c.dir, 0.0)
		print("WAVES creature at ", c.ear(), " dir ", c.dir, " chew at ", at)
		w.emit_at(at)
		for i in 90:
			await tree.physics_frame
		print("WAVES creature now at ", c.ear(), " dir ", c.dir, " marks ", w._marks.size())
		if w._field:
			var f: RefCounted = w._field
			print("WAVES readback ears ", f.heard_ears.size(), " floats ", f.heard.size(), " at tile 1: ", f.at(0, 1), " waiting ", f._waiting)
	w.emit_at(g + Vector2(60.0, -10.0))
	if OS.get_environment("WAVES_DUMP") != "":
		for i in 20:
			await tree.physics_frame
		_dump(w)
	for i in 8:
		await _shot("chew_%d" % i, 6)
	for i in 60:
		await tree.physics_frame
	w.hum_at = g + Vector2(-500.0, -200.0)
	w.hum_set = true
	w.hum_always = true
	for i in 4:
		await _shot("hum_%d" % i, 8)
	w.hum_always = false
	Input.action_press("listen")
	for i in 10:
		await _shot("listen_%d" % i, 15)
	Input.action_release("listen")
	for i in 6:
		await _shot("down_%d" % i, 15)
	print("WAVES done, ", _n, " frames")
	tree.quit()


func _shot(name: String, ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_out + "/" + name + ".png"))
	print("SHOT %s listen %.2f posing %s t %.2f" % [name, main.waves.listen, main.gecko.posing, main.gecko.pose_time()])
	_n += 1


# The field's tiles 0 and 1 as reached or not, and the distances in
# tile 1 near the wave's source, printed (WAVES_DUMP=1).
func _dump(w: Node2D) -> void:
	print("WAVES along cave ", w.along_cave(), " field ok ", w._field.ok() if w._field else false)
	var rd := RenderingServer.get_rendering_device()
	var data := rd.texture_get_data(w._field._a, 0).to_float32_array()
	var fw: int = w._field.FIELD.x * w._field.TILES_X
	for tile: int in [0, 1]:
		var ox: int = (tile % 4) * 480
		var oy: int = (tile / 4) * 270
		var reached := 0
		var mx := 0.0
		for y in range(0, 270, 3):
			for x in range(0, 480, 3):
				var k := ((oy + y) * fw + ox + x) * 4
				if data[k + 2] >= 0.0:
					reached += 1
					mx = maxf(mx, data[k + 2])
		print("WAVES tile ", tile, " reached ", reached, " of ", 160 * 90, " max base ", mx)
	var src: Vector2 = w._waves[0][0] / 4.0 if not w._waves.is_empty() else Vector2.ZERO
	for d: int in [0, 5, 10, 20, 40]:
		var x := int(src.x) + d
		var y := int(src.y)
		var k := (y * fw + 480 + x) * 4
		print("WAVES +%d cells: corner %.1f,%.1f base %.2f rock %.2f" % [d, data[k], data[k + 1], data[k + 2], data[k + 3]])
