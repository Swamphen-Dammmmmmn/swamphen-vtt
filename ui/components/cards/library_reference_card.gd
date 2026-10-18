# -*- coding: utf-8 -*-
extends Control

const Typography = preload("res://ui/theme/typography.gd")

signal primary_requested(id: String)
signal action_requested(action: String, record: Dictionary)
signal card_selected(selected: bool, record: Dictionary)

# 四库集中卡片：复用已验收棋子卡片的结构和状态。
# 使用自制竖向命令菜单，绕开原生 PopupMenu/Window 透明合成问题（2026-10-17）
const CardTheme = preload("res://ui/theme/themes/library_card_theme.gd")
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
const VerticalCommandMenu = preload("res://ui/components/overlays/vertical_command_menu.gd")

# 与状态图共用 JSON 的颜色、尺寸和纵向布局。
const CardSpec = preload("res://ui/theme/tokens/library_card_spec.gd")
var _spec: Dictionary = CardSpec.data()
var COLOR_CARD_BG: Color = CardSpec.color("card_bg")
var COLOR_BORDER: Color = CardSpec.color("border")
var COLOR_BORDER_HOVER: Color = CardSpec.color("border_hover")
var COLOR_BORDER_SELECTED: Color = CardSpec.color("border_selected")
var COLOR_MUTED: Color = CardSpec.color("muted")
var COLOR_STAGE_BG: Color = CardSpec.color("stage_bg")

# 外部配置属性
var record: Dictionary = {}
var library_kind: String = "tokens"
var primary_text: String = "编辑"
var selection_only: bool = false
var selectable: bool = false
var is_selected: bool = false
var force_mobile: bool = false
var page_shell: Control = null  # 由 library_view 传入，用于挂载菜单到 overlay_layer

# 内部控件节点
var _frame: PanelContainer
var _image_clip: PanelContainer
var _image_rect: TextureRect
var _placeholder: VBoxContainer
var _title: Label
var _tags_btn: Button
var _summary_label: Label
var _primary_btn: Button
var _more_btn: Button  # 改为普通 Button，不再使用 MenuButton
var _menu: VerticalCommandMenu  # 自制命令菜单
var _select_btn: Button

# 内部交互状态
var _is_hovered: bool = false
var _rail_y: float = 260.0
var _more_keyboard := false
var _record_revision := 0
var _menu_record_revision := -1

func _ready() -> void:
	theme = CardTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size.x = float(_spec.card.width)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_build_ui()
	resized.connect(_layout)

	var mob_node := _get_mobile_node()
	if mob_node != null and mob_node.has_signal("changed"):
		mob_node.changed.connect(_layout)

	var catalog := _get_product_catalog()
	if catalog != null and catalog.has_signal("changed"):
		catalog.changed.connect(_on_catalog_changed)

	_layout()

func _exit_tree() -> void:
	_menu_record_revision = -1
	var catalog := _get_product_catalog()
	if catalog != null and catalog.has_signal("changed") and catalog.changed.is_connected(_on_catalog_changed):
		catalog.changed.disconnect(_on_catalog_changed)

	# 清理自制菜单
	if is_instance_valid(_menu):
		_menu.close(false)
		_menu.queue_free()
		_menu = null

