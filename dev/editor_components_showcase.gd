# Editor Components Showcase - Configurable Initial States
# Demonstrates all property panel boundary conditions
extends Control

@export_category("Initial Configuration")
@export var show_left_panel := true
@export var show_right_panel := true
@export var left_initially_collapsed := false
@export var right_initially_collapsed := false
@export var use_long_title := false
@export var use_many_fields := false
@export var apply_narrow_constraints := false
@export var initial_mode := 0  # 0=Normal, 1=LongContent, 2=ReadonlyDisabled, 3=ErrorBusy, 4=NarrowScreen
@export var demo_foldable_groups := false  # Demonstrate foldable property groups

const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const EditorPanel = preload("res://ui/components/features/editor/editor_property_panel.gd")
const EditorTextField = preload("res://ui/components/forms/editor_text_field.gd")
const EditorNumberField = preload("res://ui/components/forms/editor_number_field.gd")
const EditorOptionField = preload("res://ui/components/forms/editor_option_field.gd")
const EditorCheckBoxField = preload("res://ui/components/forms/editor_checkbox_field.gd")
const EditorSliderField = preload("res://ui/components/forms/editor_slider_field.gd")
const EditorTabs = preload("res://ui/components/navigation/editor_property_tabs.gd")
const EditorFoldableGroup = preload("res://ui/components/layout/editor_foldable_group.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const PageModal = preload("res://ui/components/page_modal.gd")

enum DemoMode { NORMAL, LONG_CONTENT, READONLY_DISABLED, ERROR_BUSY, NARROW_SCREEN }

var _left_panel: EditorPanel
var _right_panel: EditorPanel
var _name_field: EditorTextField
var _health_field: EditorNumberField
var _category_field: EditorOptionField
var _speed_field: EditorNumberField
var _enable_ai_field: EditorCheckBoxField
var _aggression_field: EditorSliderField
var _tabs: EditorTabs
var _position_x: EditorNumberField
var _position_y: EditorNumberField
var _rotation: EditorNumberField
var _left_save_btn: Button
var _left_reset_btn: Button
var _right_apply_btn: Button
var _mode_buttons: Array[Button] = []
var _detail_modal: PageModal

func _ready() -> void:
	theme = FluentTheme.shared()

	# Apply narrow constraints FIRST - set both custom_minimum_size and custom_maximum_size
	if apply_narrow_constraints:
		custom_minimum_size.x = 700
		custom_maximum_size.x = 700

	var root_container := VBoxContainer.new()
	root_container.anchor_right = 1.0
	root_container.anchor_bottom = 1.0
	root_container.add_theme_constant_override("separation", 0)
	add_child(root_container)

	# Mode selection toolbar - use FlowContainer for wrapping
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 8)
	var toolbar_margin := MarginContainer.new()
	toolbar_margin.add_theme_constant_override("margin_left", 16)
	toolbar_margin.add_theme_constant_override("margin_top", 16)
	toolbar_margin.add_theme_constant_override("margin_right", 16)
	toolbar_margin.add_theme_constant_override("margin_bottom", 8)
	toolbar_margin.add_child(toolbar)
	root_container.add_child(toolbar_margin)

	var modes := ["正常", "长内容", "只读/禁用", "错误/忙碌", "窄屏"]
	for i in modes.size():
		var btn := FluentButton.new()
		btn.text = modes[i]
		btn.toggle_mode = true
		btn.custom_minimum_size.x = 100
		toolbar.add_child(btn)
		_mode_buttons.append(btn)

	# Main panel container
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main_margin := MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 16)
	main_margin.add_theme_constant_override("margin_right", 16)
	main_margin.add_theme_constant_override("margin_bottom", 16)
	main_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_child(main)
	root_container.add_child(main_margin)

	# Left panel (conditional)
	if show_left_panel:
		_create_left_panel(main)

	# Right panel (conditional)
	if show_right_panel:
		_create_right_panel(main)

	# Connect mode buttons
	for i in _mode_buttons.size():
		var btn := _mode_buttons[i]
		btn.toggled.connect(func(pressed: bool):
			if pressed:
				for other_btn in _mode_buttons:
					if other_btn != btn:
						other_btn.button_pressed = false
				_apply_mode(i))

	# Set initial mode
	_mode_buttons[initial_mode].button_pressed = true
	_apply_mode(initial_mode)

