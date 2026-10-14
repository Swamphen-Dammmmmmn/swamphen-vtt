extends "res://ui/components/creation_palette.gd"
const PlatformStore = preload("res://scripts/platform_library_store.gd")

func _init() -> void:
	category = "platform"
	entries = {"platform":[]}
	memory = {"platform":{"query":"","first":0}}

func _ready() -> void:
	super._ready()
	title.text = "地台库"
	search.placeholder_text = "搜索地台名称"

func _load_local_entries() -> void:
	var loaded := PlatformStore.read_all()
	library_error = loaded["error"]
	library_warnings = loaded["warnings"]
	entries["platform"] = []
	for record: Dictionary in loaded["entries"]:
		entries["platform"].append({"id":record["id"],"title":record["title"],"thumbnail":record["thumbnail"],"parameters":record["parameters"],"tooltip":str(record["title"])+"\n导入独立地台副本"})

func open(margin: float, key: String = "platform") -> void:
	super.open(margin,key)
	title.text = "地台库"

func _render_slots() -> void:
	super._render_slots()
	status.text = "%d 块地台" % filtered.size()
	if filtered.is_empty(): status.text = "" if entries[category].is_empty() else "没有符合搜索的地台。"
	status.visible = not status.text.is_empty()
	status.tooltip_text = status.text
	if not library_error.is_empty():
		status.visible = true
		status.text = "地台库读取失败"
		status.tooltip_text = library_error
	elif not library_warnings.is_empty():
		status.visible = true
		status.text += (" · " if not status.text.is_empty() else "") + "%d 个文件未能读取" % library_warnings.size()
		status.tooltip_text += "\n"+"\n".join(PackedStringArray(library_warnings))
