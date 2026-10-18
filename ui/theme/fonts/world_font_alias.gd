extends FontVariation

# Compatibility for the former preview_size_font.tres entry point.
func _init() -> void:
	base_font = preload("res://ui/theme/typography.gd").WORLD_REGULAR
