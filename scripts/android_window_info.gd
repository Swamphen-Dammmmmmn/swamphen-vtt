extends RefCounted
# Only platform data acquisition; Godot owns layout, input and business state.
signal updated(data: Dictionary)
var pending := false
func request() -> void:
	if pending or not OS.has_feature("android") or not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"): return
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = runtime.getActivity()
	if activity == null: return
	pending = true
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(func(): _read(activity)))
func _read(activity: Variant) -> void:
	var wrapper: Object = Engine.get_singleton("JavaClassWrapper")
	var version: Variant = wrapper.wrap("android.os.Build$VERSION")
	var sdk: int = int(version.SDK_INT)
	var window: Variant = activity.getWindow()
	if window == null: _commit.call_deferred({"error":"Android窗口尚未准备好。"}); return
	if sdk>=28:
		var attributes: Variant = window.getAttributes()
		var cutout_mode := 3 if sdk>=30 else 1
		if int(attributes.layoutInDisplayCutoutMode)!=cutout_mode:
			attributes.layoutInDisplayCutoutMode = cutout_mode
			window.setAttributes(attributes)
	var view: Variant = window.getDecorView()
	if view == null: _commit.call_deferred({"error":"Android界面尚未准备好。"}); return
	var insets: Variant = view.getRootWindowInsets()
	var density: float = float(activity.getResources().getDisplayMetrics().density)
	var rotation: int = int(activity.getWindowManager().getDefaultDisplay().getRotation())
	var info := {"density":density,"rotation":rotation,"sdk":sdk,"corners":[],"bars":[0,0,0,0],"cutouts":[]}
	if insets != null:
		if sdk >= 30:
			var types: Variant = wrapper.wrap("android.view.WindowInsets$Type")
			var edges: Variant = insets.getInsets(int(types.systemBars()) | int(types.mandatorySystemGestures()))
			info["bars"] = [int(edges.left),int(edges.top),int(edges.right),int(edges.bottom)]
		if sdk >= 28:
			var cutout: Variant = insets.getDisplayCutout()
			if cutout != null:
				var rects: Variant = cutout.getBoundingRects()
				for index in range(int(rects.size())):
					var rect: Variant = rects.get(index)
					info["cutouts"].append([int(rect.left),int(rect.top),int(rect.right),int(rect.bottom)])
		if sdk >= 31 and insets.has_java_method("getRoundedCorner"):
			for index in range(4):
				var corner: Variant = insets.getRoundedCorner(index)
				if corner != null:
					var center: Variant = corner.getCenter()
					info["corners"].append([index,int(center.x),int(center.y),int(corner.getRadius())])
	var exception: Variant = wrapper.get_exception()
	if exception != null:
		info["error"] = "Android窗口数据读取失败，采用引擎安全区域与手动设置。"
		info["corners"] = []
	_commit.call_deferred(info)
func _commit(data: Dictionary) -> void:
	pending = false
	updated.emit(data)
