extends TextureRect

# @export var num_cascades:int = 6
# @export var cascade_size:Vector2i = Vector2i(1024, 1024)
# @export var brush_type:  int = 0
# @export var clear_screen: int = 0
# @export_range(0, 5, .1) var merge_fix: int = 4

@export_range(0, 64, .1) var ray_count: int = 8
@export_range(0, 1468, .1) var max_steps:int = 256
@export var show_noise: bool = true
@export var accum_radiance: bool = true


var color = Vector4(1.,1.,0,1)
var from = Vector2(100,100)
var to = Vector2(300,200)
@export_range(1, 15) var radius:float = 5.
var drawing: bool = true

var pens = ["#7c3f58", "#eb6b6f", "#f9a875", "#fff6d3", "#000000"]

#@onready var ui_output: Label = $CanvasLayer/MarginContainer/HBoxContainer/Panel/VBoxContainer/output


var shader_file_names = {
	#"pt1": "res://shaders/pt1.glsl",
	"draw": "res://shaders/draw.glsl",
	"raymarch": "res://shaders/raymarch.glsl",
}

var rd: RenderingDevice
var pipelines = {}
var shaders = {}

var consts_buffer

var draw_texture
var output_texture
var draw_input_tex_uniform
var draw_output_tex_uniform
var raymarch_input_tex_uniform
var raymarch_output_tex_uniform


var frame:int = 0

@export var texture_rect: TextureRect


func _ready():
	frame = 0
	set_pen(3)
	setup()

func _process(delta):
	if not is_visible_in_tree():
		return
	simulate(delta)
	if Input.is_key_pressed(KEY_1):
		set_pen(3)
	elif Input.is_key_pressed(KEY_2):
		set_pen(2)
	elif Input.is_key_pressed(KEY_3):
		set_pen(1)
	elif Input.is_key_pressed(KEY_4):
		set_pen(0)
	elif Input.is_key_pressed(KEY_5):
		set_pen(4)

func setup():
	var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	var image_texture = ImageTexture.create_from_image(image)
	texture = image_texture

	rd = RenderingServer.create_local_rendering_device()

	var consts_buffer_bytes := PackedInt32Array([0]).to_byte_array()
	# consts_buffer_bytes.append_array(PackedFloat32Array([h, h2]).to_byte_array())
	consts_buffer_bytes.resize(ceil(consts_buffer_bytes.size() / 16.0) * 16)
	consts_buffer = rd.storage_buffer_create(consts_buffer_bytes.size(), consts_buffer_bytes)

	# create the output texture
	var fmt3 = RDTextureFormat.new()
	fmt3.width = size.x
	fmt3.height = size.y
	fmt3.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt3.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view3 = RDTextureView.new()
	draw_texture = rd.texture_create(fmt3, view3)
	output_texture = rd.texture_create(fmt3, view3)

	draw_input_tex_uniform = RDUniform.new()
	draw_input_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	draw_input_tex_uniform.binding = 2
	draw_input_tex_uniform.add_id(draw_texture)
	draw_output_tex_uniform = RDUniform.new()
	draw_output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	draw_output_tex_uniform.binding = 1
	draw_output_tex_uniform.add_id(draw_texture)

	raymarch_input_tex_uniform = RDUniform.new()
	raymarch_input_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	raymarch_input_tex_uniform.binding = 2
	raymarch_input_tex_uniform.add_id(draw_texture)
	raymarch_output_tex_uniform = RDUniform.new()
	raymarch_output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	raymarch_output_tex_uniform.binding = 1
	raymarch_output_tex_uniform.add_id(output_texture)

	for key in shader_file_names.keys():
		var file_name = shader_file_names[key]
		var shader_file = load(file_name)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		var shader = rd.shader_create_from_spirv(shader_spirv)
		shaders[key] = shader
		pipelines[key] = rd.compute_pipeline_create(shader)

func simulate(delta:float):
	#--- CPU work
	# n/a

	#--- CPU -> GPU
	# n/a

	#--- GPU work
	draw()
	raymarch()

	# GPU -> CPU
	rd.submit()
	rd.sync()
	send_image()
	
	frame += 1 

#--- helper functions
func get_uniform(buffer, binding: int):
	var rd_uniform = RDUniform.new()
	rd_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	rd_uniform.binding = binding
	rd_uniform.add_id(buffer)
	return rd_uniform

func dispatch(compute_list, shader_name, uniform_set, pc_bytes=null):
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[shader_name])
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	if pc_bytes:
				rd.compute_list_set_push_constant(compute_list, pc_bytes, pc_bytes.size())
	rd.compute_list_dispatch(compute_list, int(ceil(size.x / 16.0)), int(ceil(size.y / 16.0)), 1)

func send_image():
	var byte_data : PackedByteArray = rd.texture_get_data(output_texture, 0)
	var image_data := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, byte_data)
	texture.update(image_data)

func set_pen(index:int):
	var c = Color(pens[index])
	color = Vector4(c.r, c.g, c.b, c.a)


func draw():
	var mouse_position = get_local_mouse_position()
	from = to
	to = mouse_position
	drawing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var clear_screen = Input.is_key_pressed(KEY_DELETE) || Input.is_key_pressed(KEY_BACKSPACE) || frame == 0    

	var radiusSquared:float = radius * radius;
	var pc_bytes := PackedVector4Array([color]).to_byte_array()
	pc_bytes.append_array(PackedVector2Array([from, to, size]).to_byte_array())
	pc_bytes.append_array(PackedFloat32Array([radiusSquared]).to_byte_array())
	pc_bytes.append_array(PackedInt32Array([drawing, clear_screen]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)

	var shader_name = "draw"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, draw_output_tex_uniform, draw_input_tex_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()


func raymarch():
	var mouse_position = get_local_mouse_position()
	from = to
	to = mouse_position
	drawing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var clear_screen = Input.is_key_pressed(KEY_DELETE) || Input.is_key_pressed(KEY_BACKSPACE) || frame == 0    

	var radiusSquared:float = radius * radius;
	var pc_bytes := PackedVector2Array([size]).to_byte_array()
	pc_bytes.append_array(PackedInt32Array([ray_count, max_steps, show_noise, accum_radiance]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)

	var shader_name = "raymarch"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, raymarch_output_tex_uniform, raymarch_input_tex_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()