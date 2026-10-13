extends Control

const Instance = preload("res://scripts/token_instance.gd")
const UtilityPopup = preload("res://ui/components/designer_utility_popup.gd")
const Style = preload("res://ui/components/page_style.gd")
var panel: PanelContainer
var angle_input: SpinBox
var direction: TextureRect
var model_marker: Node3D
var actor: Node3D
var data: Dictionary = {}
var camera: Camera3D
var screen_point: Callable
var changed: Callable
var allowed: Callable
var marker: Node3D
var ring: MeshInstance3D
var dragging := false
var rotating := false
var start_angle := 0.0
var start_yaw := 0.0
var preview_yaw := 0.0
var radius := 1.0
var center := Vector3.ZERO
var target_id: Variant
var close_button: Button
var editing_enabled := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = UtilityPopup.new()
	panel.title = "转向"
	add_child(panel)
	var body: VBoxContainer = panel.body
	close_button = body.get_child(0).get_child(1)
	body.add_child(_label("棋子朝向",Color("187ed4")))
	var row := GoStyle.row(10)
	body.add_child(row)
	var left := _button("左转 90°",func(): _turn(1))
	row.add_child(left)
	direction = TextureRect.new()
	direction.texture = GoUi.icons().texture(GoIconSet.DOWN)
	direction.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	direction.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	direction.custom_minimum_size = Vector2(32,32)
	direction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	direction.modulate = Color("187ed4")
	direction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction.resized.connect(func(): direction.pivot_offset = direction.size/2)
	row.add_child(direction)
	row.add_child(_button("右转 90°",func(): _turn(-1)))
	body.add_child(GoStyle.divider())
	body.add_child(_label("外观旋转 · °",Color("9a5a13")))
	var angles := GoStyle.row(8)
	body.add_child(angles)
	angle_input = SpinBox.new()
	angle_input.min_value = -180
	angle_input.max_value = 180
	angle_input.step = 0.1
	angle_input.tooltip_text = "相对棋子朝向的角度"
	angle_input.custom_minimum_size = Vector2(100,44)
	angle_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angles.add_child(angle_input)
	angle_input.value_changed.connect(func(value: float):
		if not _can_edit(): return
		_cancel_drag()
		_commit(int(data.get("quarter_turn",0)),value)
	)
	angles.add_child(_button("对齐棋子朝向",func():
		_cancel_drag()
		_commit(int(data.get("quarter_turn",0)),0.0)
	))

func _label(text: String, color: Color) -> Label:
	var label := Style.text(text,14)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_color_override("font_color",color)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.button(button)
	button.pressed.connect(action)
	return button

func _can_edit() -> bool:
	return is_instance_valid(actor) and (not allowed.is_valid() or allowed.call())

func open(target: Node3D, values: Dictionary, view: Camera3D, to_screen: Callable, save: Callable, permission: Callable, at: Vector2) -> void:
	close()
	actor = target
	data = values
	target_id = values.get("id")
	camera = view
	screen_point = to_screen
	changed = save
	allowed = permission
	angle_input.set_value_no_signal(float(data.get("model_yaw_deg",0)))
	rotating = true
	panel.reveal_at(size,at)
	_refresh_direction()

func close() -> void:
	_cancel_drag()
	rotating = false
	if is_instance_valid(ring): ring.hide()
	if is_instance_valid(model_marker): model_marker.hide()
	if is_instance_valid(panel): panel.dismiss()
	actor = null
	data = {}

func over_ui(point: Vector2) -> bool:
	return panel.visible and panel.get_global_rect().has_point(point)

func _turn(amount: int) -> void:
	_cancel_drag()
	_commit(posmod(int(data.get("quarter_turn",0))+amount,4),float(data.get("model_yaw_deg",0)))

func _commit(quarter: int, offset: float) -> void:
	if not _can_edit(): return
	offset = wrapf(offset,-180,180)
	changed.call(quarter,offset)
	Instance.apply_orientation(actor,data)
	angle_input.set_value_no_signal(offset)
	_refresh_direction()

func _refresh_direction() -> void:
	var forward := Vector3.BACK.rotated(Vector3.UP,int(data.get("quarter_turn",0))*PI/2)
	var delta := camera.unproject_position(actor.global_position+forward)-camera.unproject_position(actor.global_position)
	if delta.length_squared()>0.001: direction.rotation = delta.angle()-PI/2

