class_name WorkSpot
extends Control

signal worker_ejected(worker_name: String)

var worker_type: String = ""
var stage_name: String = ""
var input_belt: ConveyorBelt = null
var output_belt: ConveyorBelt = null
var factory_zone: Control = null

var is_processing: bool = false
var current_item: Control = null
var process_time: float = 0.0
var elapsed_time: float = 0.0

# Spritesheet animation
var sprite_frames: Array[AtlasTexture] = []
var anim_frame: int = 0
var anim_timer: float = 0.0
const ANIM_FPS := 6.0

# Workstation spritesheet animation
var ws_spritesheet: Texture2D = null
var ws_idle_texture: Texture2D = null
var ws_frames: Array[AtlasTexture] = []
var ws_frame_count: int = 0
var ws_anim_frame: int = 1
var ws_anim_timer: float = 0.0
var ws_anim_fps: float = 6.0

@onready var worker_icon: TextureRect = %WorkerIcon
@onready var name_label: Label = %NameLabel
@onready var speed_label: Label = %SpeedLabel
@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var worker_area: Panel = %WorkerArea


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_display()


func set_workstation_texture(tex: Texture2D) -> void:
	ws_idle_texture = tex
	%WorkstationSprite.texture = tex


func set_workstation_spritesheet(sheet: Texture2D) -> void:
	ws_spritesheet = sheet
	ws_frames.clear()
	ws_frame_count = 0
	if sheet == null:
		return
	var frame_w := 138
	ws_frame_count = int(sheet.get_width() / frame_w)
	for i in ws_frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_w, 0, frame_w, 138)
		ws_frames.append(atlas)
	# Show idle frame from spritesheet
	if ws_frames.size() > 0:
		%WorkstationSprite.texture = ws_frames[0]


func install_worker(type: String) -> void:
	worker_type = type
	_load_sprite_frames()
	_update_display()


func eject_worker() -> String:
	if is_processing:
		return ""
	var old_type := worker_type
	worker_type = ""
	sprite_frames.clear()
	_update_display()
	return old_type


func _update_display() -> void:
	if not is_inside_tree():
		return
	if worker_type.is_empty():
		name_label.text = "EMPTY"
		speed_label.text = "Drag worker here"
		status_label.text = "No worker"
		progress_bar.value = 0
		worker_icon.visible = false
		worker_icon.texture = null
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.3, 0.3, 0.5)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		worker_area.add_theme_stylebox_override("panel", style)
	else:
		var mdata: Dictionary = FactoryData.MACHINES[worker_type]
		name_label.text = worker_type
		speed_label.text = "Ster:x%.1f Cut:x%.1f Pkg:x%.1f" % [
			mdata["sterilize_speed"], mdata["cutting_speed"], mdata["packaging_speed"]
		]
		worker_icon.visible = true
		worker_icon.position = Vector2(-32,-40);
		# Show idle frame (frame 0)
		if sprite_frames.size() > 0:
			worker_icon.texture = sprite_frames[0]
		var style := StyleBoxFlat.new()
		style.bg_color = mdata["color"].darkened(0.6)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = mdata["color"].darkened(0.2)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		worker_area.add_theme_stylebox_override("panel", style)
		if not is_processing:
			status_label.text = "Idle"
		progress_bar.value = 0


func _load_sprite_frames() -> void:
	sprite_frames.clear()
	if worker_type.is_empty():
		return
	var mdata: Dictionary = FactoryData.MACHINES[worker_type]
	var sprite_path: String = mdata.get("sprite", "")
	if sprite_path.is_empty():
		return
	var sheet: Texture2D = load(sprite_path)
	if sheet == null:
		return
	var frame_w := 96
	var frame_h := 96
	for i in 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		sprite_frames.append(atlas)


func _process(delta: float) -> void:
	if worker_type.is_empty():
		return

	if is_processing:
		elapsed_time += delta
		if process_time > 0:
			progress_bar.value = (elapsed_time / process_time) * 100.0
		# Animate working frames (frames 0-3)
		if sprite_frames.size() >= 4:
			anim_timer += delta
			if anim_timer >= 1.0 / ANIM_FPS:
				anim_timer -= 1.0 / ANIM_FPS
				anim_frame += 1
				if anim_frame > 3:
					anim_frame = 0
				worker_icon.texture = sprite_frames[anim_frame]
		# Animate workstation frames (frames 1 to last)
		if ws_frame_count > 1:
			ws_anim_timer += delta
			if ws_anim_timer >= 1.0 / ws_anim_fps:
				ws_anim_timer -= 1.0 / ws_anim_fps
				ws_anim_frame += 1
				if ws_anim_frame >= ws_frame_count:
					ws_anim_frame = 1
				%WorkstationSprite.texture = ws_frames[ws_anim_frame]
		if elapsed_time >= process_time:
			_finish_processing()
		else:
			var remaining := maxf(process_time - elapsed_time, 0.0)
			status_label.text = "Processing... %.1fs" % remaining
	else:
		# Show idle frame
		if sprite_frames.size() > 0:
			worker_icon.texture = sprite_frames[0]
		if input_belt and input_belt.has_items():
			var item: Control = input_belt.take_item()
			_start_processing(item)


func _start_processing(item: Control) -> void:
	current_item = item
	item.visible = false
	add_child(item)
	process_time = FactoryData.get_process_time(
		item.furniture_type, stage_name, worker_type
	)
	elapsed_time = 0.0
	is_processing = true
	progress_bar.value = 0
	status_label.text = "Processing %s..." % item.furniture_type
	# Start workstation animation — scale FPS so working frames fit in process_time
	if ws_frame_count > 1 and process_time > 0:
		ws_anim_fps = float(ws_frame_count - 1) / process_time
		ws_anim_frame = 1
		ws_anim_timer = 0.0
		%WorkstationSprite.texture = ws_frames[1]


func _finish_processing() -> void:
	is_processing = false
	var item := current_item
	current_item = null
	elapsed_time = 0.0
	progress_bar.value = 0
	status_label.text = "Idle"
	# Reset workstation to idle
	if ws_frames.size() > 0:
		%WorkstationSprite.texture = ws_frames[0]
	elif ws_idle_texture:
		%WorkstationSprite.texture = ws_idle_texture

	item.advance_stage()
	item.visible = true
	remove_child(item)

	if output_belt:
		output_belt.add_item(item)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("type") != "worker":
		return false
	if not worker_type.is_empty():
		return false
	if factory_zone:
		return factory_zone.budget >= data.get("machine_cost", 0)
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var cost: int = data.get("machine_cost", 0)
	if factory_zone:
		factory_zone.budget -= cost
		factory_zone._update_budget_label()
	install_worker(data["machine_name"])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not worker_type.is_empty() and not is_processing:
				var ejected := eject_worker()
				if factory_zone and not ejected.is_empty():
					var refund: int = FactoryData.MACHINES[ejected]["cost"] / 2
					factory_zone.budget += refund
					factory_zone._update_budget_label()
				worker_ejected.emit(ejected)
