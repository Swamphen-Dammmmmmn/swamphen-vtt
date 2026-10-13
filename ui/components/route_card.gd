extends PanelContainer

signal action_requested(action: String)

func _ready() -> void:
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	$Content.add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
	BoardUiStyle.style_controls(self)
	$Content/Buttons/Undo.pressed.connect(func(): action_requested.emit("undo"))
	$Content/Buttons/Confirm.pressed.connect(func(): action_requested.emit("confirm"))
	$Content/Buttons/Cancel.pressed.connect(func(): action_requested.emit("cancel"))

func update_state(amount: String, has_points: bool, editing: bool) -> void:
	$Content/Summary.text = "已固定 · " + amount
	$Content/Hint.hide()
	$Content/Buttons/Undo.disabled = not has_points or editing
	$Content/Buttons/Confirm.disabled = not has_points or editing