func _create_left_panel(parent: Control) -> void:
	var title := "超长标题用于测试标题文本在窄面板中的表现与省略效果" if use_long_title else "棋子属性"
	_left_panel = EditorPanel.new()
	_left_panel.setup(EditorPanel.PanelSide.LEFT, title, true)
	_left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Panel manages its own width - use is_collapsed() to adapt layout if needed
	_left_panel.status_detail_requested.connect(_on_status_detail_requested)
	parent.add_child(_left_panel)

	var left_content := _left_panel.content()

	# Demonstrate foldable groups if requested
	if demo_foldable_groups:
		# Basic info group (initially expanded)
		var basic_group := EditorFoldableGroup.new()
		basic_group.set_group_title("基础信息")
		basic_group.folded = false
		left_content.add_child(basic_group)

		var basic_content := basic_group.content()

		_name_field = EditorTextField.new()
		_name_field.setup("名称", "输入棋子名称", "炎爆龙")
		basic_content.add_child(_name_field)

		_health_field = EditorNumberField.new()
		_health_field.setup("生命值", "点", 1.0, 999.0, false, 100.0)
		basic_content.add_child(_health_field)

		_category_field = EditorOptionField.new()
		_category_field.setup("类别", ["英雄", "小兵", "建筑", "召唤物"], 0)
		basic_content.add_child(_category_field)

		# Combat attributes group (initially folded)
		var combat_group := EditorFoldableGroup.new()
		combat_group.set_group_title("战斗属性")
		combat_group.folded = true
		left_content.add_child(combat_group)

		var combat_content := combat_group.content()

		_speed_field = EditorNumberField.new()
		_speed_field.setup("移动速度", "格/回合", 0.5, 10.0, true, 3.5)
		combat_content.add_child(_speed_field)

		_enable_ai_field = EditorCheckBoxField.new()
		_enable_ai_field.setup("启用AI", true)
		combat_content.add_child(_enable_ai_field)

		_aggression_field = EditorSliderField.new()
		_aggression_field.setup("攻击倾向", 0.0, 100.0, 50.0, "%", "%.0f")
		combat_content.add_child(_aggression_field)
	else:
		# Original flat layout
		_name_field = EditorTextField.new()
		_name_field.setup("名称", "输入棋子名称", "炎爆龙")
		left_content.add_child(_name_field)

		_health_field = EditorNumberField.new()
		_health_field.setup("生命值", "点", 1.0, 999.0, false, 100.0)
		left_content.add_child(_health_field)

		_category_field = EditorOptionField.new()
		_category_field.setup("类别", ["英雄", "小兵", "建筑", "召唤物"], 0)
		left_content.add_child(_category_field)

		_speed_field = EditorNumberField.new()
		_speed_field.setup("移动速度", "格/回合", 0.5, 10.0, true, 3.5)
		left_content.add_child(_speed_field)

		_enable_ai_field = EditorCheckBoxField.new()
		_enable_ai_field.setup("启用AI", true)
		left_content.add_child(_enable_ai_field)

		_aggression_field = EditorSliderField.new()
		_aggression_field.setup("攻击倾向", 0.0, 100.0, 50.0, "%", "%.0f")
		left_content.add_child(_aggression_field)

	# Add many extra fields if requested
	if use_many_fields:
		for i in range(10):
			var extra := EditorNumberField.new()
			extra.setup("额外属性 %d" % (i + 1), "", 0.0, 100.0, true, 50.0)
			left_content.add_child(extra)

	_left_save_btn = FluentButton.new()
	_left_save_btn.variant = "FluentPrimary"
	_left_save_btn.text = "保存"
	_left_save_btn.pressed.connect(_on_left_save)
	_left_panel.add_action(_left_save_btn)

	_left_reset_btn = FluentButton.new()
	_left_reset_btn.text = "重置"
	_left_reset_btn.pressed.connect(_on_left_reset)
	_left_panel.add_action(_left_reset_btn)

	# Apply initial collapse state AFTER panel is fully constructed
	if left_initially_collapsed:
		_left_panel.call_deferred("toggle_collapse")

func _create_right_panel(parent: Control) -> void:
	var title := "超长标题用于测试标题文本在窄面板中的表现与省略效果" if use_long_title else "位置与旋转"
	_right_panel = EditorPanel.new()
	_right_panel.setup(EditorPanel.PanelSide.RIGHT, title, true)
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.status_detail_requested.connect(_on_status_detail_requested)
	parent.add_child(_right_panel)

	var right_content := _right_panel.content()

	_tabs = EditorTabs.new()
	_tabs.setup(["transform", "appearance"], ["变换", "外观"])
	_tabs.tab_changed.connect(_on_tab_changed)
	right_content.add_child(_tabs)

	_position_x = EditorNumberField.new()
	_position_x.setup("X坐标", "", -100.0, 100.0, true, 0.0)
	right_content.add_child(_position_x)

	_position_y = EditorNumberField.new()
	_position_y.setup("Y坐标", "", -100.0, 100.0, true, 0.0)
	right_content.add_child(_position_y)

	_rotation = EditorNumberField.new()
	_rotation.setup("旋转角度", "度", 0.0, 360.0, true, 0.0)
	right_content.add_child(_rotation)

	# Add many extra fields if requested
	if use_many_fields:
		for i in range(10):
			var extra := EditorNumberField.new()
			extra.setup("额外变换 %d" % (i + 1), "", -100.0, 100.0, true, 0.0)
			right_content.add_child(extra)

	_right_apply_btn = FluentButton.new()
	_right_apply_btn.variant = "FluentPrimary"
	_right_apply_btn.text = "应用"
	_right_apply_btn.pressed.connect(_on_right_apply)
	_right_panel.add_action(_right_apply_btn)

	# Apply initial collapse state AFTER panel is fully constructed
	if right_initially_collapsed:
		_right_panel.call_deferred("toggle_collapse")

