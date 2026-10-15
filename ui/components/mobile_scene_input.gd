extends Node

const BRIDGE_DEVICE := -420
var bridge_events: Array[InputEvent] = []
var bridge_scheduled := false
var bridge_down := false
const SLOP := 10.0
const PAIR_HOLD_MS := 280
const PAIR_DECISION_MS := 40
var pair_decision_started := 0
const PAIR_REST_SLOP := 5.0
const PAIR_START_SLOP := 8.0
var pair_mode := ""
var pair_origins: Dictionary = {}
var pair_started := 0
var lift_finger := -1
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
var skip_pair_delta := false
var joystick_session := false
var blocked_fingers: Array[int] = []
var host: Node
var kind := "preview"
var fingers: Dictionary = {}
var first_position := Vector2.ZERO
var last_position := Vector2.ZERO
var sent_down := false
var moved := false
var multitouch := false
var joystick_id := -1
var joystick_center := Vector2.ZERO
var joystick_value := Vector2.ZERO
var look_id := -1
var overlay: CanvasLayer
var surface: Control
var boost: Button
var boost_finger := -1
var boost_origin := Vector2.ZERO
var boost_canceled := false
var boost_suppress_frame := -1
var input_generation := 0
var camera_enabled := false
var previous_tool := ""
var previous_active := ""
var cancel_button: Button
var snapshot: Dictionary = {}
var expansion_snapshot: Dictionary = {}

static func attach(owner: Node) -> Node:
	if not Mobile.enabled: return null
	var controller = load("res://ui/components/mobile_scene_input.gd").new()
	controller.host = owner
	var file: String = owner.get_script().resource_path.get_file()
	controller.kind = "board" if file == "main.gd" else ("free" if file in ["platform_customize.gd", "map_customize.gd"] else "preview")
	owner.add_child(controller)
	return controller

func _ready() -> void:
	if kind == "free":
		host.tools.tool_selected.connect(_tool_changed)
		host.tools.category_changed.connect(_tool_changed)
	overlay = CanvasLayer.new()
	var layer: CanvasLayer = host.get_canvas_layer_node() if host is Control else null
	overlay.layer = layer.layer+4 if layer != null else 4
	add_child(overlay)
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(surface)
	surface.draw.connect(_draw_joystick)
	boost = Button.new()
	boost.text = "加速"
	boost.toggle_mode = true
	preload("res://ui/components/page_style.gd").card_button(boost,48)
	surface.add_child(boost)
	boost.hide()
	cancel_button = Button.new()
	cancel_button.text = "取消"
	preload("res://ui/components/page_style.gd").card_button(cancel_button,48)
	surface.add_child(cancel_button)
	cancel_button.pressed.connect(_cancel_operation)
	cancel_button.hide()

func _tool_changed(key: String) -> void:
	if not fingers.is_empty() or bridge_down: _interrupt_drag()
	reset()
	camera_enabled = host.active_tool == "mobile_camera"
	if camera_enabled:
		previous_tool = previous_active
		if host.expanded:
			if host.has_method("_toggle"): host._toggle()
			else: host._toggle_panel()
	previous_active = key

func _process(delta: float) -> void:
	if kind=="free" and camera_enabled!=(host.active_tool=="mobile_camera"):
		_interrupt_drag()
		reset()
		camera_enabled = host.active_tool=="mobile_camera"
	var inactive := _blocked() or not host.is_processing_input()
	if inactive and (not fingers.is_empty() or boost.button_pressed):
		for id in fingers:
			if id not in blocked_fingers: blocked_fingers.append(id)
		_interrupt_drag()
		reset()
	if pair_mode=="pending" and not inactive: _resolve_pair()
	boost.visible = kind == "free" and camera_enabled and not inactive
	var view := get_viewport().get_visible_rect().size
	var m: Vector4 = Mobile.margins
	boost.position = Vector2(m.x+12,view.y-m.w-120)
	boost.size = Vector2(80,48)
	cancel_button.visible = _operation_pending() and not inactive and not camera_enabled
	cancel_button.position = Vector2(view.x-m.z-92,view.y-m.w-66)
	cancel_button.size = Vector2(80,48)
	if joystick_id >= 0 and not inactive:
		var camera: Camera3D = host.preview.camera
		var direction := camera.basis.x*joystick_value.x-camera.basis.z*joystick_value.y
		var speed: float = host.fast_speed if boost.button_pressed else host.normal_speed
		camera.position += direction*(speed/5.0)*minf(delta,0.1)
	surface.queue_redraw()

