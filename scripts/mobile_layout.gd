extends Node
signal changed
const SCROLLBAR_WIDTH := 22.0
const SCROLLBAR_GAP := 12
var native_info: Dictionary = {}
var native_reader: RefCounted
var preferences: RefCounted
var camera_side := "left"
var auto_camera_dp := 0.0
var native_poll := 0.0

var enabled := OS.has_feature("android") or OS.get_cmdline_user_args().has("--mobile-preview")
var margins := Vector4.ZERO
var safe_roots: Array[WeakRef] = []
var last_window := Vector2i.ZERO
var last_keyboard := -1

func _ready() -> void:
	if not enabled: return
	preferences = preload("res://scripts/mobile_preferences.gd").shared()
	preferences.changed.connect(refresh)
	native_reader = preload("res://scripts/android_window_info.gd").new()
	native_reader.updated.connect(func(info: Dictionary):
		if native_info==info: return
		native_info = info
		refresh()
	)
	native_reader.request()
	add_child(preload("res://ui/components/mobile_ui_scroll.gd").new())
	get_tree().node_added.connect(_added)
	get_tree().root.size_changed.connect(refresh)
	refresh.call_deferred()

func register_root(control: Control) -> void:
	if not enabled: return
	safe_roots.append(weakref(control))
	refresh.call_deferred()

func refresh() -> void:
	if not enabled: return
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0: return
	# Layout size is stable across phone DPI reports; user scaling remains independent.
	var short_side := 640
	get_tree().root.content_scale_size = Vector2i(roundi(float(short_side) * window.x / window.y), short_side)
	var viewport_size := get_viewport().get_visible_rect().size
	var ratio := viewport_size / Vector2(window)
	var origin := Vector2.ZERO if OS.has_feature("android") else Vector2(DisplayServer.window_get_position())
	var window_rect := Rect2(origin,Vector2(window))
	var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(window_rect)
	if safe.size.x<=0 or safe.size.y<=0: safe = window_rect
	var left := maxf(0,safe.position.x-origin.x)
	var top := maxf(0,safe.position.y-origin.y)
	var right := maxf(0,window_rect.end.x-safe.end.x)
	var bottom := maxf(0,window_rect.end.y-safe.end.y)
	var cutouts := DisplayServer.get_display_cutouts()
	for cutout: Rect2 in cutouts:
		var local := cutout.intersection(window_rect)
		if not local.has_area(): continue
		local.position -= origin
		var center := local.get_center()
		var edges := [center.x,center.y,float(window.x)-center.x,float(window.y)-center.y]
		var nearest := 0
		for index in range(1,4):
			if edges[index]<edges[nearest]: nearest = index
		match nearest:
			0: left = maxf(left,local.end.x)
			1: top = maxf(top,local.end.y)
			2: right = maxf(right,window.x-local.position.x)
			3: bottom = maxf(bottom,window.y-local.position.y)
	var density := maxf(1,float(native_info.get("density", maxf(1,float(DisplayServer.screen_get_dpi())/160.0))))
	var bars: Array = native_info.get("bars",[0,0,0,0])
	left = maxf(left,float(bars[0]))
	top = maxf(top,float(bars[1]))
	right = maxf(right,float(bars[2]))
	bottom = maxf(bottom,float(bars[3]))
	for raw: Array in native_info.get("cutouts",[]):
		var rect := Rect2(float(raw[0]),float(raw[1]),float(raw[2])-float(raw[0]),float(raw[3])-float(raw[1]))
		if not cutouts.has(rect): cutouts.append(rect)
	var detected := "left"
	var camera_pixels := 0.0
	for rect: Rect2 in cutouts:
		if rect.get_center().x < window.x*0.5:
			if rect.end.x>camera_pixels: camera_pixels = rect.end.x; detected = "left"
		else:
			if window.x-rect.position.x>camera_pixels: camera_pixels = window.x-rect.position.x; detected = "right"
	camera_side = detected if preferences.side=="auto" else preferences.side
	if preferences.side!="auto" and posmod(int(native_info.get("rotation",0))-preferences.side_rotation,4)==2:
		camera_side = "right" if camera_side=="left" else "left"
	if camera_pixels>0:
		if detected=="left": left = float(bars[0])
		else: right = float(bars[2])
	auto_camera_dp = camera_pixels/density
	var camera_distance: float = camera_pixels if preferences.inset_dp<0 else preferences.inset_dp*density
	# Cutout insets are replaced by the user's final camera-side setting; bars remain independent.
	if preferences.inset_dp>=0 or camera_pixels>0:
		if camera_side=="left": left = maxf(float(bars[0]),camera_distance)
		else: right = maxf(float(bars[2]),camera_distance)
	var corner_edges := Vector4(8,8,8,8)*density
	for raw: Array in native_info.get("corners",[]):
		var radius := float(raw[3])
		var diagonal := radius/sqrt(2.0)
		var index := int(raw[0])
		if index in [0,3]: corner_edges.x = maxf(corner_edges.x,float(raw[1])-diagonal)
		else: corner_edges.z = maxf(corner_edges.z,window.x-float(raw[1])-diagonal)
		if index in [0,1]: corner_edges.y = maxf(corner_edges.y,float(raw[2])-diagonal)
		else: corner_edges.w = maxf(corner_edges.w,window.y-float(raw[2])-diagonal)
	margins = Vector4(maxf(left,corner_edges.x)*ratio.x,maxf(top,corner_edges.y)*ratio.y,maxf(right,corner_edges.z)*ratio.x,maxf(bottom,corner_edges.w)*ratio.y)
	var keyboard := _keyboard_height()
	for reference in safe_roots.duplicate():
		var control = reference.get_ref()
		if control == null:
			safe_roots.erase(reference)
			continue
		control.offset_left = margins.x
		control.offset_top = margins.y
		control.offset_right = -margins.z
		control.offset_bottom = -maxf(margins.w, keyboard*ratio.y)
		var background := control.get_node_or_null("Background") as ColorRect
		if background != null:
			background.offset_left = -control.offset_left
			background.offset_top = -control.offset_top
			background.offset_right = -control.offset_right
			background.offset_bottom = -control.offset_bottom
	changed.emit()
	last_window = window
	last_keyboard = keyboard
	var record := {"window":str(window),"dpi":DisplayServer.screen_get_dpi(),"layout":str(get_tree().root.content_scale_size),"viewport":str(viewport_size),"safe":str(safe),"cutouts":str(cutouts),"margins":str(margins),"keyboard":keyboard,"ui_scale":get_tree().root.content_scale_factor,"native":native_info,"camera_side":camera_side,"camera_inset_dp":preferences.inset_dp}
	print("手机布局记录："+JSON.stringify(record))
	var directory := "user://logs"
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("mobile-layout.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(record,"\t"))

func _process(delta: float) -> void:
	if enabled:
		native_poll += delta
		if native_poll >= 1.0:
			native_poll = 0
			native_reader.request()
	if enabled and (last_window != DisplayServer.window_get_size() or last_keyboard != _keyboard_height()): refresh()

func _added(node: Node) -> void:
	if node is PopupMenu: _prepare_popup.call_deferred(weakref(node))
	if node is Button or node is LineEdit or node is SpinBox or node is VScrollBar:
		_resize_control.call_deferred(weakref(node))

func _resize_control(reference: WeakRef) -> void:
	var control = reference.get_ref()
	if control == null: return
	if control.get_meta("embedded_input_action",false): return
	if control is VScrollBar:
		prepare_scrollbar(control)
		return
	if control is SpinBox: control.get_line_edit().virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 48)
	if control is Button: control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 48)

