extends RefCounted
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Spec = preload("res://ui/theme/tokens/entity_context_tokens.gd")

static func face(compact := false) -> StyleBoxFlat:
	var box := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
	box.set_content_margin_all(Spec.COMPACT_PADDING if compact else Spec.PADDING)
	return box
