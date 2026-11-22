extends "res://ui/components/features/editor/editor_property_panel.gd"

# Temporary sandbox caller; layout rules and persistence never live here.
signal create_requested(preset: String)
signal update_requested(id: String, wall_id: String, spec: Dictionary, anchor: Vector2)
signal delete_requested(id: String)
signal undo_requested
signal redo_requested
signal cancel_requested
signal frame_requested

const P = preload("res://scripts/scenery/opening_parameters.gd")
const W = preload("res://scripts/scenery/wall_parameters.gd")
const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const Number = preload("res://ui/components/forms/editor_number_field.gd")
const Option = preload("res://ui/components/forms/editor_option_field.gd")
const Check = preload("res://ui/components/forms/editor_checkbox_field.gd")
const Group = preload("res://ui/components/layout/editor_foldable_group.gd")
const ButtonType = preload("res://ui/components/controls/fluent_button.gd")
var _numbers := {}
var _options := {}
var _checks := {}
var _walls: Array = []
var _record: Dictionary = {}
var _draft: Dictionary = {}
var _host: Option
var _snap: Option
var _apply: Button
var _delete: Button
var _undo: Button
var _redo: Button
var _cancel: Button
var _create: Array[Button] = []
var _busy_state := false
var _active := false

func _init() -> void:
	super._init()
	setup(PanelSide.LEFT,"门窗 · 墙面布局沙盒",false)

func _ready() -> void:
	super._ready()
	for entry in [["放置木门","wood_door"],["放置木窗","wood_window"]]:
		var button := _button(entry[0],func(): create_requested.emit(entry[1]))
		fixed_header().add_child(button)
		_create.append(button)
	_snap=Option.new()
	_snap.setup("拖动吸附",["自由移动","0.25尺","0.5尺","1尺"],1)
	fixed_header().add_child(_snap)
	var group := Group.new()
	group.set_group_title("选中门窗 · 位置与尺寸")
	content().add_child(group)
	_host=Option.new()
	_host.setup("所属墙体",["未选择"],0)
	group.content().add_child(_host)
	for entry in [["x","水平位置（从墙左端起）",-50.0,100.0],["y","洞底离地",0.0,20.0],
		["width","洞口宽",1.0,30.0],["height","洞口高",1.0,25.0],["angle","开合角度",0.0,110.0]]:
		var key: String = entry[0]
		var field := Number.new()
		field.setup(entry[1],"度" if key=="angle" else "英尺",entry[2],entry[3],true,0.0 if key in ["x","y","angle"] else 3.0)
		group.content().add_child(field)
		_numbers[key]=field
	var orientation := Group.new()
	orientation.set_group_title("安装方向与部件")
	orientation.folded=true
	content().add_child(orientation)
	for entry in [["mounting","安装位置",["前侧","墙中","后侧"],["front","center","back"]],
		["hinge","铰链位置",["左侧","右侧"],["left","right"]],["swing","开启方向",["向前","向后"],["front","back"]]]:
		var key: String = entry[0]
		var field := Option.new()
		field.setup(entry[1],entry[2],0)
		orientation.content().add_child(field)
		_options[key]={"field":field,"values":entry[3]}
	for entry in [["frame","内框"],["trim","收边"],["leaf","门窗扇"],["glass","玻璃"],["mullions","分格条"],
		["sill_board","窗台板"],["hardware","五金"],["threshold","门槛"]]:
		var field := Check.new()
		field.setup(entry[1],false)
		orientation.content().add_child(field)
		_checks[entry[0]]=field
	_apply=_button("应用精确修改",_submit)
	_delete=_button("删除选中门窗",func():
		if not _record.is_empty(): delete_requested.emit(_record.id))
	content().add_child(_apply)
	content().add_child(_delete)
	_cancel=_button("取消当前放置 / 拖动",func(): cancel_requested.emit())
	content().add_child(_cancel)
	content().add_child(_button("查看全景",func(): frame_requested.emit()))
	var help := Label.new()
	help.text="点击门窗选择，左键拖动沿墙移动。\n放置时先在墙上预览，点击确认。\n红色预览不可放置；右键或Esc取消。\n右键转向，WASD移动，Q/E升降。"
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.theme_type_variation="FluentSecondary"
	help.add_theme_font_size_override("font_size",Typography.CAPTION)
	content().add_child(help)
	_undo=_button("撤销",func(): undo_requested.emit())
	_redo=_button("重做",func(): redo_requested.emit())
	add_action(_undo)
	add_action(_redo)
	_refresh_enabled()

