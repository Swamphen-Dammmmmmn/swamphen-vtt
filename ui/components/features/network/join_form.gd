extends VBoxContainer

# Fluent join form: invitation code, room password, join button, connection status, settings link.
# Emits: join_requested(invite_code: String, password: String), settings_requested()

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const PageField = preload("res://ui/components/page_field.gd")
const PageNotice = preload("res://ui/components/page_notice.gd")

signal join_requested(invite_code: String, password: String)
signal settings_requested()

var _invite_field: PageField
var _password_field: PageField
var _join_button: FluentButton
var _status_notice: PageNotice
var _settings_button: FluentButton
var _is_active: bool = false

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", FluentTokens.GAP)

	# Invitation code field
	_invite_field = PageField.new()
	_invite_field.set_meta("fluent_variant", true)
	add_child(_invite_field)
	_invite_field.setup("邀请码", "")
	_invite_field.input.max_length = 8
	_invite_field.input.placeholder_text = "8位邀请码"

	# Password field
	_password_field = PageField.new()
	_password_field.set_meta("fluent_variant", true)
	add_child(_password_field)
	_password_field.setup("团密码", "", true)
	_password_field.input.placeholder_text = "房间没设密码时，只填邀请码即可加入"
	_password_field.input.text_submitted.connect(_on_submit)

	# Join button (primary)
	_join_button = FluentButton.new()
	_join_button.text = "加入团"
	_join_button.variant = "FluentPrimary"
	_join_button.minimum_height = FluentTokens.BUTTON_HEIGHT
	_join_button.pressed.connect(_on_submit.bind(""))
	add_child(_join_button)

	# Status notice
	_status_notice = PageNotice.new()
	_status_notice.set_meta("fluent_variant", true)
	_status_notice.hide()
	add_child(_status_notice)

	# Connection settings button (secondary)
	_settings_button = FluentButton.new()
	_settings_button.text = "连接设置"
	_settings_button.variant = "FluentButton"
	_settings_button.minimum_height = FluentTokens.BUTTON_HEIGHT
	_settings_button.pressed.connect(func(): settings_requested.emit())
	add_child(_settings_button)

func _on_submit(_text: String = "") -> void:
	if _is_active:
		return

	# Clear previous errors
	_invite_field.set_error("")
	_password_field.set_error("")

	# Validate invitation code
	var invite := _invite_field.input.text.strip_edges()
	if invite.length() != 8:
		_invite_field.set_error("邀请码须为8位。")
		return

	var password := _password_field.input.text

	# Emit join request
	join_requested.emit(invite, password)

func set_status(message: String, is_error: bool = false) -> void:
	if message.is_empty():
		_status_notice.hide()
	else:
		_status_notice.show_message(message, is_error)

func set_active(active: bool) -> void:
	_is_active = active
	_join_button.disabled = active
	_invite_field.input.editable = not active
	_password_field.input.editable = not active
	_settings_button.disabled = active

func clear_password() -> void:
	_password_field.input.clear()

func get_invite_code() -> String:
	return _invite_field.input.text.strip_edges()

func get_password() -> String:
	return _password_field.input.text

func password_input() -> LineEdit:
	return _password_field.input

func update_network_status(message: String, network: Node) -> void:
	set_status(message, not message.is_empty() and not network.active and message != "未开放联机")
	set_active(network.active)
