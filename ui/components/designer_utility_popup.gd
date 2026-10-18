extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
var title := "显示设置"
var body: VBoxContainer
var scroll: ScrollContainer
var dragged := false
var last_available := Vector2.ZERO
var last_anchor := Vector2.ZERO
var fit_pending := false
var reveal_revision := 0

func _ready() -> void:
	hide()
	z_index = 7
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel",BoardUiStyle.card_face(12))
	scroll = ScrollContainer.new()
	Layout.scroll(scroll)
	add_child(scroll)
	body = Style.column(12)
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(body)
	body.minimum_size_changed.connect(_queue_fit)
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	var header := HBoxContainer.new()
	header.set_meta("mobile_drag","native")
	body.add_child(header)
	var label := Style.text(title,Typography.SECTION)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var close := Button.new()
	GoStyle.apply_icon(close,GoIconSet.CLOSE,18)
	close.tooltip_text = "关闭"
	Style.button(close)
	close.custom_minimum_size.x = 36
	close.pressed.connect(dismiss)
	header.add_child(close)
	header.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)!=0:
			dragged = true
			var safe := Mobile.safe_rect(get_parent().size)
			position = (position+event.relative).clamp(safe.position,(safe.end-size).max(safe.position))
	)

func reveal_at(available: Vector2, anchor: Vector2) -> void:
	reveal_revision += 1
	var revision := reveal_revision
	fit_at(available,anchor)
	await get_tree().process_frame
	if not is_inside_tree() or revision!=reveal_revision: return
	fit_at(get_parent().size,anchor)
	show()
	Style.Motion.fade_in(self)

func fit_at(available: Vector2, anchor: Vector2) -> void:
	last_available = available
	last_anchor = anchor
	var chrome := get_theme_stylebox("panel").get_minimum_size()
	var safe := Mobile.safe_rect(available)
	custom_minimum_size.x = minf(320,maxf(1,safe.size.x-48))
	size.x = custom_minimum_size.x
	scroll.size.x = maxf(1,size.x-chrome.x)
	var height := minf(body.get_combined_minimum_size().y,maxf(1,safe.size.y-48-chrome.y))
	scroll.custom_minimum_size.y = height
	size = Vector2(custom_minimum_size.x,height+chrome.y)
	if not dragged: position = Vector2(anchor.x,maxf(24,anchor.y-size.y-12))
	position = position.clamp(safe.position,(safe.end-size).max(safe.position))

func _queue_fit() -> void:
	if fit_pending: return
	fit_pending = true
	_refit.call_deferred()

func _refit() -> void:
	fit_pending = false
	if last_available!=Vector2.ZERO: fit_at(last_available,last_anchor)

func dismiss() -> void:
	reveal_revision += 1
	hide()
