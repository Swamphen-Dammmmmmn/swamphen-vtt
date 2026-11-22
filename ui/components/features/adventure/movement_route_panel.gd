extends "res://ui/components/utility_panel.gd"

signal action_requested(action: String)

const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

var _target: Label
var _summary: Label
var _instruction: Label
var _point_actions: HBoxContainer
var _move_point: FluentButton
var _delete_point: FluentButton
var _last_state: Dictionary = {}

func _init() -> void:
	fluent = true
	layout_key = "adventure.movement_route"
	host_controls_close = true
	panel_title = "移动路线"
	preferred_width = 320.0

func _ready() -> void:
	super._ready()
	configure_editor()
	_target = _label(&"FluentStrong")
	_summary = _label(&"")
	_instruction = _label(&"FluentSecondary")
	_point_actions = HBoxContainer.new()
	_point_actions.add_theme_constant_override("separation", EditorLayout.GAP)
	content().add_child(_point_actions)
	_move_point = _point_button("move_point", "修改此点", "FluentButton")
	_delete_point = _point_button("delete_point", "删除此点", "FluentDangerOutline")
	panel_action_requested.connect(func(action: String): action_requested.emit(action))
	set_workflow_state({})

func _label(variant: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variant
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(label)
	return label

func _point_button(action: String, title: String, variant: String) -> FluentButton:
	var button := FluentButton.new()
	button.text = title
	button.variant = variant
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.pressed.connect(func(): action_requested.emit(action))
	_point_actions.add_child(button)
	return button

# Data only: route calculation, permissions and edits remain with the board.
func set_workflow_state(state: Dictionary) -> void:
	if not _last_state.is_empty() and _last_state == state:
		return
	_last_state = state.duplicate(true)
	var count := maxi(0, int(state.get("points", 0)) - 1)
	var editing := int(state.get("editing_index", -1))
	var selected := int(state.get("selected_point", -1))
	var writable: bool = state.get("writable", false)
	var editing_point := editing > 0
	var point_selected := selected > 0 and selected <= count
	_target.text = str(state.get("title", "棋子"))
	_summary.text = ("预览距离 · " if editing_point else "已固定距离 · ") + str(state.get("amount", "0 英尺"))
	_instruction.text = "点击棋盘添加路径点。"
	var status := "等待添加路径点" if count == 0 else "已固定 %d 个路径点" % count
	if editing_point:
		_instruction.text = "点击棋盘固定新位置。取消修改会恢复原位置。"
		status = "正在修改路径点 %d" % editing
	elif point_selected:
		_instruction.text = "已选择路径点 %d" % selected
	elif count > 0:
		_instruction.text = "点击棋盘添加路径点，点击已有点可编辑。"
	if not writable:
		status = "当前无法操作此棋子"
		_instruction.text = "可关闭窗口退出路线。"
	_point_actions.visible = point_selected and not editing_point
	_move_point.disabled = not writable
	_delete_point.disabled = not writable
	set_editor_status(status)
	set_panel_actions([
		{"id": "confirm", "title": "确认移动", "visible": not editing_point, "enabled": writable and count > 0, "primary": true, "hint": "移动到最后一个固定点 · Enter"},
		{"id": "cancel", "title": "取消修改" if editing_point else "取消路线", "hint": "恢复当前路径点" if editing_point else "取消整条未确认路线并返回选择"},
		{"id": "undo", "title": "撤销一点", "visible": not editing_point, "enabled": writable and count > 0, "hint": "删除最近固定的路径点 · Ctrl+Z / Backspace"},
	])
