extends PanelContainer

signal remove_requested(member_id: String)
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const P = preload("res://ui/theme/tokens/party_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
const PartyTheme = preload("res://ui/theme/themes/party_card_theme.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const Menu = preload("res://ui/components/overlays/vertical_command_menu.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
var _record: Dictionary = {}
var _nickname: Label
var _name_suffix: Label
var _role: Label
var _status: Label
var _slot: Control
var _first: Control
var _actions: Control
var _more: Button
var _menu: Menu
var _more_keyboard := false
var _hovered := false

func _ready() -> void:
	theme = FluentTheme.shared()
	# 固定高度保证有无更多按钮的卡片等高；手机沿用更高的触摸目标。
	custom_minimum_size.y = P.MOBILE_CARD_HEIGHT if Mobile.enabled else P.CARD_HEIGHT
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# PASS：整卡接收悬停与完整名称提示，滚轮和拖动仍交给名单滚动容器。
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_face()
	# 操作层先于文字加入，按钮反馈绘制在文字下方；层本身忽略鼠标，只有按钮接收点击。
	_actions = Control.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actions)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", P.ROW_GAP)
	add_child(lines)
	# 第一行：昵称为主信息，同名编号与角色／本人为辅助信息，角色靠右对齐。
	var first := HBoxContainer.new()
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	first.add_theme_constant_override("separation", P.ROLE_GAP)
	lines.add_child(first)
	_first = first
	var name := HBoxContainer.new()
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_constant_override("separation", P.NAME_SUFFIX_GAP)
	first.add_child(name)
	_nickname = _label(Typography.BODY, PartyTheme.text_color())
	_nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_child(_nickname)
	_name_suffix = _label(Typography.TAG, PartyTheme.muted_color())
	name.add_child(_name_suffix)
	# 同名编号紧跟昵称，剩余空白留在编号之后，不把编号推到角色旁。
	var name_rest := Control.new()
	name_rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_child(name_rest)
	name.resized.connect(_fit_name)
	_role = _label(Typography.TAG, PartyTheme.muted_color())
	first.add_child(_role)
	# 第二行：状态与右侧更多图标位。图标位只占图标宽度，触摸区由操作层居中放置，不形成整高操作列。
	var second := HBoxContainer.new()
	second.mouse_filter = Control.MOUSE_FILTER_IGNORE
	second.add_theme_constant_override("separation", 0)
	lines.add_child(second)
	_status = _label(Typography.CAPTION, PartyTheme.muted_color())
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	second.add_child(_status)
	_slot = Control.new()
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot.custom_minimum_size.x = P.MORE_SLOT_WIDTH
	second.add_child(_slot)
	if Mobile.enabled:
		# 手机：两行贴卡底排列，首行下留出间距，状态行与48触摸区等高居中；按钮整体位于首行下方。
		lines.alignment = BoxContainer.ALIGNMENT_END
		lines.add_theme_constant_override("separation", P.MOBILE_ROW_GAP)
		second.custom_minimum_size.y = P.MOBILE_STATUS_ROW_HEIGHT
		# 状态文字止于48触摸区左缘前，触摸区右缘贴卡片描边内侧。
		var border := float(PartyTheme.member_card_face(false, true).border_width_right)
		_slot.custom_minimum_size.x = P.MOBILE_MORE_BUTTON_SIZE + border - P.CARD_PADDING_H + P.MOBILE_MORE_TEXT_GAP
	_more = Button.new()
	_more.theme = PartyTheme.get_theme()
	_more.theme_type_variation = "PartyCardMoreButton"
	_more.icon = Icons.texture("res://ui/theme/icons/library/more.svg")
	_more.expand_icon = true
	_more.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more.add_theme_constant_override("icon_max_width", P.MORE_ICON_SIZE)
	_more.custom_minimum_size = Vector2.ONE * _more_size()
	_more.size = _more.custom_minimum_size
	_more.tooltip_text = "团员操作"
	_more.accessibility_name = "团员操作"
	_more.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_actions.add_child(_more)
	_more.add_child(ButtonFocus.new())
	_more.pressed.connect(_open_menu)
	_more.gui_input.connect(_more_input)
	# 进入更多按钮时整卡仍按指针位置保持悬停，不闪烁；离开卡片后恢复。
	mouse_entered.connect(_refresh_hover)
	mouse_exited.connect(_refresh_hover)
	_more.mouse_entered.connect(_refresh_hover)
	_more.mouse_exited.connect(_refresh_hover)
	_slot.item_rect_changed.connect(_place_more)
	resized.connect(_place_more)
	_apply()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func set_member(record: Dictionary) -> void:
	if record != _record and is_instance_valid(_menu): _menu.close(false)
	_record = record.duplicate()
	_apply()

# 静态展示诊断入口，与大地图卡同名；只切换整卡悬停描边，不触发任何操作。
func set_hover_state_for_showcase(hovered: bool) -> void:
	_set_hovered(hovered)

func _apply() -> void:
	if _nickname == null: return
	var nickname := str(_record.get("nickname", ""))
	var display_name := str(_record.get("display_name", nickname))
	var has_suffix := not nickname.is_empty() and display_name.begins_with(nickname + " · ")
	# 同名短编号固定保留，只有昵称截断，窄列仍能区分同名团员。
	_nickname.text = nickname if has_suffix else display_name
	_nickname.tooltip_text = display_name
	# 文字层不接收鼠标，完整名称提示由整卡提供。
	tooltip_text = display_name
	_name_suffix.visible = has_suffix
	_name_suffix.text = display_name.substr(nickname.length()).strip_edges() if has_suffix else ""
	_role.text = str(_record.get("role_text", ""))
	_status.text = str(_record.get("status", ""))
	_status.add_theme_color_override("font_color", T.SUCCESS if _record.get("online", false) else PartyTheme.muted_color())
	var can_remove := bool(_record.get("can_remove", false))
	_more.visible = can_remove
	_slot.visible = can_remove
	_more.accessibility_name = display_name + "的团员操作"
	_fit_name.call_deferred()
	_place_more.call_deferred()

# 昵称按文字实际宽度占位，超出剩余宽度时省略；编号宽度始终保留。
func _fit_name() -> void:
	if not is_instance_valid(_nickname): return
	var name := _nickname.get_parent() as Control
	var font := _nickname.get_theme_font("font")
	var text_width := font.get_string_size(_nickname.text, HORIZONTAL_ALIGNMENT_LEFT, -1, Typography.BODY).x
	var available := name.size.x
	if _name_suffix.visible: available -= _name_suffix.get_combined_minimum_size().x + P.NAME_SUFFIX_GAP
	# 最后的分隔间距属于剩余空白，不占昵称宽度。
	available -= P.NAME_SUFFIX_GAP
	var width := floorf(clampf(text_width, 0.0, maxf(available, 0.0)))
	if not is_equal_approx(_nickname.custom_minimum_size.x, width): _nickname.custom_minimum_size.x = width

func _more_size() -> float:
	return P.MOBILE_MORE_BUTTON_SIZE if Mobile.enabled else P.MORE_BUTTON_SIZE

# 图标右缘与角色文字右缘对齐、纵向居中于状态行；触摸区限制在卡片描边内。
func _place_more() -> void:
	if not is_instance_valid(_more) or not is_inside_tree(): return
	var side := _more_size()
	var slot_rect := Rect2(_slot.global_position - global_position, _slot.size)
	var center := Vector2(slot_rect.end.x - P.MORE_ICON_SIZE * 0.5, slot_rect.get_center().y)
	var border := float(PartyTheme.member_card_face(false, Mobile.enabled).border_width_left)
	var origin := center - Vector2.ONE * side * 0.5
	origin.x = clampf(origin.x, border, maxf(border, size.x - border - side))
	origin.y = clampf(origin.y, border, maxf(border, size.y - border - side))
	if Mobile.enabled:
		# 手机：触摸区贴卡片右侧描边内，顶边不高于首行底边，避免轻点昵称／角色触发更多。
		origin.x = maxf(border, size.x - border - side)
		var first_bottom := _first.global_position.y - global_position.y + _first.size.y
		origin.y = clampf(origin.y, first_bottom, maxf(first_bottom, size.y - border - side))
	_more.size = Vector2.ONE * side
	_more.position = origin - _actions.position

func _refresh_hover() -> void:
	# 手机没有鼠标悬停，轻点不留下常驻描边。
	if Mobile.enabled: return
	_set_hovered(is_visible_in_tree() and get_global_rect().has_point(get_global_mouse_position()))

func _set_hovered(hovered: bool) -> void:
	if hovered == _hovered: return
	_hovered = hovered
	_apply_face()

func _apply_face() -> void:
	# normal 与 hover 共用同一边宽与内边距，切换只改描边颜色，不影响卡片尺寸和名单排版。
	add_theme_stylebox_override("panel", PartyTheme.member_card_face(_hovered, Mobile.enabled))

func _more_input(event: InputEvent) -> void:
	if event is InputEventKey: _more_keyboard = true
	elif event is InputEventMouseButton or event is InputEventScreenTouch: _more_keyboard = false

func _open_menu() -> void:
	if not _record.get("can_remove", false): return
	if is_instance_valid(_menu) and _menu.is_open(): _menu.close(); return
	if not is_instance_valid(_menu):
		var host: Node = self
		while host != null and not host.has_method("add_overlay"): host = host.get_parent()
		if host == null: return
		_menu = Menu.new()
		host.add_overlay(_menu)
		_menu.action_requested.connect(func(action: String):
			if action == "remove" and _record.get("can_remove", false): remove_requested.emit(str(_record["id"]))
		)
	_menu.open(_more, [{"id": "remove", "title": "删除团员…", "icon": "res://ui/theme/icons/library/trash.svg", "danger": true}], _more_keyboard)

func _exit_tree() -> void:
	if is_instance_valid(_menu): _menu.close(false); _menu.queue_free()
