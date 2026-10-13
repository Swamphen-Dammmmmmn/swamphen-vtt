extends RefCounted

const SurfaceShader = preload("res://shaders/token_acrylic.gdshader")

static func defaults() -> Dictionary:
	return {"opacity": 0.10, "roughness": 0.60, "color": "f1f7fa"}

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["opacity", "roughness"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])): return false
	if float(value["opacity"]) < 0.0 or float(value["opacity"]) > 0.6: return false
	if float(value["roughness"]) < 0.05 or float(value["roughness"]) > 0.8: return false
	return value.get("color") is String and Color.html_is_valid(value["color"])

static func material(settings: Dictionary, preview := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SurfaceShader
	result.set_shader_parameter("plate_color", Color(settings["color"]))
	result.set_shader_parameter("opacity", float(settings["opacity"]) * (0.65 if preview else 1.0))
	result.set_shader_parameter("surface_roughness", float(settings["roughness"]))
	return result