func _build_ui() -> void:
	# 1. 预览舞台容器
	_frame = PanelContainer.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = COLOR_STAGE_BG
	frame_style.set_corner_radius_all(8)
	frame_style.set_content_margin_all(0)
	_frame.add_theme_stylebox_override("panel", frame_style)
	add_child(_frame)
	var image_holder := Control.new()
	image_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(image_holder)
	_image_clip = PanelContainer.new()
	_image_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_image_clip.add_theme_stylebox_override("panel", frame_style)
	image_holder.add_child(_image_clip)

	_image_rect = TextureRect.new()
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_rect.draw.connect(_sync_placeholder_visibility)
	_image_clip.add_child(_image_rect)

	# 缺图占位
	_placeholder = VBoxContainer.new()
	_placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_theme_constant_override("separation", 8)
	_frame.add_child(_placeholder)

	var placeholder_icon := TextureRect.new()
	var img_ico := _load_icon("image")
	if img_ico:
		placeholder_icon.texture = img_ico
	placeholder_icon.custom_minimum_size = Vector2(28, 28)
	placeholder_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	placeholder_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	placeholder_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	placeholder_icon.modulate = Color("a0a0a0")
	placeholder_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_child(placeholder_icon)

	var placeholder_text := Label.new()
	placeholder_text.text = "暂无缩略图"
	placeholder_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_text.add_theme_font_size_override("font_size", Typography.TAG)
	placeholder_text.add_theme_color_override("font_color", COLOR_MUTED)
	placeholder_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_child(placeholder_text)

	_update_thumbnail()

	# 2. 多选入口按钮 (原生可切换按钮，支持键盘导航与 Tab 聚焦)
	_select_btn = Button.new()
	_select_btn.toggle_mode = true
	_select_btn.button_pressed = is_selected
	_select_btn.visible = selectable and not selection_only
	_select_btn.focus_mode = Control.FOCUS_ALL
	_select_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_select_btn.tooltip_text = "选择此项"
	_select_btn.toggled.connect(func(pressed: bool): set_selected(pressed, true))
	_apply_select_btn_style()
	add_child(_select_btn)

	# 3. 标题文字 (固定单行省略，Tooltip 提供全称)
	_title = Label.new()
	_title.text = record.get("title", "未命名" + Presentation.noun(library_kind))
	_title.tooltip_text = _title.text
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.max_lines_visible = int(_spec.title.max_lines)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", Typography.BODY)
	_title.add_theme_color_override("font_color", CardSpec.color("text"))
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_title)

	# 4. 标签栏 (纯文字次要色，无外框底色，无下划线，无焦点环残留)
	_tags_btn = Button.new()
	_tags_btn.theme_type_variation = "GeminiTag"
	_tags_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", Typography.TAG)
	_summary_label.add_theme_color_override("font_color", COLOR_MUTED)
	_summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary_label)
	_refresh_tags_text()
	_tags_btn.clip_text = true
	_tags_btn.disabled = selection_only
	_tags_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not selection_only else Control.CURSOR_ARROW
	_tags_btn.pressed.connect(func(): action_requested.emit("tags", record))
	add_child(_tags_btn)

	# 5. 主动作按钮
	_primary_btn = Button.new()
	_primary_btn.text = primary_text
	_primary_btn.theme_type_variation = "GeminiPrimary" if selection_only else "GeminiAction"
	_primary_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER if selection_only else HORIZONTAL_ALIGNMENT_LEFT
	_primary_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if not selection_only:
		var edit_ico := _load_icon("edit")
		if edit_ico:
			_primary_btn.icon = edit_ico
			_primary_btn.expand_icon = true
			_primary_btn.add_theme_constant_override("icon_max_width", 18)

	_primary_btn.pressed.connect(func(): primary_requested.emit(record.get("id", "")))
	add_child(_primary_btn)

	# 6. 更多菜单按钮（普通 Button，点击打开自制菜单）
	_more_btn = Button.new()
	_more_btn.theme_type_variation = "GeminiIcon"
	_more_btn.visible = not selection_only
	_more_btn.tooltip_text = "更多操作"
	_more_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var more_ico := _load_icon("more")
	if more_ico:
		_more_btn.icon = more_ico
		_more_btn.expand_icon = true
		_more_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_more_btn.add_theme_constant_override("icon_max_width", 20)

	_more_btn.pressed.connect(_on_more_pressed)
	_more_btn.gui_input.connect(_more_input)
	add_child(_more_btn)

	# 创建自制命令菜单（放在根 Canvas 层）
	if not selection_only: _setup_menu.call_deferred()

func _setup_menu() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	# 菜单通过 page_shell.add_overlay() 挂载，避免被页面 CanvasLayer 遮挡
	if not is_instance_valid(page_shell) or page_shell.is_queued_for_deletion() or not page_shell.has_method("add_overlay"):
		push_warning("library_reference_card: page_shell 未设置或缺少 add_overlay 方法")
		return

	_menu = VerticalCommandMenu.new()
	page_shell.add_overlay(_menu)
	_menu.action_requested.connect(_on_menu_action)

