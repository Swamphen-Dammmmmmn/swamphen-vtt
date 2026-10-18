extends VBoxContainer
const ButtonComponent = preload("res://ui/components/controls/fluent_button.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
var _message: Label
var _details_button: Button
var _details := ""

func _ready() -> void:
	add_theme_constant_override("separation", LibTokens.STATUS_GAP)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)
	_details_button = ButtonComponent.new()
	_details_button.text = "查看原因"
	_details_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(_details_button)
	_details_button.pressed.connect(_show_details)
	hide()

func update_state(message: String, details := "", failed := false) -> void:
	_details = details
	_message.text = message
	_message.add_theme_color_override("font_color", LibTokens.ERROR_TEXT if failed else LibTokens.SECONDARY_TEXT)
	_message.visible = not message.is_empty()
	_details_button.visible = not details.is_empty()
	visible = not message.is_empty()

func _show_details() -> void:
	var owner: Node = self
	while owner!=null and not owner.has_method("add_overlay"): owner = owner.get_parent()
	if owner==null: return
	var modal := Modal.new()
	owner.add_overlay(modal)
	modal.configure("读取详情", _details)
	modal.add_action("关闭", modal.dismiss)
