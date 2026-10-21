# A look at a level: loaded, the light settled, the whole cave shot at
# zoom 0.5 with the light on and off, and close-ups at the game's zoom
# (the spots below), to runs/look/. Run inside the game as a probe:
#
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json GECKO_PROBE=res://tests/look_probe.gd \
#     GECKO_LOOK=showcase GECKO_EDIT=1 xvfb-run -a -s "-screen 0 1920x1080x24" \
#     godot --display-driver x11 --rendering-driver vulkan --audio-driver Dummy --path . --fixed-fps 60
extends Node
var main: Node2D
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var tree := get_tree()
	var name := OS.get_environment("GECKO_LOOK")
	var out := "res://runs/look"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for i in 5:
		await tree.physics_frame
	print("LOOK " + main.load_level(name))
	main._set_debug(false)
	main.set_light(true)
	for i in 150:
		await tree.physics_frame
	var half: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	main.edit_zoom(0.25, half)
	main._cam = Vector2(960.0, 540.0)
	main._cam_target = main._cam
	main._follow()
	main.edit_ghost({})
	await tree.physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/whole_lit.png"))
	main.set_light(false)
	await tree.physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/whole_flat.png"))
	main.set_light(true)
	var spots := {"nook": Vector2(350.0, 640.0), "hall": Vector2(860.0, 540.0), "lake": Vector2(860.0, 760.0), "pit": Vector2(1380.0, 820.0), "climb": Vector2(1480.0, 560.0), "loft": Vector2(1550.0, 270.0)}
	main.edit_zoom(4.0, half)
	for k in spots:
		main._cam = spots[k]
		main._cam_target = main._cam
		main._follow()
		for i in 30:
			await tree.physics_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		main.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/" + k + ".png"))
	tree.quit()
