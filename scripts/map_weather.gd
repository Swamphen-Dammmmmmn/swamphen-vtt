extends RefCounted

const Profile = preload("res://scripts/environment_profile.gd")
const Grass = preload("res://scripts/grass_patch.gd")
const TIMES := {"morning":"清晨","noon":"正午","evening":"黄昏","custom":"自定义"}
const CONDITIONS := {"clear":"晴朗","cloudy":"多云","overcast":"阴天"}
const LIMITS := {
	"sky":{"clouds":[0.0,1.0],"high_clouds":[0.0,1.0],"brightness":[0.1,2.0]},
	"light":{"energy":[0.0,5.0],"altitude":[0.0,90.0],"azimuth":[0.0,360.0],"ambient_energy":[0.0,2.0]},
	"wind":{"wind_direction":[0.0,360.0],"wind_strength":[0.0,3.0],"gust_strength":[0.0,3.0],"gust_frequency":[0.0,2.0],"wave_width_feet":[1.0,300.0],"wave_speed_feet":[0.0,100.0],"sway_period":[0.1,10.0],"sway_amplitude":[0.0,2.0]}
}
const ADJUSTMENTS := {"brightness":[0.25,2.0],"warmth":[-1.0,1.0],"weather_strength":[0.0,1.0]}

static func defaults() -> Dictionary:
	var p := Profile.defaults()
	var wind := {}
	var grass := Grass.defaults()
	for key in LIMITS["wind"]: wind[key] = grass[key]
	return {"profile":"board_default_v1","time_preset":"noon","weather_preset":"clear","brightness":1.0,"warmth":0.0,"weather_strength":1.0,
		"sky":{"top_color":p["g_top"].to_html(false),"bottom_color":p["g_bottom"].to_html(false),"clouds":p["g_clouds"],"high_clouds":p["g_high_clouds"],"brightness":1.0},
		"light":{"color":p["g_light"].to_html(false),"energy":p["g_energy"],"altitude":p["g_altitude"],"azimuth":p["g_azimuth"],"shadows":p["g_shadow"],"ambient_color":p["g_ambient"].to_html(false),"ambient_energy":p["g_ambient_energy"]},"wind":wind}

static func select_time(data: Dictionary, key: String) -> void:
	var base := defaults()
	if key=="morning":
		base["sky"]["top_color"] = "86bbed"
		base["sky"]["bottom_color"] = "b4d1e4"
		base["sky"]["brightness"] = 0.72
		base["light"].merge({"color":"fff0dc","energy":1.1,"altitude":22.0,"ambient_color":"b8cadc","ambient_energy":0.28},true)
	elif key=="evening":
		base["sky"]["top_color"] = "687dae"
		base["sky"]["bottom_color"] = "a1b5d7"
		base["sky"]["brightness"] = 0.45
		base["light"].merge({"color":"ffbf80","energy":1.15,"altitude":12.0,"ambient_color":"a3a5c2","ambient_energy":0.24},true)
	base["light"]["azimuth"] = data["light"]["azimuth"]
	data["sky"] = base["sky"]
	data["light"] = base["light"]
	data["brightness"] = 1.0
	data["warmth"] = 0.0
	data["time_preset"] = key

