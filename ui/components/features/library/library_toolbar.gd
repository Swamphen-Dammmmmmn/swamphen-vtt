extends VBoxContainer
signal management_requested
signal query_changed(value: String)
signal create_requested
const ButtonComponent = preload("res://ui/components/controls/fluent_button.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
var noun := ""
var mode := Presentation.Mode.MANAGE
var management_text := ""
var _search: LineEdit
var _create: Button
var _row: HBoxContainer
var _preferred_search_width := 0
var _preferred_create_width := 0

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var control_height := LibTokens.CONTROL_HEIGHT_MOBILE if Mobile.enabled else LibTokens.CONTROL_HEIGHT_DESKTOP
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", LibTokens.TOOLBAR_GAP)
	add_child(_row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称"
	_search.max_length = 80
	_search.custom_minimum_size = Vector2(0, control_height)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.right_icon = load("res://ui/theme/icons/library/search.svg")
	_row.add_child(_search)
	_search.text_changed.connect(func(value: String): query_changed.emit(value))
	_create = ButtonComponent.new()
	_create.text = management_text if mode == Presentation.Mode.SELECT else "创建"+noun
	_create.variant = "FluentButton" if mode == Presentation.Mode.SELECT else "FluentPrimary"
	_create.minimum_height = control_height
	_preferred_create_width = LibTokens.CREATE_BUTTON_WIDTH
	_create.custom_minimum_size.x = _preferred_create_width
	if mode == Presentation.Mode.MANAGE: _create.icon = Icons.texture("res://ui/theme/icons/library/plus_tintable.svg")
	_create.expand_icon = true
	_create.add_theme_constant_override("icon_max_width", 20)
	_create.visible = mode == Presentation.Mode.MANAGE or not management_text.is_empty()
	_row.add_child(_create)
	_create.pressed.connect(_on_action)
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	call_deferred("_fit")

func clear_query() -> void:
	_search.text = ""

func _fit() -> void:
	if not is_inside_tree() or _search==null or _create==null: return
	var available := size.x
	if available < 1: return
	_preferred_search_width = LibTokens.SEARCH_MIN_WIDTH_MOBILE if Mobile.enabled else LibTokens.SEARCH_MIN_WIDTH_DESKTOP
	var height := LibTokens.CONTROL_HEIGHT_MOBILE if Mobile.enabled else LibTokens.CONTROL_HEIGHT_DESKTOP
	_search.custom_minimum_size.y = height
	_create.custom_minimum_size.y = height
	var search_min := _preferred_search_width
	var create_width := maxf(_preferred_create_width, _create.get_combined_minimum_size().x)
	var gap := LibTokens.TOOLBAR_GAP
	var needed: float = float(search_min) + (create_width + gap if _create.visible else 0.0)
	var should_stack: bool = _create.visible and needed > available
	var is_stacked := _create.get_parent() != _row
	if should_stack and not is_stacked:
		_create.reparent(self, false)
	elif not should_stack and is_stacked:
		_create.reparent(_row, false)
	# 首选宽只决定换行，不成为父页面的硬最小宽，避免阻止窗口收窄。
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.x = 0

func _on_action() -> void:
	if mode == Presentation.Mode.SELECT: management_requested.emit()
	else: create_requested.emit()
