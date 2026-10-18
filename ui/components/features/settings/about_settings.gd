extends VBoxContainer

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const UpdatePanel = preload("res://ui/components/software_update_panel.gd")
const FontAttribution = preload("res://ui/components/features/settings/font_attribution.gd")

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", T.GAP)
	if Mobile.enabled:
		var version := Label.new()
		version.text = "紫水鸡棋盘 v" + str(ProjectSettings.get_setting("application/config/version", ""))
		version.add_theme_font_size_override("font_size", Typography.SUBTITLE)
		version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(version)
		var license_label := Label.new()
		license_label.text = "GNU GPL v3.0"
		license_label.add_theme_font_size_override("font_size", Typography.CAPTION)
		add_child(license_label)
	else:
		var panel := UpdatePanel.new()
		panel.set_meta("fluent_variant", true)
		add_child(panel)
	var attribution := FontAttribution.new()
	attribution.set_meta("fluent_variant", true)
	add_child(attribution)
