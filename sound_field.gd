# The sound field on the GPU (shaders/sound_field.glsl), for waves.gd's
# rings that follow the cave: one tile of an atlas per wave, the hum's
# tile 0, at 4 px cells. Every frame a few passes carry each tile's
# distances a few cells further from its source; the waves shader reads
# the atlas straight from the GPU (a Texture2DRD), and a probe pass
# reads it at the creatures' ears and sends that back without a stall
# (buffer_get_data_async) for the hearing. The world's classes come
# from the sim's per-tick readback (sim.gd cells), uploaded every few
# frames. On the main rendering device, all of it on the render thread.
extends RefCounted

const CELL := 4.0                # World px of a field cell
const FIELD := Vector2i(480, 270)   # Field cells of a tile: the sim's 960 x 540 cells folded 2 x 2
const TILES_X := 4
const TILES_Y := 3
const TILES := TILES_X * TILES_Y
const PASSES := 8                # A frame's passes, even so the result lands back in A: 8 cells a frame, far ahead of any front
const MAX_EARS := 32
const CLS_W := 960
const CLS_H := 540

var texture: Texture2DRD         # The atlas, for the waves shader
var heard_ears: Array = []       # The creatures the last readback was for, in its order
var heard := PackedFloat32Array()   # Per ear and tile: corner x, y (world px), distance (px, below 0 not reached), rock crossed (px)
var water_cost := 1.6
var rock_cost := 6.0

var _rd: RenderingDevice
var _shader: RID
var _pipe: RID
var _probe_shader: RID
var _probe_pipe: RID
var _a: RID
var _b: RID
var _cls: RID
var _seeds: RID
var _ears: RID
var _out: RID
var _set_ab: RID
var _set_ba: RID
var _probe_set: RID
var _ok := false
var _waiting := false            # A readback on its way


func _init() -> void:
	texture = Texture2DRD.new()
	RenderingServer.call_on_render_thread(_create)


func ok() -> bool:
	return _ok


func _create() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	_shader = _load("sound_field")
	_probe_shader = _load("sound_probe")
	if not _shader.is_valid() or not _probe_shader.is_valid():
		return
	_pipe = _rd.compute_pipeline_create(_shader)
	_probe_pipe = _rd.compute_pipeline_create(_probe_shader)
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.width = FIELD.x * TILES_X
	tf.height = FIELD.y * TILES_Y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_a = _rd.texture_create(tf, RDTextureView.new())
	_b = _rd.texture_create(tf, RDTextureView.new())
	var cf := RDTextureFormat.new()
	cf.format = RenderingDevice.DATA_FORMAT_R32_UINT
	cf.width = CLS_W
	cf.height = CLS_H
	cf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_cls = _rd.texture_create(cf, RDTextureView.new())
	var seeds := PackedByteArray()
	seeds.resize(TILES * 16)
	_seeds = _rd.storage_buffer_create(seeds.size(), seeds)
	var ears := PackedByteArray()
	ears.resize(MAX_EARS * 8)
	_ears = _rd.storage_buffer_create(ears.size(), ears)
	var out := PackedByteArray()
	out.resize(MAX_EARS * TILES * 16)
	_out = _rd.storage_buffer_create(out.size(), out)
	_set_ab = _rd.uniform_set_create([_img(0, _a), _img(1, _b), _img(2, _cls), _buf(3, _seeds)], _shader, 0)
	_set_ba = _rd.uniform_set_create([_img(0, _b), _img(1, _a), _img(2, _cls), _buf(3, _seeds)], _shader, 0)
	_probe_set = _rd.uniform_set_create([_img(0, _a), _buf(1, _ears), _buf(2, _out)], _probe_shader, 0)
	texture.texture_rd_rid = _a
	_ok = true


