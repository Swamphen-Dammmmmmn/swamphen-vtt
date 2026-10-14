extends VBoxContainer

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const Modal = preload("res://ui/components/page_modal.gd")
var selectors: Dictionary = {}
var toggles: Dictionary = {}
var resolution: OptionButton
var mode: OptionButton
var confirmation: Control
var confirmation_layer: CanvasLayer
var countdown: Label
var state: Label
var actual_size: Label
var ratio_filter: OptionButton
var detect_button: Button
var detected_size := Vector2i.ZERO
const RATIOS := ["全部", "当前屏幕比例", "16:9", "16:10", "3:2", "4:3", "5:4", "超宽", "其他"]
var syncing := false

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_choice("preset", "画质预设", ["流畅", "标准", "高"] if Graphics.mobile else ["流畅", "标准", "高", "极高"])
	_section("显示")
	if Mobile.enabled: add_child(preload("res://ui/components/mobile_display_panel.gd").new())
	if not Graphics.mobile:
		actual_size = Style.text("", 14, true)
		add_child(actual_size)
		ratio_filter = _option("屏幕比例")
		for item in RATIOS: ratio_filter.add_item(item)
		ratio_filter.item_selected.connect(func(_index: int): _populate_resolutions())
		resolution = _option("分辨率")
		resolution.get_popup().max_size.y = 480
		detect_button = Button.new()
		detect_button.text = "识别"
		detect_button.tooltip_text = "识别并选择当前屏幕分辨率"
		Style.card_button(detect_button)
		resolution.get_parent().add_child(detect_button)
		detect_button.pressed.connect(_detect_resolution)
		detected_size = DisplayServer.screen_get_size()
		_populate_resolutions()
		mode = _option("显示模式")
		mode.add_item("窗口")
		mode.add_item("无边框窗口")
		mode.add_item("全屏")
		var apply := Button.new()
		apply.text = "应用显示设置"
		Style.card_button(apply)
		add_child(apply)
		apply.pressed.connect(func(): Graphics.request_display(resolution.get_selected_id(), mode.selected))
		add_child(Style.text("分辨率不自动调整；更改显示设置后需在 15 秒内确认。", 14, true))
	else:
		add_child(Style.text("屏幕尺寸跟随手机系统自动适应。", 14, true))
	_choice("fps", "帧率上限", ["30", "60", "90", "120", "144", "不限"])
	_toggle("vsync", "垂直同步")
	add_child(Style.text("垂直同步开启时，帧率还受显示器刷新率限制。", 14, true))
	_section("基础画质")
	_choice("scale", "三维渲染比例", ["50%", "67%", "75%", "100%"])
	_choice("aa", "抗锯齿 · MSAA", ["关闭", "2×", "4×"])
	_choice("shadow", "阴影质量", ["关闭", "低 · 1024", "中 · 2048", "高 · 4096"])
	_choice("shadow_distance", "阴影显示距离", ["近 · 30", "标准 · 60", "远 · 120", "很远 · 200"])
	_toggle("glow", "梦幻柔光")
	_choice("glow_strength", "柔光强度", ["轻微 · 0.15", "默认 · 0.27", "明显 · 0.40", "强 · 0.55"])
	add_child(Style.text("渲染比例只改变三维画面，不降低界面文字清晰度。", 14, true))
	if not Graphics.mobile:
		_section("PC 画面增强")
		_toggle("ssao", "接触阴影 · SSAO")
		_toggle("ssil", "间接补光 · SSIL")
		_toggle("ssr", "屏幕空间反射 · SSR")
		_toggle("volume", "体积雾")
		_choice("effects_quality", "增强质量", ["低", "标准", "高"])
		add_child(Style.text("增强质量控制补光与接触阴影的采样、反射步数和体积雾精度，仅作用于已开启效果。", 14, true))
	var reset := Button.new()
	reset.text = "恢复视频默认"
	Style.card_button(reset)
	add_child(reset)
	reset.pressed.connect(Graphics.reset_defaults)
	add_child(Style.text("恢复画质、帧率和垂直同步，不改变已确认的分辨率或窗口模式。", 14, true))
	state = Layout.status()
	add_child(state)
	Graphics.changed.connect(_sync)
	Graphics.display_pending_changed.connect(_sync_display)
	_sync()
	_sync_display()

func _section(title: String) -> void:
	if get_child_count() > 0: add_child(HSeparator.new())
	add_child(Style.text(title, 20))

