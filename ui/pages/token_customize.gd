extends Control
var mobile_touch: Node
var orbit_button := 0
var orbit_pending := false
var orbit_origin := Vector2.ZERO

const Layout = preload("res://ui/components/editor_layout.gd")
const Style = preload("res://ui/components/page_style.gd")
const Field = preload("res://ui/components/page_field.gd")
const Preview = preload("res://ui/components/token_preview.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const TagsPanel = preload("res://ui/components/token_tags_panel.gd")
const Parameters = preload("res://scripts/token_parameters.gd")
const Store = preload("res://scripts/token_library_store.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const Surface = preload("res://scripts/token_surface.gd")
const MaterialEditor = preload("res://ui/components/token_material_editor.gd")
var material_editors: Dictionary = {}
signal return_requested
signal saved(token_id: String)
signal instance_applied(parameters: Dictionary)
var instance_mode := false
var lock_footprint := true
var instance_return_title := "返回场景"
var instance_apply_title := "应用到场内棋子"
var kind := "basic"
var page: Control
var fields: Dictionary = {}
var size_input: OptionButton
var base_input: OptionButton
var color_input: ColorWell
var stats_fold: FoldableContainer
var save_button: Button
var status_label: Label
var preview: Control
var options_panel: PanelContainer
var rotating := false
var form_scroll: ScrollContainer
var initial_values: Dictionary = {}
var discard_modal: Control
var accepted_leave := false
var editing_record: Dictionary = {}
var persisted_id := ""
var heading_title: Label
var options_content: VBoxContainer
var form: VBoxContainer
var fit_queued := false
var tags_modal: Control
var save_error_modal: Control
var basic_handle: Button
var basic_open := true
var basic_tween: Tween

func _ready() -> void:
	_mobile_attach.call_deferred()
	persisted_id = "" if instance_mode else str(editing_record.get("id",""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview = _new_preview()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	options_panel = Style.card()
	options_panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(Layout.PADDING))
	add_child(options_panel)
	var container := Style.column(12)
	options_content = container
	options_panel.add_child(container)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	container.add_child(heading)
	var back := Button.new()
	back.text = "返回"
	back.hide()
	Style.button(back)
	back.pressed.connect(func(): return_requested.emit())
	heading.add_child(back)
	var heading_space := Control.new()
	heading_space.custom_minimum_size = Vector2(44, 44)
	heading_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(heading_space)
	heading_title = Style.text(("编辑" if not editing_record.is_empty() else "创建") + _type_name(), 20)
	heading_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_title)
	form_scroll = ScrollContainer.new()
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(form_scroll)
	Layout.scroll(form_scroll)
	form = Style.column(12)
	form_scroll.add_child(form)
	_add_field(form, "title", "名称", "棋子名称", 40, "棋子")
	var tag_entry := Button.new()
	var tags: Array = editing_record.get("tags", [])
	tag_entry.text = _type_name() + (" · 标签" if tags.is_empty() else " · %d 个标签" % tags.size())
	Style.card_button(tag_entry, 44)
	tag_entry.add_theme_font_size_override("font_size", 14)
	tag_entry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag_entry.tooltip_text = "查看类型与分类标签"
	tag_entry.pressed.connect(_show_tags)
	form.add_child(tag_entry)
	var view_actions := preload("res://ui/components/orbit_view_actions.gd").new()
	form.add_child(view_actions)
	view_actions.configure(_orbit_focus,_orbit_overview)
	_build_appearance_form(form)
	stats_fold = GoStyle.foldable("初始数值", true, null, false)
	Layout.fold(stats_fold)
	form.add_child(stats_fold)
	var stats_body := Style.column(12)
	stats_fold.add_child(stats_body)
	_add_field(stats_body, "hp", "当前 HP", "可留空", 6)
	_add_field(stats_body, "max_hp", "最大 HP", "可留空", 6)
	_add_field(stats_body, "ac", "AC", "可留空", 6)
	stats_body.add_child(Style.text("HP 两项均留空表示未设置；只填一项时，另一项取相同值。", 14, true))
	if not editing_record.is_empty():
		var params: Dictionary = editing_record["parameters"]
		fields["title"].input.text = editing_record["title"]
		_load_appearance(params)
		for key in ["hp", "max_hp", "ac"]:
			fields[key].input.text = "" if int(params[key]) < 0 else str(int(params[key]))
	preview.configure(_appearance())
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	container.add_child(actions)
	var cancel := Button.new()
	cancel.text = "返回" if Mobile.enabled else (instance_return_title if instance_mode else "返回棋子库")
	Style.button(cancel)
	cancel.pressed.connect(func(): return_requested.emit())
	actions.add_child(cancel)
	status_label = Layout.status()
	container.add_child(status_label)
	container.move_child(status_label, actions.get_index())
	status_label.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_input_problem()
	)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	save_button = Button.new()
	save_button.text = ("应用" if instance_mode else "保存") if Mobile.enabled else (instance_apply_title if instance_mode else ("保存修改" if not editing_record.is_empty() else "保存到棋子库"))
	Style.button(save_button, true)
	save_button.custom_minimum_size.x = 128
	save_button.pressed.connect(_save)
	actions.add_child(save_button)
	_connect_appearance()
	if instance_mode and lock_footprint:
		if kind == "basic": size_input.disabled = true
		else:
			get("width_input").editable = false
			get("length_input").editable = false
	initial_values = _raw().duplicate(true)
	_mark_changed()
	for field in fields.values():
		field.input.text_changed.connect(func(_text: String): _mark_changed())
	resized.connect(_queue_fit)
	form.minimum_size_changed.connect(_queue_fit)
	options_content.minimum_size_changed.connect(_queue_fit)
	if kind == "basic":
		basic_handle = Button.new()
		Style.card_button(basic_handle)
		basic_handle.custom_minimum_size = Vector2(44, 44)
		basic_handle.icon = preload("res://ui/icons/chevron_left.svg")
		basic_handle.expand_icon = true
		basic_handle.add_theme_constant_override("icon_max_width", 20)
		basic_handle.pressed.connect(_toggle_basic)
		add_child(basic_handle)
	_queue_fit()

func _add_field(parent: Control, key: String, title: String, placeholder: String, limit: int, initial := "") -> void:
	var field := Field.new()
	parent.add_child(field)
	field.set_meta("compact_error", true)
	field.setup(title, placeholder)
	field.input.max_length = limit
	field.input.text = initial
	field.input.focus_exited.connect(_validate_fields)
	fields[key] = field

func _add_choice(parent: Control, title: String, choices: Array) -> OptionButton:
	var row := Layout.field(parent, title)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for item in choices: choice.add_item(item)
	row.add_child(choice)
	BoardUiStyle.style_controls(choice, Style.BUTTON_HEIGHT)
	return choice

func _show_tags() -> void:
	if is_instance_valid(tags_modal): return
	tags_modal = TagsPanel.new()
	page.add_overlay(tags_modal)
	tags_modal.configure_token(fields["title"].input.text, kind, editing_record.get("tags", []))
	tags_modal.dismissed.connect(func(): tags_modal = null)

func _appearance() -> Dictionary:
	return {"size": size_input.selected + 1, "base": Appearance.BASES[base_input.selected], "color": color_input.color, "materials": {"base": material_editors.base.value.duplicate(true), "standee": material_editors.standee.value.duplicate(true)}}

func _raw() -> Dictionary:
	var raw := _appearance()
	for key in fields: raw[key] = fields[key].input.text
	return raw

func _refresh_preview() -> void:
	preview.configure(_appearance())
	_mark_changed()

func _mark_changed() -> void:
	if status_label == null: return
	var dirty := editing_record.is_empty() or _raw() != initial_values
	_set_status("未保存" if dirty else "已保存", Color("64748b") if dirty else Color("28785e"))
	if kind == "basic": _validate_fields()

func _set_status(text: String, color: Color, detail := "", animate := false) -> void:
	var changed := status_label.text != text
	status_label.text = text
	status_label.tooltip_text = detail
	status_label.set_meta("detail", detail)
	status_label.add_theme_color_override("font_color", color)
	if animate and changed: Style.Motion.fade_in(status_label, Style.Motion.NOTICE_FADE)

func _show_save_error(message: String, title := "保存失败") -> void:
	if is_instance_valid(save_error_modal): save_error_modal.dismiss()
	save_error_modal = Modal.new()
	page.add_overlay(save_error_modal)
	save_error_modal.configure(title, message)
	save_error_modal.add_action("继续编辑", save_error_modal.dismiss)
	save_error_modal.dismissed.connect(func(): save_error_modal = null)

func _validate_fields() -> void:
	for field in fields.values(): field.set_error("")
	var result := Store.validate(_raw())
	if not result["ok"] and fields.has(result["field"]):
		fields[result["field"]].set_error(result["message"])
		_set_status(result["message"], Color("b33c3c"), result["message"])

func _save() -> bool:
	var checked := Store.validate(_raw())
	if not checked["ok"]:
		_set_status("检查输入", Color("b33c3c"))
		_validate_fields()
		if checked["field"] in ["hp", "max_hp", "ac"]: stats_fold.folded = false
		if fields.has(checked["field"]): fields[checked["field"]].input.grab_focus()
		return false
	if instance_mode:
		initial_values = _raw().duplicate(true)
		_set_status("已应用", Color("28785e"), "", true)
		instance_applied.emit(checked["parameters"].duplicate(true))
		return true
	save_button.disabled = true
	var updating := not persisted_id.is_empty()
	var result := Store.create(_raw()) if persisted_id.is_empty() else Store.update(persisted_id, _raw())
	if not result["ok"]:
		_set_status("保存失败", Color("b33c3c"), result["message"], true)
		_show_save_error(result["message"])
		save_button.disabled = false
		return false
	persisted_id = result["id"]
	print("棋子保存：%s，编号 %s" % ["更新原件" if updating else "首次保存",persisted_id])
	var params: Dictionary = checked["parameters"].duplicate(true)
	var title: String = params["title"]
	params.erase("title")
	editing_record = {"id": result["id"], "kind": kind, "title": title, "parameters": params, "tags": editing_record.get("tags", []).duplicate()}
	initial_values = _raw().duplicate(true)
	heading_title.text = "编辑" + _type_name()
	save_button.text = "保存" if Mobile.enabled else "保存修改"
	save_button.disabled = false
	_set_status("已保存", Color("28785e"), "", true)
	saved.emit(result["id"])
	return true

func has_unsaved_changes() -> bool:
	return _raw() != initial_values

func guard_leave(next_action: Callable) -> bool:
	if accepted_leave or _raw() == initial_values:
		return false
	if is_instance_valid(discard_modal):
		return true
	discard_modal = Modal.new()
	page.add_overlay(discard_modal)
	discard_modal.configure("有未应用的修改" if instance_mode else "有未保存的修改", "返回前是否应用？放弃只丢弃本次尚未应用的修改。" if instance_mode else "返回前是否保存？放弃只会丢弃尚未保存的改动，已保存的棋子会保留。")
	discard_modal.add_action("应用并返回" if instance_mode else "保存并返回", func():
		discard_modal.dismiss()
		if _save(): next_action.call()
	, true)
	discard_modal.add_action("继续编辑", discard_modal.dismiss)
	discard_modal.add_action("放弃修改并返回", func():
		accepted_leave = true
		next_action.call()
	, false, true, true)
	discard_modal.dismissed.connect(func(): discard_modal = null)
	return true

func _queue_fit() -> void:
	if fit_queued: return
	fit_queued = true
	_fit.call_deferred()

func _fit() -> void:
	fit_queued = false
	var safe := Mobile.safe_rect(size)
	var bounds := safe.size
	var margin := 24.0
	var width := minf(320.0 if Mobile.enabled else Style.CUSTOMIZE_PANEL_WIDTH, maxf(1, bounds.x - margin * 2))
	var height_limit := maxf(1, bounds.y - margin * 2)
	for editor in material_editors.values():
		editor.fit_width(maxf(1,width-32-(Mobile.SCROLLBAR_WIDTH if Mobile.enabled else 10)))
	var animating := basic_tween != null and basic_tween.is_running()
	if not animating: options_panel.position = Vector2(safe.position.x+margin if basic_open else -width, safe.position.y+margin)
	options_panel.size.x = width
	var chrome := options_panel.get_theme_stylebox("panel").get_minimum_size().y
	var visible_count := 0
	for child in options_content.get_children():
		if child is Control and child.visible:
			visible_count += 1
			if child != form_scroll: chrome += child.get_combined_minimum_size().y
	chrome += maxf(0, visible_count - 1) * options_content.get_theme_constant("separation")
	var body_height := form.get_combined_minimum_size().y
	form_scroll.custom_minimum_size.y = minf(body_height, maxf(1, height_limit - chrome))
	options_panel.size = Vector2(width, minf(height_limit, chrome + body_height))
	if is_instance_valid(basic_handle) and not animating:
		basic_handle.position = Vector2(safe.position.x+margin + 16 if basic_open else safe.position.x, safe.position.y+margin + 16)
		basic_handle.icon = preload("res://ui/icons/chevron_left.svg") if basic_open else preload("res://ui/icons/chevron_right.svg")

func _popup_open() -> bool:
	return (is_instance_valid(discard_modal) and discard_modal.visible) or (is_instance_valid(tags_modal) and tags_modal.visible) or (is_instance_valid(save_error_modal) and save_error_modal.visible) or _appearance_popup_open()

func _orbit_focus() -> void:
	preview.focus_selected()

func _orbit_overview() -> void:
	preview.fit_all()

func _orbit_pointer_on_ui(point: Vector2) -> bool:
	if has_method("_pointer_on_ui"): return call("_pointer_on_ui",point)
	return not get_global_rect().has_point(point) or (basic_open and options_panel.get_global_rect().has_point(point)) or basic_handle.get_global_rect().has_point(point)

func _orbit_dragging() -> bool:
	return false

func _orbit_can_rotate(_point: Vector2) -> bool:
	return true

func _orbit_keyboard_blocked() -> bool:
	if _popup_open() or _orbit_dragging() or not is_visible_in_tree() or not is_processing_input(): return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit or focused is SpinBox

func _process(delta: float) -> void:
	if not is_instance_valid(preview) or _orbit_keyboard_blocked(): return
	var direction := preload("res://scripts/orbit_camera.gd").lift_direction()
	if direction!=0:
		preview.target.y += direction*preload("res://scripts/orbit_camera.gd").lift_step(preview.distance,delta)
		preview._position_camera()

func _orbit_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and not event.pressed and event.button_index==orbit_button:
		orbit_button = 0
		orbit_pending = false
		get_viewport().set_input_as_handled()
		return true
	if _popup_open(): orbit_button = 0; orbit_pending = false; return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F:
		if _orbit_keyboard_blocked(): return false
		_orbit_focus()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.pressed and not _orbit_pointer_on_ui(event.position):
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.device==-420 or not _orbit_can_rotate(event.position): return false
			orbit_button = MOUSE_BUTTON_LEFT
			orbit_pending = true
			orbit_origin = event.position
		elif event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			orbit_button = event.button_index
			orbit_pending = false
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			preview.zoom_view(preload("res://scripts/orbit_camera.gd").zoom_factor(0.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/0.9))
		else: return false
		var focused := get_viewport().gui_get_focus_owner()
		if focused!=null: focused.release_focus()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and orbit_button!=0:
		if orbit_pending:
			if event.position.distance_to(orbit_origin)<8.0:
				get_viewport().set_input_as_handled()
				return true
			orbit_pending = false
		if preload("res://scripts/orbit_camera.gd").mouse_rotates(orbit_button): preview.rotate_view(event.relative)
		else: preview.pan_view(event.relative)
		get_viewport().set_input_as_handled()
		return true
	return false

func _input(event: InputEvent) -> void:
	if is_instance_valid(mobile_touch) and mobile_touch.handle(event): return
	_orbit_input(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		orbit_button = 0
		orbit_pending = false
		rotating = false

func _type_name() -> String:
	return "高级棋子" if kind == "advanced" else "基础棋子"

func _new_preview() -> Control:
	return Preview.new()

func _build_appearance_form(parent: Control) -> void:
	parent.add_child(Style.text("外观", 16))
	size_input = _add_choice(parent, "占地", ["1 × 1", "2 × 2", "3 × 3", "4 × 4", "5 × 5"])
	base_input = _add_choice(parent, "底座", ["正方形", "圆形", "六边形"])
	base_input.select(1)
	var color_row := Layout.field(parent, "颜色")
	color_input = ColorWell.new()
	color_input.popup_host = self
	color_input.color = Color("2e7ae0")
	color_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_input.custom_minimum_size.y = Style.BUTTON_HEIGHT
	color_row.add_child(color_input)
	Style.card_button(color_input)

	for part in ["base", "standee"]:
		var fold := GoStyle.foldable("底座材质" if part == "base" else "立牌材质", true, null, false)
		Layout.fold(fold)
		parent.add_child(fold)
		var editor := MaterialEditor.new()
		editor.popup_host = self
		fold.add_child(editor)
		material_editors[part] = editor
		editor.configure(Surface.basic_defaults(color_input.color)[part], Surface.basic_defaults(color_input.color)[part])
		editor.changed.connect(_refresh_preview)

func _load_appearance(params: Dictionary) -> void:
	size_input.select(int(params["size"]) - 1)
	base_input.select(Appearance.BASES.find(params["base"]))
	color_input.color = params["color"]
	var defaults := Surface.basic_defaults(color_input.color)
	for part in material_editors:
		material_editors[part].configure(params.get("materials", defaults)[part], defaults[part])

func _connect_appearance() -> void:
	size_input.item_selected.connect(func(_index: int): _refresh_preview())
	base_input.item_selected.connect(func(_index: int): _refresh_preview())
	color_input.color_changed.connect(func(color: Color):
		var colors := Surface.basic_defaults(color)
		for part in material_editors:
			var settings: Dictionary = material_editors[part].value.duplicate(true)
			settings.color = colors[part].color
			material_editors[part].configure(settings, colors[part])
		_refresh_preview())

func _appearance_popup_open() -> bool:
	for editor in material_editors.values():
		if editor.color_input.get_popup().visible: return true
	return color_input.get_popup().visible or size_input.get_popup().visible or base_input.get_popup().visible

func _show_input_problem() -> void:
	var checked := Store.validate(_raw())
	if checked["ok"]: return
	var key: String = checked.get("field", "")
	if key in ["hp", "max_hp", "ac"]: stats_fold.folded = false
	if fields.has(key):
		form_scroll.ensure_control_visible(fields[key])
		fields[key].input.grab_focus()
	_show_save_error(checked["message"], "检查输入")

func _toggle_basic() -> void:
	basic_open = not basic_open
	rotating = false
	for editor in material_editors.values(): editor.color_input.get_popup().hide()
	color_input.get_popup().hide()
	size_input.get_popup().hide()
	base_input.get_popup().hide()
	if basic_tween != null and basic_tween.is_valid(): basic_tween.kill()
	options_panel.show()
	Layout.enabled(options_panel, basic_open)
	if is_instance_valid(tags_modal): tags_modal.dismiss()
	basic_handle.icon = preload("res://ui/icons/chevron_left.svg") if basic_open else preload("res://ui/icons/chevron_right.svg")
	var margin := 24.0+Mobile.safe_rect(size).position.x
	basic_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	basic_tween.tween_property(options_panel, "position:x", margin if basic_open else -options_panel.size.x, preload("res://ui/components/page_motion.gd").duration(0.16))
	basic_tween.tween_property(options_panel, "modulate:a", 1.0 if basic_open else 0.0, preload("res://ui/components/page_motion.gd").duration(0.16))
	basic_tween.tween_property(basic_handle, "position:x", margin + 16 if basic_open else Mobile.safe_rect(size).position.x, preload("res://ui/components/page_motion.gd").duration(0.16))
	basic_tween.finished.connect(func():
		if not basic_open: options_panel.hide()
	)

func _mobile_attach() -> void:
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	if Mobile.enabled: mobile_touch = preload("res://ui/components/mobile_scene_input.gd").attach(self)
