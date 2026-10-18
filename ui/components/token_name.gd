extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")

signal action_requested(action: String)
signal notes_changed(text: String)
var expanded := false
var notes_editor: TextEdit
var expand_button: Button
var temporary_label: Label
var health_bar: Control
var syncing_notes := false
var cached_notes := ""
var face: StyleBoxFlat
var selected := false

func _ready() -> void:
	theme = GoUi.theme()
	face = BoardUiStyle.card_face(8.0)
	add_theme_stylebox_override("panel", face)
	for button in [$Content/Header/HP, $Content/Header/AC]:
		GoStyle.style_button(button, GoStyle.Tone.COMPACT)
		button.custom_minimum_size = Vector2(0, 26)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.add_theme_font_size_override("font_size", Typography.STATUS)
		for state in [&"normal", &"hover", &"pressed", &"disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT if state == &"normal" else Color("edf2f8")
			style.set_corner_radius_all(BoardUiStyle.CONTROL_RADIUS)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 3
			style.content_margin_bottom = 3
			button.add_theme_stylebox_override(state, style)
	$Content/Header/HP.icon = preload("res://ui/icons/heart_color.svg")
	$Content/Header/AC.icon = preload("res://ui/icons/shield_color.svg")
	for button in [$Content/Header/HP, $Content/Header/AC]:
		button.add_theme_constant_override("icon_max_width", 18)
		button.expand_icon = false
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_color_override("icon_" + state + "_color", Color.WHITE)
	$Content/Header/HP.pressed.connect(func(): action_requested.emit("hp"))
	$Content/Header/AC.pressed.connect(func(): action_requested.emit("ac"))
	temporary_label = Label.new()
	temporary_label.add_theme_color_override("font_color",Color("168de1"))
	temporary_label.add_theme_font_size_override("font_size",Typography.STATUS)
	temporary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Content/Header.add_child(temporary_label)
	$Content/Header.move_child(temporary_label,4)
	expand_button = GoStyle.button("",_toggle_notes,GoStyle.Tone.COMPACT)
	GoStyle.apply_icon(expand_button,GoIconSet.CHEVRON_DOWN,16)
	expand_button.tooltip_text = "展开备注"
	expand_button.custom_minimum_size = Vector2(26,26)
	expand_button.focus_mode = Control.FOCUS_NONE
	BoardUiStyle.action_button(expand_button,26)
	$Content/Header.add_child(expand_button)
	$Content/Health.hide()
	health_bar = preload("res://ui/components/token_health_bar.gd").new()
	health_bar.custom_minimum_size.y = 5
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Content.add_child(health_bar)
	notes_editor = TextEdit.new()
	notes_editor.placeholder_text = "备注"
	notes_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes_editor.custom_minimum_size = Vector2(300,120)
	notes_editor.add_theme_font_size_override("font_size",Typography.BODY)
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
	expanded = not expanded
	notes_editor.visible = expanded
	GoStyle.apply_icon(expand_button,GoIconSet.CHEVRON_UP if expanded else GoIconSet.CHEVRON_DOWN,16)
	expand_button.tooltip_text = "收起备注" if expanded else "展开备注"
	reset_size()

func set_editable(value: bool) -> void:
	if notes_editor.editable!=value: notes_editor.editable = value
	for button in [$Content/Header/HP,$Content/Header/AC]: button.disabled = not value

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	face.border_color = Color("3973bc") if value else BoardUiStyle.BORDER_COLOR
	queue_redraw()

func update_data(title: String, color: Color, hp: int, maximum: int, ac: int, temporary: int = 0, notes: String = "") -> void:
	$Content/Header/Name.text = title
	$Content/Header/Name.tooltip_text = title
	var name_label := $Content/Header/Name as Label
	var text_width := name_label.get_theme_font("font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x
	var max_width := minf(480.0, get_viewport_rect().size.x * 0.35)
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