func _blocked() -> bool:
	if not is_instance_valid(host) or not host.is_inside_tree(): return true
	if kind == "free":
		if host.get_script().resource_path.get_file() == "map_customize.gd": return is_instance_valid(host.platform_editor) or host._blocked()
		return host._camera_blocked()
	if kind == "preview": return host._popup_open() or not host.is_visible_in_tree()
	return not host.is_processing_input() or host.ui.rename_open()

func _over_ui(point: Vector2) -> bool:
	if Mobile.point_on_ui_scroll(point): return true
	if boost.visible and boost.get_global_rect().has_point(point): return true
	if cancel_button.visible and cancel_button.get_global_rect().has_point(point): return true
	if kind == "free": return host._over_ui(point) or not host.get_global_rect().has_point(point)
	if kind == "board": return host.ui.rename_open() or _control_at(host.ui,point)
	if host.has_method("_pointer_on_ui"): return host._pointer_on_ui(point) or not host.get_global_rect().has_point(point)
	return not host.get_global_rect().has_point(point) or (host.basic_open and host.options_panel.get_global_rect().has_point(point)) or host.basic_handle.get_global_rect().has_point(point)

func _control_at(root: Node, point: Vector2) -> bool:
	if root is Control and not root.is_visible_in_tree(): return false
	if root is PanelContainer or root is BaseButton or root is LineEdit or root is TextEdit or root is ScrollContainer:
		if root.get_global_rect().has_point(point): return true
	for child in root.get_children():
		if _control_at(child,point): return true
	return false

func handle(event: InputEvent) -> bool:
	if event is InputEventMouse and event.device == -421: return true
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION and (boost_finger>=0 or Engine.get_process_frames()<=boost_suppress_frame):
		get_viewport().set_input_as_handled()
		return true
	# Native mouse emulation remains available to GUI controls, never to scene tools.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return true
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return false
	if event is InputEventScreenTouch and event.pressed and boost_finger<0 and boost.visible and not _blocked() and blocked_fingers.is_empty() and boost.get_global_rect().has_point(event.position):
		boost_finger = event.index
		boost_origin = event.position
		boost_canceled = false
		get_viewport().set_input_as_handled()
		return true
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and event.index==boost_finger:
		if event.position.distance_to(boost_origin)>SLOP: boost_canceled = true
		if event is InputEventScreenTouch and not event.pressed:
			if not event.canceled and not boost_canceled and boost.visible and not _blocked() and boost.get_global_rect().has_point(event.position): _boost_click.call_deferred(input_generation)
			boost_finger = -1
			boost_suppress_frame = Engine.get_process_frames()+1
		get_viewport().set_input_as_handled()
		return true
	if not blocked_fingers.is_empty():
		if event is InputEventScreenTouch:
			if event.pressed and event.index not in blocked_fingers: blocked_fingers.append(event.index)
			elif not event.pressed: blocked_fingers.erase(event.index)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenTouch:
		if event.pressed:
			if not fingers.is_empty() and (_blocked() or _over_ui(event.position)):
				blocked_fingers.assign(fingers.keys())
				blocked_fingers.append(event.index)
				_interrupt_drag()
				reset()
				get_viewport().set_input_as_handled()
				return true
			if _blocked() or _over_ui(event.position): return false
			fingers[event.index] = event.position
			if fingers.size()>2:
				blocked_fingers.assign(fingers.keys())
				_interrupt_drag()
				reset()
				get_viewport().set_input_as_handled()
				return true
			if fingers.size() == 1:
				_mouse_motion(event.position,Vector2.ZERO)
				first_position = event.position
				last_position = event.position
				moved = false
				multitouch = false
				sent_down = false
				_capture_snapshot()
			if fingers.size()>=2: skip_pair_delta = true
			if camera_enabled:
				var joystick_area: bool = event.position.x < get_viewport().get_visible_rect().size.x*0.45 and event.position.y > get_viewport().get_visible_rect().size.y*0.45
				if joystick_id < 0 and joystick_area:
					joystick_session = true
					joystick_id = event.index
					joystick_center = event.position
					for id in fingers:
						if id != joystick_id: look_id = id; break
				elif look_id < 0:
					look_id = event.index
			elif fingers.size() == 1:
				if _paint_brush(): _mouse_button(true,event.position)
			else:
				multitouch = true
				_interrupt_drag()
			if fingers.size()==2 and not joystick_session:
				multitouch = true
				if kind!="free": _begin_pair()
		else:
			if not fingers.has(event.index): return false
			if event.canceled:
				blocked_fingers.assign(fingers.keys())
				blocked_fingers.erase(event.index)
				_interrupt_drag()
				reset()
			else:
				if fingers.size()==1 and not multitouch and not camera_enabled and _over_ui(event.position):
					_interrupt_drag()
					reset(false)
					get_viewport().set_input_as_handled()
					return true
				if fingers.size() == 1 and not multitouch and not camera_enabled:
					if sent_down: _mouse_button(false,event.position)
					elif not moved or _placement_pending(): _mouse_button(true,event.position); _mouse_button(false,event.position)
				if event.index == joystick_id: joystick_id = -1; joystick_value = Vector2.ZERO
				if event.index == look_id: look_id = -1
				fingers.erase(event.index)
				skip_pair_delta = true
				if fingers.is_empty(): reset(false)
		get_viewport().set_input_as_handled()
		return true
	if not fingers.has(event.index): return false
	var old: Vector2 = fingers[event.index]
	fingers[event.index] = event.position
	if event.index == joystick_id:
		var offset: Vector2 = (event.position-joystick_center)/52.0
		joystick_value = Vector2(offset.x,-offset.y).limit_length() if offset.length()>0.12 else Vector2.ZERO
	elif camera_enabled and joystick_session:
		if look_id<0: look_id = event.index
		if event.index==look_id: _turn_free(event.position-old)
	elif fingers.size() >= 2:
		if kind!="free":
			_pair_drag(event.index,old)
			get_viewport().set_input_as_handled()
			return true
		if skip_pair_delta:
			skip_pair_delta = false
			get_viewport().set_input_as_handled()
			return true
		var ids := fingers.keys()
		var other: Vector2 = fingers[ids[1] if ids[0] == event.index else ids[0]]
		var center := (old+other)*0.5
		var delta_center: Vector2 = (event.position-old)*0.5
		_pan(delta_center)
		var before := old.distance_to(other)
		var after: float = event.position.distance_to(other)
		if before > 24 and after > 24: _zoom(before/after,center)
	elif not multitouch:
		if camera_enabled: _turn_free(event.position-old)
		elif _single_camera():
			if event.position.distance_to(first_position)>SLOP: moved = true
			if moved: _rotate(event.position-old)
		else:
			if event.position.distance_to(first_position)>SLOP:
				moved = true
				if not sent_down and not _placement_pending(): _mouse_button(true,first_position)
			_mouse_motion(event.position,event.position-old)
	last_position = event.position
	get_viewport().set_input_as_handled()
	return true