func _on_more_pressed() -> void:
	if not is_instance_valid(_menu) or not is_instance_valid(_more_btn):
		return
	if _menu.is_open():
		_menu.close()
		return

	# 构建菜单项
	var actions: Array[Dictionary] = [
		{title = "重命名", id = "rename", icon = "res://ui/theme/icons/library/edit.svg"},
		{title = "复制", id = "copy", icon = "res://ui/theme/icons/library/copy.svg"}
	]

	# 升级项仅在基础棋子中显示
	if library_kind == "tokens" and record.get("kind", "basic") == "basic":
		actions.append({title = "升级为高级棋子…", id = "upgrade", icon = "res://ui/theme/icons/library/up.svg"})

	# 分隔线 + 危险项
	actions.append({title = "删除…", id = "delete", danger = true, separator_before = true})

	_menu_record_revision = _record_revision
	_menu.open(_more_btn, actions, _more_keyboard)

func _more_input(event: InputEvent) -> void:
	if event is InputEventKey: _more_keyboard = true
	elif event is InputEventMouseButton or event is InputEventScreenTouch: _more_keyboard = false

func _on_menu_action(action_id: String) -> void:
	if _menu_record_revision != _record_revision or not is_inside_tree() or is_queued_for_deletion(): return
	action_requested.emit(action_id, record)

func _update_thumbnail() -> void:
	if _image_rect == null: return
	if record.has("preview_texture") and record["preview_texture"] != null:
		_image_rect.texture = record["preview_texture"]
		_placeholder.visible = false
	elif record.has("catalog_kind") and record.has("id"):
		var catalog := _get_product_catalog()
		if catalog != null and catalog.has_method("request_preview"):
			catalog.request_preview(record, _image_rect)
			_placeholder.visible = (_image_rect.texture == null)
		else:
			_image_rect.texture = null
			_placeholder.visible = true
	else:
		_image_rect.texture = null
		_placeholder.visible = true

func _on_catalog_changed(kind: String) -> void:
	# 响应目录修补通知：仅当本卡片缺图且属于对应类别时，从已更新的内存索引获取最新 revision，避免每卡重复枚举全磁盘
	if kind != record.get("catalog_kind", ""): return
	if _image_rect != null and _image_rect.texture != null: return
	var catalog := _get_product_catalog()
	if catalog == null: return
	var key := kind + ":" + str(record.get("id", ""))
	if catalog.get("metadata") is Dictionary and catalog.metadata.has(key):
		var meta: Dictionary = catalog.metadata[key]
		var rev: String = str(meta.get("preview_revision", ""))
		if not rev.is_empty() and rev != str(record.get("preview_revision", "")):
			record["preview_revision"] = rev
			record["preview_version"] = meta.get("preview_version",0)
			catalog.request_preview(record, _image_rect)
			_sync_placeholder_visibility()

func _sync_placeholder_visibility() -> void:
	if _placeholder != null and _image_rect != null:
		_placeholder.visible = (_image_rect.texture == null)
		_fit_preview_image()

func _fit_preview_image() -> void:
	if _image_clip == null or _frame == null: return
	# _image_clip 与舞台等大，填满整个预览区域。TextureRect 的 STRETCH_KEEP_ASPECT_COVERED
	# 保证图片等比铺满舞台；_image_clip 的圆角裁切溢出部分，所有资产使用统一规则。
	_place(_image_clip, Rect2(Vector2.ZERO, _frame.size))

func _refresh_tags_text() -> void:
	if _tags_btn == null: return
	_tags_btn.visible = library_kind == "tokens"
	_summary_label.visible = library_kind != "tokens"
	if library_kind != "tokens":
		_summary_label.text = Presentation.summary(library_kind, record)
		_summary_label.tooltip_text = _summary_label.text
		return
	var tags: Array = record.get("tags", []).duplicate()
	var type_tag: String = "基础棋子" if record.get("kind", "basic") == "basic" else "高级棋子"
	if not tags.has(type_tag):
		tags.push_front(type_tag)

	if tags.size() == 1:
		_tags_btn.text = str(tags[0])
	elif tags.size() == 2:
		_tags_btn.text = str(tags[0]) + " · " + str(tags[1])
	else:
		_tags_btn.text = str(tags[0]) + " · " + str(tags[1]) + (" · 另有 %d 项" % (tags.size() - 2))
	_tags_btn.tooltip_text = "、".join(PackedStringArray(tags))

