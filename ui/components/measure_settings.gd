extends "res://ui/components/utility_panel.gd"

signal action_requested(action: String)

var status: Label
var instruction: Label

func _init() -> void:
	fluent = true
	layout_key = "adventure.measure"
	host_controls_close = true
	panel_title = "测距工具"
	preferred_width = 320.0

func _ready() -> void:
	super._ready()
	configure_editor()
	instruction = Label.new()
	instruction.text = "轻点棋盘选择起点与路径点；轻点棋子可绑定端点。"
	instruction.theme_type_variation = &"FluentSecondary"
	instruction.add_theme_font_size_override("font_size", Typography.CAPTION)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(instruction)
	panel_action_requested.connect(func(action: String): action_requested.emit(action))
	status = editor_status
	set_state(false, false, false)

func set_state(drawing: bool, has_start: bool, editing: bool) -> void:
	set_workflow_state({"drawing": drawing, "points": 1 if has_start else 0, "editing": editing})

func set_workflow_state(state: Dictionary) -> void:
	var drawing: bool = state.get("drawing", false)
	var editing: bool = state.get("editing", false)
	var count := int(state.get("points", 0))
	var writable: bool = state.get("writable", true)
	set_editor_status("修改节点中" if editing else ("等待起点" if drawing and count == 0 else ("绘制中 · %d 个节点" % count if drawing else "就绪")))
	instruction.text = str(state.get("summary", "轻点棋盘选择起点和路径点；轻点棋子可绑定端点。空白处左键拖动旋转镜头。"))
	var target := str(state.get("target", ""))
	if not target.is_empty(): instruction.text = target + "\n" + instruction.text
	set_panel_actions([
		{"id": "new", "title": "新建测距", "visible": not drawing and not editing, "enabled": writable and state.get("can_new", true), "primary": true},
		{"id": "confirm_node" if editing else "finish", "title": "确认节点" if editing else "完成测距", "visible": drawing or editing, "enabled": writable and (state.get("fixed", false) if editing else count > 1), "primary": true},
		{"id": "cancel_node" if editing else "cancel_creation", "title": "取消本次", "visible": drawing or editing},
		{"id": "undo_point", "title": "撤销上个点", "visible": drawing and count > 0, "enabled": writable and state.get("can_undo", false)},
		{"id": "undo_measure", "title": "撤销删除", "visible": state.get("can_restore", false), "enabled": writable},
	])
