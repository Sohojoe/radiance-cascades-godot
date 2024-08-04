extends TextureRect

#var image_size : Vector2i = Vector2i(128, 128)

@export var num_cascades:int = 6
@export var cascade_size:Vector2i = Vector2i(1024, 1024)
@export var brush_type:  int = 0
@export var clear_screen: int = 0
@export_range(0, 5, .1) var merge_fix: int = 4

@onready var ui_output: Label = $CanvasLayer/MarginContainer/HBoxContainer/Panel/VBoxContainer/output

var shader_file_names = {
	"buffer_b": "res://shaders/radiance_cascades_buffer_b.glsl",
	"cube_a": "res://shaders/radiance_cascades_cube_a.glsl",
	"image": "res://shaders/radiance_cascades_image.glsl",
}

var rd: RenderingDevice
var pipelines = {}
var shaders = {}

var consts_buffer
var numX: int
var numY: int

var iMouse: Vector4 = Vector4.ZERO
var mouseA: Vector4 = Vector4.ZERO
var mouseB: Vector4 = Vector4.ZERO
var mouseC: Vector4 = Vector4.ZERO
var iFrame: int = 0
var iTime: float = 0.0

var emissivity_texture
var emissivity_tex_uniform
var cascades_texture_0
var cascades_tex_uniform_0
var cascades_texture_1
var cascades_tex_uniform_1
var cascades_texture_2
var cascades_tex_uniform_2
var cascades_texture_3
var cascades_tex_uniform_3
var cascades_texture_4
var cascades_tex_uniform_4
var cascades_texture_5
var cascades_tex_uniform_5

var output_texture
var output_tex_uniform
# @onready var compute_texture: TextureRect = $compute_texture
@export var texture_rect: TextureRect

func _ready():
	iFrame = 0
	iTime = 0.0
	setup()

func _process(delta):
	# if the control is disabled, don't run the simulation
	if not is_visible_in_tree():
		return
	iTime += delta
	simulate(delta)
	var debug_str = " Brush type: "
	if brush_type == 0:
		debug_str += "COLOR"
	elif brush_type == 1:
		debug_str += "WALL"
	else:
		str(brush_type)
	debug_str +=  "\n MERGE_FIX: " + str(merge_fix)
	#ui_output.text = "Frame: " + str(iFrame) + "\nTime: " + str(iTime)
	ui_output.text = debug_str

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


	# create the emissivity texture
	var fmt := RDTextureFormat.new()
	fmt.width = numX
	fmt.height = numY
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view := RDTextureView.new()
	emissivity_texture = rd.texture_create(fmt, view)
	emissivity_tex_uniform = RDUniform.new()
	emissivity_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	emissivity_tex_uniform.binding = 1
	emissivity_tex_uniform.add_id(emissivity_texture)

	# create the cascades texture array
	var fmt2 = RDTextureFormat.new()
	fmt2.width = cascade_size.x
	fmt2.height = cascade_size.y
	fmt2.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt2.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	cascades_texture_0 = rd.texture_create(fmt2, view)
	cascades_texture_1 = rd.texture_create(fmt2, view)
	cascades_texture_2 = rd.texture_create(fmt2, view)
	cascades_texture_3 = rd.texture_create(fmt2, view)
	cascades_texture_4 = rd.texture_create(fmt2, view)
	cascades_texture_5 = rd.texture_create(fmt2, view)
	cascades_tex_uniform_0 = RDUniform.new()
	cascades_tex_uniform_0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_0.binding = 10
	cascades_tex_uniform_0.add_id(cascades_texture_0)
	cascades_tex_uniform_1 = RDUniform.new()
	cascades_tex_uniform_1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_1.binding = 11
	cascades_tex_uniform_1.add_id(cascades_texture_1)
	cascades_tex_uniform_2 = RDUniform.new()
	cascades_tex_uniform_2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_2.binding = 12
	cascades_tex_uniform_2.add_id(cascades_texture_2)
	cascades_tex_uniform_3 = RDUniform.new()
	cascades_tex_uniform_3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_3.binding = 13
	cascades_tex_uniform_3.add_id(cascades_texture_3)
	cascades_tex_uniform_4 = RDUniform.new()
	cascades_tex_uniform_4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_4.binding = 14
	cascades_tex_uniform_4.add_id(cascades_texture_4)
	cascades_tex_uniform_5 = RDUniform.new()
	cascades_tex_uniform_5.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cascades_tex_uniform_5.binding = 15
	cascades_tex_uniform_5.add_id(cascades_texture_5)

	# create the output texture
	var fmt3 = RDTextureFormat.new()
	fmt3.width = numX
	fmt3.height = numY
	fmt3.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt3.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var view3 = RDTextureView.new()
	output_texture = rd.texture_create(fmt3, view3)
	output_tex_uniform = RDUniform.new()
	output_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_uniform.binding = 3
	output_tex_uniform.add_id(output_texture)

	for key in shader_file_names.keys():
		var file_name = shader_file_names[key]
		var shader_file = load(file_name)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		var shader = rd.shader_create_from_spirv(shader_spirv)
		shaders[key] = shader
		pipelines[key] = rd.compute_pipeline_create(shader)


