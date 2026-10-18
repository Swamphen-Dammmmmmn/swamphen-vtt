extends VBoxContainer
const Store = preload("res://scripts/map_library_store.gd")
const Rename = preload("res://ui/components/product_rename.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
const View = preload("res://ui/components/features/library/library_view.gd")
signal create_requested
signal edit_requested(id: String)
var page: Control
var entries: Array = []
var mode := Presentation.Mode.MANAGE
var _view: View

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view = View.new()
	_view.library_kind = "maps"
	_view.noun = "地图"
	_view.mode = mode
	_view.primary_text = "添加" if mode == Presentation.Mode.SELECT else "编辑"
	_view.controls_host = page
	add_child(_view)
	_view.create_requested.connect(func(): create_requested.emit())
	_view.primary_requested.connect(func(id: String): edit_requested.emit(id))
	_view.action_requested.connect(_action)
	ProductCatalog.changed.connect(_catalog_changed)
	reload()

func reload() -> void:
	var loaded := Store.read_catalog()
	entries = loaded["entries"]
	_view.set_entries(entries,loaded["error"],loaded["warnings"])

func _action(action: String, record: Dictionary) -> void:
	if action=="rename":
		var modal := Rename.new()
		page.add_overlay(modal)
		modal.configure_product(record["title"],60,func(title: String): return Store.rename(record["id"],title))
		modal.name_saved.connect(reload)
	elif action=="copy":
		var result := Store.copy(record["id"])
		if result["ok"]: reload()
		else: _message("复制失败",result["message"])
	elif action=="delete": _delete(record)

func _delete(record: Dictionary) -> void:
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure("删除地图？","删除“%s”后将从地图库移除，地台库中的原件不受影响。" % record["title"])
	modal.add_action("取消",modal.dismiss)
	modal.add_action("删除",func():
		var result := Store.delete(record["id"])
		modal.dismiss()
		if result["ok"]: reload()
		else: _message("删除失败",result["message"])
	,false,true,true)

func _message(title: String, message: String) -> void:
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure(title,message)
	modal.add_action("返回地图库",modal.dismiss)

var catalog_refresh_queued := false
func _catalog_changed(kind: String) -> void:
	if kind!="maps" or catalog_refresh_queued or not is_visible_in_tree(): return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)
func _reload_catalog() -> void:
	catalog_refresh_queued = false
	reload()
