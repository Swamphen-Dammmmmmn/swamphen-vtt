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
var replay_queue: Array[InputEvent] = []
var replay_scheduled := false
var replay_down := false
var replay_owner: WeakRef
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
	if not root.is_visible_in_tree(): return null
	if root.clip_contents and not root.get_global_rect().has_point(point): return null
	var children := root.get_children()
	children.reverse()
	for child in children:
		if child is Control:
			var found := _target_at(child,point)
			if found!=null: return found
	if root.get_global_rect().has_point(point) and (root is BaseButton or root is LineEdit or root is TextEdit or root is Slider or root is ScrollBar or root is FoldableContainer): return root
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device==DEVICE: return
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
				if mode=="scroll": inertia = active
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
			var horizontal := absf(distance.x)>absf(distance.y)*1.2
			if is_instance_valid(target) and ((horizontal and (target is HSlider or target is HScrollBar or ((target is LineEdit or target is TextEdit) and target.has_focus()))) or (not horizontal and (target is VScrollBar or target is VSlider))):
				mode = "native"
				_mouse(true,origin)
			else: mode = "scroll"
		if mode=="scroll":
			var change: float = previous.y-event.position.y
			active.get_v_scroll_bar().value += change
			velocity = change/maxf(0.008,get_process_delta_time())
		elif mode=="native": _motion(event.position,event.position-previous)
		previous = event.position
		get_viewport().set_input_as_handled()

func _threshold() -> float:
	var physical: Vector2i = DisplayServer.window_get_size()
	var density: float = float(Mobile.native_info.get("density",maxf(1,float(DisplayServer.screen_get_dpi())/160)))
	return maxf(4,8*density*get_viewport().get_visible_rect().size.y/maxf(1,physical.y))

func _mouse(pressed: bool, point: Vector2) -> void:
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
	var event := InputEventMouseMotion.new()
	event.device = DEVICE
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_enqueue_replay(event)

func _enqueue_replay(event: InputEvent) -> void:
	if replay_queue.is_empty(): replay_owner = weakref(active) if is_instance_valid(active) else null
	replay_queue.append(event)
	if not replay_scheduled:
		replay_scheduled = true
		_flush_replay.call_deferred()

func _flush_replay() -> void:
	# Never nest another input dispatch inside the original touch callback.
	# Coordinates are already viewport-local; global Input would transform them twice.
	var owner = replay_owner.get_ref() if replay_owner!=null else null
	if replay_owner!=null and (owner==null or not owner.is_visible_in_tree() or not owner.can_process()):
		_cancel()
	var batch := replay_queue.duplicate()
	replay_queue.clear()
	replay_scheduled = false
	for event in batch:
		get_viewport().push_input(event,true)
		if event is InputEventMouseButton: replay_down = event.pressed

func _process(delta: float) -> void:
	if finger>=0 and (not is_instance_valid(active) or not active.is_visible_in_tree() or not active.can_process()):
		blocked_fingers.append(finger)
		_cancel()
	if finger<0 and is_instance_valid(inertia):
		if not inertia.is_visible_in_tree() or not inertia.can_process() or absf(velocity)<8: inertia = null; return
		inertia.get_v_scroll_bar().value += velocity*delta
		velocity *= exp(-8*delta)

func _cancel() -> void:
	replay_queue.clear()
	replay_owner = null
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