func update_marker(target: Node3D, values: Dictionary, parent: Node3D) -> void:
	if not is_instance_valid(marker):
		marker = _arrow()
		parent.add_child(marker)
	marker.visible = is_instance_valid(target)
	if not is_instance_valid(target): return
	var width := float(values.get("width",values.get("size",1)))
	var length := float(values.get("length",values.get("size",1)))
	var quarter := int(values.get("quarter_turn",0))
	var forward := Vector3.BACK.rotated(Vector3.UP,quarter*PI/2)
	var distance := (length if quarter%2==0 else width)/2+0.35
	marker.position = target.position+Vector3.UP*0.035+forward*distance
	marker.rotation.y = quarter*PI/2
	if panel.visible and (not is_instance_valid(actor) or target!=actor): close()
	if panel.visible:
		_refresh_direction()
		var enabled := _can_edit()
		if enabled!=editing_enabled:
			editing_enabled = enabled
			for button in panel.find_children("*","Button",true,false):
				if button!=close_button: button.disabled = not enabled
			angle_input.editable = enabled
		if not dragging and not angle_input.get_line_edit().has_focus(): angle_input.set_value_no_signal(float(data.get("model_yaw_deg",0)))
	if not is_instance_valid(ring):
		ring = MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.97
		mesh.outer_radius = 1.03
		mesh.rings = 64
		mesh.ring_segments = 8
		ring.mesh = mesh
		ring.material_override = _material(Color("efa43b"))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(ring)
		model_marker = _arrow(true)
		parent.add_child(model_marker)
	ring.visible = panel.visible and rotating and _can_edit()
	model_marker.visible = ring.visible
	if not ring.visible: return
	var bounds: AABB = actor.get_meta("appearance_bounds",AABB(Vector3(-0.5,0,-0.5),Vector3(1,1,1)))
	center = actor.to_global(bounds.get_center())
	radius = maxf(0.8,maxf(bounds.size.x,bounds.size.z)*0.65)
	ring.global_position = center
	ring.scale = Vector3(radius,0.7,radius)
	var offset := preview_yaw if dragging else float(data.get("model_yaw_deg",0))
	var angle := deg_to_rad(int(data.get("quarter_turn",0))*90.0+offset)
	model_marker.global_position = center+Vector3.BACK.rotated(Vector3.UP,angle)*(radius+0.1)
	model_marker.global_rotation.y = angle

func _arrow(model := false) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var shape: Array[Vector3] = [Vector3(-0.23,0,-0.15),Vector3(0,0,0.3),Vector3(0.23,0,-0.15)]
	if model:
		shape = [Vector3(-0.24,0,0),Vector3(0,0,0.32),Vector3(0.24,0,0),Vector3(0.09,0,0),Vector3(0.09,0,-0.35),Vector3(-0.09,0,-0.35),Vector3(-0.09,0,0)]
	var polygon := PackedVector2Array()
	for point in shape: polygon.append(Vector2(point.x,point.z))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var vertices := PackedVector3Array()
	for index in triangles: vertices.append(shape[index])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	node.mesh = mesh
	node.material_override = _material(Color("efa43b") if model else Color("187ed4"))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _plane(point: Vector2) -> Variant:
	var position: Vector2 = screen_point.call(point)
	return Plane(Vector3.UP,center.y).intersects_ray(camera.project_ray_origin(position),camera.project_ray_normal(position))

func handle_pointer(event: InputEvent, on_ui: bool) -> bool:
	if not panel.visible or not rotating or not _can_edit(): return false
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and dragging:
		_cancel_drag()
		return true
	if event is InputEventMouseMotion and dragging:
		var point: Variant = _plane(event.position)
		if point!=null:
			var angle := atan2(point.x-center.x,point.z-center.z)
			preview_yaw = wrapf(start_yaw+rad_to_deg(angle-start_angle),-180,180)
			var preview := data.duplicate()
			preview["model_yaw_deg"] = preview_yaw
			Instance.apply_orientation(actor,preview)
			angle_input.set_value_no_signal(preview_yaw)
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if dragging and not event.pressed:
			dragging = false
			_commit(int(data.get("quarter_turn",0)),preview_yaw)
			return true
		if event.pressed and not on_ui:
			var point: Variant = _plane(event.position)
			var on_arrow := false
			if point!=null and is_instance_valid(model_marker) and model_marker.visible:
				var local: Vector3 = model_marker.to_local(point)
				on_arrow = Rect2(-0.24,-0.35,0.48,0.67).has_point(Vector2(local.x,local.z))
			if point!=null and (on_arrow or absf(Vector2(point.x-center.x,point.z-center.z).length()-radius)<maxf(0.15,radius*0.12)):
				start_angle = atan2(point.x-center.x,point.z-center.z)
				start_yaw = float(data.get("model_yaw_deg",0))
				preview_yaw = start_yaw
				dragging = true
				return true
	return false

func _cancel_drag() -> void:
	if dragging and is_instance_valid(actor):
		Instance.apply_orientation(actor,data)
		angle_input.set_value_no_signal(float(data.get("model_yaw_deg",0)))
	dragging = false

func _exit_tree() -> void:
	if is_instance_valid(marker): marker.queue_free()
	if is_instance_valid(ring): ring.queue_free()
	if is_instance_valid(model_marker): model_marker.queue_free()