func _apply_select_btn_style() -> void:
	if _select_btn == null: return
	var is_mob := _is_mobile_mode()
	var corner_r := 14 if is_mob else 12

	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(corner_r)

		if is_selected:
			var bg := COLOR_BORDER_SELECTED
			if state == "hover": bg = Color("106ebe")
			elif state == "pressed": bg = Color("004578")

			box.bg_color = bg
			box.border_color = Color.BLACK if state == "focus" else Color.TRANSPARENT
			box.set_border_width_all(2 if state == "focus" else 0)
		else:
			box.bg_color = Color("f0f6fc") if state == "hover" else (Color("ebebeb") if state == "pressed" else Color(1, 1, 1, 0.85))
			box.border_color = Color.BLACK if state == "focus" else (COLOR_BORDER_HOVER if state == "hover" else Color("c0c0c0"))
			box.set_border_width_all(2 if state == "focus" else 1)

		_select_btn.add_theme_stylebox_override(state, box)

	if is_selected:
		var chk_ico := _load_icon("check")
		_select_btn.icon = chk_ico
		_select_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_select_btn.expand_icon = true
		_select_btn.add_theme_constant_override("icon_max_width", 20 if is_mob else 14)
	else:
		_select_btn.icon = null

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_select_btn.add_theme_color_override("icon_" + state + "_color", Color.WHITE if is_selected else CardSpec.color("text"))
	_select_btn.queue_redraw()

# 公开状态控制接口
func set_selectable(enable: bool) -> void:
	selectable = enable
	if _select_btn != null:
		_select_btn.visible = selectable and not selection_only
	_layout()
	queue_redraw()

func set_selected(selected: bool, emit_notify: bool = false) -> void:
	if is_selected == selected: return
	is_selected = selected
	if _select_btn != null and _select_btn.button_pressed != is_selected:
		_select_btn.set_pressed_no_signal(is_selected)
	_apply_select_btn_style()
	queue_redraw()
	if emit_notify:
		card_selected.emit(is_selected, record)

func update_record(new_record: Dictionary) -> void:
	# 菜单项与打开时的记录绑定；换绑必须先取消旧命令，再更新内容。
	_record_revision += 1
	_menu_record_revision = -1
	if is_instance_valid(_menu):
		_menu.close(false)
	record = new_record
	# 切换数据时显式清空旧纹理，防止无图数据残留旧图
	if _image_rect != null:
		_image_rect.texture = null
	if _title != null:
		_title.text = record.get("title", "未命名" + Presentation.noun(library_kind))
		_title.tooltip_text = _title.text
	_refresh_tags_text()
	_update_thumbnail()
	_layout()
	queue_redraw()

