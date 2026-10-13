extends PanelContainer
const Style = preload("res://ui/components/page_style.gd")
const Thumbnail = preload("res://ui/components/token_thumbnail.gd")
signal cleared
var thumbnail: Control
var title_label: Label
var type_label: Label
var state_label: Label
var state_badge: PanelContainer
var clear_button: Button
var body: PanelContainer
var empty: Label
var cached := {}

func _ready() -> void:
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var column := Style.column(8)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := Style.text("当前选择",14,true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading)
	clear_button = Button.new()
	GoStyle.apply_icon(clear_button,GoIconSet.CLOSE,16)
	clear_button.tooltip_text = "取消选择"
	clear_button.focus_mode = Control.FOCUS_NONE
	Style.card_button(clear_button,28)
	clear_button.custom_minimum_size.x = 28
	clear_button.pressed.connect(func(): cleared.emit())
	header.add_child(clear_button)
	body = PanelContainer.new()
	var face := BoardUiStyle.card_face(1)
	face.bg_color = Color.WHITE
	face.border_color = Color("d4deeb")
	face.set_border_width_all(1)
	face.set_corner_radius_all(8)
	body.add_theme_stylebox_override("panel",face)
	body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	column.add_child(body)
	var content := Style.column(0)
	body.add_child(content)
	thumbnail = Thumbnail.new()
	thumbnail.custom_minimum_size = Vector2(0,130)
	thumbnail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(thumbnail)
	var text_margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]:
		text_margin.add_theme_constant_override("margin_"+edge,10)
	content.add_child(text_margin)
	var details := Style.column(6)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.add_child(details)
	title_label = Style.text("棋子",18)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.custom_minimum_size.y = 24
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(title_label)
	var metadata := HBoxContainer.new()
	metadata.add_theme_constant_override("separation",8)
	details.add_child(metadata)
	type_label = Style.text("",14,true)
	type_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	metadata.add_child(type_label)
	state_badge = PanelContainer.new()
	state_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var badge_face := BoardUiStyle.card_face(0)
	badge_face.bg_color = Color("dfeaf6")
	badge_face.set_border_width_all(0)
	badge_face.set_corner_radius_all(4)
	badge_face.content_margin_left = 6
	badge_face.content_margin_right = 6
	badge_face.content_margin_top = 2
	badge_face.content_margin_bottom = 2
	state_badge.add_theme_stylebox_override("panel",badge_face)
	metadata.add_child(state_badge)
	state_label = Style.text("",12)
	state_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	state_badge.add_child(state_label)
	empty = Style.text("未选择",14,true)
	column.add_child(empty)
	configure({})

func configure(data: Dictionary, state := "") -> void:
	var populated := not data.is_empty()
	body.visible = populated
	empty.visible = not populated
	clear_button.visible = populated
	if not populated:
		cached.clear()
		return
	var title := str(data.get("title","棋子")).strip_edges()
	title_label.text = "棋子" if title.is_empty() else title
	title_label.tooltip_text = title_label.text
	type_label.text = "高级棋子" if data.get("kind","basic")=="advanced" else "基础棋子"
	state_label.text = state
	state_badge.visible = not state.is_empty()
	var appearance := data.duplicate(true)
	for key in ["id","cell","hp","max_hp","ac","title","tags"]: appearance.erase(key)
	if appearance!=cached:
		cached = appearance
		thumbnail.configure(data)
