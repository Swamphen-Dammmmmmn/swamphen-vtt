extends PanelContainer

const SAVED_MEASUREMENT_INK := Color("80602b")

var _tone: StringName = &"default"

func _ready() -> void:
	_apply_tone()

func set_amount_text(value: String) -> void:
	$Amount.text = value

func amount_text() -> String:
	return $Amount.text

func set_tone(tone: StringName) -> void:
	_tone = tone
	if is_node_ready():
		_apply_tone()

func _apply_tone() -> void:
	if _tone == &"saved_measurement":
		$Amount.add_theme_color_override("font_color", SAVED_MEASUREMENT_INK)
	else:
		$Amount.remove_theme_color_override("font_color")
