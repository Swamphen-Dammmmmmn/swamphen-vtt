extends VBoxContainer

# Fluent host form: optional room password, read-only invite code, copy button,
# open/close networking, status, and settings link.
# Emits: open_requested(password: String), close_requested(), copy_requested(), settings_requested()

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const PageField = preload("res://ui/components/page_field.gd")
const PageNotice = preload("res://ui/components/page_notice.gd")

signal open_requested(password: String)
signal close_requested()
signal copy_requested()
signal settings_requested()

var _password_field: PageField
var _invite_field: LineEdit
var _copy_button: FluentButton
var _open_button: FluentButton
var _close_button: FluentButton
var _status_notice: PageNotice
var _settings_button: FluentButton
var _is_active: bool = false

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", T.GAP)

	# Password field (optional)
	_password_field = PageField.new()
	_password_field.set_meta("fluent_variant", true)
	add_child(_password_field)
	_password_field.setup("团密码", "", true)
	_password_field.input.placeholder_text = "选填，留空则凭邀请码加入"
	_password_field.input.text_submitted.connect(func(_text: String): _on_open())

	# Read-only fields share the same label spacing and theme as editable fields.
	var invite_field := PageField.new()
	invite_field.set_meta("fluent_variant", true)
	add_child(invite_field)
	invite_field.setup("邀请码", "开放联机后生成")
	_invite_field = invite_field.input
	_invite_field.editable = false

	# Copy invitation code button
	_copy_button = FluentButton.new()
	_copy_button.text = "复制邀请码"
	_copy_button.variant = "FluentButton"
	_copy_button.minimum_height = T.BUTTON_HEIGHT
	_copy_button.disabled = true
	_copy_button.pressed.connect(func(): copy_requested.emit())
	add_child(_copy_button)

	# Open networking button (primary)
	_open_button = FluentButton.new()
	_open_button.text = "开放联机"
	_open_button.variant = "FluentPrimary"
	_open_button.minimum_height = T.BUTTON_HEIGHT
	_open_button.pressed.connect(_on_open)
	add_child(_open_button)

	# Close networking button
	_close_button = FluentButton.new()
	_close_button.text = "关闭联机"
	_close_button.variant = "FluentButton"
	_close_button.minimum_height = T.BUTTON_HEIGHT
	_close_button.disabled = true
	_close_button.pressed.connect(func(): close_requested.emit())
	add_child(_close_button)

	# Status notice
	_status_notice = PageNotice.new()
	_status_notice.set_meta("fluent_variant", true)
	_status_notice.hide()
	add_child(_status_notice)

	# Connection settings button
	_settings_button = FluentButton.new()
	_settings_button.text = "连接设置"
	_settings_button.variant = "FluentButton"
	_settings_button.minimum_height = T.BUTTON_HEIGHT
	_settings_button.pressed.connect(func(): settings_requested.emit())
	add_child(_settings_button)

func _on_open() -> void:
	if _is_active: return
	# Emit open request with password (may be empty)
	var password := _password_field.input.text
	open_requested.emit(password)

func update_network_status(message: String, network: Node) -> void:
	# Update UI based on network state
	_is_active = network.active
	var is_hosting: bool = network.hosting

	# Update status
	if message.is_empty():
		_status_notice.hide()
	else:
		var is_error := not message.is_empty() and not _is_active and message != "未开放联机"
		_status_notice.show_message(message, is_error)

	# Update button states
	_open_button.disabled = _is_active
	_close_button.disabled = not _is_active
	_copy_button.disabled = not is_hosting or network.room_code.is_empty()

	# Update invite code field
	_invite_field.text = network.room_code if is_hosting else ""

	# Password is read-only while active, editable when not hosting
	_password_field.input.editable = not _is_active

	# When hosting and active, restore the password for display
	if _is_active and is_hosting:
		_password_field.input.text = network.password

func password_input() -> LineEdit:
	# Public accessor for sensitive field registration
	return _password_field.input

func get_password() -> String:
	return _password_field.input.text
