extends RefCounted

const Acrylic = preload("res://scripts/token_acrylic.gd")
const BlendShader = preload("res://shaders/token_surface_transparent.gdshader")
const OpaqueShader = preload("res://shaders/token_surface_opaque.gdshader")
const Invisible = preload("res://shaders/token_image_carrier.gdshader")
const KINDS := ["matte", "gloss", "metal", "frosted", "acrylic"]
const TITLES := ["哑光", "光面", "金属", "磨砂", "亚克力"]

static func defaults(kind := "matte", color := "2e7ae0") -> Dictionary:
	return {"version": 2, "color": color, "opacity": 0.1 if kind == "acrylic" else 1.0,
		"roughness": {"matte":0.85,"gloss":0.22,"metal":0.25,"frosted":0.78,"acrylic":0.60}[kind],
		"grain": 0.45 if kind == "frosted" else 0.0, "metallic": 1.0 if kind == "metal" else 0.0,
		"edge": 1.0 if kind == "acrylic" else 0.0, "board_visible": true}

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	var version: Variant = value.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) not in [1.0, 2.0]: return false
	if int(version) == 1 and value.get("kind") not in KINDS: return false
	if not value.get("color") is String or not Color.html_is_valid(value.color): return false
	var keys := ["opacity", "roughness", "grain"]
	if int(version) == 2: keys.append_array(["metallic", "edge"])
	for key in keys:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)): return false
		if float(number) < 0.0 or float(number) > 1.0: return false
	return value.get("board_visible") is bool

# Call after validation; old modes are converted to their actual rendered parameters.
static func normalize(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	if int(result.version) == 1:
		result.metallic = 1.0 if result.kind == "metal" else 0.0
		result.edge = 1.0 if result.kind == "acrylic" else 0.0
		if result.kind != "frosted": result.grain = 0.0
		result.erase("kind")
		result.version = 2
	result.color = Color(result.color).to_html(false)
	return result

static func matching_preset(value: Dictionary) -> String:
	var settings := normalize(value)
	for kind in KINDS:
		var preset := defaults(kind)
		var matches := true
		for key in ["opacity", "roughness", "grain", "metallic", "edge"]:
			if not is_equal_approx(float(settings[key]), float(preset[key])):
				matches = false
				break
		if matches: return kind
	return ""

static func for_component(component: Dictionary, name: String) -> Dictionary:
	if component.has("material"): return normalize(component.material)
	var image: bool = name == "standee" and component.get("presentation", "solid") == "image"
	if image:
		var old: Dictionary = component.get("acrylic", Acrylic.defaults())
		var result := defaults("acrylic", str(old.color))
		result.opacity = float(old.opacity)
		result.roughness = float(old.roughness)
		result.board_visible = component.has("contour")
		return result
	return defaults("matte", str(component.get("color", "2e7ae0")))

static func material(value: Dictionary, part := "standee", preview := false) -> Material:
	var settings := normalize(value)
	if not settings.board_visible:
		var hidden := ShaderMaterial.new()
		hidden.shader = Invisible
		return hidden
	var color := Color(settings.color)
	var opacity := float(settings.opacity) * (0.65 if preview else 1.0)
	if float(settings.grain) > 0.0 or float(settings.edge) > 0.0:
		var combined := ShaderMaterial.new()
		combined.shader = BlendShader if opacity < 0.9999 else OpaqueShader
		combined.set_shader_parameter("surface_color", color)
		combined.set_shader_parameter("surface_roughness", float(settings.roughness))
		combined.set_shader_parameter("grain_strength", float(settings.grain))
		combined.set_shader_parameter("surface_metallic", float(settings.metallic))
		combined.set_shader_parameter("edge_strength", float(settings.edge))
		combined.set_shader_parameter("face_axis", Vector3.UP if part == "base" else Vector3.BACK)
		combined.set_shader_parameter("opacity", opacity)
		return combined
	var surface := StandardMaterial3D.new()
	color.a = opacity
	surface.albedo_color = color
	surface.roughness = float(settings.roughness)
	surface.metallic = float(settings.metallic)
	if opacity < 0.9999: surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return surface

static func basic_defaults(color: Color) -> Dictionary:
	return {"base":defaults("matte",color.darkened(0.25).to_html(false)),"standee":defaults("matte",color.to_html(false))}

static func apply_basic(actor: Node3D, values: Dictionary, preview := false) -> void:
	for part in ["base", "standee"]:
		if not values.has(part): continue
		var node := actor.get_node("Base" if part == "base" else "Standee") as MeshInstance3D
		node.material_override = material(values[part], part, preview)

static func preview_reflection(environment: Environment) -> void:
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var colors := ProceduralSkyMaterial.new()
	colors.sky_top_color = Color("a5b4c6")
	colors.sky_horizon_color = Color("eef2f7")
	colors.ground_horizon_color = Color("eef2f7")
	colors.ground_bottom_color = Color("596575")
	sky.sky_material = colors
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
