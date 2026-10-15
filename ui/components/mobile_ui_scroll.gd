extends Node
const DEVICE := -421
var active: ScrollContainer
var target: Control
var finger := -1
var origin := Vector2.ZERO
var previous := Vector2.ZERO
var mode := ""
var suppress_frame := -1
var down := false
var velocity := 0.0
var inertia: ScrollContainer
var inertia_axis := "y"
var custom_fingers: Array[int] = []
var replay_queue: Array[InputEvent] = []
var replay_scheduled := false
var replay_down := false
var replay_owner: WeakRef
var replay_target: WeakRef
var blocked_fingers: Array[int] = []

func _ready() -> void:
	name = "MobileUIScroll"

# Resolve the frontmost eligible control before choosing its scroll ancestor.
# A background scroll must never capture through an overlay or a disabled page.
func _front_control(node: Node, point: Vector2, hit: Dictionary, layer := 0, depth := 0) -> void:
	if node is Viewport and node!=get_viewport(): return
	if node is CanvasLayer:
		if not node.visible: return
		layer = node.layer
		depth = 0
	if node is Control:
		if not node.is_visible_in_tree() or not node.can_process(): return
		if node.clip_contents and not node.get_global_rect().has_point(point): return
		depth = depth+node.z_index if node.z_as_relative else node.z_index
		if node.mouse_filter!=Control.MOUSE_FILTER_IGNORE and node.get_global_rect().has_point(point):
			if layer>int(hit.get("layer",-100000)) or (layer==int(hit.get("layer",-100000)) and depth>=int(hit.get("depth",-100000))):
				hit["control"] = node
				hit["layer"] = layer
				hit["depth"] = depth
	for child in node.get_children(): _front_control(child,point,hit,layer,depth)

func _popup_visible(node: Node) -> bool:
	if node is Window and node!=get_viewport() and node.visible: return true
	for child in node.get_children():
		if _popup_visible(child): return true
	return false

func _pick(point: Vector2) -> ScrollContainer:
	if _popup_visible(get_tree().root): return null
	var hit := {}
	_front_control(get_tree().root,point,hit)
	var control: Node = hit.get("control")
	while control!=null:
		if control is ScrollContainer: return control
		control = control.get_parent()
	return null

func owns(point: Vector2) -> bool:
	return finger>=0 or not blocked_fingers.is_empty() or _pick(point)!=null

func _target_at(root: Control, point: Vector2) -> Control:
	var actual := _actual_target(root,point)
	if actual!=null: return actual
	var hit := {"distance":INF}
	_near_target(root,point,root.get_global_rect(),hit)
	return hit.get("control")

func _near_target(root: Control, point: Vector2, clip: Rect2, hit: Dictionary) -> void:
	if not root.is_visible_in_tree() or not root.can_process(): return
	if root.clip_contents: clip = clip.intersection(root.get_global_rect())
	if not clip.has_point(point): return
	if root is BaseButton or root is LineEdit:
		if root is BaseButton and root.disabled: return
		var rect := root.get_global_rect()
		var padding := (Vector2.ONE*Mobile.touch_units(48)-rect.size).max(Vector2.ZERO)*0.5
		if rect.grow_individual(padding.x,padding.y,padding.x,padding.y).has_point(point):
			var distance := point.distance_squared_to(rect.get_center())
			if distance<float(hit.distance):
				hit["control"] = root
				hit["distance"] = distance
	for child in root.get_children():
		if child is Control: _near_target(child,point,clip,hit)

