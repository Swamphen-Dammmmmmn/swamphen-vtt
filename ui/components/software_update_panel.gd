extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
const Paths = preload("res://scripts/storage_paths.gd")
var status: Label
var notes: Label
var progress: ProgressBar
var check_button: Button
var download_button: Button
var import_button: Button
var apply_button: Button
var rollback_button: Button
var download_size: Label

func _ready() -> void:
	add_theme_constant_override("separation",16)
	add_child(Style.text("紫水鸡棋盘 · "+str(ProjectSettings.get_setting("application/config/version","")),24))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	add_child(actions)
	check_button = _button(actions,"检查更新",func(): Updates.start("check"))
	download_button = _button(actions,"下载更新",func(): Updates.start("download"),true)
	var next := HBoxContainer.new()
	next.add_theme_constant_override("separation",12)
	add_child(next)
	import_button = _button(next,"导入更新ZIP",_choose_package)
	apply_button = _button(next,"更新并重启",func(): Updates.restart_requested.emit("apply"),true)
	progress = ProgressBar.new()
	progress.max_value = 1
	progress.show_percentage = true
	progress.custom_minimum_size.y = 24
	add_child(progress)
	download_size = Style.text("",14,true)
	add_child(download_size)
	status = Style.text("",16,true)
	add_child(status)
	notes = Style.text("",16)
	add_child(notes)
	add_child(HSeparator.new())
	var folders := HBoxContainer.new()
	folders.add_theme_constant_override("separation",12)
	add_child(folders)
	_button(folders,"打开程序目录",func(): OS.shell_open(Paths.install_root()))
	_button(folders,"打开数据目录",func(): OS.shell_open(Paths.data_root()))
	rollback_button = _button(self,"恢复上个版本",func(): Updates.restart_requested.emit("rollback"))
	Updates.changed.connect(_refresh)
	_refresh()

func _button(parent: Control, title: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.button(button,primary)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _choose_package() -> void:
	var browser := FileDialog.new()
	browser.access = FileDialog.ACCESS_FILESYSTEM
	browser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	browser.use_native_dialog = true
	browser.filters = PackedStringArray(["*.zip ; 更新ZIP"])
	add_child(browser)
	browser.file_selected.connect(func(path: String): Updates.start("import",path); browser.queue_free())
	browser.canceled.connect(browser.queue_free)
	browser.popup_centered_ratio()

func _refresh() -> void:
	status.text = Updates.status+(" · "+Updates.latest if not Updates.latest.is_empty() else "")
	notes.text = Updates.notes
	notes.visible = not notes.text.is_empty()
	progress.visible = Updates.busy() and Updates.phase in ["download","verify"]
	download_size.visible = Updates.busy() and Updates.phase=="download"
	download_size.text = "%.1f / %.1f MiB" % [Updates.downloaded/1048576.0,Updates.total/1048576.0]
	progress.value = Updates.progress
	check_button.disabled = not Updates.available or Updates.busy()
	import_button.disabled = check_button.disabled
	download_button.disabled = check_button.disabled or Updates.state!="available"
	apply_button.visible = Updates.available and FileAccess.file_exists(Paths.install_root().path_join("cache/updates/staged.json"))
	apply_button.disabled = not Updates.available or Updates.busy()
	rollback_button.visible = Updates.available and Updates.has_previous()
	rollback_button.disabled = Updates.busy()
