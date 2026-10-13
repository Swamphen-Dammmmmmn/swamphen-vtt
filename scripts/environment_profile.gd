extends RefCounted

const DaySky = preload("res://assets/environment/gdquest/day_sky.tres")

static func defaults() -> Dictionary:
	return {"g_top": Color(0.34902, 0.588235, 1), "g_bottom": Color(0, 0.329412, 0.968627), "g_clouds": 0.4, "g_high_clouds": 0.2,
		"g_light": Color("fff4e5"), "g_energy": 1.0, "g_altitude": 39.704, "g_azimuth": 10.2, "g_shadow": true,
		"g_ambient": Color("bdc9d6"), "g_ambient_energy": 0.3, "g_sky_contribution": 0.2, "g_shadow_opacity": 0.95, "g_exposure": 1.0,
		"dream_on": true, "dream_intensity": 0.27, "dream_spread": 0.6, "dream_threshold": 0.85, "dream_bloom": 0.04, "g_saturation": 1.0}

static func create(copy_resources := true) -> Node3D:
	var root := Node3D.new()
	root.name = "SceneEnvironment"
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = DaySky.duplicate(copy_resources)
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	root.add_child(sun)
	apply(root, defaults())
	return root

static func apply(root: Node3D, data: Dictionary) -> void:
	var world: WorldEnvironment = root.get_node("WorldEnvironment")
	var env := world.environment
	var sky: ShaderMaterial = env.sky.sky_material
	var sun: DirectionalLight3D = root.get_node("DirectionalLight3D")
	sky.set_shader_parameter("top_color", data["g_top"])
	sky.set_shader_parameter("bottom_color", data["g_bottom"])
	sky.set_shader_parameter("clouds_density", data["g_clouds"])
	sky.set_shader_parameter("high_clouds_density", data["g_high_clouds"])
	sun.light_color = data["g_light"]
	sun.light_energy = data["g_energy"]
	sun.rotation_degrees = Vector3(-float(data["g_altitude"]), float(data["g_azimuth"]), 0)
	sun.shadow_enabled = data["g_shadow"]
	sun.shadow_opacity = data["g_shadow_opacity"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = data["g_sky_contribution"]
	env.ambient_light_color = data["g_ambient"]
	env.ambient_light_energy = data["g_ambient_energy"]
	env.tonemap_exposure = data["g_exposure"]
	env.adjustment_enabled = not is_equal_approx(float(data["g_saturation"]), 1.0)
	env.adjustment_saturation = data["g_saturation"]
	apply_glow(env, data)

static func apply_glow(env: Environment, data: Dictionary) -> void:
	var dream: bool = data["dream_on"]
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = data["dream_intensity"] if dream else 0.25
	env.glow_hdr_threshold = data["dream_threshold"] if dream else 1.2
	env.glow_bloom = data["dream_bloom"] if dream else 0.02
	var tight := [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0]
	var wide := [0.0, 0.1, 0.2, 0.3, 0.45, 0.25, 0.0]
	var spread: float = data["dream_spread"] if dream else 0.0
	for i in range(7): env.set_glow_level(i, lerpf(tight[i], wide[i], spread))
