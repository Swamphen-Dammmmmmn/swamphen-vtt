extends RefCounted
## Opaque sample water; visual depth does not change landing heights.

const Ground = preload("res://scripts/ground_material.gd")
const SurfaceShader = preload("res://shaders/sample_water.gdshader")

static func defaults() -> Dictionary:
	return {"edge_color": Color("28b9c1"), "center_color": Color("07678f"),
		"gradient_range": 0.6, "wave_strength": 0.11, "wave_feet": 7.0,
		"flow_speed": 0.6, "highlight_strength": 0.14, "gloss": 0.65,
		"shore_enabled": true, "shore_strength": 0.42, "shore_width_feet": 6.0, "shore_period": 4.0}

static func create() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter("wave_noise", Ground.macro_texture())
	apply(material, defaults())
	return material

static func apply(material: ShaderMaterial, values: Dictionary) -> void:
	for key in values:
		material.set_shader_parameter(key, values[key])
