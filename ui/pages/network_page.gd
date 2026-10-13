extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
const Field = preload("res://ui/components/page_field.gd")
const Settings = preload("res://scripts/network_settings.gd")
var page: Control
var network: Node
var host_mode := false
var feedback: Label
var room_label: LineEdit
var password: Field
var invite: Field
var open_button: Button
var close_button: Button
var copy_button: Button

func _ready() -> void:
	page.configure("联机房间" if host_mode else "加入团")
	var center := CenterContainer.new()
	add_child(center)
	var panel := Style.card()
	center.add_child(panel)
	center.resized.connect(func(): panel.custom_minimum_size.x = minf(520,center.size.x))
	panel.custom_minimum_size.x = 520
	var form := Style.column(16)
	panel.add_child(form)
	if not host_mode:
		invite = Field.new()
		form.add_child(invite)
		invite.setup("邀请码", "")
		invite.input.max_length = 8
	password = Field.new()
	form.add_child(password)
	password.setup("团密码","",true)
	if host_mode:
		if network.hosting and network.active: password.input.text = network.password
		form.add_child(Style.text("邀请码",16))
		room_label = LineEdit.new()
		room_label.editable = false
		room_label.custom_minimum_size.y = 44
		form.add_child(room_label)
		var copy := Button.new()
		copy_button = copy
		copy.text = "复制邀请码"
		Style.button(copy)
		form.add_child(copy)
		copy.pressed.connect(func():
			if not network.room_code.is_empty(): DisplayServer.clipboard_set(network.room_code)
		)
	open_button = Button.new()
	open_button.text = "开放联机" if host_mode else "加入团"
	Style.button(open_button,true)
	form.add_child(open_button)
	open_button.pressed.connect(_submit)
	password.input.text_submitted.connect(func(_text: String): _submit())
	if host_mode:
		close_button = Button.new()
		close_button.text = "关闭联机"
		Style.button(close_button)
		form.add_child(close_button)
		close_button.pressed.connect(network.close)
	feedback = Style.text("",14,true)
	feedback.autowrap_mode = TextServer.AUTOWRAP_OFF
	feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	feedback.custom_minimum_size.y = 24
	form.add_child(feedback)
	var settings := Button.new()
	settings.text = "连接设置"
	Style.button(settings)
	form.add_child(settings)
	settings.pressed.connect(func(): page.navigation_requested.emit("network_settings",""))
	network.status_changed.connect(_status)
	_status(network.status)
	page.set_meta("password_input",password.input)

func _submit() -> void:
	if password.input.text.is_empty(): password.set_error("请填写团密码。") ; return
	if host_mode:
		network.open_host(password.input.text)
	else:
		if invite.input.text.strip_edges().length()!=8: invite.set_error("邀请码须为8位。") ; return
		network.join(invite.input.text,password.input.text)
	if not host_mode: password.input.clear()

func _status(message: String) -> void:
	feedback.text = message
	feedback.tooltip_text = message
	open_button.disabled = network.active
	if host_mode:
		room_label.text = network.room_code
		close_button.disabled = not network.active
		copy_button.disabled = network.room_code.is_empty()
		password.input.editable = not network.active
		if network.active and network.hosting: password.input.text = network.password

static func add_settings(parent: Control) -> void:
	var options := Settings.read()
	var form := Style.column(16)
	parent.add_child(form)
	var address := Field.new()
	form.add_child(address)
	address.setup("连接协调地址", "")
	address.input.max_length = 512
	address.input.text = options["address"]
	var certificate := Field.new()
	form.add_child(certificate)
	certificate.setup("公开证书", "")
	certificate.input.max_length = 1024
	certificate.input.text = options["certificate"]
	var choose := Button.new()
	choose.text = "选择公开证书"
	Style.button(choose)
	form.add_child(choose)
	var browser := FileDialog.new()
	browser.access = FileDialog.ACCESS_FILESYSTEM
	browser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	browser.use_native_dialog = true
	browser.filters = PackedStringArray(["*.crt,*.pem ; 公开证书"])
	form.add_child(browser)
	browser.file_selected.connect(func(path: String): certificate.input.text = path)
	choose.pressed.connect(func(): browser.popup_centered_ratio())
	var status := Style.text("",14,true)
	form.add_child(status)
	var save := Button.new()
	save.text = "保存连接设置"
	Style.button(save,true)
	form.add_child(save)
	save.pressed.connect(func():
		var error := Settings.save(address.input.text,certificate.input.text)
		status.text = "已保存，下次连接生效" if error==OK else "无法保存，请检查地址和公开证书。"
	)
