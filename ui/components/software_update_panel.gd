extends VBoxContainer

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
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
var _use_fluent := false

func _ready() -> void:
	_use_fluent = get_meta("fluent_variant", false)
	if _use_fluent:
		theme = FluentTheme.shared()
		add_theme_constant_override("separation", FluentTokens.GAP)
	else:
		add_theme_constant_override("separation", 16)

	_add_title("紫水鸡棋盘 · " + str(ProjectSettings.get_setting("application/config/version", "")))

	# Flow only the Fluent variant; older embedded panels retain their layout.
	var actions_container: Container = HFlowContainer.new() if _use_fluent else HBoxContainer.new()
	actions_container.add_theme_constant_override("separation", 12)
	add_child(actions_container)
	check_button = _create_button("检查更新", func(): Updates.start("check"))
	actions_container.add_child(check_button)
	download_button = _create_button("下载更新", func(): Updates.start("download"), true)
	actions_container.add_child(download_button)

	var next: Container = HFlowContainer.new() if _use_fluent else HBoxContainer.new()
	next.add_theme_constant_override("separation", 12)
	add_child(next)
	import_button = _create_button("导入更新ZIP", _choose_package)
	next.add_child(import_button)
	apply_button = _create_button("更新并重启", func(): Updates.restart_requested.emit("apply"), true)
	next.add_child(apply_button)

	progress = ProgressBar.new()
	progress.max_value = 1
	progress.show_percentage = true
	progress.custom_minimum_size.y = 24
	add_child(progress)

	download_size = Label.new()
	download_size.add_theme_font_size_override("font_size", Typography.CAPTION)
	if _use_fluent:
		download_size.add_theme_color_override("font_color", FluentTokens.SECONDARY)
	add_child(download_size)

	status = Label.new()
	status.add_theme_font_size_override("font_size", Typography.BODY)
	if _use_fluent:
		status.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

	notes = Label.new()
	notes.add_theme_font_size_override("font_size", Typography.BODY)
	if _use_fluent:
		notes.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(notes)

	if _use_fluent:
		var sep := HSeparator.new()
		var style := StyleBoxFlat.new()
		style.bg_color = FluentTokens.STROKE
		sep.add_theme_stylebox_override("separator", style)
		add_child(sep)
	else:
		add_child(HSeparator.new())

	var folders: Container = HFlowContainer.new() if _use_fluent else HBoxContainer.new()
	folders.add_theme_constant_override("separation", 12)
	add_child(folders)
	var open_program := _create_button("打开程序目录", func(): OS.shell_open(Paths.install_root()))
	folders.add_child(open_program)
	var open_data := _create_button("打开数据目录", func(): OS.shell_open(Paths.data_root()))
	folders.add_child(open_data)

	rollback_button = _create_button("恢复上个版本", func(): Updates.restart_requested.emit("rollback"))
	add_child(rollback_button)

	Updates.changed.connect(_refresh)
	_refresh()

func _add_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	if _use_fluent:
		label.add_theme_font_override("font", Typography.MEDIUM)
		label.add_theme_font_size_override("font_size", Typography.SECTION)
		label.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	else:
		label.add_theme_font_size_override("font_size", Typography.DIALOG_TITLE)
	add_child(label)

func _create_button(text: String, callback: Callable, disabled: bool = false) -> Button:
	if _use_fluent:
		var button := FluentButton.new()
		button.text = text
		button.variant = "FluentButton"
		button.minimum_height = 36
		button.disabled = disabled
		button.pressed.connect(callback)
		return button
	else:
		var button := Button.new()
		button.text = text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = disabled
		Style.button(button, false)
		button.pressed.connect(callback)
		return button

func _choose_package() -> void:
	var browser := FileDialog.new()
	browser.access = FileDialog.ACCESS_FILESYSTEM
	browser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	browser.use_native_dialog = true
	browser.filters = PackedStringArray(["*.zip ; 更新ZIP"])
	add_child(browser)
	browser.file_selected.connect(func(path: String): Updates.start("import", path); browser.queue_free())
	browser.canceled.connect(browser.queue_free)
	browser.popup_centered_ratio()

func _refresh() -> void:
	status.text = Updates.status + (" · " + Updates.latest if not Updates.latest.is_empty() else "")
	notes.text = Updates.notes
	notes.visible = not notes.text.is_empty()
	progress.visible = Updates.busy() and Updates.phase in ["download", "verify"]
	download_size.visible = Updates.busy() and Updates.phase == "download"
	download_size.text = "%.1f / %.1f MiB" % [Updates.downloaded / 1048576.0, Updates.total / 1048576.0]
	progress.value = Updates.progress
	check_button.disabled = not Updates.available or Updates.busy()
	download_button.disabled = check_button.disabled or Updates.state != "available"
	apply_button.visible = Updates.available and FileAccess.file_exists(Paths.install_root().path_join("cache/updates/staged.json"))
	apply_button.disabled = not Updates.available or Updates.busy()
	rollback_button.visible = Updates.available and Updates.has_previous()
	rollback_button.disabled = Updates.busy()