func _actual_target(root: Control, point: Vector2) -> Control:
	if not root.is_visible_in_tree(): return null
	if root is ScrollContainer:
		var bar: VScrollBar = root.get_v_scroll_bar()
		if bar.is_visible_in_tree() and root.get_global_rect().has_point(point) and bar.get_global_rect().grow_individual(8,0,0,0).has_point(point): return bar
	if root.clip_contents and not root.get_global_rect().has_point(point): return null
	var children := root.get_children()
	children.reverse()
	for child in children:
		if child is Control:
			var found := _actual_target(child,point)
			if found!=null: return found
	if root.get_global_rect().has_point(point) and root.has_meta("mobile_drag"): return root
	if root.get_global_rect().has_point(point) and (root is BaseButton or root is LineEdit or root is TextEdit or root is Slider or root is ScrollBar or root is FoldableContainer): return root
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==DEVICE: return
	if mode=="custom" and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if not is_instance_valid(target) or not target.is_visible_in_tree():
			_cancel()
		else:
			if event is InputEventScreenTouch and event.pressed and (custom_fingers.size()>=2 or not target.get_global_rect().has_point(event.position)):
				blocked_fingers.assign(custom_fingers)
				blocked_fingers.append(event.index)
				_cancel()
				get_viewport().set_input_as_handled()
				return
			if event is InputEventScreenTouch:
				if event.pressed and event.index not in custom_fingers: custom_fingers.append(event.index)
				elif not event.pressed: custom_fingers.erase(event.index)
			target.mobile_touch_event(event)
			if custom_fingers.is_empty():
				finger = -1
				active = null
				target = null
				mode = ""
		suppress_frame = Engine.get_process_frames()+1
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.pressed and not blocked_fingers.is_empty() and event.index not in blocked_fingers:
		blocked_fingers.append(event.index)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.index in blocked_fingers:
		if not event.pressed: blocked_fingers.erase(event.index)
		suppress_frame = Engine.get_process_frames()+1
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag and event.index in blocked_fingers:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION and (finger>=0 or not blocked_fingers.is_empty() or Engine.get_process_frames()<=suppress_frame):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger>=0:
				blocked_fingers.assign([finger,event.index])
				_cancel()
				get_viewport().set_input_as_handled()
				return
			var scroll := _pick(event.position)
			if scroll==null: return
			active = scroll
			target = _target_at(scroll,event.position)
			finger = event.index
			origin = event.position
			previous = origin
			mode = "pending"
			if is_instance_valid(target) and target.get_meta("mobile_drag","")=="custom":
				mode = "custom"
				custom_fingers.assign([event.index])
				target.mobile_touch_event(event)
			inertia = null
			velocity = 0
			get_viewport().set_input_as_handled()
		elif event.index==finger:
			if event.canceled or not is_instance_valid(active) or not active.is_visible_in_tree() or not active.can_process():
				_cancel()
				get_viewport().set_input_as_handled()
				return
			if is_instance_valid(active):
				if mode=="pending" and event.position.distance_to(origin)<=_threshold() and _pick(event.position)==active and _target_at(active,event.position)==target:
					_mouse(true,event.position)
					_mouse(false,event.position)
				elif down: _mouse(false,event.position)
				if mode in ["scroll_x","scroll_y"]:
					inertia = active
					inertia_axis = "x" if mode=="scroll_x" else "y"
			else: inertia = null
			finger = -1
			active = null
			target = null
			mode = ""
			down = false
			suppress_frame = Engine.get_process_frames()+1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index==finger:
		if not is_instance_valid(active) or not active.is_visible_in_tree() or not active.can_process():
			_cancel()
			get_viewport().set_input_as_handled()
			return
		var distance: Vector2 = event.position-origin
		if mode=="pending" and distance.length()>_threshold():
			var horizontal := absf(distance.x)>absf(distance.y)*1.8
			var native_area: bool = is_instance_valid(target) and target.get_meta("mobile_drag","")=="native"
			var native_slider: bool = is_instance_valid(target) and (target is ScrollBar or (horizontal and target is HSlider) or (not horizontal and target is VSlider) or (horizontal and (target is LineEdit or target is TextEdit) and target.has_focus()))
			if native_area or native_slider:
				mode = "native"
				_mouse(true,origin)
			elif horizontal and active.get_h_scroll_bar().max_value>active.get_h_scroll_bar().page:
				mode = "scroll_x"
			else: mode = "scroll_y"
		if mode in ["scroll_x","scroll_y"]:
			var change: float = previous.x-event.position.x if mode=="scroll_x" else previous.y-event.position.y
			var bar: ScrollBar = active.get_h_scroll_bar() if mode=="scroll_x" else active.get_v_scroll_bar()
			bar.value += change
			velocity = change/maxf(0.008,get_process_delta_time())
		elif mode=="native": _motion(event.position,event.position-previous)

		previous = event.position
		get_viewport().set_input_as_handled()