func _apply_mode(mode_index: int) -> void:
	var mode := mode_index as DemoMode

	# Reset all states first
	if _left_panel:
		if _name_field:
			_name_field.set_readonly(false)
			_name_field.set_disabled(false)
			_name_field.set_error("")
		if _health_field:
			_health_field.set_readonly(false)
			_health_field.set_disabled(false)
			_health_field.set_error("")
		if _category_field:
			_category_field.set_readonly(false)
			_category_field.set_disabled(false)
		if _speed_field:
			_speed_field.set_readonly(false)
			_speed_field.set_disabled(false)
			_speed_field.set_error("")
		if _enable_ai_field:
			_enable_ai_field.set_readonly(false)
			_enable_ai_field.set_disabled(false)
		if _aggression_field:
			_aggression_field.set_readonly(false)
			_aggression_field.set_disabled(false)
		_left_panel.set_status("", false)
		_left_panel.set_busy(false)
		_left_panel.set_actions_disabled(false)

	if _right_panel:
		if _position_x:
			_position_x.set_readonly(false)
			_position_x.set_disabled(false)
		if _position_y:
			_position_y.set_readonly(false)
			_position_y.set_disabled(false)
		if _rotation:
			_rotation.set_readonly(false)
			_rotation.set_disabled(false)
		_right_panel.set_status("", false)
		_right_panel.set_busy(false)

	# Apply mode-specific states
	match mode:
		DemoMode.NORMAL:
			pass

		DemoMode.LONG_CONTENT:
			if _left_panel:
				_left_panel.set_status("这是一个非常非常长的状态消息示例，用于测试多行换行和详情按钮的显示效果。实际使用时应该能够完整显示错误原因而不被截断，确保用户能够理解问题所在并采取相应的修正措施。", false)
			if _right_panel:
				_right_panel.set_status("未保存的更改：X坐标、Y坐标和旋转角度已修改但尚未应用到游戏中。", false)
			if _name_field:
				_name_field.set_value("这是一个非常非常长的棋子名称示例，用于测试文本字段在处理长内容时的表现")

		DemoMode.READONLY_DISABLED:
			if _name_field:
				_name_field.set_readonly(true)
			if _health_field:
				_health_field.set_disabled(true)
			if _category_field:
				_category_field.set_readonly(true)
			if _speed_field:
				_speed_field.set_disabled(true)
			if _position_x:
				_position_x.set_readonly(true)
			if _enable_ai_field:
				_enable_ai_field.set_readonly(true)
			if _aggression_field:
				_aggression_field.set_disabled(true)
			if _left_panel:
				_left_panel.set_status("只读模式", false)
				_left_panel.set_actions_disabled(true)

		DemoMode.ERROR_BUSY:
			if _health_field:
				_health_field.set_error("生命值必须为正整数")
			if _speed_field:
				_speed_field.set_error("移动速度不能超过最大值")
			if _left_panel:
				_left_panel.set_status("保存失败：数据验证错误，请修正后重试", true)
			if _right_panel:
				_right_panel.set_busy(true)
				_right_panel.set_status("正在应用更改...", false)

		DemoMode.NARROW_SCREEN:
			# In narrow screen mode, use narrower widths through public API
			if _left_panel and (not left_initially_collapsed or not _left_panel.is_collapsed()):
				_left_panel.set_minimum_width(280)
				_left_panel.set_status("窄屏模式测试", false)
			if _right_panel and (not right_initially_collapsed or not _right_panel.is_collapsed()):
				_right_panel.set_minimum_width(280)

func _on_left_save() -> void:
	print("Left panel save")
	if _left_panel:
		_left_panel.set_status("已保存", false)

func _on_left_reset() -> void:
	print("Left panel reset")
	if _name_field:
		_name_field.set_value("炎爆龙")
	if _health_field:
		_health_field.set_value(100.0)
	if _category_field:
		_category_field.set_selected_index(0)
	if _speed_field:
		_speed_field.set_value(3.5)
	if _enable_ai_field:
		_enable_ai_field.set_value(true)
	if _aggression_field:
		_aggression_field.set_value(50.0)
	if _left_panel:
		_left_panel.set_status("", false)

func _on_right_apply() -> void:
	print("Right panel apply")
	if _right_panel:
		_right_panel.set_status("已应用", false)

func _on_tab_changed(index: int, tab_id: String) -> void:
	print("Tab changed to: %s (%d)" % [tab_id, index])

func _on_status_detail_requested(status_text: String) -> void:
	if _detail_modal and is_instance_valid(_detail_modal):
		_detail_modal.queue_free()
	_detail_modal = PageModal.new()
	add_child(_detail_modal)
	_detail_modal.configure("状态详情", status_text)
	_detail_modal.add_action("确定", func():
		if _detail_modal and is_instance_valid(_detail_modal):
			_detail_modal.dismiss()
		_detail_modal = null
	, true)
	_detail_modal.dismissed.connect(func():
		_detail_modal = null)