func _load(name: String) -> RID:
	var file := load("res://shaders/%s.glsl" % name) as RDShaderFile
	var spirv := file.get_spirv()
	var err := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err != "":
		push_error("Shader %s: %s" % [name, err])
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _img(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _buf(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


# One frame of the field. seeds: per tile x, y (world px), on, reset;
# cls: the sim's classes to upload, or empty to keep the last; ears:
# the creatures to read the field at (anything with ear()).
func step(seeds: PackedFloat32Array, cls: PackedByteArray, ears: Array) -> void:
	if not _ok:
		return
	var pos := PackedFloat32Array()
	pos.resize(MAX_EARS * 2)
	var list: Array = ears.slice(0, MAX_EARS)
	for i in list.size():
		var e: Vector2 = list[i].ear()
		pos[i * 2] = e.x
		pos[i * 2 + 1] = e.y
	RenderingServer.call_on_render_thread(_step.bind(seeds, cls, pos, list))


func _step(seeds: PackedFloat32Array, cls: PackedByteArray, pos: PackedFloat32Array, list: Array) -> void:
	var sd := seeds.duplicate()
	for t in TILES:
		sd[t * 4] /= CELL
		sd[t * 4 + 1] /= CELL
	_rd.buffer_update(_seeds, 0, TILES * 16, sd.to_byte_array())
	if cls.size() == CLS_W * CLS_H * 4:
		_rd.texture_update(_cls, 0, cls)
	var push := PackedInt32Array([FIELD.x, FIELD.y, TILES_X, TILES, 0, 0, 0, 0]).to_byte_array()
	push.encode_float(16, water_cost)
	push.encode_float(20, rock_cost)
	var probe := not list.is_empty() and not _waiting
	if probe:
		_rd.buffer_update(_ears, 0, pos.size() * 4, pos.to_byte_array())   # Before the list: no updates inside one
	var gx := ceili(FIELD.x * TILES_X / 8.0)
	var gy := ceili(FIELD.y * TILES_Y / 8.0)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	for i in PASSES:
		push.encode_s32(24, 1 if i == 0 else 0)
		_rd.compute_list_bind_uniform_set(cl, _set_ab if i % 2 == 0 else _set_ba, 0)
		_rd.compute_list_set_push_constant(cl, push, push.size())
		_rd.compute_list_dispatch(cl, gx, gy, 1)
		_rd.compute_list_add_barrier(cl)
	if probe:
		var pp := PackedInt32Array([FIELD.x, FIELD.y, TILES_X, TILES, list.size(), 0, 0, 0]).to_byte_array()
		pp.encode_float(20, CELL)
		_rd.compute_list_bind_compute_pipeline(cl, _probe_pipe)
		_rd.compute_list_bind_uniform_set(cl, _probe_set, 0)
		_rd.compute_list_set_push_constant(cl, pp, pp.size())
		_rd.compute_list_dispatch(cl, ceili(list.size() * TILES / 64.0), 1, 1)
	_rd.compute_list_end()
	if probe:
		_waiting = true
		_rd.buffer_get_data_async(_out, func(data: PackedByteArray) -> void:
			heard = data.to_float32_array()
			heard_ears = list
			_waiting = false, 0, list.size() * TILES * 16)


# The readback for one ear and tile: corner, distance, rock; or null.
func at(ear_i: int, tile: int) -> Variant:
	var k := (ear_i * TILES + tile) * 4
	if k + 3 >= heard.size() or heard[k + 2] < 0.0:
		return null
	return [Vector2(heard[k], heard[k + 1]), heard[k + 2], heard[k + 3]]


func free_all() -> void:
	if _rd == null:
		return
	RenderingServer.call_on_render_thread(func() -> void:
		texture.texture_rd_rid = RID()
		for r in [_set_ab, _set_ba, _probe_set, _a, _b, _cls, _seeds, _ears, _out, _pipe, _probe_pipe, _shader, _probe_shader]:
			if r.is_valid():
				_rd.free_rid(r)
		_ok = false)
