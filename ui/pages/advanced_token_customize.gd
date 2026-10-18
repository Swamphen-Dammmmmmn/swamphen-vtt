extends "res://ui/pages/token_customize.gd"


const ImageStore = preload("res://scripts/token_image_store.gd")
const StickerData = preload("res://scripts/token_sticker.gd")
var image_dialog: FileDialog
var file_picker_active := false
var sticker_options: Dictionary = {}
var image_modal: Control
var sticker_inputs: Dictionary = {}
var sticker_adjustment_actions: BoxContainer
var visibility_row: HBoxContainer
var smoothing_slider: HSlider
var smoothing_sync := false
var sticker_rows: Control
var sticker_empty: Label
var sticker_picture: TextureRect
var sticker_backing: ColorWell
var sticker_info: Label
var sticker_face := "front"
var sticker_face_buttons: Dictionary = {}
var sticker_actions: Dictionary = {}
var sticker_mode := ""
var sticker_panel: PanelContainer
const StickerPanel = preload("res://ui/components/token_sticker_panel.gd")
var sticker_cached_id := "@"
var sticker_error := ""
var sticker_error_face := ""
const AdvancedPreview = preload("res://ui/components/advanced_token_preview.gd")
const ComponentData = preload("res://scripts/token_components.gd")
const TransformScene = preload("res://ui/components/utility_panel.tscn")
const TransformPanel = preload("res://ui/components/token_transform_panel.gd")
var width_input: LineEdit
var length_input: LineEdit
var adjustment_mode := ""
var transform_panel: PanelContainer
var component_kind := "base"
var component_values := ComponentData.defaults()
var component_inputs: Dictionary = {}
var component_rows: Dictionary = {}
var shape_choice: OptionButton
var sides_input: OptionButton
var visible_input: CheckButton
var component_color: ColorWell
var component_tabs: Dictionary = {}
var boundary_notice: Label
var loading_component := false
var editor_panel: PanelContainer
var editor_content: VBoxContainer
var editor_scroll: ScrollContainer
var editor_title: Label
var presentation_bar: HBoxContainer
var presentation_buttons: Dictionary = {}
const ContourData = preload("res://scripts/token_contour.gd")
var material_editor: MaterialEditor
var mode_materials: Dictionary = {}
var contour_body: VBoxContainer
var contour_inputs: Dictionary = {}
var contour_button: Button
var contour_status: Label
var dimension_label: Label
var thickness_label: Label
var sticker_notice: Label
var attribute_bodies: Dictionary = {}
var attribute_buttons: Dictionary = {}
var attribute_page := {"base": "shape", "standee": "shape"}
var attribute_scroll := {"base.shape": 0, "base.display": 0, "standee.shape": 0, "standee.display": 0, "standee.image": 0}
var designer_visibility := {"base": true, "standee": true}
var eye_buttons: Dictionary = {}
var adjustment_buttons: Dictionary = {}
var adjustment_actions: BoxContainer
var size_reset_values: Array = []
var list_panel: VBoxContainer
var list_heading: Button
var list_scroll: VBoxContainer
var list_body: VBoxContainer
var list_expanded := true
var left_handle: Button
var right_handle: Button
var edge_open := {"left": true, "right": true}
var edge_tweens: Dictionary = {}
var component_message := ""
var common_error_field := ""
var error_component := ""
var error_components: Array = []
var list_arrow: TextureRect
var list_arrow_tween: Tween
var component_marks: Dictionary = {}
const LeftIcon = preload("res://ui/icons/chevron_left.svg")
const RightIcon = preload("res://ui/icons/chevron_right.svg")
const DownIcon = preload("res://ui/icons/chevron_down.svg")
const EyeOpen = preload("res://ui/icons/eye_open.svg")
const EyeClosed = preload("res://ui/icons/eye_closed.svg")

func _init() -> void:
	kind = "advanced"

func _new_preview() -> Control:
	return AdvancedPreview.new()

func _ready() -> void:
	super._ready()
	options_panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(16))
	form.add_theme_constant_override("separation", 12)
	Layout.fold(stats_fold)
	list_panel.reparent(form)
	var heading: HBoxContainer = heading_title.get_parent()
	heading.get_child(0).hide()
	heading.get_child(1).hide()
	heading.add_theme_constant_override("separation", 8)
	heading_title.text = "棋子设置"
	heading_title.add_theme_font_size_override("font_size", Typography.SECTION)
	var header_space := Control.new()
	header_space.custom_minimum_size = Vector2(44, 44)
	header_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(header_space)
	heading.move_child(header_space, 0)
	var footer: HBoxContainer = save_button.get_parent()
	footer.get_child(0).text = "返回"
	footer.add_theme_constant_override("separation", 8)
	save_button.text = instance_apply_title if instance_mode else "保存"
	save_button.custom_minimum_size.x = 72
	left_handle = _icon_button(LeftIcon, func(): _toggle_edge("left"))
	add_child(left_handle)
	right_handle = _icon_button(RightIcon, func(): _toggle_edge("right"))
	add_child(right_handle)
	_prepare_scroll(form_scroll, options_content)
	_prepare_scroll(editor_scroll, editor_content)
	boundary_notice.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _show_input_problem()
	)
	_queue_fit()

func _icon_button(texture: Texture2D, action: Callable) -> Button:
	var button := _button("", action)
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)
	button.custom_minimum_size = Vector2(44, 44)
	return button

func _separator(parent: Control) -> void:
	var separator := HSeparator.new()
	var face := StyleBoxLine.new()
	face.color = Color("dce3ec")
	face.thickness = 1
	separator.add_theme_stylebox_override("separator", face)
	parent.add_child(separator)

func _flat_button(button: Button) -> void:
	button.set_meta("flat_list_row", true)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var face := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		face.set_border_width_all(0)
		face.bg_color = Color.WHITE if state == "normal" else Color("e8eff8")
		button.add_theme_stylebox_override(state, face)

func _button(text: String, action: Callable, height := 44.0) -> Button:
	var button := Button.new()
	button.text = text
	Style.card_button(button, height)
	button.pressed.connect(action)
	return button