func set_hover_state_for_showcase(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

# 只读几何供独立展示记录；调用方不能藉此改内部控件。
func layout_snapshot_for_showcase() -> Dictionary:
	return {"title": _title.get_rect(), "tags": _tags_btn.get_rect(), "primary": _primary_btn.get_rect(), "more": _more_btn.get_rect(), "rail_y": _rail_y}

func get_primary_button() -> Button:
	return _primary_btn

func get_more_button() -> Button:
	return _more_btn

func get_select_button() -> Button:
	return _select_btn

func _is_mobile_mode() -> bool:
	if force_mobile: return true
	var mob := _get_mobile_node()
	if mob != null:
		return bool(mob.get("enabled"))
	return OS.has_feature("android")

func _get_mobile_node() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root.has_node("Mobile"):
		return main_loop.root.get_node("Mobile")
	return null

func _get_product_catalog() -> Node:
	if Engine.has_singleton("ProductCatalog"):
		return Engine.get_singleton("ProductCatalog")
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root.has_node("ProductCatalog"):
		return main_loop.root.get_node("ProductCatalog")
	return null

func _load_icon(icon_name: String) -> Texture2D:
	return preload("res://ui/theme/icons/library_icons.gd").texture("res://ui/theme/icons/library/" + icon_name + ".svg")

static func preferred_width() -> float:
	return float(CardSpec.data().card.width)

# 布局自适应逻辑：PC 与移动端共享统一纵向卡片结构，移动端触控区自动满足 >= 48px
func _layout() -> void:
	if _frame == null: return
	var is_mob := _is_mobile_mode()
	var mode := "mobile" if is_mob else "desktop"
	var w := size.x if size.x > 0 else float(_spec.card.width)
	var spacing: Dictionary = _spec.spacing
	var title_spec: Dictionary = _spec.title
	var tags_spec: Dictionary = _spec.tags
	var buttons: Dictionary = _spec.buttons
	_place(_frame, Rect2(float(spacing.preview_side), float(spacing.preview_top), maxf(1, w - 2 * float(spacing.preview_side)), float(_spec.card.preview_height)))
	_fit_preview_image()
	if _select_btn != null and _select_btn.visible:
		var btn_dim := float(_spec.select_button["size_" + mode])
		_place(_select_btn, Rect2(w - float(spacing.select_btn_margin) - btn_dim, float(spacing.select_btn_margin) - 4, btn_dim, btn_dim))
	_place(_title, Rect2(float(title_spec.x), float(title_spec.y), maxf(1, w + float(title_spec.width_offset)), float(title_spec.height)))
	custom_minimum_size.y = float(_spec.card["height_" + mode])
	_rail_y = float(buttons["rail_y_" + mode])
	var tags_w := minf(_get_tag_content_width(), maxf(1, w - 2 * float(tags_spec.x)))
	var tag_y := float(title_spec.y) + float(title_spec.height) + float(tags_spec.title_gap)
	_place(_tags_btn, Rect2(float(tags_spec.x), tag_y, tags_w, float(tags_spec["height_" + mode])))
	_place(_summary_label, Rect2(float(tags_spec.x), tag_y, maxf(1, w - 2 * float(tags_spec.x)), float(tags_spec["height_" + mode])))
	var btn_h := float(buttons["height_" + mode])
	var btn_y := _rail_y + float(buttons.rail_offset)
	if selection_only:
		_place(_primary_btn, Rect2(12, btn_y, maxf(1, w - 24), btn_h))
		_more_btn.visible = false
	else:
		_more_btn.visible = true
		var more_w := float(buttons["more_width_" + mode])
		_place(_primary_btn, Rect2(8, btn_y, maxf(1, w - more_w - 26), btn_h))
		_place(_more_btn, Rect2(w - more_w - 8, btn_y, more_w, btn_h))

	queue_redraw()

func _get_tag_content_width() -> float:
	var font := _tags_btn.get_theme_font("font")
	var font_size := _tags_btn.get_theme_font_size("font_size")
	if font == null: return 120.0
	return ceilf(font.get_string_size(_tags_btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 4.0

func _place(ctrl: Control, rect: Rect2) -> void:
	ctrl.position = rect.position
	ctrl.size = rect.size

func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()

func _draw() -> void:
	var border_color := COLOR_BORDER
	var border_w := int(_spec.card.border_width_normal)

	if is_selected:
		border_color = COLOR_BORDER_SELECTED
		border_w = int(_spec.card.border_width_selected)
	elif _is_hovered:
		border_color = COLOR_BORDER_HOVER

	var is_mob := _is_mobile_mode()
	var r := int(_spec.card.border_radius_mobile) if is_mob else int(_spec.card.border_radius)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_CARD_BG
	card_style.border_color = border_color
	card_style.set_border_width_all(border_w)
	card_style.set_corner_radius_all(r)
	draw_style_box(card_style, Rect2(Vector2.ZERO, size))

	# 动作栏分割线 (水平线与按钮间垂直线)
	draw_line(Vector2(1, _rail_y), Vector2(size.x - 1, _rail_y), COLOR_BORDER)
	if not selection_only:
		var mode := "mobile" if is_mob else "desktop"
		var btn_h := float(_spec.buttons["height_" + mode])
		var sep_x := _more_btn.position.x - 4.0
		draw_line(Vector2(sep_x, _rail_y + float(_spec.buttons.rail_offset) + float(_spec.spacing.button_separator_padding)), Vector2(sep_x, _rail_y + float(_spec.buttons.rail_offset) + btn_h - float(_spec.spacing.button_separator_padding)), COLOR_BORDER)

	# 选中态备用标记 (仅在未挂载或隐藏 _select_btn 时绘制)
	if is_selected and (_select_btn == null or not _select_btn.visible):
		var badge_center := Vector2(size.x - 24, 24)
		draw_circle(badge_center, 12.0, COLOR_BORDER_SELECTED)
		var p1 := badge_center + Vector2(-5, 0)
		var p2 := badge_center + Vector2(-1, 4)
		var p3 := badge_center + Vector2(5, -4)
		draw_line(p1, p2, Color.WHITE, 2.0)
		draw_line(p2, p3, Color.WHITE, 2.0)
