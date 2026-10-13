extends Node
const StoragePaths = preload("res://scripts/storage_paths.gd")

signal changed
signal display_pending_changed
var PATH := StoragePaths.data_path("graphics_settings.cfg")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const ResolutionCatalog = preload("res://scripts/display_resolutions.gd")
var resolution_sizes: Array[Vector2i] = []
const SCALES := [0.5, 0.67, 0.75, 1.0]
const FPS := [30, 60, 90, 120, 144, 0]
const SHADOW_DISTANCES := [30.0, 60.0, 120.0, 200.0]
const GLOW_STRENGTHS := [0.15, 0.27, 0.4, 0.55]
var values: Dictionary
var display := {"resolution": 2, "mode": 0}
var previous_display: Dictionary = {}
var remaining := 0.0
var status := "设置仅保存在本机。"
var mobile := OS.has_feature("android") or OS.has_feature("ios")

func preset(index: int) -> Dictionary:
	var tier := clampi(index, 0, 2 if mobile else 3)
	return {"preset": tier, "scale": [2, 3, 3, 3][tier], "aa": [0, 1, 2, 2][tier], "shadow": [1, 2, 3, 3][tier], "shadow_distance": [0, 1, 2, 3][tier], "glow": tier > 0, "glow_strength": 1, "fps": 1, "vsync": true, "ssao": not mobile and tier >= 2, "ssil": not mobile and tier >= 2, "ssr": not mobile and tier >= 3, "volume": not mobile and tier >= 3, "effects_quality": [0, 1, 1, 2][tier]}

func _ready() -> void:
	resolution_sizes = ResolutionCatalog.catalog()
	display["resolution"] = resolution_sizes.find(Vector2i(1920, 1080))
	values = preset(1)
	var config := ConfigFile.new()
	var error := config.load(PATH)
	if error == OK:
		for key in values:
			var saved: Variant = config.get_value("quality", key, values[key])
			if typeof(saved) == typeof(values[key]): values[key] = saved
		var saved_mode: Variant = config.get_value("display", "window_mode", -1)
		if typeof(saved_mode) == TYPE_INT and saved_mode >= 0 and saved_mode <= 2:
			display["mode"] = saved_mode
		else:
			var legacy_fullscreen: Variant = config.get_value("display", "fullscreen", false)
			display["mode"] = 2 if typeof(legacy_fullscreen) == TYPE_BOOL and legacy_fullscreen else 0
		var width: Variant = config.get_value("display", "width", 0)
		var height: Variant = config.get_value("display", "height", 0)
		var saved_size := Vector2i(1920, 1080)
		if typeof(width) == TYPE_INT and typeof(height) == TYPE_INT and ResolutionCatalog.allowed(Vector2i(width, height)):
			saved_size = Vector2i(width, height)
		else:
			var legacy: Variant = config.get_value("display", "resolution", 2)
			if typeof(legacy) == TYPE_INT and legacy >= 0 and legacy < ResolutionCatalog.LEGACY.size(): saved_size = ResolutionCatalog.LEGACY[legacy]
		if not resolution_sizes.has(saved_size): resolution_sizes.append(saved_size)
		display["resolution"] = resolution_sizes.find(saved_size)
	elif error != ERR_FILE_NOT_FOUND: status = "无法读取画面设置，使用默认值。"
	values["scale"] = clampi(values["scale"], 0, SCALES.size() - 1)
	values["aa"] = clampi(values["aa"], 0, 2)
	values["shadow"] = clampi(values["shadow"], 0, 3)
	values["fps"] = clampi(values["fps"], 0, FPS.size() - 1)
	values["preset"] = clampi(values["preset"], -1, 2 if mobile else 3)
	values["shadow_distance"] = clampi(values["shadow_distance"], 0, 3)
	values["glow_strength"] = clampi(values["glow_strength"], 0, 3)
	values["effects_quality"] = clampi(values["effects_quality"], 0, 2)
	display["resolution"] = clampi(display["resolution"], 0, resolution_sizes.size() - 1)
	get_tree().node_added.connect(_node_added)
	_apply_display(display)
	apply_all()

func _node_added(node: Node) -> void:
	if node is Viewport or node is WorldEnvironment or node is Light3D:
		_apply_node.call_deferred(node)

func _apply_node(node: Node) -> void:
	if not is_instance_valid(node): return
	if node is Viewport:
		node.scaling_3d_scale = SCALES[values["scale"]]
		node.msaa_3d = values["aa"]
		node.positional_shadow_atlas_size = [0, 1024, 2048, 4096][values["shadow"]]
		if node is SubViewport and node.render_target_update_mode == SubViewport.UPDATE_DISABLED: return
		if node is SubViewport and node.render_target_update_mode != SubViewport.UPDATE_ALWAYS: node.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif node is Light3D:
		if not node.has_meta("graphics_shadow_original"): node.set_meta("graphics_shadow_original", node.shadow_enabled)
		node.shadow_enabled = node.get_meta("graphics_shadow_original") and values["shadow"] > 0
		if node is DirectionalLight3D: node.directional_shadow_max_distance = SHADOW_DISTANCES[values["shadow_distance"]]
	elif node is WorldEnvironment and node.environment != null:
		apply_environment(node.environment)
		# Library cards and small creation previews do not need costly scene effects.
		if node.get_viewport() is SubViewport:
			node.environment.ssao_enabled = false
			node.environment.ssil_enabled = false
			node.environment.ssr_enabled = false
			node.environment.volumetric_fog_enabled = false