func _boost_click(generation: int) -> void:
	if generation!=input_generation: return
	if not is_instance_valid(boost) or not boost.is_visible_in_tree() or _blocked(): return
	# Replay a complete GUI click; this also works for a second touch while the joystick is held.
	var point := boost.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.device = -421
	hover.position = point
	hover.global_position = point
	get_viewport().push_input(hover,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.device = -421
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event,true)

func _begin_pair() -> void:
	pair_mode = "pending"
	pair_origins = fingers.duplicate()
	pair_started = Time.get_ticks_msec()
	pair_decision_started = 0
	lift_finger = -1

func _pair_drag(index: int, old: Vector2) -> void:
	if fingers.size()!=2 or pair_origins.size()!=2: return
	var ids := fingers.keys()
	var other_id: int = ids[1] if ids[0]==index else ids[0]
	var point: Vector2 = fingers[index]
	var other: Vector2 = fingers[other_id]
	if pair_mode=="lift":
		if index==lift_finger: _lift(-(point.y-old.y))
		return
	var before_center := (old+other)*0.5
	var before_distance := old.distance_to(other)
	if pair_mode=="pending": return
	_pan((point+other)*0.5-before_center)
	var after_distance := point.distance_to(other)
	if before_distance>24 and after_distance>24: _zoom(before_distance/after_distance,before_center)

