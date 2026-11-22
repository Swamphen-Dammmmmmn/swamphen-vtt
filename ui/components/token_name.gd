extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")
const CardTheme = preload("res://ui/theme/themes/token_card_theme.gd")
const Spec = preload("res://ui/theme/tokens/token_card_tokens.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

signal action_requested(action: String)
signal notes_changed(text: String)
var expanded := false
var notes_editor: TextEdit
var expand_button: Button
var temporary_label: Label
var health_bar: Control
var syncing_notes := false
var cached_notes := ""
var selected := false

func _ready() -> void:
	set_meta("style_owned", true)
	theme = CardTheme.shared()
	theme_type_variation = &"TokenCard"
	$Content.add_theme_constant_override("separation", Spec.GAP)
	$Content/Header.add_theme_constant_override("separation", Spec.GAP)
	$Content/Header/Name.theme_type_variation = &"TokenCardName"
	for button in [$Content/Header/HP, $Content/Header/AC]:
		button.theme_type_variation = &"TokenStat"
		button.custom_minimum_size = Vector2(0, Spec.TOUCH_HEIGHT if Mobile.enabled else Spec.HEADER_HEIGHT)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.focus_mode = Control.FOCUS_ALL
		button.add_child(ButtonFocus.new())
	$Content/Header/HP.icon = preload("res://ui/icons/heart_color.svg")
	$Content/Header/AC.icon = preload("res://ui/icons/shield_color.svg")
	for button in [$Content/Header/HP, $Content/Header/AC]:
		button.expand_icon = false
	$Content/Header/HP.pressed.connect(func(): action_requested.emit("hp"))
	$Content/Header/AC.pressed.connect(func(): action_requested.emit("ac"))
	temporary_label = Label.new()
	temporary_label.add_theme_color_override("font_color", T.BRAND)
	temporary_label.add_theme_font_size_override("font_size",Typography.STATUS)
	temporary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Content/Header.add_child(temporary_label)
	$Content/Header.move_child(temporary_label,3)
	expand_button = Button.new()
	expand_button.theme_type_variation = &"TokenCardExpand"
	expand_button.pressed.connect(_toggle_notes)
	GoStyle.apply_icon(expand_button,GoIconSet.CHEVRON_DOWN,16)
	expand_button.tooltip_text = "展开备注"
	var action_size := Spec.TOUCH_HEIGHT if Mobile.enabled else Spec.HEADER_HEIGHT
	expand_button.custom_minimum_size = Vector2(action_size, action_size)
	expand_button.add_child(ButtonFocus.new())
	$Content/Header.add_child(expand_button)
	health_bar = preload("res://ui/components/token_health_bar.gd").new()
	health_bar.custom_minimum_size.y = Spec.HEALTH_HEIGHT
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Content.add_child(health_bar)
	notes_editor = TextEdit.new()
	notes_editor.theme_type_variation = &"TokenCardNotes"
	notes_editor.placeholder_text = "备注"
	notes_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes_editor.custom_minimum_size = Vector2(Spec.NOTES_WIDTH, Spec.NOTES_HEIGHT)
	$Content.add_child(notes_editor)
	notes_editor.hide()
	notes_editor.text_changed.connect(func():
		if syncing_notes: return
		var text := notes_editor.text
		if text.length()>8000:
			text = text.left(8000)
			syncing_notes = true
			notes_editor.text = text
			syncing_notes = false
		cached_notes = text
		notes_changed.emit(text)
	)

func _toggle_notes() -> void:
	set_notes_expanded(not expanded)

func set_notes_expanded(value: bool) -> void:
	expanded = value
	notes_editor.visible = expanded
	GoStyle.apply_icon(expand_button,GoIconSet.CHEVRON_UP if expanded else GoIconSet.CHEVRON_DOWN,16)
	expand_button.tooltip_text = "收起备注" if expanded else "展开备注"
	reset_size()

func set_details_interactive(interactive: bool) -> void:
	expand_button.disabled = not interactive
	expand_button.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	$Content/Header/HP.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	$Content/Header/AC.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

func set_editable(value: bool) -> void:
	if notes_editor.editable!=value: notes_editor.editable = value
	for button in [$Content/Header/HP,$Content/Header/AC]: button.disabled = not value

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	theme_type_variation = &"TokenCardSelected" if value else &"TokenCard"
	$Content/Header/Name.theme_type_variation = &"TokenCardNameSelected" if value else &"TokenCardName"

func update_data(title: String, color: Color, hp: int, maximum: int, ac: int, temporary: int = 0, notes: String = "") -> void:
	tooltip_text = title + ("\n临时生命值：%d" % temporary if temporary > 0 else "")
	$Content/Header/Name.text = title
	$Content/Header/Name.tooltip_text = title
	var name_label := $Content/Header/Name as Label
	var text_width := name_label.get_theme_font("font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x
	var max_width := minf(Spec.NAME_MAX_WIDTH, get_viewport_rect().size.x * Spec.NAME_VIEWPORT_RATIO)
	name_label.custom_minimum_size.x = minf(ceilf(text_width), max_width)
	$Content/Header/Swatch.color = color
	$Content/Header/HP.text = "%d/%d" % [hp, maximum] if maximum > 0 else "—"
	$Content/Header/AC.text = str(ac) if ac >= 0 else "—"
	temporary_label.text = "+%d" % temporary
	temporary_label.visible = temporary>0
	health_bar.visible = maximum>0
	health_bar.set_values(hp,maximum,temporary)
	if notes!=cached_notes:
		cached_notes = notes
		syncing_notes = true
		var vertical := notes_editor.scroll_vertical
		notes_editor.text = notes
		notes_editor.scroll_vertical = vertical
		syncing_notes = false
