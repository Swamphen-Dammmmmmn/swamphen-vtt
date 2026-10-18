extends VBoxContainer
signal management_requested
signal create_requested
signal primary_requested(id: String)
signal action_requested(action: String, record: Dictionary)
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const Toolbar = preload("res://ui/components/features/library/library_toolbar.gd")
const Filters = preload("res://ui/components/features/library/token_library_filters.gd")
const Status = preload("res://ui/components/features/library/library_status.gd")
const ReferenceCard = preload("res://ui/components/cards/library_reference_card.gd")
var library_kind := ""
var noun := ""
var primary_text := "编辑"
var mode := Presentation.Mode.MANAGE
var management_text := ""
var controls_host: Control
var _records: Array = []
var _error := ""
var _query := ""
var _kind := "all"
var _tag := ""
var _toolbar: Toolbar
var _filters: Filters
var _filters_row: HBoxContainer
var _grid: GridContainer
var _warning: Status
var _empty: Status
var _clear: Button

func _ready() -> void:
	theme = FluentTheme.shared()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", LibTokens.CONTROLS_GAP)
	var controls := VBoxContainer.new()
	controls.theme = theme
	controls.add_theme_constant_override("separation", LibTokens.CONTROLS_GAP)
	add_child(controls)
	_toolbar = Toolbar.new()
	_toolbar.noun = noun
	_toolbar.mode = mode
	_toolbar.management_text = management_text
	_toolbar.management_requested.connect(func(): management_requested.emit())
	controls.add_child(_toolbar)
	_toolbar.create_requested.connect(func(): create_requested.emit())
	_toolbar.query_changed.connect(func(value: String): _query = value; _refresh())
	_filters_row = HBoxContainer.new()
	_filters_row.add_theme_constant_override("separation", LibTokens.CONTROLS_GAP)
	controls.add_child(_filters_row)
	if library_kind=="tokens":
		_filters = Filters.new()
		_filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_filters_row.add_child(_filters)
		_filters.filters_changed.connect(func(kind: String, tag: String): _kind = kind; _tag = tag; _refresh())
	_clear = preload("res://ui/components/controls/fluent_button.gd").new()
	_clear.text = "清除筛选"
	_clear.variant = "FluentCompact"
	_clear.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_clear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_clear.minimum_height = LibTokens.FILTER_HEIGHT_MOBILE if Mobile.enabled else LibTokens.FILTER_HEIGHT_DESKTOP
	_filters_row.add_child(_clear)
	_clear.hide()
	_clear.pressed.connect(_reset)
	if is_instance_valid(controls_host): controls_host.mount_library_controls(controls)
	_warning = Status.new()
	add_child(_warning)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]: inset.add_theme_constant_override("margin_"+edge, LibTokens.CONTENT_INSET)
	add_child(inset)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_grid.add_theme_constant_override("h_separation", LibTokens.GRID_GAP)
	_grid.add_theme_constant_override("v_separation", LibTokens.GRID_GAP)
	inset.add_child(_grid)
	_empty = Status.new()
	add_child(_empty)
	resized.connect(_fit)

func set_entries(records: Array, error := "", warnings: Array = []) -> void:
	_records = records
	_error = error
	var warning := error
	if not warnings.is_empty(): warning += ("\n" if not warning.is_empty() else "")+"有%d个%s未能读取，其他内容仍可使用。" % [warnings.size(),noun]
	_warning.update_state(warning,"\n".join(PackedStringArray(warnings)) if error.is_empty() else error+"\n"+"\n".join(PackedStringArray(warnings)),not warning.is_empty())
	if _filters!=null:
		var tags: Array = []
		for record in records: tags.append_array(record.get("tags",[]))
		_filters.set_tags(tags)
		_tag = _filters.selected_tag
	_refresh()

func _refresh() -> void:
	if _grid==null: return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var query := _query.strip_edges().to_lower()
	var filtered := not query.is_empty() or _kind!="all" or not _tag.is_empty()
	_clear.visible = filtered
	_filters_row.visible = _filters != null or filtered
	if _error.is_empty() or not _records.is_empty():
		for record: Dictionary in _records:
			if not query.is_empty() and not str(record["title"]).to_lower().contains(query): continue
			if library_kind=="tokens" and (_kind!="all" and record["kind"]!=_kind or not _tag.is_empty() and not record.get("tags",[]).has(_tag)): continue
			var card := ReferenceCard.new()
			card.record = record
			card.library_kind = library_kind
			card.primary_text = primary_text
			card.selection_only = mode == Presentation.Mode.SELECT
			if controls_host != null:
				card.page_shell = controls_host
			_grid.add_child(card)
			card.primary_requested.connect(func(id: String): primary_requested.emit(id))
			card.action_requested.connect(func(action: String, data: Dictionary): action_requested.emit(action,data))
	var none := _grid.get_child_count()==0
	_empty.update_state("" if not _error.is_empty() or not none else ("没有匹配结果" if filtered else "暂无"+noun))
	_fit.call_deferred()

func _reset() -> void:
	_query = ""
	_kind = "all"
	_tag = ""
	_toolbar.clear_query()
	if _filters!=null: _filters.reset()
	_refresh()

func _fit() -> void:
	if _grid==null: return
	var available := maxf(1,size.x-LibTokens.CONTENT_INSET*2)
	var target_width: float = ReferenceCard.preferred_width()
	_grid.columns = maxi(1,floori((available+LibTokens.GRID_GAP)/(target_width+LibTokens.GRID_GAP)))
	var card_width := maxf(0,floorf((available-LibTokens.GRID_GAP*(_grid.columns-1))/_grid.columns))
	card_width = minf(card_width,target_width)
	for card in _grid.get_children(): card.custom_minimum_size.x = card_width
