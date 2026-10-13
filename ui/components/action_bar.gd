extends PanelContainer

signal action_requested(action: String)

func _ready() -> void:
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.ACTION_PADDING))

func set_actions(actions: Array) -> void:
	for child in $Actions.get_children():
		$Actions.remove_child(child)
		child.queue_free()
	for action: Dictionary in actions:
		var button := Button.new()
		button.text = action["label"]
		button.tooltip_text = action.get("tooltip", "")
		button.focus_mode = Control.FOCUS_NONE
		BoardUiStyle.action_button(button, BoardUiStyle.ACTION_HEIGHT, action.get("primary", false), action["id"] == "delete")
		button.disabled = action.get("disabled", false)
		if action.get("primary", false):
			button.theme_type_variation = &"PrimaryButton"
		var action_id: String = action["id"]
		button.pressed.connect(func(): action_requested.emit(action_id))
		$Actions.add_child(button)
	reset_size()
