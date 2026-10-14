extends SubViewportContainer

const Sticker = preload("res://scripts/token_sticker.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Components = preload("res://scripts/token_components.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
var viewport: SubViewport
var model_root: Node3D
var camera: Camera3D
var actor: Node3D
var image_warning: Label

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(96, 84)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	model_root = Node3D.new()
	viewport.add_child(model_root)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("edf2f8")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	preload("res://scripts/token_surface.gd").preview_reflection(settings)
	environment.environment = settings
	model_root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	model_root.add_child(light)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 35
	model_root.add_child(camera)
	image_warning = Label.new()
	image_warning.text = "图片资源缺失或损坏"
	image_warning.add_theme_color_override("font_color", Color("b33c3c"))
	image_warning.add_theme_font_size_override("font_size", 13)
	image_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_warning.hide()
	add_child(image_warning)
	resized.connect(_refresh)
	visibility_changed.connect(_refresh)

func configure(data: Dictionary) -> void:
	if actor != null:
		model_root.remove_child(actor)
		actor.queue_free()
		actor = null
	var count := maxi(1, int(data.get("size", 1)))
	if data.has("components") and not data["components"].is_empty():
		var checked := Components.validate(data["components"], Vector2i(int(data["width"]), int(data["length"])))
		if not checked["ok"]: return
		actor = Components.build(checked)
	else:
		actor = Appearance.build(count, data.get("color", Color("2e7ae0")), data.get("base", "circle"), false, data.get("materials", {}))
	model_root.add_child(actor)
	var standee := actor.get_node_or_null("Standee")
	image_warning.visible = standee != null and standee.has_meta("missing_image")
	var specification: Dictionary = data.get("components", {}).get("standee", {}).get("sticker", Sticker.defaults())
	for image_id in Sticker.resource_ids(specification):
		if not Images.load_image(image_id)["ok"]: image_warning.show()
	camera.position = Vector3(1.8, 1.5, 2.6) * count
	var target := Vector3(0, count * 0.4, 0)
	if actor.has_meta("appearance_bounds"):
		var bounds: AABB = actor.get_meta("appearance_bounds")
		target = bounds.get_center()
		var span := maxf(0.5, bounds.size.length())
		camera.position = target + Vector3(1.8, 1.5, 2.6).normalized() * span * 1.8
	camera.look_at(target)
	_refresh.call_deferred()

func _refresh() -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree(): _refresh.call_deferred()