func _option(title: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(Style.field_label(title))
	row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_SHRINK_END
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.resized.connect(func(): option.custom_minimum_size.x = clampf(row.size.x * 0.45, 160, 400))
	row.add_child(option)
	BoardUiStyle.style_controls(row, 44)
	return option

func _choice(key: String, title: String, items: Array) -> void:
	var option := _option(title)
	for item in items: option.add_item(item)
	if key == "preset": option.add_item("自定义")
	selectors[key] = option
	option.item_selected.connect(func(index: int):
		if syncing: return
		if key == "preset":
			if index < items.size(): Graphics.select_preset(index)
		else: Graphics.set_value(key, index)
	)

func _toggle(key: String, title: String) -> void:
	var button := CheckButton.new()
	button.text = title
	button.custom_minimum_size.y = 44
	add_child(button)
	toggles[key] = button
	button.toggled.connect(func(active: bool):
		if not syncing: Graphics.set_value(key, active)
	)

func _sync() -> void:
	if not is_instance_valid(state): return
	syncing = true
	for key in selectors:
		var value: int = Graphics.values[key]
		selectors[key].select(selectors[key].item_count - 1 if value < 0 else value)
	for key in toggles: toggles[key].set_pressed_no_signal(Graphics.values[key])
	selectors["shadow_distance"].disabled = Graphics.values["shadow"] == 0
	selectors["glow_strength"].disabled = not Graphics.values["glow"]
	if selectors.has("effects_quality"):
		selectors["effects_quality"].disabled = not (Graphics.values["ssao"] or Graphics.values["ssil"] or Graphics.values["ssr"] or Graphics.values["volume"])
	Layout.set_status(state, Graphics.status)
	syncing = false

func _sync_display() -> void:
	if resolution == null: return
	var size: Vector2i = Graphics.resolution_sizes[Graphics.display["resolution"]]
	if ratio_filter.selected > 0 and not _matches_ratio(size):
		ratio_filter.select(0)
		_populate_resolutions()
	for i in range(resolution.item_count):
		if not resolution.get_popup().is_item_separator(i) and resolution.get_item_id(i) == Graphics.display["resolution"]:
			resolution.select(i)
			break
	mode.select(Graphics.display["mode"])
	if Graphics.previous_display.is_empty(): _close_confirmation()
	elif not is_instance_valid(confirmation): _open_confirmation()

func _open_confirmation() -> void:
	confirmation_layer = CanvasLayer.new()
	var parent_layer := get_canvas_layer_node()
	confirmation_layer.layer = parent_layer.layer + 1 if parent_layer != null else 1
	add_child(confirmation_layer)
	var dialog := Modal.new()
	confirmation = dialog
	dialog.theme = theme
	confirmation_layer.add_child(dialog)
	var size: Vector2i = Graphics.resolution_sizes[Graphics.display["resolution"]]
	var mode_name: String = ["窗口", "无边框窗口", "全屏"][Graphics.display["mode"]]
	dialog.configure("保留显示设置？", "%d × %d · %s" % [size.x, size.y, mode_name])
	countdown = Style.text("%d 秒后自动恢复之前的显示设置。" % ceili(Graphics.remaining), 16, true)
	dialog.content.add_child(countdown)
	var keep := dialog.add_action("保留", Graphics.confirm_display, true)
	dialog.add_action("恢复", Graphics.cancel_display)
	keep.grab_focus()
	dialog.dismissed.connect(func():
		confirmation = null
		countdown = null
		Graphics.cancel_display()
		if is_instance_valid(confirmation_layer): confirmation_layer.queue_free()
		confirmation_layer = null
	)

func _close_confirmation() -> void:
	if is_instance_valid(confirmation): confirmation.dismiss()

func _matches_ratio(size: Vector2i) -> bool:
	var selected: String = RATIOS[ratio_filter.selected]
	if selected == "全部": return true
	if selected == "当前屏幕比例":
		return detected_size.y > 0 and absf(float(size.x) / size.y - float(detected_size.x) / detected_size.y) < 0.015
	return Graphics.ResolutionCatalog.ratio(size) == selected

func _populate_resolutions(preferred_id := -1) -> void:
	if resolution == null: return
	var selected_id := preferred_id if preferred_id >= 0 else resolution.get_selected_id()
	resolution.clear()
	for group in Graphics.ResolutionCatalog.groups(Graphics.resolution_sizes):
		var candidates: Array = []
		for size in group[1]:
			if _matches_ratio(size): candidates.append(size)
		if candidates.is_empty(): continue
		resolution.add_separator(group[0])
		for size in candidates:
			var suffix := " · 当前屏幕" if size == detected_size else ""
			resolution.add_item("%d × %d%s" % [size.x, size.y, suffix], Graphics.resolution_sizes.find(size))
	var fallback := -1
	for i in range(resolution.item_count):
		if resolution.get_popup().is_item_separator(i): continue
		if fallback < 0: fallback = i
		if resolution.get_item_id(i) == selected_id:
			resolution.select(i)
			return
	if fallback >= 0: resolution.select(fallback)

func _detect_resolution() -> void:
	detected_size = DisplayServer.screen_get_size()
	if not Graphics.ResolutionCatalog.allowed(detected_size): return
	if not Graphics.resolution_sizes.has(detected_size): Graphics.resolution_sizes.append(detected_size)
	ratio_filter.select(1)
	_populate_resolutions(Graphics.resolution_sizes.find(detected_size))

func _process(_delta: float) -> void:
	if is_instance_valid(countdown): countdown.text = "%d 秒后自动恢复之前的显示设置。" % maxi(0, ceili(Graphics.remaining))
	if actual_size != null:
		var dimensions := DisplayServer.window_get_size()
		var native := DisplayServer.screen_get_size()
		if detected_size != native:
			detected_size = native
			if Graphics.ResolutionCatalog.allowed(native) and not Graphics.resolution_sizes.has(native): Graphics.resolution_sizes.append(native)
			_populate_resolutions()
		detect_button.disabled = not Graphics.ResolutionCatalog.allowed(native)
		actual_size.text = "当前屏幕：%d × %d · %s\n当前窗口：%d × %d · %s" % [native.x, native.y, Graphics.ResolutionCatalog.ratio(native), dimensions.x, dimensions.y, Graphics.ResolutionCatalog.ratio(dimensions)]

func _exit_tree() -> void:
	if Graphics.changed.is_connected(_sync): Graphics.changed.disconnect(_sync)
	if Graphics.display_pending_changed.is_connected(_sync_display): Graphics.display_pending_changed.disconnect(_sync_display)
	Graphics.cancel_display()
	_close_confirmation()
