extends Control

signal navigation_requested(destination: String, detail: String)
signal back_requested
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const Header = preload("res://ui/components/layout/fluent_page_header.gd")
const Card = preload("res://ui/components/cards/asset_category_card.gd")
const CATEGORIES := [
	["棋子", "token_library"],
	["预制件／合成体", ""],
	["地台", "platform_library"],
	["地图", "map_library"],
	["冒险", "adventure_library"]
]
var _header: Header
var _scroll: ScrollContainer
var _grid: GridContainer
var _cards: Array[Card] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = FluentTheme.shared()
	var background := ColorRect.new()
	background.color = T.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_header = Header.new()
	_header.title = "定制"
	_header.back_requested.connect(func(): back_requested.emit())
	add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_"+edge, T.CATEGORY_VIEWPORT_INSET)
	_scroll.add_child(inset)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", T.CATEGORY_GAP)
	_grid.add_theme_constant_override("v_separation", T.CATEGORY_GAP)
	inset.add_child(_grid)
	for category in CATEGORIES:
		var card := Card.new()
		card.title = category[0]
		var route: String = category[1]
		card.disabled = route.is_empty()
		card.pressed.connect(func(): navigation_requested.emit(route, ""))
		_grid.add_child(card)
		_cards.append(card)
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	_fit()

func _fit() -> void:
	var safe := Mobile.safe_rect(size)
	var padding := 32 if safe.size.x < 1200 else 64
	var side := maxf(padding, (safe.size.x-T.CATEGORY_CONTENT_WIDTH)*0.5)
	var width := maxf(0, safe.size.x-side*2)
	var compact := safe.size.y < 760
	var top := 24 if compact else 48
	_header.position = safe.position+Vector2(side,top)
	_header.size = Vector2(width,48)
	_scroll.position = safe.position+Vector2(side,top+80)
	_scroll.size = Vector2(width,maxf(0,safe.size.y-top-80-padding))
	# Reserve the mobile scrollbar + gap even before layout settles to avoid column oscillation.
	var available := maxf(0,width-34-T.CATEGORY_VIEWPORT_INSET*2)
	var columns := 3 if available >= (760 if compact else 840) else (2 if available >= 480 else 1)
	_grid.columns = columns
	var card_width := maxf(0,floorf((available-T.CATEGORY_GAP*(columns-1))/columns))
	for card in _cards: card.set_extent(card_width, compact)
