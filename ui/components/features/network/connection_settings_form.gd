extends VBoxContainer

# Fluent connection settings form: coordination address, certificate path, file browser, save and result.
# Emits: save_requested(address: String, certificate_path: String)

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const PageField = preload("res://ui/components/page_field.gd")
const PageNotice = preload("res://ui/components/page_notice.gd")

signal save_requested(address: String, certificate_path: String)

var _address_field: PageField
var _certificate_field: PageField
var _browse_button: FluentButton
var _save_button: FluentButton
var _result_notice: PageNotice
var _file_dialog: FileDialog

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", FluentTokens.GAP)

	# Address field
	_address_field = PageField.new()
	_address_field.set_meta("fluent_variant", true)
	add_child(_address_field)
	_address_field.setup("连接协调地址", "")
	_address_field.input.max_length = 512
	_address_field.input.placeholder_text = "wss://example.com/coordinate"

	# Certificate field
	_certificate_field = PageField.new()
	_certificate_field.set_meta("fluent_variant", true)
	add_child(_certificate_field)
	_certificate_field.setup("公开证书", "")
	_certificate_field.input.max_length = 1024
	_certificate_field.input.placeholder_text = "选择.crt或.pem文件"

	# Browse button (secondary)
	_browse_button = FluentButton.new()
	_browse_button.text = "选择公开证书"
	_browse_button.variant = "FluentButton"
	_browse_button.minimum_height = FluentTokens.BUTTON_HEIGHT
	_browse_button.pressed.connect(_on_browse)
	add_child(_browse_button)

	# Native file dialog
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.crt,*.pem ; 公开证书"])
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	# Save button (primary)
	_save_button = FluentButton.new()
	_save_button.text = "保存连接设置"
	_save_button.variant = "FluentPrimary"
	_save_button.minimum_height = FluentTokens.BUTTON_HEIGHT
	_save_button.pressed.connect(_on_save)
	add_child(_save_button)

	# Result notice
	_result_notice = PageNotice.new()
	_result_notice.set_meta("fluent_variant", true)
	_result_notice.hide()
	add_child(_result_notice)

func _on_browse() -> void:
	_file_dialog.popup_centered_ratio()

func _on_file_selected(path: String) -> void:
	_certificate_field.input.text = path

func _on_save() -> void:
	# Clear previous errors
	_address_field.set_error("")
	_certificate_field.set_error("")
	_result_notice.hide()

	var address := _address_field.input.text.strip_edges()
	var cert_path := _certificate_field.input.text.strip_edges()

	# Basic validation
	if address.is_empty():
		_address_field.set_error("请填写协调地址。")
		return

	# Emit save request
	save_requested.emit(address, cert_path)

func set_result(success: bool, message: String) -> void:
	if message.is_empty():
		_result_notice.hide()
	else:
		_result_notice.show_message(message, not success)

func load_settings(address: String, certificate_path: String) -> void:
	_address_field.input.text = address
	_certificate_field.input.text = certificate_path
	_result_notice.hide()

func get_address() -> String:
	return _address_field.input.text.strip_edges()

func get_certificate_path() -> String:
	return _certificate_field.input.text.strip_edges()
