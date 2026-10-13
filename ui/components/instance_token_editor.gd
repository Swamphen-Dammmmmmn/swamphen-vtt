extends Control
const Shell = preload("res://ui/components/page_shell.tscn")
const Basic = preload("res://ui/pages/token_customize.gd")
const Advanced = preload("res://ui/pages/advanced_token_customize.gd")
const Instance = preload("res://scripts/token_instance.gd")
const Style = preload("res://ui/components/page_style.gd")
signal applied(parameters: Dictionary)
signal closed
var data: Dictionary
var editor: Control
var shell: Control
var tray_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Style.BACKGROUND
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell = Shell.instantiate()
	add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor = Advanced.new() if data.get("kind","basic")=="advanced" else Basic.new()
	editor.instance_mode = true
	editor.lock_footprint = not tray_mode
	if tray_mode:
		editor.instance_return_title = "返回托盘"
		editor.instance_apply_title = "应用修改"
	editor.editing_record = Instance.record(data)
	editor.page = shell
	shell.use_fullscreen_content(editor)
	editor.instance_applied.connect(func(parameters: Dictionary): applied.emit(parameters))
	editor.return_requested.connect(_return)
	shell.back_requested.connect(_return)
	Style.Motion.fade_in(self)

func _return() -> void:
	if editor.guard_leave(_return): return
	hide()
	closed.emit()
	queue_free()