func _button(text: String, action: Callable) -> Button:
	var button := ButtonType.new()
	button.text=text
	button.pressed.connect(action)
	return button

func snap_step() -> float:
	return [0.0,0.25,0.5,1.0][_snap.get_selected_index()]

func show_record(layout: Dictionary, record: Dictionary) -> void:
	_walls=layout.walls.duplicate(true)
	_record=record.duplicate(true)
	_draft=record.get("spec",P.defaults("wood_window")).duplicate(true)
	var titles: Array = []
	var selected := 0
	for i in _walls.size():
		titles.append(_walls[i].id+" · "+W.SURFACE_TITLES[W.SURFACES.find(_walls[i].parameters.surface)])
		if _walls[i].id==record.get("wall_id",""): selected=i
	_host.setup("所属墙体",titles if not titles.is_empty() else ["无墙体"],selected)
	for key in _numbers:
		var value: float = record.get("anchor",Vector2.ZERO).x if key=="x" else (record.get("anchor",Vector2.ZERO).y if key=="y" else float(_draft[key]))
		_numbers[key].set_value(value,true)
	for key in _options: _options[key].field.set_selected_index(_options[key].values.find(_draft[key]))
	for key in _checks: _checks[key].set_value(_draft[key])
	_refresh_enabled()

func set_workspace_state(busy: bool, active: bool, undo_available: bool, redo_available: bool) -> void:
	_busy_state=busy
	_active=active
	set_busy(busy)
	set_action_enabled(_undo,undo_available)
	set_action_enabled(_redo,redo_available)
	_refresh_enabled()

func _refresh_enabled() -> void:
	var disabled := _busy_state or _active or _record.is_empty()
	for field in _numbers.values(): field.set_disabled(disabled)
	for entry in _options.values(): entry.field.set_disabled(disabled)
	for field in _checks.values(): field.set_disabled(disabled)
	if _host!=null: _host.set_disabled(disabled)
	if _snap!=null: _snap.set_disabled(_busy_state or _active)
	for button in _create: button.disabled=_busy_state
	if _apply!=null: _apply.disabled=disabled
	if _delete!=null: _delete.disabled=disabled
	if _cancel!=null: _cancel.disabled=_busy_state or not _active

func _submit() -> void:
	if _record.is_empty() or _walls.is_empty(): return
	for field in _numbers.values():
		var parsed: Dictionary = field.validate_draft()
		if not parsed.ok:
			set_status(parsed.message,true)
			return
	# Read validated drafts rather than stale committed values after a focus change.
	var numbers := {}
	for key in _numbers: numbers[key]=_numbers[key].validate_draft().value
	var spec := _draft.duplicate(true)
	for key in ["width","height","angle"]: spec[key]=numbers[key]
	for key in _options: spec[key]=_options[key].values[_options[key].field.get_selected_index()]
	for key in _checks: spec[key]=_checks[key].get_value()
	update_requested.emit(_record.id,_walls[_host.get_selected_index()].id,spec,Vector2(numbers.x,numbers.y))

func is_popup_open() -> bool:
	if _host.is_popup_open() or _snap.is_popup_open(): return true
	for entry in _options.values():
		if entry.field.is_popup_open(): return true
	return false

func close_popups() -> void:
	_host.close_popup()
	_snap.close_popup()
	for entry in _options.values(): entry.field.close_popup()
