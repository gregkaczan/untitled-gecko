# The drawn creatures and threads (worms, jellyfish, strands) on the
# GPU: each is a few textured quads (a worm's sprite along its body, a
# strand's along its rope) or one sprite (a jellyfish), drawn into an
# offscreen viewport a pixel a sim cell, so the art lands on the world's
# 2 px grid, and the viewport laid over the world with nearest
# filtering. The CPU only hands over a few dozen quads a creature a
# frame; drawn a pixel at a time from script they cost several ms.
# A pixel in the water takes the water's hue (critter_layer.gdshader,
# from the sim's cell classes, sim.gd cells_tex).
extends Node2D

var _vp: SubViewport
var _canvas: Node2D
var _screen: Sprite2D


func setup(cell: float, w: int, h: int, draw_fn: Callable) -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(w, h)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_canvas = Node2D.new()
	_canvas.scale = Vector2(1.0 / cell, 1.0 / cell)   # Drawn in world px, a viewport pixel a cell
	_canvas.draw.connect(func() -> void: draw_fn.call(_canvas))
	_vp.add_child(_canvas)
	_screen = Sprite2D.new()
	_screen.texture = _vp.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.centered = false
	_screen.scale = Vector2(cell, cell)
	_screen.z_index = 1
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/critter_layer.gdshader")
	_screen.material = mat
	add_child(_screen)


func set_cells_tex(tex: Texture2D) -> void:
	var mat := _screen.material as ShaderMaterial
	mat.set_shader_parameter("cells_tex", tex)
	mat.set_shader_parameter("water_tint", tex != null)


func redraw() -> void:
	if _canvas:
		_canvas.queue_redraw()