static func decode(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.get("profile")!="board_default_v1": return {"ok":false,"message":"不支持此地图环境配置。"}
	var data := defaults()
	for group in ["sky","light","wind"]:
		if not raw.has(group): continue
		if not raw[group] is Dictionary: return {"ok":false,"message":"地图天气参数格式无效。"}
		for key in data[group]:
			if not raw[group].has(key): continue
			var value = raw[group][key]
			if data[group][key] is String:
				if not value is String or value.length()!=6 or not value.is_valid_hex_number(false): return {"ok":false,"message":"地图天气颜色无效。"}
			elif data[group][key] is bool:
				if not value is bool: return {"ok":false,"message":"地图阴影设置无效。"}
			else:
				var bounds: Array = LIMITS[group][key]
				if not _in_range(value,bounds): return {"ok":false,"message":"地图天气数值超出允许范围。"}
			data[group][key] = value
	for key in ["time_preset","weather_preset"]:
		if raw.has(key):
			var allowed: Dictionary = TIMES if key=="time_preset" else CONDITIONS
			if not raw[key] is String or not allowed.has(raw[key]): return {"ok":false,"message":"地图氛围类型无效。"}
			data[key] = raw[key]
	for key in ADJUSTMENTS:
		if raw.has(key):
			if not _in_range(raw[key],ADJUSTMENTS[key]): return {"ok":false,"message":"地图氛围调整值无效。"}
			data[key] = raw[key]
	if not raw.has("time_preset"):
		var base := defaults()
		if data["sky"]!=base["sky"] or data["light"]!=base["light"]: data["time_preset"] = "custom"
	elif raw.has("sky") and not raw["sky"].has("brightness"):
		# Migrate only unchanged old preset recipes; preserve manual configurations.
		if data["time_preset"]=="morning" and data["sky"]["top_color"]=="79b9ef" and data["sky"]["bottom_color"]=="e8c7a0" and is_equal_approx(float(data["light"]["energy"]),0.8) and is_equal_approx(float(data["light"]["altitude"]),22.0):
			data["sky"]["brightness"] = 0.72
			data["light"]["energy"] = 1.1
		elif data["time_preset"]=="evening" and data["sky"]["top_color"]=="687dae" and data["sky"]["bottom_color"]=="dc9270" and is_equal_approx(float(data["light"]["energy"]),0.7) and is_equal_approx(float(data["light"]["altitude"]),12.0):
			data["sky"]["brightness"] = 0.45
			data["light"]["energy"] = 1.15
	_migrate_palette(data)
	return {"ok":true,"data":data}

static func _migrate_palette(data: Dictionary) -> void:
	var key: String = data["time_preset"]
	var sky: Dictionary = data["sky"]
	var light: Dictionary = data["light"]
	var old_morning: bool = key=="morning" and sky["top_color"]=="79b9ef" and sky["bottom_color"]=="e8c7a0" and light["color"]=="ffe1bb" and light["ambient_color"]=="c9c5be" and is_equal_approx(float(light["altitude"]),22.0) and is_equal_approx(float(light["energy"]),1.1) and is_equal_approx(float(sky["brightness"]),0.72)
	var old_evening: bool = key=="evening" and sky["top_color"]=="687dae" and sky["bottom_color"]=="dc9270" and light["color"]=="ffbf80" and light["ambient_color"]=="a3a5c2" and is_equal_approx(float(light["altitude"]),12.0) and is_equal_approx(float(light["energy"]),1.15) and is_equal_approx(float(sky["brightness"]),0.45)
	if not old_morning and not old_evening: return
	if not is_equal_approx(float(sky["clouds"]),0.4) or not is_equal_approx(float(sky["high_clouds"]),0.2): return
	if not is_equal_approx(float(light["ambient_energy"]),0.28 if old_morning else 0.24): return
	if not is_equal_approx(float(data["brightness"]),1.0) or not is_zero_approx(float(data["warmth"])): return
	var shadows: bool = light["shadows"]
	select_time(data,key)
	data["light"]["shadows"] = shadows

static func _in_range(value: Variant, bounds: Array) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=bounds[0] and float(value)<=bounds[1]

static func lighting(data: Dictionary) -> Dictionary:
	var result := Profile.defaults()
	var sky: Dictionary = data["sky"]
	var light: Dictionary = data["light"]
	result["g_top"] = Color(sky["top_color"])
	result["g_bottom"] = Color(sky["bottom_color"])
	result["g_clouds"] = sky["clouds"]
	result["g_high_clouds"] = sky["high_clouds"]
	result["g_light"] = Color(light["color"])
	result["g_energy"] = light["energy"]
	result["g_altitude"] = light["altitude"]
	result["g_azimuth"] = light["azimuth"]
	result["g_shadow"] = light["shadows"]
	result["g_ambient"] = Color(light["ambient_color"])
	result["g_ambient_energy"] = light["ambient_energy"]
	var warmth := float(data["warmth"])
	if not is_zero_approx(warmth):
		var tint := Color("ffd1a0") if warmth>0 else Color("b9d8ff")
		result["g_light"] = result["g_light"].lerp(tint,absf(warmth)*0.6)
		result["g_ambient"] = result["g_ambient"].lerp(tint,absf(warmth)*0.2)
	var daylight := clampf(float(sky["brightness"]),0.1,2.0)
	var dusk := clampf((1.0-daylight)/0.55,0.0,1.0)
	var cloud_tint_weight := dusk*0.25
	if data["time_preset"]!="noon" or not is_zero_approx(warmth): cloud_tint_weight = maxf(0.18,cloud_tint_weight)
	result["cloud_color"] = Color.WHITE.lerp(result["g_light"],cloud_tint_weight)
	result["cloud_shadow_color"] = Color("839bb6").lerp(Color("6f779a"),dusk*0.6)
	result["sun_color"] = result["g_light"]
	result["scatter_color"] = result["g_light"]*lerpf(0.16,0.3,dusk)
	result["sky_brightness"] = daylight
	result["astro_energy"] = lerpf(3.0,1.2,dusk)
	result["sun_visibility"] = 1.0
	var strength := float(data["weather_strength"])
	var condition: String = data["weather_preset"]
	result["coherent_sky"] = data["time_preset"]!="noon" or (condition!="clear" and strength>0.0) or not is_zero_approx(warmth)
	if not result["coherent_sky"]: result["scatter_color"] = Color(0.298039,0.298039,0.298039)
	if condition!="clear":
		var overcast := condition=="overcast"
		result["g_clouds"] = lerpf(float(result["g_clouds"]),0.95 if overcast else 0.72,strength)
		result["g_high_clouds"] = lerpf(float(result["g_high_clouds"]),0.7 if overcast else 0.45,strength)
		result["g_energy"] *= lerpf(1.0,0.45 if overcast else 0.72,strength)
		result["g_shadow_opacity"] *= lerpf(1.0,0.22 if overcast else 0.7,strength)
		result["sun_visibility"] = lerpf(1.0,0.2 if overcast else 0.75,strength)
		result["g_ambient_energy"] += (0.08 if overcast else 0.06)*strength*daylight
		result["sky_brightness"] *= lerpf(1.0,0.68 if overcast else 0.82,strength)
		result["g_ambient"] = result["g_ambient"].lerp(Color("d0d4dc"),(0.45 if overcast else 0.18)*strength)
		for key in ["g_top","g_bottom"]:
			var color: Color = result[key]
			var luminance := color.r*0.2126+color.g*0.7152+color.b*0.0722
			result[key] = color.lerp(Color(luminance*0.85,luminance*0.85,luminance*0.9),(0.65 if overcast else 0.2)*strength)
		result["cloud_color"] = result["cloud_color"].lerp(Color("d0d3d9"),strength*(0.9 if overcast else 0.3))
		result["cloud_shadow_color"] = result["cloud_shadow_color"].lerp(Color("969eac"),strength*(0.65 if overcast else 0.25))
		result["scatter_color"] *= lerpf(1.0,0.4 if overcast else 0.75,strength)
		result["astro_energy"] *= float(result["sun_visibility"])
	result["g_energy"] *= float(data["brightness"])
	result["g_ambient_energy"] *= float(data["brightness"])
	result["sky_brightness"] *= float(data["brightness"])
	return result

static func apply_scene(root: Node3D, data: Dictionary) -> void:
	var values := lighting(data)
	Profile.apply(root,values)
	var sky: ShaderMaterial = root.get_node("WorldEnvironment").environment.sky.sky_material
	sky.set_shader_parameter("show_sun_disk",true)
	sky.set_shader_parameter("sun_disk_visibility",values["sun_visibility"])
	sky.set_shader_parameter("clouds_light_color",values["cloud_color"])
	sky.set_shader_parameter("sun_scatter",values["scatter_color"])
	sky.set_shader_parameter("astro_intensity",values["astro_energy"])
	sky.set_shader_parameter("background_brightness",values["sky_brightness"])
	sky.set_shader_parameter("coherent_sky",values["coherent_sky"])
	sky.set_shader_parameter("clouds_shadow_color",values["cloud_shadow_color"])
	sky.set_shader_parameter("solar_color",values["sun_color"])