func _threshold() -> float:
	return Mobile.drag_slop()

func _bar_point(point: Vector2) -> Vector2:
	if is_instance_valid(target) and target is VScrollBar and mode not in ["scroll_x","scroll_y"]:
		var rect := target.get_global_rect()
		point.x = rect.get_center().x
	if mode!="native" and is_instance_valid(target) and (target is BaseButton or target is LineEdit) and not target.get_global_rect().has_point(point):
		point = target.get_global_rect().get_center()
	return point

func _mouse(pressed: bool, point: Vector2) -> void:
	point = _bar_point(point)
	# Establish hover before a mouse press; BaseButton requires it.
	if pressed: _motion(point,Vector2.ZERO)
	var event := InputEventMouseButton.new()
	event.device = DEVICE
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = point
	event.global_position = point
	down = pressed
	_enqueue_replay(event)

func _motion(point: Vector2, relative: Vector2) -> void:
	point = _bar_point(point)
	var event := InputEventMouseMotion.new()
	event.device = DEVICE
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_enqueue_replay(event)

func _enqueue_replay(event: InputEvent) -> void:
	if replay_queue.is_empty():
		replay_owner = weakref(active) if is_instance_valid(active) else null
		replay_target = weakref(target) if is_instance_valid(target) else null
	replay_queue.append(event)
	if not replay_scheduled:
		replay_scheduled = true
		_flush_replay.call_deferred()

func _flush_replay() -> void:
	# Never nest another input dispatch inside the original touch callback.
	# Coordinates are already viewport-local; global Input would transform them twice.
	var owner = replay_owner.get_ref() if replay_owner!=null else null
	var control = replay_target.get_ref() if replay_target!=null else null
	var invalid_target: bool = replay_target!=null and (control==null or not control.is_visible_in_tree() or not control.can_process())
	if invalid_target or (replay_owner!=null and (owner==null or not owner.is_visible_in_tree() or not owner.can_process())):
		_cancel()
	var batch := replay_queue.duplicate()
	replay_queue.clear()
	replay_scheduled = false
	for event in batch:
		if event is InputEventMouseButton and event.pressed:
			if not is_instance_valid(owner) or _pick(event.position)!=owner or _target_at(owner,event.position)!=control:
				_cancel()
				break
		get_viewport().push_input(event,true)
		if event is InputEventMouseButton: replay_down = event.pressed

func _process(delta: float) -> void:
	if finger>=0 and (not is_instance_valid(active) or not active.is_visible_in_tree() or not active.can_process()):
		blocked_fingers.append(finger)
		_cancel()
	if finger<0 and is_instance_valid(inertia):
		if not inertia.is_visible_in_tree() or not inertia.can_process() or absf(velocity)<8: inertia = null; return
		var center := inertia.get_global_rect().get_center()
		if _pick(center)!=inertia:
			inertia = null
			return
		var bar: ScrollBar = inertia.get_h_scroll_bar() if inertia_axis=="x" else inertia.get_v_scroll_bar()
		bar.value += velocity*delta
		velocity *= exp(-8*delta)

func _cancel() -> void:
	if mode=="custom" and is_instance_valid(target): target.mobile_touch_cancel()
	custom_fingers.clear()
	replay_queue.clear()
	replay_owner = null
	replay_target = null
	if replay_down: _mouse(false,Vector2(-10000,-10000))
	finger = -1
	active = null
	target = null
	inertia = null
	down = false
	mode = ""
	suppress_frame = Engine.get_process_frames()+1
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel()
		blocked_fingers.clear()