func simulate(delta:float):

	#--- CPU work
	buffer_a_cpu(delta)

	#--- CPU -> GPU
	# n/a

	#--- GPU work
	buffer_b()
	cube_a()
	image_shader()
	# profile_buffer_b()
	# profile_cube_a()
	# profile_image_shader()

	# GPU -> CPU
	rd.submit()
	rd.sync()
	send_image()

	clear_screen = 0
	iFrame += 1
	
func send_image():
	var byte_data : PackedByteArray = rd.texture_get_data(output_texture, 0)
	var image_data := Image.create_from_data(numX, numY, false, Image.FORMAT_RGBAF, byte_data)
	#var byte_data : PackedByteArray = rd.texture_get_data(cascades_texture_0, 0)
	#var image := Image.create_from_data(cascade_size.x, cascade_size.y, false, Image.FORMAT_RGBAF, byte_data)
	texture.update(image_data)

func profile_buffer_b():
	buffer_b()
	rd.submit()
	rd.sync()

func profile_cube_a():
	cube_a()
	rd.submit()
	rd.sync()

func profile_image_shader():
	image_shader()
	rd.submit()
	rd.sync()

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

func dispatch_cascade(compute_list, shader_name, uniform_set, pc_bytes=null):
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[shader_name])
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	if pc_bytes:
				rd.compute_list_set_push_constant(compute_list, pc_bytes, pc_bytes.size())
	rd.compute_list_dispatch(compute_list, int(ceil(cascade_size.x / 16.0)), int(ceil(cascade_size.y / 16.0)), 1)

#--- shader functions
func buffer_a_cpu(delta:float):
# additional input
	if (Input.is_key_pressed(KEY_1)):
		brush_type = 0
	elif (Input.is_key_pressed(KEY_2)):
		brush_type = 1
	# elif (Input.is_key_pressed(KEY_3)):
	# 	brush_type = 2
	if clear_screen == 0:
		clear_screen = int(Input.is_key_pressed(KEY_DELETE)) || int(Input.is_key_pressed(KEY_BACKSPACE))
	else:
		clear_screen = 1
	if (Input.is_key_pressed(KEY_F1)):
		merge_fix = 0
	elif (Input.is_key_pressed(KEY_F2)):
		merge_fix = 1
	elif (Input.is_key_pressed(KEY_F3)):
		merge_fix = 2
	elif (Input.is_key_pressed(KEY_F4)):
		merge_fix = 3
	elif (Input.is_key_pressed(KEY_F5)):
		merge_fix = 4
	elif (Input.is_key_pressed(KEY_F6)):
		merge_fix = 5
	

	
