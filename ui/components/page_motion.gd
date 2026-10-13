extends RefCounted

# Page effects are visual only; business actions never wait for a tween.
const PAGE_FADE := 0.16
const NOTICE_FADE := 0.12
const HOVER_TIME := 0.10
const PRESS_TIME := 0.06
const Preferences = preload("res://scripts/ui_preferences.gd")

static func duration(seconds: float) -> float:
	return Preferences.shared().duration(seconds)

static func fade_in(control: Control, duration := PAGE_FADE) -> void:
	control.modulate.a = 0.0
	fade_to(control, 1.0, duration)

static func fade_to(control: Control, alpha: float, duration := NOTICE_FADE) -> Tween:
	if control.has_meta("page_fade_tween"):
		var previous := control.get_meta("page_fade_tween") as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := control.create_tween()
	control.set_meta("page_fade_tween", tween)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", alpha, Preferences.shared().duration(duration))
	return tween

static func prepare_button(button: Button) -> void:
	if button.has_meta("page_motion_prepared"):
		return
	button.set_meta("page_motion_prepared", true)
	# Capture final styles after component-specific overrides have been applied.
	_install_button.call_deferred(button)

static func _install_button(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var colors: Dictionary = {}
	for state in ["normal", "hover", "pressed"]:
		var face := button.get_theme_stylebox(state) as StyleBoxFlat
		if face == null:
			return
		colors[state] = face.bg_color
	var normal: Color = colors["normal"]
	if is_zero_approx(normal.a):
		var hover: Color = colors["hover"]
		colors["normal"] = Color(hover.r, hover.g, hover.b, 0.0)
	var animated_face := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	animated_face.bg_color = colors["normal"]
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, animated_face)
	button.set_meta("page_motion_colors", colors)
	button.set_meta("page_motion_face", animated_face)
	button.mouse_entered.connect(func(): _button_state(button, button.is_pressed()))
	button.mouse_exited.connect(func(): _button_state(button))
	button.button_down.connect(func(): _button_state(button, true))
	button.button_up.connect(func(): _button_state(button, false))
	_button_state(button)

static func _button_state(button: Button, pressing := false) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var state := "pressed" if pressing else ("hover" if button.is_hovered() else "normal")
	var colors: Dictionary = button.get_meta("page_motion_colors")
	var face := button.get_meta("page_motion_face") as StyleBoxFlat
	if button.has_meta("page_button_tween"):
		var previous := button.get_meta("page_button_tween") as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := button.create_tween()
	button.set_meta("page_button_tween", tween)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(face, "bg_color", colors[state], duration(PRESS_TIME if pressing else HOVER_TIME))