func _resolve_pair() -> void:
	if fingers.size()!=2 or pair_origins.size()!=2: return
	var ids := fingers.keys()
	var first: Vector2 = fingers[ids[0]]
	var second: Vector2 = fingers[ids[1]]
	var first_origin: Vector2 = pair_origins[ids[0]]
	var second_origin: Vector2 = pair_origins[ids[1]]
	var first_motion := first-first_origin
	var second_motion := second-second_origin
	if maxf(first_motion.length(),second_motion.length())<=PAIR_START_SLOP: return
	var now := Time.get_ticks_msec()
	if pair_decision_started==0:
		pair_decision_started = now
		return
	# Touch events arrive per finger. Collect both before classifying a same-direction swipe.
	if now-pair_decision_started<PAIR_DECISION_MS: return
	var moving_id: int = ids[0]
	var motion := first_motion
	var stationary := second_motion.length()<=PAIR_REST_SLOP
	if first_motion.length()<=PAIR_REST_SLOP and second_motion.length()>PAIR_START_SLOP:
		moving_id = ids[1]
		motion = second_motion
		stationary = true
	var rested_before_move := pair_decision_started-pair_started>=PAIR_HOLD_MS
	if rested_before_move and stationary and absf(motion.y)>absf(motion.x)*1.6:
		pair_mode = "lift"
		lift_finger = moving_id
		return
	pair_mode = "normal"
	_pan((first+second-first_origin-second_origin)*0.5)
	var before := first_origin.distance_to(second_origin)
	var after := first.distance_to(second)
	if before>24 and after>24: _zoom(before/after,(first+second)*0.5)

func _lift(amount: float) -> void:
	var camera: Camera3D = host.camera if kind=="board" else host.preview.camera
	var distance: float = host.camera_distance if kind=="board" else host.preview.distance
	var height := get_viewport().get_visible_rect().size.y
	var step := OrbitCamera.pan_delta(camera,distance,Vector2(0,amount),height,true,true).y
	if kind=="board":
		host.focus.y += step
		host._update_camera()
	else:
		host.preview.target.y += step
		host.preview._position_camera()

func _single_camera() -> bool:
	if kind == "preview":
		return not host.has_method("_pointer_on_ui") or (host.adjustment_mode.is_empty() and host.sticker_mode.is_empty())
	if kind == "board": return int(host.tool) == 0 and not host.turn_control.panel.visible
	return camera_enabled

func _paint_brush() -> bool:
	return kind == "free" and host.get_script().resource_path.get_file()=="platform_customize.gd" and host.active_tool=="paint" and host.paint_tool.method=="brush"

func _placement_pending() -> bool:
	if kind == "free" and host.get_script().resource_path.get_file()=="map_customize.gd": return not host.draft.is_empty()
	if kind == "board": return int(host.tool)!=0
	if kind == "free": return not host.token_tool.draft.is_empty() or not host.token_tool.moving.is_empty()
	return false