# mouse	
	var RADIUS:float = numY * 0.015
	var FRICTION:float = 0.05
	var mouse_position = get_local_mouse_position()
	var last_mouse = iMouse
	
	iMouse = Vector4(float(mouse_position.x), float(mouse_position.y), 0.0, 0.0)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		iMouse.z = last_mouse.x
		iMouse.w = last_mouse.y

	# the auto intro animation
	# if iMouse == Vector4.ZERO:
	# 	var t = iTime * 3.0
	# 	iMouse.x = cos(3.14159 * t) + sin(0.72834 * t + 0.3)
	# 	iMouse.y = sin(2.781374 * t + 3.47912) + cos(t)
	# 	iMouse.x *= 0.25 + 0.5
	# 	iMouse.y *= 0.25 + 0.5
	# 	iMouse.x *= size.x
	# 	iMouse.y *= size.y
	# 	iMouse.z = MAGIC # intro flag

	mouseA = mouseB
	mouseB = mouseC
	mouseC = iMouse
	# mouseC = Vector4.ZERO
	mouseC.z = iMouse.z
	mouseC.w = iMouse.w

	var dist = Vector2(mouseB.x, mouseB.y).distance_to(Vector2(iMouse.x, iMouse.y))
	if mouseB.z > 0.0 and dist > 0.0:
		var dir = (Vector2(iMouse.x, iMouse.y) - Vector2(mouseB.x, mouseB.y)) / dist
		var _len = max(dist - RADIUS, 0.0)
		var _ease = 1.0 - pow(FRICTION, delta * 10.0)
		mouseC.x = mouseB.x + dir.x * _len * _ease
		mouseC.y = mouseB.y + dir.y * _len * _ease
	else:
		mouseC.x = iMouse.x
		mouseC.y = iMouse.y
		
func buffer_b():
	var pc_bytes := PackedVector4Array([
			iMouse,
			mouseA,
			mouseB,
			mouseC,
		]).to_byte_array()	
	pc_bytes.append_array(PackedInt32Array([
		iFrame,
		brush_type,
		clear_screen,
		]).to_byte_array())
	pc_bytes.append_array(PackedFloat32Array([iTime,]).to_byte_array())
	pc_bytes.append_array(PackedVector2Array([size]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)
	
	var shader_name = "buffer_b"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create(
		[consts_buffer_uniform, emissivity_tex_uniform], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()

func cube_a():

	var compute_list = rd.compute_list_begin()

	var shader_name = "cube_a"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, emissivity_tex_uniform, 
		cascades_tex_uniform_0,
		cascades_tex_uniform_1,
		cascades_tex_uniform_2,
		cascades_tex_uniform_3,
		cascades_tex_uniform_4,
		cascades_tex_uniform_5,
		], 
		shaders[shader_name], 
		0)

	for cascade_index in range(num_cascades-1, -1, -1):
				# int cascade_index; // Current cascade level
				# int num_cascades; // Total number of cascades
				# int cascade_size_x; // Size of each cascade
				# int cascade_size_y; // Size of each cascade
		var pc_bytes := PackedInt32Array([
				cascade_index,
				num_cascades,
				cascade_size.x,
				cascade_size.y,
				merge_fix,
			]).to_byte_array()	
		# pc_bytes.append_array(PackedVector2iArray([cascade_size]).to_byte_array())
		# pc_bytes.append_array(PackedInt32Array([iFrame,]).to_byte_array())
		# pc_bytes.append_array(PackedFloat32Array([iTime,]).to_byte_array())
		pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)
		dispatch_cascade(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()

func  image_shader():
	var pc_bytes := PackedInt32Array([
			num_cascades,
			cascade_size.x,
			cascade_size.y,
		]).to_byte_array()	
	# pc_bytes.append_array(PackedVector2iArray([cascade_size]).to_byte_array())
	# pc_bytes.append_array(PackedInt32Array([iFrame,]).to_byte_array())
	# pc_bytes.append_array(PackedFloat32Array([iTime,]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)

	var shader_name = "image"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, emissivity_tex_uniform, output_tex_uniform,
		cascades_tex_uniform_0,
		cascades_tex_uniform_1,
		cascades_tex_uniform_2,
		cascades_tex_uniform_3,
		cascades_tex_uniform_4,
		cascades_tex_uniform_5,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()
