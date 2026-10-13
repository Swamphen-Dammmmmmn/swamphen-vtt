extends PanelContainer

signal action_requested(action: String)
var health_tween: Tween
var previous_hp := -2
var previous_max := -2
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
		button.add_theme_font_size_override("font_size", 13)
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
	var background := StyleBoxFlat.new()
	background.bg_color = Color("e2e7ed")
	background.set_corner_radius_all(3)
	background.set_content_margin_all(0)
	$Content/Health.add_theme_stylebox_override("background", background)
	var fill := background.duplicate() as StyleBoxFlat
	fill.bg_color = Color("429d86")
	$Content/Health.add_theme_stylebox_override("fill", fill)

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	face.border_color = Color("3973bc") if value else BoardUiStyle.BORDER_COLOR
	queue_redraw()

func update_data(title: String, color: Color, hp: int, maximum: int, ac: int) -> void:
	$Content/Header/Name.text = title
	$Content/Header/Name.tooltip_text = title
	var name_label := $Content/Header/Name as Label
	var text_width := name_label.get_theme_font("font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x
	var max_width := minf(480.0, get_viewport_rect().size.x * 0.35)
	name_label.custom_minimum_size.x = minf(ceilf(text_width), max_width)
	$Content/Header/Swatch.color = color
	$Content/Header/HP.text = "%d/%d" % [hp, maximum] if maximum > 0 else "—"
	$Content/Header/AC.text = str(ac) if ac >= 0 else "—"
	if hp != previous_hp or maximum != previous_max:
		if health_tween:
			health_tween.kill()
		var target := 100.0 * hp / maximum if maximum > 0 else 0.0
		if previous_hp == -2:
			$Content/Health.value = target
		else:
			health_tween = create_tween()
			health_tween.tween_property($Content/Health, "value", target, preload("res://ui/components/page_motion.gd").duration(0.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if hp >= 0 and previous_hp >= 0 and hp != previous_hp:
				$Content/Header/HP.modulate = Color("bd4949") if hp < previous_hp else Color("28876a")
				health_tween.parallel().tween_property($Content/Header/HP, "modulate", Color.WHITE, preload("res://ui/components/page_motion.gd").duration(0.3))
		previous_hp = hp
		previous_max = maximum