func _mouse_button(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.device = BRIDGE_DEVICE
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	sent_down = pressed
	_queue_bridge(event)

func _mouse_motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = BRIDGE_DEVICE
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if sent_down else 0
	_queue_bridge(event)

func _queue_bridge(event: InputEvent) -> void:
	bridge_events.append(event)
	if not bridge_scheduled:
		bridge_scheduled = true
		_flush_bridge.call_deferred()

func _flush_bridge() -> void:
	var batch := bridge_events.duplicate()
	bridge_events.clear()
	bridge_scheduled = false
	if not is_instance_valid(host) or not host.is_inside_tree(): return
	if not host.can_process() or _blocked():
		var release_needed := bridge_down
		_interrupt_drag()
		bridge_events.clear()
		bridge_down = false
		snapshot.clear()
		expansion_snapshot.clear()
		if release_needed:
			var release := InputEventMouseButton.new()
			release.device = BRIDGE_DEVICE
			release.button_index = MOUSE_BUTTON_LEFT
			release.position = Vector2(-10000,-10000)
			release.global_position = release.position
			get_viewport().push_input(release,true)
		return
	var generation := input_generation
	for event in batch:
		if generation!=input_generation or not host.can_process() or _blocked():
			_interrupt_drag()
			break
		if event is InputEventMouseButton: bridge_down = event.pressed
		get_viewport().push_input(event,true)
		if event is InputEventMouseButton and not event.pressed:
			snapshot.clear()
			expansion_snapshot.clear()

func _turn_free(relative: Vector2) -> void:
	var height := get_viewport().get_visible_rect().size.y
	var amount := OrbitCamera.rotation_delta(relative,height,true)
	# Free camera uses the opposite pitch sign to the orbit target convention.
	host.preview.free_yaw -= amount.x
	host.preview.free_pitch = OrbitCamera.clamp_pitch(host.preview.free_pitch-amount.y)
	host.preview.camera.rotation = Vector3(host.preview.free_pitch,host.preview.free_yaw,0)

func _rotate(relative: Vector2) -> void:
	if kind=="board": host._orbit_rotate(relative,true)
	else: host.preview.rotate_view(relative,true)

func _pan(relative: Vector2) -> void:
	if kind=="board": host._orbit_pan(relative,true)
	elif kind=="preview": host.preview.pan_view(relative,true)
	else:
		var camera: Camera3D = host.preview.camera
		camera.position += OrbitCamera.pan_delta(camera,10.0,relative,get_viewport().get_visible_rect().size.y,true,true)

func _zoom(ratio: float, _center: Vector2) -> void:
	var factor := OrbitCamera.zoom_factor(ratio,true)
	if kind=="free": host.preview.camera.position += host.preview.camera.basis.z*log(factor)*6.0
	elif kind=="board":
		host.camera_distance = clampf(host.camera_distance*factor,3.0,100000.0)
		host._update_camera()
	else: host.preview.zoom_view(factor)

func _capture_snapshot() -> void:
	snapshot = {}
	if kind == "free" and host.get_script().resource_path.get_file()=="platform_customize.gd": expansion_snapshot = host.expansion_values.duplicate()
	elif kind == "preview" and host.has_method("_pointer_on_ui"): snapshot = host.component_values.duplicate(true)

func _interrupt_drag() -> void:
	var editing := sent_down or bridge_down
	bridge_events.clear()
	if kind == "free":
		if host.get_script().resource_path.get_file()=="platform_customize.gd":
			var moving_id: String = host.token_tool.moving
			host._pause_tools()
			if not moving_id.is_empty():
				host.token_tool.selected = moving_id
				host.token_tool._move()
			if editing:
				for key in expansion_snapshot:
					host.expansion_values[key] = expansion_snapshot[key]
					host.expansion_inputs[key].set_value_no_signal(expansion_snapshot[key])
			if host.active_tool=="expand": host._refresh_expansion()
		else:
			host.move_gizmo.end_drag()
			host.preview.hide_ghost()
			if not host.moving.is_empty():
				var item: Dictionary = host._item(host.moving)
				host.candidate = item["offset_feet"]
				host.candidate_valid = true
				host.move_gizmo.configure_platform(preload("res://scripts/map_data.gd").bounds(item).get_center(),item["offset_feet"])
	elif kind == "preview" and host.has_method("_pointer_on_ui"):
		host.preview.gizmo.end_drag()
		host.preview.sticker_gizmo.end_drag()
		host.rotating = false
		if editing and not snapshot.is_empty(): host.component_values = snapshot.duplicate(true); host._load_component()
	elif kind == "board":
		if is_instance_valid(host.turn_control): host.turn_control._cancel_drag()
		host.left_orbit_pending = false
		host.camera_button = 0
	if bridge_down:
		sent_down = false
		var release := InputEventMouseButton.new()
		release.device = BRIDGE_DEVICE
		release.position = Vector2(-10000,-10000)
		release.global_position = release.position
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_queue_bridge(release)

func _operation_pending() -> bool:
	if kind == "board": return int(host.tool) == 4
	if kind != "free": return false
	if host.get_script().resource_path.get_file()=="map_customize.gd": return not host.moving.is_empty() or not host.draft.is_empty()
	return not host.token_tool.draft.is_empty() or not host.token_tool.moving.is_empty()

func _cancel_operation() -> void:
	_interrupt_drag()
	if kind == "board": host._on_tool("select")
	elif kind == "free":
		if host.has_method("_cancel_operation"): host._cancel_operation()
		else: host.token_tool.cancel()
	reset()

func reset(reset_boost := true) -> void:
	if reset_boost:
		input_generation += 1
		bridge_events.clear()
		if bridge_down: _mouse_button(false,Vector2(-10000,-10000))
	if not bridge_down:
		snapshot.clear()
		expansion_snapshot.clear()
	fingers.clear()
	joystick_id = -1
	joystick_session = false
	pair_mode = ""
	pair_decision_started = 0
	pair_origins.clear()
	lift_finger = -1
	skip_pair_delta = false
	look_id = -1
	joystick_value = Vector2.ZERO
	sent_down = false
	multitouch = false
	if reset_boost:
		boost_canceled = true
		if is_instance_valid(boost): boost.button_pressed = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		blocked_fingers.clear()
		boost_finger = -1
		boost_canceled = true
		_interrupt_drag()
		reset()

func _draw_joystick() -> void:
	if joystick_id < 0: return
	surface.draw_circle(joystick_center,58,Color(0.92,0.96,1,0.5))
	surface.draw_arc(joystick_center,58,0,TAU,48,Color("64748b"),2,true)
	surface.draw_circle(joystick_center+Vector2(joystick_value.x,-joystick_value.y)*38,22,Color("327dde"))
