# Blob layer: metaball rendering for chain creatures. Two offscreen
# viewports at the sim's render resolution. The density viewport sums
# soft circle splats additively. The color viewport holds flat circles
# in each creature's color. A screen sprite runs metaball.gdshader over
# both and upscales with nearest filtering, so blobs sit on a pixel grid
# of pixel_sz world units: 2 px by default, twice as fine as the
# terrain's, or 4 px to share the rock's grid (keys 1 and 2 in main.gd).
#
# Usage per frame: set_blobs([[pos, radius, color], ...]).
# set_pixel_size(sz) switches the grid at runtime.
extends Node2D

const WORLD_W := 1920
const WORLD_H := 1080
const PIXEL_SZ_FINE := 2.0      # The gecko reads at 2 px pixels over 4 px rock
const PIXEL_SZ_COARSE := 4.0    # The old look: the gecko shares the rock's grid
const SPLAT_SCALE := 1.6     # Splat draw radius over the body radius
const SPLAT_TEX_SIZE := 64

var _density_vp: SubViewport
var _color_vp: SubViewport
var _density_canvas: Node2D
var _color_canvas: Node2D
var _screen: Sprite2D
var _splat_tex: ImageTexture
var _blobs: Array = []
var pixel_sz := PIXEL_SZ_FINE


func _ready() -> void:
	_splat_tex = _make_splat_texture()
	_density_vp = _make_viewport()
	_color_vp = _make_viewport()
	add_child(_density_vp)
	add_child(_color_vp)

	_density_canvas = Node2D.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_density_canvas.material = add_mat
	_density_canvas.draw.connect(_draw_density)
	_density_vp.add_child(_density_canvas)

	_color_canvas = Node2D.new()
	_color_canvas.draw.connect(_draw_color)
	_color_vp.add_child(_color_canvas)

	_screen = Sprite2D.new()
	_screen.texture = _density_vp.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.centered = false
	_screen.scale = Vector2(pixel_sz, pixel_sz)
	_screen.z_index = 5
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/metaball.gdshader")
	mat.set_shader_parameter("color_tex", _color_vp.get_texture())
	_screen.material = mat
	add_child(_screen)


func set_blobs(blobs: Array) -> void:
	_blobs = blobs
	_density_canvas.queue_redraw()
	_color_canvas.queue_redraw()


# Switch the blob grid: both viewports resize and the screen sprite
# rescales so the layer still covers the world.
func set_pixel_size(sz: float) -> void:
	if sz == pixel_sz:
		return
	pixel_sz = sz
	var size := Vector2i(int(WORLD_W / sz), int(WORLD_H / sz))
	_density_vp.size = size
	_color_vp.size = size
	_screen.scale = Vector2(sz, sz)
	_density_canvas.queue_redraw()
	_color_canvas.queue_redraw()


func _make_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(WORLD_W / pixel_sz), int(WORLD_H / pixel_sz))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	return vp


# Soft kernel: (1 - (r/R)^2)^2, white with full alpha so the additive
# blend adds the kernel value to every color channel.
func _make_splat_texture() -> ImageTexture:
	var n := SPLAT_TEX_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(x - c, y - c).length() / c
			var f := 0.0
			if r < 1.0:
				f = (1.0 - r * r)
				f = f * f
			img.set_pixel(x, y, Color(f, f, f, 1.0))
	return ImageTexture.create_from_image(img)


func _draw_density() -> void:
	for blob in _blobs:
		var pos: Vector2 = blob[0] / pixel_sz
		var r: float = blob[1] / pixel_sz * SPLAT_SCALE
		var rect := Rect2(pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		_density_canvas.draw_texture_rect(_splat_tex, rect, false)


func _draw_color() -> void:
	for blob in _blobs:
		var pos: Vector2 = blob[0] / pixel_sz
		var r: float = blob[1] / pixel_sz * SPLAT_SCALE
		_color_canvas.draw_circle(pos, r, blob[2])
