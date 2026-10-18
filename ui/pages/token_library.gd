extends VBoxContainer
signal create_requested
signal edit_requested(id: String)
signal delete_requested(data: Dictionary)
signal copy_requested(id: String)
signal rename_requested(id: String)
signal tags_requested(id: String)
signal upgrade_requested(id: String)
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
const View = preload("res://ui/components/features/library/library_view.gd")
var entries: Array[Dictionary] = []
var mode := Presentation.Mode.MANAGE
var page: Control
var _view: View
var _pending_error := ""
var _pending_warnings: Array = []
var catalog_refresh_queued := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view = View.new()
	_view.library_kind = "tokens"
	_view.noun = "棋子"
	_view.mode = mode
	_view.primary_text = "添加到托盘" if mode == Presentation.Mode.SELECT else "编辑"
	_view.controls_host = page
	add_child(_view)
	_view.create_requested.connect(func(): create_requested.emit())
	_view.primary_requested.connect(func(id: String): edit_requested.emit(id))
	_view.action_requested.connect(_action)
	ProductCatalog.changed.connect(_catalog_changed)
	_view.set_entries(entries,_pending_error,_pending_warnings)

func set_entries(data: Array[Dictionary], read_error := "", warnings: Array = []) -> void:
	entries = data.duplicate(true)
	_pending_error = read_error
	_pending_warnings = warnings.duplicate()
	if is_instance_valid(_view): _view.set_entries(entries,read_error,warnings)

func _action(action: String, record: Dictionary) -> void:
	var id: String = record["id"]
	match action:
		"rename": rename_requested.emit(id)
		"copy": copy_requested.emit(id)
		"delete": delete_requested.emit(record)
		"tags": tags_requested.emit(id)
		"upgrade": upgrade_requested.emit(id)

func _catalog_changed(kind: String) -> void:
	if kind!="tokens" or catalog_refresh_queued or not is_visible_in_tree(): return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)

func _reload_catalog() -> void:
	catalog_refresh_queued = false
	var loaded: Dictionary = load("res://scripts/token_library_store.gd").read_catalog()
	var records: Array[Dictionary] = []
	for record in loaded["entries"]: records.append(record)
	set_entries(records,loaded["error"],loaded["warnings"])
