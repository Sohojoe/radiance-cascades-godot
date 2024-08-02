extends TextureRect

@export_range(0, 48, .1) var jfa_ray_count: int = 32
@export_range(0, 32, .1) var jfa_raymarch_max_steps:int = 32
@export_range(0, 48, .1) var ray_count: int = 8
@export_range(0, 6.2) var sun_angle:float = 4.2
@export var show_noise: bool = true
@export var show_grain: bool = true
@export var enable_sun: bool = true
# @export var use_temporal_accum: bool = false

@export_range(0, 1468, .1) var raymarch_max_steps:int = 256
@export var accum_radiance: bool = true


@export_range(0, 11, .1) var jfa_passes_count: int = 11

@export var cascade_size = Vector2(1024,1024)

var color = Vector4(1.,1.,0,1)
var from = Vector2(100,100)
var to = Vector2(300,200)
@export_range(1, 15) var radius:float = 5.
var drawing: bool = true

var pens = [
	"#fff6d3", 
	"#f9a875", 
	"#eb6b6f", 
	"#7c3f58", 
	"#000000"]

@onready var simple_ui: CanvasLayer = $simple_ui


var shader_file_names = {
	"draw": "res://shaders/draw.glsl",
	"raymarch": "res://shaders/raymarch.glsl",
	"jump_flood_algorithm": "res://shaders/jump_flood_algorithm.glsl",
	"seed": "res://shaders/seed.glsl",
	"distance": "res://shaders/distance.glsl",
	"jfa_raymarch": "res://shaders/jfa_raymarch.glsl",
	"cube_a": "res://shaders/radiance_cascades_cube_a.glsl",
	"image": "res://shaders/radiance_cascades_image.glsl",
}

var rd: RenderingDevice
var pipelines = {}
var shaders = {}

var consts_buffer

var input_texture
var output_texture
var jfa_texture
var jfa_texture_prev
var distance_texture

var input_tex_in_uniform
var input_tex_out_uniform
var output_tex_out_uniform
var output_tex_in_uniform
var distance_tex_out_uniform
var distance_tex_in_b3_uniform
var jfa_prev_tex_input_uniform
var jfa_tex_out_uniform

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

var frame:int = 0
var time:float = 0.0
var cur_pen_index:int = 0
var display_mode:String 

@export var texture_rect: TextureRect
@export var num_cascades:int = 6
@export_range(0, 5, .1) var merge_fix: int = 1

func _ready():
	frame = 0
	time = 0.0
	set_pen(0)
	setup()

func _process(delta):
	if not is_visible_in_tree():
		return
	simulate(delta)
	time += delta
	if Input.is_key_pressed(KEY_1):
		set_pen(0)
	elif Input.is_key_pressed(KEY_2):
		set_pen(1)
	elif Input.is_key_pressed(KEY_3):
		set_pen(2)
	elif Input.is_key_pressed(KEY_4):
		set_pen(3)
	elif Input.is_key_pressed(KEY_5):
		set_pen(4)


# @export_range(0, 6.2) var sun_angle:float = 4.2
# @export var show_noise: bool = true
# @export var show_grain: bool = true
# @export var enable_sun: bool = true

	if Input.is_action_just_pressed("toggle_1"):
		show_noise = !show_noise
	if Input.is_action_just_pressed("toggle_2"):
		show_grain = !show_grain
	if Input.is_action_just_pressed("toggle_3"):
		enable_sun = !enable_sun
	if Input.is_action_just_pressed("toggle_4"):
		sun_angle += 6.2 / 7.333
		if sun_angle > 6.2:
			sun_angle -= 6.2


	if Input.is_key_pressed(KEY_F5):
		display_mode="draw"
	elif Input.is_key_pressed(KEY_F6):
		display_mode="jfa"
	elif Input.is_key_pressed(KEY_F7):
		display_mode="distance"
	else:
		display_mode="default"
		
	var debug_str = " Pen: " + str(cur_pen_index + 1)
	debug_str +=  "\n Display Mode: " + display_mode
	simple_ui.set_debug_output_text(debug_str)

func setup():
	var image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBAF)
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
	input_texture = rd.texture_create(fmt3, view3)
	output_texture = rd.texture_create(fmt3, view3)
	jfa_texture = rd.texture_create(fmt3, view3)
	jfa_texture_prev = rd.texture_create(fmt3, view3)
	distance_texture = rd.texture_create(fmt3, view3)

	input_tex_in_uniform = RDUniform.new()
	input_tex_in_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_tex_in_uniform.binding = 2
	input_tex_in_uniform.add_id(input_texture)
	input_tex_out_uniform = RDUniform.new()
	input_tex_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_tex_out_uniform.binding = 1
	input_tex_out_uniform.add_id(input_texture)
	
	output_tex_in_uniform = RDUniform.new()
	output_tex_in_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_in_uniform.binding = 2
	output_tex_in_uniform.add_id(output_texture)
	output_tex_out_uniform = RDUniform.new()
	output_tex_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_tex_out_uniform.binding = 1
	output_tex_out_uniform.add_id(output_texture)
	
	distance_tex_out_uniform = RDUniform.new()
	distance_tex_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	distance_tex_out_uniform.binding = 1
	distance_tex_out_uniform.add_id(distance_texture)	
	distance_tex_in_b3_uniform = RDUniform.new()
	distance_tex_in_b3_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	distance_tex_in_b3_uniform.binding = 3
	distance_tex_in_b3_uniform.add_id(distance_texture)

	jfa_prev_tex_input_uniform = RDUniform.new()
	jfa_prev_tex_input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	jfa_prev_tex_input_uniform.binding = 2
	jfa_prev_tex_input_uniform.add_id(jfa_texture_prev)
	jfa_tex_out_uniform = RDUniform.new()
	jfa_tex_out_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	jfa_tex_out_uniform.binding = 1
	jfa_tex_out_uniform.add_id(jfa_texture)

	# create the cascades texture array
	var fmt2 = RDTextureFormat.new()
	fmt2.width = cascade_size.x
	fmt2.height = cascade_size.y
	fmt2.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt2.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var view := RDTextureView.new()
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

	for key in shader_file_names.keys():
		var file_name = shader_file_names[key]
		var shader_file = load(file_name)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		var shader = rd.shader_create_from_spirv(shader_spirv)
		shaders[key] = shader
		pipelines[key] = rd.compute_pipeline_create(shader)