func _build_appearance_form(parent: Control) -> void:
	parent.add_child(Style.text("实际占地 · 格", Typography.BODY))
	var footprint_row := _pair_row(parent, "宽", "长")
	width_input = footprint_row[0]
	length_input = footprint_row[1]
	width_input.text = "1"
	length_input.text = "1"
	_build_component_list()
	editor_panel = Style.card()
	editor_panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(16))
	add_child(editor_panel)
	editor_content = Style.column(12)
	editor_panel.add_child(editor_content)
	var heading := HBoxContainer.new()
	editor_content.add_child(heading)
	editor_title = Style.text("底座", Typography.SECTION)
	editor_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(editor_title)
	var header_space := Control.new()
	header_space.custom_minimum_size = Vector2(44, 44)
	header_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(header_space)
	presentation_bar = HBoxContainer.new()
	presentation_bar.add_theme_constant_override("separation", 8)
	editor_content.add_child(presentation_bar)
	for item in [["solid", "实体立牌"], ["image", "图片立牌"]]:
		var key: String = item[0]
		var button := _button(item[1], func(): _select_presentation(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presentation_bar.add_child(button)
		presentation_buttons[key] = button
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	editor_content.add_child(tabs)
	for item in [["shape", "形状与尺寸"], ["display", "材质与显示"], ["image", "图片"]]:
		var key: String = item[0]
		var button := _button(item[1], func(): _switch_attribute(key), 36)
		button.add_theme_font_size_override("font_size", Typography.CAPTION)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
		attribute_buttons[key] = button
	editor_scroll = ScrollContainer.new()
	editor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_content.add_child(editor_scroll)
	var stack := Style.column(0)
	editor_scroll.add_child(stack)
	for key in ["shape", "display", "image"]:
		var body := Style.column(12)
		stack.add_child(body)
		attribute_bodies[key] = body
	var shape_body: VBoxContainer = attribute_bodies["shape"]
	shape_choice = _add_choice(shape_body, "样式", ["圆", "椭圆", "矩形", "正多边形"])
	sides_input = _add_choice(shape_body, "边数", ["3", "4", "5", "6", "7", "8", "9", "10", "11", "12"])
	component_rows["sides"] = sides_input.get_parent()
	dimension_label = Style.text("尺寸 · 英尺", Typography.BODY)
	shape_body.add_child(dimension_label)
	var dimensions := _pair_row(shape_body, "直径", "长")
	component_inputs["width_ft"] = dimensions[0]
	component_inputs["length_ft"] = dimensions[1]
	component_inputs["height_ft"] = dimensions[1]
	component_rows["width_ft"] = dimensions[0].get_parent()
	component_rows["length_ft"] = dimensions[1].get_parent()
	thickness_label = Style.text("厚度", Typography.CAPTION, true)
	shape_body.add_child(thickness_label)
	component_inputs["thickness_ft"] = _numeric_input(shape_body)
	_build_contour_form(shape_body)
	var display_body: VBoxContainer = attribute_bodies["display"]
	material_editor = MaterialEditor.new()
	material_editor.popup_host = self
	display_body.add_child(material_editor)
	component_color = material_editor.color_input
	visible_input = CheckButton.new()
	visible_input.text = ""
	Style.button(visible_input)
	visibility_row = HBoxContainer.new()
	var visibility_label := Style.text("实际显示")
	visibility_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visibility_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	visibility_row.add_child(visibility_label)
	visibility_row.add_child(visible_input)
	display_body.add_child(visibility_row)
	_build_sticker_form(attribute_bodies["image"])
	boundary_notice = Layout.status()
	editor_content.add_child(boundary_notice)
	var actions := Layout.pair(editor_content)
	adjustment_actions = actions
	for item in [["position", "调整位置"], ["rotation", "调整旋转"], ["scale", "调整尺寸"]]:
		var next_mode: String = item[0]
		var button := _button(item[1], func(): _open_adjustment(next_mode))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if next_mode == "scale":
			editor_content.add_child(button)
		else: actions.add_child(button)
		adjustment_buttons[next_mode] = button
	editor_content.move_child(sticker_adjustment_actions, editor_content.get_child_count() - 1)
	transform_panel = TransformScene.instantiate()
	transform_panel.set_script(TransformPanel)
	add_child(transform_panel)
	transform_panel.values_changed.connect(_transform_values_changed)
	transform_panel.reset_requested.connect(_reset_transform)
	transform_panel.panel_closed.connect(_close_adjustment)
	transform_panel.interval_changed.connect(func(value: float):
		preview.gizmo.end_drag()
		preview.gizmo.snap_interval = value
	)
	preview.gizmo.values_changed.connect(_gizmo_values_changed)
	for body in attribute_bodies.values(): body.minimum_size_changed.connect(_queue_fit)
	_load_component()

func _build_component_list() -> void:
	list_panel = Style.column(8)
	add_child(list_panel)
	_separator(list_panel)
	list_heading = _button("部件", _toggle_list, 36)
	list_heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_flat_button(list_heading)
	list_panel.add_child(list_heading)
	list_arrow = TextureRect.new()
	list_arrow.texture = DownIcon
	list_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	list_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	list_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_heading.add_child(list_arrow)
	list_arrow.anchor_left = 1.0
	list_arrow.anchor_right = 1.0
	list_arrow.anchor_top = 0.5
	list_arrow.anchor_bottom = 0.5
	list_arrow.offset_left = -28
	list_arrow.offset_right = -8
	list_arrow.offset_top = -10
	list_arrow.offset_bottom = 10
	list_arrow.pivot_offset = Vector2(10, 10)
	list_scroll = Style.column(4)
	list_panel.add_child(list_scroll)
	list_body = list_scroll
	for item in [["base", "底座"], ["standee", "立牌"]]:
		var key: String = item[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		list_body.add_child(row)
		var select := _button(item[1], func(): _switch_component(key))
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_flat_button(select)
		row.add_child(select)
		component_tabs[key] = select
		var mark := Style.text("", Typography.TAG, true)
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mark)
		component_marks[key] = mark
		var eye := _icon_button(EyeOpen, func(): _toggle_designer_visibility(key))
		_flat_button(eye)
		row.add_child(eye)
		eye_buttons[key] = eye

func _load_appearance(params: Dictionary) -> void:
	width_input.text = str(params["width"])
	length_input.text = str(params["length"])
	component_values = params["components"].duplicate(true)
	_load_component()

func _connect_appearance() -> void:
	width_input.text_changed.connect(func(_text: String): _refresh_preview())
	length_input.text_changed.connect(func(_text: String): _refresh_preview())
	shape_choice.item_selected.connect(func(_index: int):
		if component_values["base"]["shape"] == "circle" and shape_choice.selected != 0:
			component_inputs["length_ft"].text = str(component_values["base"]["length_ft"])
		_capture_component()
		_adjust_rows()
		_refresh_preview()
		if adjustment_mode == "scale": _open_adjustment("scale")
	)
	sides_input.item_selected.connect(func(_index: int): _refresh_preview())
	visible_input.toggled.connect(func(_value: bool): _refresh_preview())
	material_editor.changed.connect(func():
		if not loading_component: _refresh_material_preview())
	for input in [component_inputs["width_ft"], component_inputs["length_ft"], component_inputs["thickness_ft"]]:
		input.text_changed.connect(func(_text: String):
			if not loading_component:
				preview.gizmo.end_drag()
				_refresh_preview()
				if adjustment_mode == "scale": transform_panel.sync_values(_adjustment_values("scale"))
		)
	_refresh_preview()

func _number_text(text: String) -> Variant:
	var value := text.strip_edges()
	return value.to_float() if value.is_valid_float() else value

func _capture_component() -> void:
	if loading_component: return
	var data: Dictionary = component_values[component_kind]
	data["visible"] = visible_input.button_pressed
	data["shape"] = ["circle", "ellipse", "rectangle", "polygon"][shape_choice.selected] if component_kind == "base" else "rectangle"
	data["sides"] = sides_input.selected + 3
	for key in ["width_ft", "length_ft", "height_ft", "thickness_ft"]:
		if (component_kind == "base" and key == "height_ft") or (component_kind == "standee" and key == "length_ft"): continue
		data[key] = _number_text(component_inputs[key].text)
	if data["shape"] == "circle": data["length_ft"] = data["width_ft"]
	data["material"] = material_editor.value.duplicate(true)
	data["color"] = str(data["material"]["color"])
	if component_kind == "standee" and not sticker_inputs.is_empty():
		var specification := _sticker_spec()
		specification["faces"][sticker_face]["scale"] = _percent(sticker_inputs["scale"].text)
		specification["faces"][sticker_face]["backing_color"] = sticker_backing.color.to_html(false)
		if not contour_inputs.is_empty():
			var options := {}
			for key in contour_inputs: options[key] = _number_text(contour_inputs[key].text)
			data["contour_options"] = options

func _load_component() -> void:
	loading_component = true
	var data: Dictionary = component_values[component_kind]
	shape_choice.select(maxi(0, ["circle", "ellipse", "rectangle", "polygon"].find(data["shape"])))
	sides_input.select(int(data.get("sides", 6)) - 3)
	visible_input.set_pressed_no_signal(data["visible"])
	var image_mode: bool = component_kind == "standee" and data.get("presentation", "solid") == "image"
	var defaults := Surface.defaults("acrylic", "f1f7fa") if image_mode else Surface.defaults("matte", ComponentData.defaults()[component_kind]["color"])
	defaults.board_visible = data.has("contour") if image_mode else true
	material_editor.configure(Surface.for_component(data, component_kind), defaults, image_mode)
	component_inputs["width_ft"].text = str(data["width_ft"])
	component_inputs["length_ft"].text = str(data["length_ft"] if component_kind == "base" else data["height_ft"])
	component_inputs["thickness_ft"].text = str(data["thickness_ft"])
	var options: Dictionary = component_values["standee"].get("contour_options", ContourData.defaults())
	for key in contour_inputs: contour_inputs[key].text = str(options.get(key, 0.0 if key == "smooth_pct" else ContourData.defaults()[key]))
	_sync_smoothing_slider()
	_load_sticker()
	_adjust_rows()
	loading_component = false

func _adjust_rows() -> void:
	var is_base := component_kind == "base"
	shape_choice.get_parent().visible = is_base
	var image_mode: bool = not is_base and component_values["standee"].get("presentation", "solid") == "image"
	dimension_label.text = "参考尺寸 · 英尺" if image_mode else "尺寸 · 英尺"
	presentation_bar.visible = not is_base
	for key in presentation_buttons: _highlight_button(presentation_buttons[key], component_values["standee"].get("presentation", "solid") == key)
	thickness_label.visible = true
	component_inputs["thickness_ft"].visible = true
	contour_body.visible = image_mode
	component_rows["sides"].visible = is_base and shape_choice.selected == 3
	component_rows["length_ft"].visible = not is_base or shape_choice.selected != 0
	component_rows["width_ft"].get_child(0).text = "直径" if is_base and shape_choice.selected == 0 else "宽"
	component_rows["length_ft"].get_child(0).text = "长" if is_base else "高"
	_update_list()
	editor_title.text = "底座" if is_base else "立牌"
	_show_attribute(false)

func _build_contour_form(parent: Control) -> void:
	contour_body = Style.column(12)
	parent.add_child(contour_body)
	_separator(contour_body)
	contour_body.add_child(Style.text("自动轮廓", Typography.BODY))
	var edges := _pair_row(contour_body, "包边 · 英尺", "连接条宽 · 英尺")
	contour_inputs["border_ft"] = edges[0]
	contour_inputs["bridge_ft"] = edges[1]
	contour_body.add_child(Style.text("填补孔洞上限 · 平方英寸", Typography.CAPTION, true))
	contour_inputs["hole_sq_in"] = _numeric_input(contour_body)
	contour_body.add_child(Style.text("圆滑程度 · %", Typography.CAPTION, true))
	var smoothing_row := HBoxContainer.new()
	smoothing_row.add_theme_constant_override("separation", 8)
	contour_body.add_child(smoothing_row)
	smoothing_slider = HSlider.new()
	smoothing_slider.min_value = 0
	smoothing_slider.max_value = 100
	smoothing_slider.step = 1
	smoothing_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smoothing_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	smoothing_slider.custom_minimum_size.y = 28
	smoothing_row.add_child(smoothing_slider)
	contour_inputs["smooth_pct"] = _numeric_input(smoothing_row)
	contour_inputs["smooth_pct"].size_flags_horizontal = Control.SIZE_FILL
	contour_inputs["smooth_pct"].custom_minimum_size.x = 72
	smoothing_slider.value_changed.connect(func(value: float):
		if not smoothing_sync and not loading_component: contour_inputs["smooth_pct"].text = str(value)
	)
	contour_inputs["smooth_pct"].text_changed.connect(func(_text: String): _sync_smoothing_slider())
	for key in contour_inputs:
		contour_inputs[key].text = str(ContourData.defaults()[key])
		contour_inputs[key].text_changed.connect(func(_text: String):
			if not loading_component: _refresh_preview()
		)
	contour_button = _button("生成轮廓", _generate_contour)
	contour_body.add_child(contour_button)
	contour_status = Layout.status()
	contour_status.text = "尚未生成"
	contour_body.add_child(contour_status)

func _generate_contour() -> void:
	_capture_component()
	_close_adjustment()
	_close_sticker_adjustment()
	var checked := ComponentData.validate(component_values, preview.current_extent, false)
	if not checked["ok"]:
		_show_contour_error(checked["message"])
		return
	var prepared := ContourData.prepare(checked["components"]["standee"])
	if not prepared["ok"]:
		_show_contour_error(prepared["message"])
		return
	var count: int = prepared["islands"].size()
	if count <= 1:
		_finish_contour(prepared, false)
		return
	image_modal = Modal.new()
	page.add_overlay(image_modal)
	image_modal.configure("连接分离部分？", "检测到%d个分离部分。可用透明连接条连接，或保留全部部分独立存在。" % count)
	image_modal.add_action("连接并生成", func():
		image_modal.dismiss()
		_finish_contour(prepared, true)
	, true)
	image_modal.add_action("保持分离并生成", func():
		image_modal.dismiss()
		_finish_contour(prepared, false)
	)
	image_modal.add_action("取消", func(): image_modal.dismiss())
	image_modal.dismissed.connect(func(): image_modal = null)

func _finish_contour(prepared: Dictionary, connect: bool) -> void:
	if prepared["signature"] != ContourData.signature(component_values["standee"]):
		_show_contour_error("参数已经变化，请重新生成。")
		return
	var result := ContourData.finish(prepared, connect)
	if not result["ok"]:
		_show_contour_error(result["message"])
		return
	component_values["standee"]["contour"] = result["contour"]
	material_editor.value.board_visible = true
	material_editor.configure(material_editor.value, material_editor.default_value, true)
	_refresh_preview()

func _show_contour_error(message: String) -> void:
	image_modal = Modal.new()
	page.add_overlay(image_modal)
	image_modal.configure("轮廓未生成", message)
	image_modal.add_action("关闭", func(): image_modal.dismiss())
	image_modal.dismissed.connect(func(): image_modal = null)

func _select_presentation(mode: String) -> void:
	if component_kind != "standee" or component_values["standee"].get("presentation", "solid") == mode: return
	_capture_component()
	_close_adjustment()
	_close_sticker_adjustment()
	component_color.get_popup().hide()
	sticker_backing.get_popup().hide()
	var previous: String = component_values["standee"].get("presentation", "solid")
	mode_materials[previous] = material_editor.value.duplicate(true)
	component_values["standee"]["presentation"] = mode
	var legacy: Dictionary = component_values["standee"].duplicate(true)
	legacy.erase("material")
	component_values["standee"]["material"] = mode_materials.get(mode, Surface.for_component(legacy, "standee")).duplicate(true)
	_load_component()
	attribute_page["standee"] = "image" if mode == "image" else "shape"
	_adjust_rows()
	_sync_sticker_buttons()
	_refresh_preview()

func _switch_component(name: String) -> void:
	if name != component_kind:
		_capture_component()
		attribute_scroll[component_kind + "." + attribute_page[component_kind]] = editor_scroll.scroll_vertical
		_close_adjustment()
		_close_sticker_adjustment()
		component_color.get_popup().hide()
		sticker_backing.get_popup().hide()
		component_kind = name
		_load_component()
		_show_attribute(true)
		_refresh_preview()
	if not edge_open["right"]: _toggle_edge("right")

func _switch_attribute(key: String) -> void:
	if key == attribute_page[component_kind]: return
	attribute_scroll[component_kind + "." + attribute_page[component_kind]] = editor_scroll.scroll_vertical
	_close_sticker_adjustment()
	attribute_page[component_kind] = key
	_close_adjustment()
	component_color.get_popup().hide()
	sticker_backing.get_popup().hide()
	_show_attribute(true)
	_refresh_preview()

func _show_attribute(animate: bool) -> void:
	var image_mode: bool = component_kind == "standee" and component_values["standee"].get("presentation", "solid") == "image"
	attribute_buttons["image"].visible = component_kind == "standee"
	attribute_buttons["display"].visible = true
	attribute_buttons["shape"].text = "板体与轮廓" if image_mode else "形状与尺寸"
	attribute_buttons["image"].text = "图片与布局" if image_mode else "图片"
	# Image task comes first; other modes keep shape/display/image order.
	var tab_bar: HBoxContainer = attribute_buttons["shape"].get_parent()
	tab_bar.move_child(attribute_buttons["image"], 0 if image_mode else tab_bar.get_child_count() - 1)
	var visibility_parent: Control = attribute_bodies["display"]
	if visibility_row.get_parent() != visibility_parent:
		visibility_row.reparent(visibility_parent)
	_sync_attribute_edges()
	var selected: String = attribute_page[component_kind]
	adjustment_actions.visible = selected == "shape"
	sticker_adjustment_actions.visible = selected == "image"
	adjustment_buttons["scale"].visible = selected == "shape" and component_kind == "base"
	for key in attribute_bodies:
		attribute_bodies[key].visible = key == selected
		_highlight_button(attribute_buttons[key], key == selected)
	if animate: Style.Motion.fade_in(attribute_bodies[selected], 0.12)
	editor_scroll.set_deferred("scroll_vertical", attribute_scroll[component_kind + "." + selected])
	_queue_fit()

func _toggle_designer_visibility(key: String) -> void:
	designer_visibility[key] = not designer_visibility[key]
	if key == component_kind:
		preview.gizmo.end_drag()
		preview.sticker_gizmo.end_drag()
	_refresh_preview()

func _update_list() -> void:
	for key in component_tabs:
		var label := "底座" if key == "base" else "立牌"
		component_marks[key].text = "有误" if key in error_components else ("实际隐藏" if not component_values[key]["visible"] else "")
		component_marks[key].add_theme_color_override("font_color", Color("b33c3c") if key in error_components else Color("64748b"))
		component_tabs[key].text = label
		_highlight_button(component_tabs[key], key == component_kind)
		eye_buttons[key].icon = EyeOpen if designer_visibility[key] else EyeClosed
		eye_buttons[key].tooltip_text = "在设计器中隐藏" if designer_visibility[key] else "在设计器中显示"

func _toggle_list() -> void:
	list_expanded = not list_expanded
	if list_arrow_tween != null and list_arrow_tween.is_valid(): list_arrow_tween.kill()
	list_arrow_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	list_arrow_tween.tween_property(list_arrow, "rotation", 0.0 if list_expanded else -PI / 2, preload("res://ui/components/page_motion.gd").duration(0.16))
	if list_expanded:
		list_scroll.show()
		Style.Motion.fade_in(list_scroll, 0.16)
		_queue_fit()
	else:
		_set_ui_enabled(list_scroll, false)
		var tween := Style.Motion.fade_to(list_scroll, 0.0, 0.16)
		tween.finished.connect(func():
			if not list_expanded:
				list_scroll.hide()
				_queue_fit()
		)
	_set_ui_enabled(list_scroll, list_expanded)

func _appearance() -> Dictionary:
	_capture_component()
	return {"kind": "advanced", "width": _number_text(width_input.text), "length": _number_text(length_input.text), "components": component_values.duplicate(true), "active_component": component_kind, "designer_visibility": designer_visibility.duplicate(), "sticker_face": sticker_face, "sticker_editing": component_kind == "standee" and attribute_page["standee"] == "image"}

func _raw() -> Dictionary:
	var raw := super._raw()
	raw.erase("active_component")
	raw.erase("designer_visibility")
	raw.erase("sticker_face")
	raw.erase("sticker_editing")
	return raw

func _refresh_material_preview() -> void:
	_refresh_preview_internal(true)

func _refresh_preview() -> void:
	_refresh_preview_internal(false)

func _refresh_preview_internal(material_only: bool) -> void:
	if loading_component: return
	if material_only: preview.configure_material(_appearance())
	else: preview.configure(_appearance())
	var report: Dictionary = preview.validation
	var outside: Array = report.get("outside", [])
	var message: String = report.get("message", "")
	if report.get("ok", false) and not outside.is_empty():
		message = "底座超出实际占地。" if outside[0] == "base" else "立牌超出外扩一格的范围。"
	error_component = ""
	if not outside.is_empty(): error_component = outside[0]
	elif not report.get("ok", false): error_component = str(report.get("field", "")).get_slice(".", 0)
	error_components = outside.duplicate()
	if not report.get("ok", false) and error_component in ["base", "standee"]: error_components.append(error_component)
	_update_sticker_resource()
	if component_values["standee"].get("presentation", "solid") == "image" and StickerData.resource_ids(_sticker_spec()).is_empty():
		sticker_error = "图片立牌至少需要一面的图片。"
		sticker_error_face = "front"
	if not sticker_error.is_empty():
		message = sticker_error
		error_component = "standee"
		if not "standee" in error_components: error_components.append("standee")
	var standee: Dictionary = component_values["standee"]
	var has_contour := standee.has("contour")
	var ready: bool = has_contour and ContourData.current(standee) and int(standee["contour"].get("version", 1)) == 3
	contour_button.text = "重新生成轮廓" if has_contour else "生成轮廓"
	contour_button.disabled = not report.get("ok", false) or StickerData.resource_ids(_sticker_spec()).is_empty() or not sticker_error.is_empty()
	contour_status.text = ("已生成 · %d部分 · %s" % [int(standee["contour"].get("parts", 1)), "已连接" if standee["contour"].get("connected", false) else "保持分离"]) if ready else ("参数已改变，需要重新生成" if has_contour else "尚未生成")
	if standee.get("presentation", "solid") == "image" and not ready and message.is_empty():
		message = "轮廓需要重新生成。" if has_contour else "请先生成图片轮廓。"
		error_component = "standee"
		if not "standee" in error_components: error_components.append("standee")
	var current_error := component_kind in error_components
	Layout.set_status(boundary_notice, message if current_error else "", current_error)
	component_message = message
	_mark_component_errors(report)
	_update_list()
	_mark_changed()

func _locate_error() -> void:
	if error_component in ["base", "standee"]:
		_switch_component(error_component)
		var image_error := error_component == "standee" and (not sticker_error.is_empty() or str(preview.validation.get("field", "")).begins_with("standee.sticker"))
		var material_error: bool = str(preview.validation.get("field", "")).ends_with(".material")
		_switch_attribute("display" if material_error else ("image" if image_error else "shape"))
		if image_error:
			var face_name := sticker_error_face
			if face_name.is_empty(): face_name = "back" if str(preview.validation.get("message", "")).begins_with("背面") else "front"
			_select_sticker_face(face_name)
	else:
		if not edge_open["left"]: _toggle_edge("left")
		width_input.grab_focus()

func _save() -> bool:
	_refresh_preview()
	if not component_message.is_empty() or not common_error_field.is_empty():
		_show_input_problem()
		return false
	var result := super._save()
	heading_title.text = "棋子设置"
	save_button.text = instance_apply_title if instance_mode else "保存"
	return result

func _appearance_popup_open() -> bool:
	return component_color.get_popup().visible or sticker_backing.get_popup().visible or shape_choice.get_popup().visible or sides_input.get_popup().visible or file_picker_active or (is_instance_valid(image_dialog) and image_dialog.visible) or (is_instance_valid(image_modal) and image_modal.visible)

func _numeric_input(parent: Control) -> LineEdit:
	var input := LineEdit.new()
	input.max_length = 32
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = Style.BUTTON_HEIGHT
	parent.add_child(input)
	BoardUiStyle.style_controls(input, Style.BUTTON_HEIGHT)
	return input

func _pair_row(parent: Control, first: String, second: String) -> Array[LineEdit]:
	var row := Layout.pair(parent)
	var inputs: Array[LineEdit] = []
	for title in [first, second]:
		var group := VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_theme_constant_override("separation", 6)
		row.add_child(group)
		group.add_child(Style.text(title, Typography.CAPTION, true))
		inputs.append(_numeric_input(group))
	return inputs

func _adjustment_values(mode: String) -> Array:
	var data: Dictionary = component_values[component_kind]
	if mode == "scale": return [data["width_ft"], data["thickness_ft"], data["length_ft"]]
	return data["offset_ft" if mode == "position" else "rotation_deg"].duplicate()

func _open_adjustment(next_mode: String) -> void:
	if attribute_page[component_kind] != "shape" or (next_mode == "scale" and component_kind != "base"): return
	_close_sticker_adjustment()
	_capture_component()
	rotating = false
	preview.gizmo.end_drag()
	if next_mode == "scale" and adjustment_mode != "scale": size_reset_values = _adjustment_values("scale").duplicate()
	adjustment_mode = next_mode
	transform_panel.open_transform(next_mode, _adjustment_values(next_mode), editor_panel.position - Vector2(336, 0), component_kind == "base" and component_values["base"]["shape"] == "circle")
	transform_panel.get_node("Shell/Header/Row/Title").text = ("底座" if component_kind == "base" else "立牌") + " · " + {"position": "位置", "rotation": "旋转", "scale": "尺寸"}[next_mode]
	_update_adjustment_buttons()
	preview.set_adjustment_mode(next_mode)

func _close_adjustment() -> void:
	adjustment_mode = ""
	transform_panel.dragging = false
	transform_panel.hide()
	preview.set_adjustment_mode("")
	_update_adjustment_buttons()

func _apply_adjustment(mode: String, values: Array) -> void:
	if mode == "scale":
		var data: Dictionary = component_values["base"]
		data["width_ft"] = values[0]
		data["thickness_ft"] = values[1]
		data["length_ft"] = values[0] if data["shape"] == "circle" else values[2]
		# Keep the regular dimension form from overwriting incoming gizmo values.
		loading_component = true
		component_inputs["width_ft"].text = str(data["width_ft"])
		component_inputs["length_ft"].text = str(data["length_ft"])
		component_inputs["thickness_ft"].text = str(data["thickness_ft"])
		loading_component = false
	else: component_values[component_kind]["offset_ft" if mode == "position" else "rotation_deg"] = values
	_refresh_preview()

func _transform_values_changed(values: Array) -> void:
	if adjustment_mode.is_empty(): return
	preview.gizmo.end_drag()
	var numbers: Array = []
	for value in values: numbers.append(_number_text(str(value)))
	_apply_adjustment(adjustment_mode, numbers)

func _gizmo_values_changed(mode: String, values: Array) -> void:
	if mode != adjustment_mode: return
	_apply_adjustment(mode, values)
	transform_panel.sync_values(_adjustment_values(mode))

func _reset_transform() -> void:
	if adjustment_mode.is_empty(): return
	preview.gizmo.end_drag()
	_gizmo_values_changed(adjustment_mode, size_reset_values.duplicate() if adjustment_mode == "scale" else [0.0, 0.0, 0.0])

func _pointer_on_ui(at: Vector2) -> bool:
	for panel in [left_handle, right_handle, transform_panel, sticker_panel]:
		if is_instance_valid(panel) and panel.visible and panel.get_global_rect().has_point(at): return true
	return (edge_open["left"] and options_panel.get_global_rect().has_point(at)) or (edge_open["right"] and editor_panel.get_global_rect().has_point(at))

func _orbit_dragging() -> bool:
	return preview.gizmo.dragged>=0 or preview.sticker_gizmo.dragged>=0 or (is_instance_valid(transform_panel) and transform_panel.dragging) or (is_instance_valid(sticker_panel) and sticker_panel.dragging)

func _orbit_can_rotate(point: Vector2) -> bool:
	var active_gizmo: Node3D = preview.sticker_gizmo if not sticker_mode.is_empty() else preview.gizmo
	return active_gizmo.pick(point,true)<0

func _orbit_focus() -> void:
	preview.focus_selected(component_kind)

func _input(event: InputEvent) -> void:
	if is_instance_valid(mobile_touch) and mobile_touch.handle(event): return
	var active_gizmo: Node3D = preview.sticker_gizmo if not sticker_mode.is_empty() else preview.gizmo
	if _popup_open():
		orbit_button = 0
		active_gizmo.end_drag()
		if not sticker_mode.is_empty(): _close_sticker_adjustment()
		return
	if active_gizmo.dragged < 0 and _orbit_input(event): return
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			if active_gizmo.dragged>=0:
				active_gizmo.end_drag()
				get_viewport().set_input_as_handled()
			return
		if active_gizmo.dragged>=0:
			get_viewport().set_input_as_handled()
			return
		if _pointer_on_ui(event.position): return
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var axis: int = active_gizmo.pick(event.position,true)
			if axis>=0:
				active_gizmo.begin_drag(event.position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if active_gizmo.dragged>=0:
			active_gizmo.drag(event.position)
			get_viewport().set_input_as_handled()
		else: active_gizmo.hover(Vector2(-10000,-10000) if _pointer_on_ui(event.position) else event.position)

func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(preview):
		preview.gizmo.end_drag()
		preview.sticker_gizmo.end_drag()

func _update_adjustment_buttons() -> void:
	for key in adjustment_buttons:
		_highlight_button(adjustment_buttons[key], key == adjustment_mode)

func _set_ui_enabled(root: Control, enabled: bool) -> void:
	if root == list_scroll and not list_expanded: enabled = false
	if not root.has_meta("expanded_mouse_filter"):
		root.set_meta("expanded_mouse_filter", root.mouse_filter)
	root.mouse_filter = root.get_meta("expanded_mouse_filter") if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled and root.has_focus(): root.release_focus()
	if root is BaseButton:
		if not root.has_meta("expanded_focus_mode"): root.set_meta("expanded_focus_mode", root.focus_mode)
		root.focus_mode = root.get_meta("expanded_focus_mode") if enabled else Control.FOCUS_NONE
	elif root is LineEdit:
		root.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	for child in root.get_children():
		if child is Control: _set_ui_enabled(child, enabled)

func _toggle_edge(side: String) -> void:
	edge_open[side] = not edge_open[side]

	if not edge_open[side]: _close_owned_popups(side)
	_animate_edge(side)

func _close_owned_popups(side: String) -> void:
	rotating = false
	preview.gizmo.end_drag()
	if side == "right":
		_close_sticker_adjustment()
		_close_adjustment()
		component_color.get_popup().hide()
		sticker_backing.get_popup().hide()
		shape_choice.get_popup().hide()
		sides_input.get_popup().hide()
	elif is_instance_valid(tags_modal): tags_modal.dismiss()

func _edge_position(side: String, expanded: bool) -> Vector2:
	var panel: PanelContainer = options_panel if side == "left" else editor_panel
	var safe := Mobile.safe_rect(size)
	return Vector2(safe.position.x+24 if expanded else -panel.size.x,safe.position.y+24) if side=="left" else Vector2(safe.end.x-panel.size.x-24 if expanded else size.x,safe.position.y+24)

func _animate_edge(side: String) -> void:
	var panel: PanelContainer = options_panel if side == "left" else editor_panel
	var handle: Button = left_handle if side == "left" else right_handle
	var expanded: bool = edge_open[side]
	if edge_tweens.has(side) and edge_tweens[side].is_valid(): edge_tweens[side].kill()
	panel.show()
	_set_ui_enabled(panel, expanded)
	handle.icon = (LeftIcon if expanded else RightIcon) if side == "left" else (RightIcon if expanded else LeftIcon)
	handle.tooltip_text = ("收起" if expanded else "展开") + ("棋子设置" if side == "left" else "部件编辑")
	var tween := create_tween().set_parallel(true)
	edge_tweens[side] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position", _edge_position(side, expanded), preload("res://ui/components/page_motion.gd").duration(0.16))
	tween.tween_property(panel, "modulate:a", 1.0 if expanded else 0.0, preload("res://ui/components/page_motion.gd").duration(0.16))
	tween.tween_property(handle, "position", _handle_position(side, expanded), preload("res://ui/components/page_motion.gd").duration(0.16))
	tween.finished.connect(func():
		if not edge_open[side]: panel.hide()
		_queue_fit()
	)

func _fit_card(panel: PanelContainer, content: VBoxContainer, scroll: ScrollContainer, body: Control, width: float, height_limit: float) -> void:
	var chrome := panel.get_theme_stylebox("panel").get_minimum_size().y
	var count := 0
	for child in content.get_children():
		if child is Control and child.visible:
			count += 1
			if child != scroll: chrome += child.get_combined_minimum_size().y
	chrome += maxi(0, count - 1) * content.get_theme_constant("separation")
	var body_height := body.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(body_height, maxf(1, height_limit - chrome))
	panel.size = Vector2(width, minf(height_limit, chrome + body_height))

func _fit() -> void:
	fit_queued = false
	if not is_instance_valid(left_handle) or not is_instance_valid(editor_panel): return
	var safe := Mobile.safe_rect(size)
	var available := maxf(1,safe.size.y-48)
	var dual: bool = edge_open["left"] and edge_open["right"]
	var width_budget := maxf(1,(safe.size.x-96)/2) if dual else maxf(1,safe.size.x-48)
	var width_left := minf(320,width_budget)
	var width_right := minf(344,width_budget)
	material_editor.fit_width(maxf(1,width_right-32-(Mobile.SCROLLBAR_WIDTH+Mobile.SCROLLBAR_GAP if Mobile.enabled else 10)))
	_fit_card(options_panel, options_content, form_scroll, form, width_left, available)
	_fit_card(editor_panel, editor_content, editor_scroll, attribute_bodies[attribute_page[component_kind]], width_right, available)
	left_handle.size = Vector2(44, 44)
	right_handle.size = Vector2(44, 44)

	for side in ["left", "right"]:
		var panel: PanelContainer = options_panel if side == "left" else editor_panel
		var handle: Button = left_handle if side == "left" else right_handle
		if edge_tweens.has(side) and edge_tweens[side].is_running(): continue
		panel.position = _edge_position(side, edge_open[side])
		panel.visible = edge_open[side]
		panel.modulate.a = 1.0 if edge_open[side] else 0.0
		handle.position = _handle_position(side, edge_open[side])
		handle.icon = (LeftIcon if edge_open[side] else RightIcon) if side == "left" else (RightIcon if edge_open[side] else LeftIcon)
		handle.tooltip_text = ("收起" if edge_open[side] else "展开") + ("棋子设置" if side == "left" else "部件编辑")
		_set_ui_enabled(panel, edge_open[side])


func _highlight_button(button: Button, selected: bool) -> void:
	if button.has_meta("designer_selected") and button.get_meta("designer_selected") == selected: return
	button.set_meta("designer_selected", selected)
	var colors := {"normal": Color("dce8f7") if selected else (Color.WHITE if button.has_meta("flat_list_row") else Color("f0f4f9")), "hover": Color("cddff5") if selected else Color("e6edf6"), "pressed": Color("bbd2ef")}
	if button.has_meta("page_motion_colors"):
		button.set_meta("page_motion_colors", colors)
		Style.Motion._button_state(button)
	else:
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var face := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			face.bg_color = colors["pressed" if state == "hover_pressed" else state]
			button.add_theme_stylebox_override(state, face)

func _add_choice(parent: Control, title: String, choices: Array) -> OptionButton:
	var row := Style.column(6)
	parent.add_child(row)
	row.add_child(Style.text(title, Typography.CAPTION, true))
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in choices: choice.add_item(item)
	row.add_child(choice)
	BoardUiStyle.style_controls(choice, Style.BUTTON_HEIGHT)
	return choice

func _handle_position(side: String, expanded: bool) -> Vector2:
	var safe := Mobile.safe_rect(size)
	if side=="left": return Vector2(safe.position.x+(40 if expanded else 0),safe.position.y+40)
	return Vector2(safe.end.x-(84 if expanded else 48),safe.position.y+40)

func _prepare_scroll(scroll: ScrollContainer, _content: VBoxContainer) -> void:
	Layout.scroll(scroll)

func _percent(text: String) -> Variant:
	var value: Variant = _number_text(text)
	return float(value) / 100.0 if value is float or value is int else value

func _sticker_spec() -> Dictionary:
	var value: Dictionary = component_values["standee"].get("sticker", StickerData.defaults())
	if value.get("version", 1) != 3: value = StickerData.migrate(value)
	if value.get("back_shared", false):
		var snapshot: Dictionary = value["faces"]["front"].duplicate(true)
		if value["back_mirrored"] and not snapshot["image_id"].is_empty():
			snapshot["offset"][0] = -float(snapshot["offset"][0]) if StickerData._number(snapshot["offset"][0]) else snapshot["offset"][0]
			snapshot["rotation_deg"] = -float(snapshot["rotation_deg"]) if StickerData._number(snapshot["rotation_deg"]) else snapshot["rotation_deg"]
			snapshot["flip_x"] = not snapshot["flip_x"]
		value["faces"]["back"] = snapshot
		value["back_shared"] = false
	component_values["standee"]["sticker"] = value
	return value

func _sticker_face_data() -> Dictionary:
	return _sticker_spec()["faces"][sticker_face]

func _build_sticker_form(parent: Control) -> void:
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 8)
	parent.add_child(faces)
	for item in [["front", "正面"], ["back", "背面"]]:
		var key: String = item[0]
		var button := _button(item[1], func(): _select_sticker_face(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		faces.add_child(button)
		sticker_face_buttons[key] = button
	sticker_notice = Style.text("至少导入一面的图片才能保存", Typography.CAPTION, true)
	parent.add_child(sticker_notice)
	var image_row := Layout.pair(parent,300.0)
	var image_column := Style.column(6)
	image_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_row.add_child(image_column)
	sticker_picture = TextureRect.new()
	sticker_picture.custom_minimum_size = Vector2(100, 100)
	sticker_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sticker_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_column.add_child(sticker_picture)
	sticker_empty = Style.text("未导入图片", Typography.CAPTION, true)
	sticker_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sticker_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sticker_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sticker_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sticker_picture.add_child(sticker_empty)
	sticker_info = Style.text("", Typography.CAPTION, true)
	image_column.add_child(sticker_info)
	var image_actions := Style.column(8)
	image_actions.size_flags_horizontal = Control.SIZE_FILL
	image_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image_actions.custom_minimum_size.x = 132
	image_row.add_child(image_actions)
	var import_button := _button("导入图片", _select_image)
	image_actions.add_child(import_button)
	sticker_actions["import"] = import_button
	var remove_button := _button("移除图片", func(): _sticker_action("remove"))
	remove_button.add_theme_color_override("font_color", Color("b33c3c"))
	image_actions.add_child(remove_button)
	sticker_actions["remove"] = remove_button
	var copy_button := _button("镜像到另一面", _mirror_sticker)
	parent.add_child(copy_button)
	sticker_actions["copy"] = copy_button
	sticker_rows = Style.column(12)
	parent.add_child(sticker_rows)
	_separator(sticker_rows)
	sticker_rows.add_child(Style.text("布局", Typography.BODY))
	var adjustment := Layout.pair(editor_content)
	sticker_adjustment_actions = adjustment
	for item in [["position", "调整位置"], ["rotation", "调整旋转"]]:
		var key: String = item[0]
		var button := _button(item[1], func(): _open_sticker_adjustment(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		adjustment.add_child(button)
		sticker_actions[key] = button
	var scale_group := Layout.field(sticker_rows, "缩放 · %")
	sticker_inputs["scale"] = _numeric_input(scale_group)
	sticker_inputs["scale"].text_changed.connect(func(_text: String):
		if not loading_component: _refresh_preview()
	)
	var flips := HBoxContainer.new()
	flips.add_theme_constant_override("separation", 8)
	sticker_rows.add_child(flips)
	for item in [["flip_x", "水平镜像"], ["flip_y", "竖直镜像"]]:
		var key: String = item[0]
		var button := _button(item[1], func(): _toggle_sticker_option(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flips.add_child(button)
		sticker_options[key] = button
	sticker_rows.add_child(Style.text("图案背色", Typography.CAPTION, true))
	sticker_backing = ColorWell.new()
	sticker_backing.color = Color.WHITE
	sticker_backing.popup_host = self
	sticker_backing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticker_rows.add_child(sticker_backing)
	Style.card_button(sticker_backing)
	sticker_backing.color_changed.connect(func(_color: Color):
		if not loading_component: _refresh_preview()
	)
	var reset_button := _button("重置图片布局", func(): _sticker_action("center"))
	sticker_rows.add_child(reset_button)
	sticker_actions["center"] = reset_button
	image_dialog = FileDialog.new()
	image_dialog.use_native_dialog = true
	image_dialog.mode_overrides_title = false
	image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; PNG / JPG 图片"])
	image_dialog.title = "选择立牌图片 · 最大 2.5 MB"
	add_child(image_dialog)
	image_dialog.canceled.connect(func(): file_picker_active = false)
	image_dialog.file_selected.connect(_image_selected)
	sticker_panel = TransformScene.instantiate()
	sticker_panel.set_script(StickerPanel)
	add_child(sticker_panel)
	sticker_panel.values_changed.connect(func(values: Array):
		if sticker_mode.is_empty(): return
		preview.sticker_gizmo.end_drag()
		_apply_sticker_values(values)
	)
	sticker_panel.reset_requested.connect(func():
		if sticker_mode.is_empty(): return
		preview.sticker_gizmo.end_drag()
		_apply_sticker_values([0.0, 0.0] if sticker_mode == "position" else [0.0])
		sticker_panel.sync_values(_sticker_adjustment_values())
	)
	sticker_panel.interval_changed.connect(func(value: float):
		preview.sticker_gizmo.end_drag()
		preview.sticker_gizmo.snap_interval = value
	)
	sticker_panel.panel_closed.connect(_close_sticker_adjustment)
	preview.sticker_gizmo.values_changed.connect(func(mode: String, values: Array):
		if mode != sticker_mode: return
		_apply_sticker_values(values)
		sticker_panel.sync_values(_sticker_adjustment_values())
	)

func _reload_sticker() -> void:
	loading_component = true
	_load_sticker()
	loading_component = false

func _load_sticker() -> void:
	if sticker_inputs.is_empty(): return
	var settings := _sticker_face_data()
	sticker_backing.color = Color(settings.get("backing_color", "ffffff"))
	var scale_value = settings["scale"]
	sticker_inputs["scale"].text = str(float(scale_value) * 100) if scale_value is float or scale_value is int else str(scale_value)
	sticker_cached_id = "@"
	_update_sticker_resource()
	_sync_sticker_buttons()

func _sync_sticker_buttons() -> void:
	if sticker_rows == null: return
	var settings := _sticker_face_data()
	var has_image: bool = not settings["image_id"].is_empty()
	sticker_notice.visible = component_values["standee"].get("presentation", "solid") == "image" and StickerData.resource_ids(_sticker_spec()).is_empty()
	for key in sticker_face_buttons: _highlight_button(sticker_face_buttons[key], key == sticker_face)
	sticker_rows.visible = true
	sticker_actions["import"].text = "替换图片" if has_image else "导入图片"
	sticker_inputs["scale"].editable = has_image
	sticker_backing.disabled = not has_image
	sticker_actions["copy"].tooltip_text = "复制到背面，复制后独立编辑" if sticker_face == "front" else "复制到正面，复制后独立编辑"
	for key in ["center", "remove", "position", "rotation", "copy"]:
		sticker_actions[key].disabled = not has_image
	for key in sticker_options:
		sticker_options[key].disabled = not has_image
		_highlight_button(sticker_options[key], settings.get(key, false))
	for key in ["position", "rotation"]: _highlight_button(sticker_actions[key], sticker_mode == key)
	_queue_fit()

func _update_sticker_resource() -> void:
	if sticker_info == null: return
	var settings := _sticker_face_data()
	var id: String = settings["image_id"]
	var ids := StickerData.resource_ids(_sticker_spec())
	var signature := str(component_values["standee"].get("presentation", "solid")) + ":" + sticker_face + ":" + id + ":" + ":".join(ids)
	_sync_sticker_buttons()
	if signature == sticker_cached_id: return
	sticker_cached_id = signature
	sticker_error = ""
	sticker_error_face = ""
	sticker_picture.texture = null
	sticker_empty.visible = id.is_empty()
	sticker_info.visible = not id.is_empty()
	for resource_id in ids:
		var check := ImageStore.load_image(resource_id)
		if not check["ok"]:
			sticker_error = check["message"]
			for face_name in ["front", "back"]:
				if _sticker_spec()["faces"][face_name]["image_id"] == resource_id:
					sticker_error_face = face_name
					break
			break
	if id.is_empty():
		sticker_info.text = "此面未设置图片"
	else:
		var loaded := ImageStore.load_image(id)
		if loaded["ok"]:
			var image: Image = loaded["image"]
			sticker_picture.texture = ImageStore.texture(id)
			sticker_info.text = "%d × %d · %.2f MB" % [image.get_width(), image.get_height(), int(loaded["bytes"]) / 1000000.0]
		else: sticker_info.text = loaded["message"]

	sticker_info.add_theme_color_override("font_color", Color("b33c3c") if not sticker_error.is_empty() else Color("64748b"))
	_queue_fit()

func _select_sticker_face(name: String) -> void:
	if name == sticker_face: return
	_capture_component()
	_close_sticker_adjustment()
	sticker_backing.get_popup().hide()
	sticker_face = name
	_reload_sticker()
	Style.Motion.fade_in(sticker_picture, 0.12)
	_refresh_preview()

func _mirror_sticker() -> void:
	_capture_component()
	_close_adjustment()
	_close_sticker_adjustment()
	sticker_backing.get_popup().hide()
	var checked := StickerData._validate_face(_sticker_face_data())
	if not checked["ok"]:
		_show_mirror_error(checked["message"])
		return
	var settings: Dictionary = checked["face"]
	if settings["image_id"].is_empty(): return
	var resource := ImageStore.load_image(settings["image_id"])
	if not resource["ok"]:
		_show_mirror_error(resource["message"])
		return
	var destination := "back" if sticker_face == "front" else "front"
	var copied := StickerData.mirror_face(settings)
	if _sticker_spec()["faces"][destination]["image_id"].is_empty():
		_apply_mirrored_face(destination, copied)
		return
	image_modal = Modal.new()
	page.add_overlay(image_modal)
	image_modal.configure("覆盖另一面？", "%s已有图片，是否覆盖其图片、布局和背色？" % ("背面" if destination == "back" else "正面"))
	image_modal.add_action("覆盖并镜像", func():
		image_modal.dismiss()
		_apply_mirrored_face(destination, copied)
	, false, true, true)
	image_modal.add_action("取消", func(): image_modal.dismiss())
	image_modal.dismissed.connect(func(): image_modal = null)

func _apply_mirrored_face(destination: String, settings: Dictionary) -> void:
	_sticker_spec()["faces"][destination] = settings.duplicate(true)
	_reload_sticker()
	_refresh_preview()

func _show_mirror_error(message: String) -> void:
	image_modal = Modal.new()
	page.add_overlay(image_modal)
	image_modal.configure("未能镜像到另一面", message)
	image_modal.add_action("关闭", func(): image_modal.dismiss())
	image_modal.dismissed.connect(func(): image_modal = null)

func _toggle_sticker_option(key: String) -> void:
	_capture_component()
	preview.sticker_gizmo.end_drag()
	var settings := _sticker_face_data()
	settings[key] = not settings.get(key, false)
	_sync_sticker_buttons()
	_refresh_preview()

func _sticker_action(key: String) -> void:
	_capture_component()
	_close_sticker_adjustment()
	var specification := _sticker_spec()
	if key == "remove": specification["faces"][sticker_face] = StickerData.face_defaults()
	else:
		var settings := _sticker_face_data()
		settings["offset"] = [0.0, 0.0]
		settings["scale"] = 1.0
		settings["rotation_deg"] = 0.0
		settings["ignore_margin"] = false
	_reload_sticker()
	_refresh_preview()

func _sticker_adjustment_values() -> Array:
	var settings := _sticker_face_data()
	if sticker_mode == "rotation": return [settings["rotation_deg"], 0.0, 0.0]
	return [float(settings["offset"][0]) * 100 if StickerData._number(settings["offset"][0]) else settings["offset"][0], float(settings["offset"][1]) * 100 if StickerData._number(settings["offset"][1]) else settings["offset"][1], 0.0]

func _open_sticker_adjustment(mode: String) -> void:
	if component_kind != "standee" or attribute_page["standee"] != "image": return
	_capture_component()
	_close_adjustment()
	preview.sticker_gizmo.end_drag()
	rotating = false
	sticker_mode = mode
	sticker_panel.open_sticker(mode, _sticker_adjustment_values(), editor_panel.position - Vector2(336, 0), sticker_face)
	preview.set_sticker_mode(mode)
	_sync_sticker_buttons()

func _close_sticker_adjustment() -> void:
	sticker_mode = ""
	if is_instance_valid(sticker_panel):
		sticker_panel.dragging = false
		sticker_panel.hide()
	if is_instance_valid(preview): preview.set_sticker_mode("")
	_sync_sticker_buttons()

func _apply_sticker_values(values: Array) -> void:
	if sticker_mode.is_empty(): return
	var settings := _sticker_face_data()
	if sticker_mode == "rotation": settings["rotation_deg"] = _number_text(str(values[0]))
	else: settings["offset"] = [_percent(str(values[0])), _percent(str(values[1]))]
	_refresh_preview()

func _image_selected(path: String) -> void:
	file_picker_active = false
	var result := ImageStore.import_file(path)
	if not result["ok"]:
		_show_image_error(result["message"])
		return
	var saved_image := ImageStore.save_image(result["data"])
	if not saved_image["ok"]:
		_show_image_error(saved_image["message"])
		return
	_capture_component()
	var specification := _sticker_spec()
	specification["faces"][sticker_face]["image_id"] = saved_image["id"]
	specification["faces"][sticker_face]["ignore_margin"] = false
	_reload_sticker()
	_refresh_preview()

func _android_image_selected(selected: bool, paths: PackedStringArray, _filter: int) -> void:
	file_picker_active = false
	if not is_inside_tree() or not selected: return
	if paths.size()!=1:
		_show_image_error("未收到有效的图片，请重新选择。")
		return
	_image_selected(paths[0])

func _select_image() -> void:
	if file_picker_active: return
	rotating = false
	preview.gizmo.end_drag()
	_close_sticker_adjustment()
	_close_adjustment()
	sticker_backing.get_popup().hide()
	file_picker_active = true
	if OS.has_feature("android"):
		var result := DisplayServer.file_dialog_show("选择立牌图片 · 最大 2.5 MB","","",false,DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,PackedStringArray(["image/png", "image/jpeg"]),_android_image_selected,DisplayServer.MAIN_WINDOW_ID)
		if result!=OK:
			file_picker_active = false
			push_warning("安卓图片选择器启动失败：%s" % error_string(result))
			_show_image_error("无法打开系统选图，请确认手机已启用系统文件选择器后重试。")
		return
	image_dialog.popup_file_dialog()

func _show_image_error(message: String) -> void:
	image_modal = Modal.new()
	page.add_overlay(image_modal)
	image_modal.configure("图片未导入", message)
	image_modal.add_action("关闭", image_modal.dismiss)
	image_modal.dismissed.connect(func(): image_modal = null)

func _sync_attribute_edges() -> void:
	var visible_tabs: Array[Button] = []
	for child in attribute_buttons["shape"].get_parent().get_children():
		if child is Button and child.visible: visible_tabs.append(child)
	Layout.tabs(visible_tabs)

func _sync_smoothing_slider() -> void:
	if smoothing_slider == null: return
	var raw: String = contour_inputs["smooth_pct"].text.strip_edges()
	if not raw.is_valid_float() or not is_finite(raw.to_float()): return
	smoothing_sync = true
	smoothing_slider.set_value_no_signal(clampf(raw.to_float(), 0, 100))
	smoothing_sync = false

func _mark_changed() -> void:
	super._mark_changed()
	if status_label == null: return
	var common := {"title": fields["title"].input.text, "size": 1, "base": "circle"}
	for key in ["hp", "max_hp", "ac"]: common[key] = fields[key].input.text
	var checked := Parameters.validate(common)
	common_error_field = "" if checked["ok"] else checked["field"]
	for field in fields.values(): field.set_error("")
	if not common_error_field.is_empty(): fields[common_error_field].set_error(checked["message"])
	var message: String = component_message if not component_message.is_empty() else (checked["message"] if not checked["ok"] else "")
	save_button.disabled = not message.is_empty()
	if not message.is_empty(): _set_status(message, Color("b33c3c"), message)

func _show_input_problem() -> void:
	if not component_message.is_empty():
		_locate_error()
		_show_save_error(component_message, "检查输入")
	elif not common_error_field.is_empty():
		if not edge_open["left"]: _toggle_edge("left")
		if common_error_field in ["hp", "max_hp", "ac"]: stats_fold.folded = false
		form_scroll.ensure_control_visible(fields[common_error_field])
		fields[common_error_field].input.grab_focus()
		_show_save_error(status_label.tooltip_text, "检查输入")

func _mark_component_errors(report: Dictionary) -> void:
	for input in component_inputs.values(): Layout.field_error(input, "")
	for input in contour_inputs.values(): Layout.field_error(input, "")
	for input in [width_input, length_input]: Layout.field_error(input, "")
	if report.get("ok", false): return
	var field: String = report.get("field", "")
	var message: String = report.get("message", "")
	if field == "footprint":
		Layout.field_error(width_input, message)
		Layout.field_error(length_input, message)
	elif field.begins_with(component_kind + "."):
		var key := field.get_slice(".", 1)
		if component_inputs.has(key): Layout.field_error(component_inputs[key], message)
		elif key == "contour":
			for input in contour_inputs.values(): Layout.field_error(input, message)