func prepare_scrollbar(bar: VScrollBar) -> void:
	if not enabled: return
	if not bar.has_meta("mobile_scrollbar_width_connected"):
		bar.set_meta("mobile_scrollbar_width_connected",true)
		bar.theme_changed.connect(_fit_scrollbar.bind(weakref(bar)),CONNECT_DEFERRED)
	_fit_scrollbar(weakref(bar))

func _fit_scrollbar(reference: WeakRef) -> void:
	var bar := reference.get_ref() as VScrollBar
	if bar==null: return
	var width := maxf(bar.custom_minimum_size.x,SCROLLBAR_WIDTH)
	bar.custom_minimum_size.x = width
	# ScrollContainer reserves get_minimum_size(), not custom_minimum_size.
	# Keep the track's intrinsic width consistent with the actual control width.
	for state in ["scroll","scroll_focus"]:
		var style := bar.get_theme_stylebox(state)
		var missing := width-style.get_minimum_size().x
		if missing<=0: continue
		var fitted := style.duplicate() as StyleBox
		fitted.content_margin_left = style.get_content_margin(SIDE_LEFT)+missing*0.5
		fitted.content_margin_right = style.get_content_margin(SIDE_RIGHT)+missing*0.5
		bar.add_theme_stylebox_override(state,fitted)
	var scroll := bar.get_parent() as ScrollContainer
	if scroll!=null and scroll.get_theme_constant("scrollbar_h_separation")!=SCROLLBAR_GAP:
		scroll.add_theme_constant_override("scrollbar_h_separation",SCROLLBAR_GAP)

func _keyboard_height() -> int:
	return DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0

func safe_rect(available: Vector2) -> Rect2:
	if not enabled: return Rect2(Vector2.ZERO,available)
	var keyboard := _keyboard_height()*available.y/maxf(1,DisplayServer.window_get_size().y)
	return Rect2(Vector2(margins.x,margins.y),Vector2(maxf(1,available.x-margins.x-margins.z),maxf(1,available.y-margins.y-maxf(margins.w,keyboard))))
func point_on_ui_scroll(point: Vector2) -> bool:
	var router := get_node_or_null("MobileUIScroll")
	return router != null and router.owns(point)

# Convert physical Android dp once; UI visual scale remains independent.
func touch_units(dp: float) -> float:
	if not enabled: return dp
	var density := maxf(1,float(native_info.get("density",maxf(1,float(DisplayServer.screen_get_dpi())/160.0))))
	return dp*density*get_viewport().get_visible_rect().size.y/maxf(1,DisplayServer.window_get_size().y)

func drag_slop() -> float:
	return maxf(4,touch_units(8))

func hit_radius() -> float:
	return maxf(18,touch_units(24))

func local_safe_rect(control: Control) -> Rect2:
	var safe := safe_rect(get_viewport().get_visible_rect().size)
	var inverse := control.get_global_transform_with_canvas().affine_inverse()
	return Rect2(inverse*safe.position,inverse*safe.end-inverse*safe.position).intersection(Rect2(Vector2.ZERO,control.size))

func _prepare_popup(reference: WeakRef) -> void:
	var popup = reference.get_ref()
	if popup==null: return
	# Reparenting a fixed toolbar re-enters its popup into the tree; keep one lifetime binding.
	if popup.get_meta("mobile_popup_prepared",false): return
	popup.set_meta("mobile_popup_prepared",true)
	popup.about_to_popup.connect(_fit_popup.bind(reference))

func _fit_popup(reference: WeakRef) -> void:
	var popup = reference.get_ref()
	if popup==null: return
	popup.add_theme_constant_override("v_separation",maxi(12,ceili(touch_units(48)-popup.get_theme_font_size("font_size")*1.4)))
	popup.max_size.y = maxi(1,int(safe_rect(get_viewport().get_visible_rect().size).size.y-24))
