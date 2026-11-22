extends "res://ui/components/utility_panel.gd"

signal action_requested(action: String)

var _token_name: Label
var _footprint: Label
var _instruction: Label

func _init() -> void:
	fluent = true
	layout_key = "adventure.token_placement"
	host_controls_close = true
	panel_title = "摆放棋子"
	preferred_width = 320.0

func _ready() -> void:
	super._ready()
	configure_editor()
	_token_name = Label.new()
	_token_name.theme_type_variation = &"FluentStrong"
	_token_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(_token_name)
	_footprint = _description()
	_instruction = _description()
	panel_action_requested.connect(func(action: String): action_requested.emit(action))
	set_workflow_state({})

func _description() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"FluentSecondary"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(label)
	return label

func set_workflow_state(state: Dictionary) -> void:
	_token_name.text = str(state.get("title", "棋子"))
	_footprint.text = str(state.get("footprint", ""))
	_footprint.visible = not _footprint.text.is_empty()
	var fixed: bool = state.get("fixed", false)
	var valid: bool = state.get("valid", false)
	var from_tray: bool = state.get("from_tray", false)
	if from_tray:
		_instruction.text = "轻点有效网格直接放置。取消摆放会保留托盘中的棋子。"
	else:
		_instruction.text = "落点已固定，请确认放置或取消本次。" if fixed else "在棋盘选择有效网格固定落点，再确认放置。"
	set_editor_status("落点已固定" if fixed and valid else ("请选择有效落点" if not valid else "选择落点"))
	set_panel_actions([
		{"id": "confirm", "title": "确认放置", "visible": not from_tray, "enabled": fixed and valid and state.get("writable", true), "primary": true},
		{"id": "cancel", "title": "取消摆放"},
	])
