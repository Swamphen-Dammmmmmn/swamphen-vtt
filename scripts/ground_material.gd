extends RefCounted
## Shared ground resources; one unit in the scene represents five feet.

const SurfaceShader = preload("res://assets/ground/ground_surface.gdshader")
const GrainColor = preload("res://assets/ground/sand_grain_color.png")
const Microstructure = preload("res://assets/ground/sand_microstructure.png")
const MacroMask = preload("res://assets/ground/macro.png")
const GrassMasks = [preload("res://assets/ground/grass_0.png"), preload("res://assets/ground/grass_1.png"),
	preload("res://assets/ground/grass_2.png"), preload("res://assets/ground/grass_3.png")]
const SandMasks = [preload("res://assets/ground/sand_0.png"), preload("res://assets/ground/sand_1.png"),
	preload("res://assets/ground/sand_2.png"), preload("res://assets/ground/sand_3.png")]
static var detail_cache: Dictionary = {}
static var macro_cache: ImageTexture
static var micro_cache: ImageTexture
static var grain_color_cache: ImageTexture

static func defaults(kind: String) -> Dictionary:
	return {"color": Color("40b85a") if kind == "grass" else (Color("e4d3af") if kind == "sand" else Color("dfbe7b")),
		"contrast": 0.65, "texture_feet": 10.0, "seed": 1, "varied": true, "variant": 0,
		"relief_feet": 0.035 if kind == "sand" else (0.28 if kind == "beach" else 0.0),
		"ripple_strength": 0.055 if kind == "sand" else (0.045 if kind == "beach" else 0.0),
		"patch_strength": 0.23 if kind == "beach" else (0.35 if kind == "sand" else 0.0),
		"grain_normal": 0.22 if kind == "beach" else (0.18 if kind == "sand" else 0.0),
		"glint_strength": 0.75 if kind == "beach" else (0.55 if kind == "sand" else 0.0),
		"glint_density": 0.35 if kind == "beach" else (0.18 if kind == "sand" else 0.0),
		"grain_feet": 5.9 if kind == "beach" else 6.0,
		"grain_color": 1.0 if kind == "beach" else (0.7 if kind == "sand" else 0.0)}

static func detail_texture(kind: String) -> Texture2DArray:
	var safe_kind := "sand" if kind != "grass" else "grass"
	if detail_cache.has(safe_kind): return detail_cache[safe_kind]
	var images: Array[Image] = []
	var sources: Array = SandMasks if safe_kind == "sand" else GrassMasks
	for resource: Texture2D in sources:
		var image := resource.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGB8)
		image.generate_mipmaps()
		images.append(image)
	var array := Texture2DArray.new()
	var error := array.create_from_images(images)
	if error != OK:
		push_error("Ground mask array could not be created: %s" % error)
		return null
	detail_cache[safe_kind] = array
	return array

static func macro_texture() -> ImageTexture:
	if macro_cache == null:
		var image := MacroMask.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGB8)
		image.generate_mipmaps()
		macro_cache = ImageTexture.create_from_image(image)
	return macro_cache

static func micro_texture() -> ImageTexture:
	if micro_cache == null:
		var image := Microstructure.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		micro_cache = ImageTexture.create_from_image(image)
	return micro_cache

static func grain_color_texture() -> ImageTexture:
	if grain_color_cache == null:
		var image := GrainColor.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGB8)
		image.generate_mipmaps()
		grain_color_cache = ImageTexture.create_from_image(image)
	return grain_color_cache

static func create(kind: String, offset := Vector2.ZERO) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter("detail_masks", detail_texture(kind))
	material.set_shader_parameter("macro_mask", macro_texture())
	material.set_shader_parameter("sand_microstructure", micro_texture())
	material.set_shader_parameter("sand_grain_color", grain_color_texture())
	material.set_shader_parameter("ground_offset", offset)
	material.set_shader_parameter("sand_surface", kind != "grass")
	material.set_shader_parameter("grain_strength", 0.24 if kind == "grass" else 0.14)
	apply(material, defaults(kind))
	return material

static func apply(material: ShaderMaterial, values: Dictionary) -> void:
	material.set_shader_parameter("base_color", values["color"])
	material.set_shader_parameter("contrast", values["contrast"])
	material.set_shader_parameter("texture_feet", values["texture_feet"])
	material.set_shader_parameter("pattern_seed", int(values["seed"]))
	material.set_shader_parameter("varied", values["varied"])
	material.set_shader_parameter("single_variant", int(values["variant"]))

	material.set_shader_parameter("sand_grain_feet",values["grain_feet"])
	material.set_shader_parameter("sand_color_strength",values["grain_color"])
	for key in ["relief_feet", "ripple_strength", "patch_strength", "grain_normal", "glint_strength", "glint_density"]:
		material.set_shader_parameter(key, values[key])

static func apply_wind(material: ShaderMaterial, values: Dictionary) -> void:
	material.set_shader_parameter("ground_wind_enabled", bool(values["enabled"]))
	for key in ["wind_direction", "wind_strength", "gust_strength", "gust_frequency", "wave_width_feet", "wave_speed_feet", "sway_period", "sway_amplitude", "softness", "ground_wave_strength"]:
		material.set_shader_parameter(key, values[key])