func apply_environment(env: Environment) -> void:
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	EnvironmentProfile.apply_glow(env, EnvironmentProfile.defaults())
	env.glow_enabled = values["glow"]
	env.glow_intensity = GLOW_STRENGTHS[values["glow_strength"]]
	env.ssao_enabled = forward and not mobile and values["ssao"]
	env.ssao_intensity = 0.5
	env.ssao_radius = 0.6
	env.ssil_enabled = forward and not mobile and values["ssil"]
	env.ssil_intensity = 0.4
	env.ssr_enabled = forward and not mobile and values["ssr"]
	env.ssr_max_steps = [32, 64, 96][values["effects_quality"]]
	env.volumetric_fog_enabled = forward and not mobile and values["volume"]
	env.volumetric_fog_density = 0.005

func _walk(node: Node) -> void:
	_apply_node(node)
	for child in node.get_children(): _walk(child)

func apply_all() -> void:
	Engine.max_fps = FPS[values["fps"]]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size([256, 1024, 2048, 4096][values["shadow"]], true)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		var quality: int = values["effects_quality"]
		RenderingServer.environment_set_ssao_quality(quality + 1, quality < 2, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(quality + 1, quality < 2, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size([128, 256, 384][quality], [64, 128, 192][quality])
	_walk(get_tree().root)
	changed.emit()

func set_value(key: String, value: Variant) -> void:
	if not values.has(key) or typeof(value) != typeof(values[key]): return
	if typeof(value) == TYPE_INT:
		var limits := {"scale": 3, "aa": 2, "shadow": 3, "shadow_distance": 3, "glow_strength": 3, "fps": FPS.size() - 1, "effects_quality": 2}
		if not limits.has(key) or value < 0 or value > limits[key]: return
	values[key] = value
	if key not in ["fps", "vsync"]: values["preset"] = -1
	apply_all()
	_save()

func select_preset(index: int) -> void:
	var saved_fps: int = values["fps"]
	var saved_vsync: bool = values["vsync"]
	values = preset(index)
	values["fps"] = saved_fps
	values["vsync"] = saved_vsync
	apply_all()
	_save()

func reset_defaults() -> void:
	values = preset(1)
	apply_all()
	_save()

func request_display(resolution: int, window_mode: int) -> void:
	if mobile or resolution < 0 or resolution >= resolution_sizes.size() or window_mode < 0 or window_mode > 2: return
	if not previous_display.is_empty(): cancel_display()
	previous_display = {"resolution": display["resolution"], "mode": display["mode"], "size": DisplayServer.window_get_size(), "position": DisplayServer.window_get_position(), "actual_mode": DisplayServer.window_get_mode(), "borderless": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)}
	display = {"resolution": resolution, "mode": window_mode}
	remaining = 15.0
	_apply_display(display)
	display_pending_changed.emit()

func _apply_display(data: Dictionary) -> void:
	if mobile or DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, data["mode"] == 1)
	DisplayServer.window_set_size(resolution_sizes[data["resolution"]])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if data["mode"] == 2 else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)

func confirm_display() -> void:
	if previous_display.is_empty(): return
	previous_display.clear()
	remaining = 0
	_save()
	display_pending_changed.emit()

func cancel_display() -> void:
	if previous_display.is_empty(): return
	display = {"resolution": previous_display["resolution"], "mode": previous_display["mode"]}
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, previous_display["borderless"])
	DisplayServer.window_set_size(previous_display["size"])
	DisplayServer.window_set_position(previous_display["position"])
	DisplayServer.window_set_mode(previous_display["actual_mode"])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	previous_display.clear()
	remaining = 0
	display_pending_changed.emit()

func _process(delta: float) -> void:
	if previous_display.is_empty(): return
	remaining -= delta
	if remaining <= 0: cancel_display()

func _save() -> void:
	var config := ConfigFile.new()
	for key in values: config.set_value("quality", key, values[key])
	var committed := display if previous_display.is_empty() else previous_display
	var size: Vector2i = resolution_sizes[committed["resolution"]]
	config.set_value("display", "width", size.x)
	config.set_value("display", "height", size.y)
	config.set_value("display", "window_mode", committed["mode"])
	var error := config.save(PATH)
	status = "已保存到本机。" if error == OK else "设置已生效，但保存失败：" + error_string(error)
	changed.emit()