func simulate(_delta:float):
	#--- CPU work
	# n/a

	#--- CPU -> GPU
	# n/a

	#--- GPU work
	draw()
	# raymarch() # non jfa version
	create_seed()
	jump_flood_algorithm()
	create_distance()
	# jfa_raymarch()
	cube_a()
	image_shader()

	# GPU -> CPU
	rd.submit()
	rd.sync()
	if display_mode=="jfa":
		send_image(jfa_texture)
	elif display_mode=="distance":
		send_image(distance_texture)
	elif display_mode=="draw":
		send_image(input_texture)
	else:
		send_image(output_texture)
	
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

func send_image(img_to_show):
	var byte_data : PackedByteArray = rd.texture_get_data(img_to_show, 0)
	var image_data := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, byte_data)
	texture.update(image_data)

func set_pen(index:int):
	var c = Color(pens[index])
	color = Vector4(c.r, c.g, c.b, c.a)
	cur_pen_index = index

func swap_jfa_image():
	var tmp = jfa_texture
	jfa_texture = jfa_texture_prev
	jfa_texture_prev = tmp
	jfa_prev_tex_input_uniform.clear_ids()
	jfa_tex_out_uniform.clear_ids()
	jfa_prev_tex_input_uniform.add_id(jfa_texture_prev)
	jfa_tex_out_uniform.add_id(jfa_texture)



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
		consts_buffer_uniform, input_tex_out_uniform, input_tex_in_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()


func raymarch():
	var pc_bytes := PackedVector2Array([size]).to_byte_array()
	pc_bytes.append_array(PackedInt32Array([ray_count, raymarch_max_steps, show_noise, accum_radiance]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)

	var shader_name = "raymarch"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, output_tex_out_uniform, input_tex_in_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set, pc_bytes)
	rd.compute_list_end()


func create_seed():
	var shader_name = "seed"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, jfa_tex_out_uniform, input_tex_in_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set)
	rd.compute_list_end()


func jump_flood_algorithm():
	var oneOverSize := Vector2.ONE / size
	var skip:bool = jfa_passes_count == 0

	var shader_name = "jump_flood_algorithm"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set

	var compute_list = rd.compute_list_begin()

	var max_dimension = max(size.x, size.y)
	var max_steps = ceil(log(max_dimension) / log(2))
	var passes = clamp(jfa_passes_count, 1, max_steps)
	for i in range(passes-1, -1, -1):
		var uOffset:float = pow(2, i)

		var pc_bytes := PackedVector2Array([oneOverSize]).to_byte_array()
		pc_bytes.append_array(PackedFloat32Array([uOffset]).to_byte_array())
		pc_bytes.append_array(PackedInt32Array([skip]).to_byte_array())
		pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)
		
		swap_jfa_image()
		uniform_set = rd.uniform_set_create([
			consts_buffer_uniform, jfa_tex_out_uniform, jfa_prev_tex_input_uniform,
			], 
			shaders[shader_name], 
			0)			

		dispatch(compute_list, shader_name, uniform_set, pc_bytes)
		
	rd.compute_list_end()
	
func create_distance():
	var shader_name = "distance"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, distance_tex_out_uniform, jfa_prev_tex_input_uniform,
		], 
		shaders[shader_name], 
		0)

	var compute_list = rd.compute_list_begin()
	dispatch(compute_list, shader_name, uniform_set)
	rd.compute_list_end()

func jfa_raymarch():
	var pc_bytes := PackedVector2Array([size]).to_byte_array()
	pc_bytes.append_array(PackedFloat32Array([
		time, 
		sun_angle]).to_byte_array())
	pc_bytes.append_array(PackedInt32Array([
		jfa_ray_count, 
		jfa_raymarch_max_steps, 
		show_noise, 
		show_grain, 
		enable_sun, 
		# use_temporal_accum, 
		]).to_byte_array())
	pc_bytes.resize(ceil(pc_bytes.size() / 16.0) * 16)

	var shader_name = "jfa_raymarch"
	var consts_buffer_uniform = get_uniform(consts_buffer, 0)
	var uniform_set = rd.uniform_set_create([
		consts_buffer_uniform, output_tex_out_uniform, input_tex_in_uniform, distance_tex_in_b3_uniform,
		], 
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
		consts_buffer_uniform, input_tex_in_uniform, distance_tex_in_b3_uniform,
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
		dispatch(compute_list, shader_name, uniform_set, pc_bytes)
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
		#consts_buffer_uniform, emissivity_tex_uniform, output_tex_uniform,
		consts_buffer_uniform, output_tex_out_uniform, input_tex_in_uniform,
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
