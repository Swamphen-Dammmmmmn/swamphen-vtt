extends "res://ui/components/utility_panel.gd"

const Typography = preload("res://ui/theme/typography.gd")

signal action_requested(action: String)
var establish: Button
var status: Label
var instruction: Label

func _ready() -> void:
	super._ready()
	configure_editor()
	establish = GoStyle.button("创建", func(): action_requested.emit("new"), GoStyle.Tone.PRIMARY)
	editor_footer.add_child(establish)
	status = editor_status
	instruction = EditorStyle.text("", Typography.CAPTION, true)
	content().add_child(instruction)
	instruction.hide()
	set_state(false, false, false)

func set_state(drawing: bool, has_start: bool, editing: bool) -> void:
	establish.disabled = drawing or editing
	set_editor_status("创建中" if drawing else ("修改节点中" if editing else "就绪"))
