extends CanvasLayer

@export_multiline var title_text = ""
@export var ui_is_visible:bool = true
@export var auto_show_delay:float = 3.0


@onready var title: Label = $MarginContainer/HBoxContainer/Panel/VBoxContainer/Title
@onready var output: Label = $MarginContainer/HBoxContainer/Panel/VBoxContainer/output
@onready var fps_label: Label = $MarginContainer/HBoxContainer/Panel/VBoxContainer/fps

var debounce:= false
var auto_mode:= true

var time_since_mouse:= 0.0

func _ready():
	visible = ui_is_visible
	title.text = title_text

func _process(delta):
	do_auto_mode(delta)
	toggle_hide_via_esc()
	var fps = Engine.get_frames_per_second()
	fps_label.text = " FPS: %d" % fps

func set_debug_output_text(text):
	output.text = text

func do_auto_mode(delta):
	if auto_mode == false:
		return

	time_since_mouse += delta

	#if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) || Input.get_last_mouse_screen_velocity() > Vector2.ZERO:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		time_since_mouse = 0.0
		ui_is_visible = false
		visible = ui_is_visible

	if time_since_mouse > auto_show_delay:
		ui_is_visible = true
		visible = ui_is_visible
		
	
func toggle_hide_via_esc():
	if debounce:
		if Input.is_key_pressed(KEY_ESCAPE):
			return
		debounce = false
	
	if (Input.is_key_pressed(KEY_ESCAPE)):
		debounce = true
		ui_is_visible = !ui_is_visible
		visible = ui_is_visible
		time_since_mouse = 0.0
		auto_mode = false
		
