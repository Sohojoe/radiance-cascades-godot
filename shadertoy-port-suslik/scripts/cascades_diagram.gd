extends TextureRect

#var image_size : Vector2i = Vector2i(128, 128)

@export var bilinearFixEnabled:bool = true
@export var forkingFixEnabled:bool = false   

var shader_file_names = {
	"cascades_diagram": "res://fluid_simulation/shaders/cascades_diagram.glsl",
}

var rd: RenderingDevice
var pipelines = {}
var shaders = {}

var consts_buffer
var numX: int
var numY: int

var output_texture
var output_tex_uniform
# @onready var compute_texture: TextureRect = $compute_texture
@export var texture_rect: TextureRect

func _ready():
	setup()

func _process(_delta):
	# if the control is disabled, don't run the simulation
	if not is_visible_in_tree():
		return
	simulate()


func set_data(data : PackedByteArray):
	var image := Image.create_from_data(numX, numY, false, Image.FORMAT_RGBAF, data)
	texture.update(image)

func setup():
	numX = int(size.x)
	numY = int(size.y)
	var image = Image.create(numX, numY, false, Image.FORMAT_RGBAF)
	var image_texture = ImageTexture.create_from_image(image)
	texture = image_texture

	rd = RenderingServer.create_local_rendering_device()

	var consts_buffer_bytes := PackedInt32Array([0]).to_byte_array()
	# consts_buffer_bytes.append_array(PackedFloat32Array([h, h2]).to_byte_array())
	consts_buffer_bytes.resize(ceil(consts_buffer_bytes.size() / 16.0) * 16)
	consts_buffer = rd.storage_buffer_create(consts_buffer_bytes.size(), consts_buffer_bytes)


	var fmt := RDTextureFormat.new()
	fmt.width = numX
	fmt.height = numY
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view := RDTextureView.new()
	var output_image := Image.create(numX, numY, false, Image.FORMAT_RGBAF)
	output_texture = rd.texture_create(fmt, view, [output_image.get_data()])
	output_tex_uniform = RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 1
	output_tex_uniform.add_id(output_texture)

	for key in shader_file_names.keys():
		var file_name = shader_file_names[key]
		var shader_file = load(file_name)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		var shader = rd.shader_create_from_spirv(shader_spirv)
		shaders[key] = shader
		pipelines[key] = rd.compute_pipeline_create(shader)


func simulate():
	#--- CPU -> GPU
	# n/a

	#--- GPU work
	cascades_diagram()

	# GPU -> CPU
	rd.submit()
	rd.sync()
	var byte_data : PackedByteArray = rd.texture_get_data(output_texture, 0)
	set_data(byte_data)


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
	rd.compute_list_dispatch(compute_list, int(ceil(numX / 16.0)), int(ceil(numY / 16.0)), 1)

#--- shader functions
func cascades_diagram():
	#var mouse_position = get_viewport().get_mouse_position()
	var mouse_position =get_local_mouse_position()
	var pc_bytes := PackedVector2Array([size, mouse_position]).to_byte_array()
	var mouse_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	pc_bytes.append_array(PackedInt32Array([
			int(mouse_held),
			int(bilinearFixEnabled), int(forkingFixEnabled)
		]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 32.0) * 32)
	
	var shader_name = "cascades_diagram"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create(
		[consts_buffer_uniform, output_tex_uniform], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()
