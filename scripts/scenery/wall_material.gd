extends RefCounted

const PlankShader = preload("res://assets/scenery/materials/horizontal_planks.gdshader")
const LogShader = preload("res://assets/scenery/materials/round_logs.gdshader")
const TextureBank = preload("res://scripts/scenery/plank_texture_bank.gd")
const BarkBank = preload("res://scripts/scenery/bark_texture_bank.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const BOARD_LENGTH := TextureBank.BOARD_LENGTH # Five-foot boards, adjacent rows offset by half.
const BOARD_HEIGHT := TextureBank.BOARD_HEIGHT # One foot, matching the project's five-foot world scale.
const SEAM_HALF_WIDTH := 0.004
const GROOVE_RATIO := 0.12 # Fraction of each half-thickness; keeps unequal miters compatible.

static func create(surface: String, color: Color, length := 1.0, slopes := Vector2.ZERO, margins := Vector2.ZERO) -> Material:
	if Parameters.is_logs(surface):
		var logs := ShaderMaterial.new()
		logs.shader = LogShader
		if surface=="logs_bark": BarkBank.apply_to(logs)
		else: TextureBank.apply_to(logs)
		logs.set_shader_parameter("surface_color",color)
		return logs
	if Parameters.is_planks(surface):
		var wood := ShaderMaterial.new()
		wood.shader = PlankShader
		TextureBank.apply_to(wood)
		wood.set_shader_parameter("surface_color", color)
		wood.set_shader_parameter("board_height", BOARD_HEIGHT)
		wood.set_shader_parameter("board_length", BOARD_LENGTH)
		wood.set_shader_parameter("vertical_planks", surface == "planks_vertical")
		wood.set_shader_parameter("wall_length", length)
		wood.set_shader_parameter("end_slopes", slopes)
		wood.set_shader_parameter("end_margins", margins)
		wood.set_shader_parameter("seam_half_width", SEAM_HALF_WIDTH)
		return wood
	var gray := StandardMaterial3D.new()
	gray.albedo_color = color
	gray.roughness = 0.95
	return gray

static func color_of(material: Material) -> Color:
	if material is ShaderMaterial: return material.get_shader_parameter("surface_color")
	return (material as StandardMaterial3D).albedo_color

static func recolor(material: Material, color: Color) -> Material:
	var copy := material.duplicate() as Material
	if copy is ShaderMaterial: copy.set_shader_parameter("surface_color", color)
	else: (copy as StandardMaterial3D).albedo_color = color
	return copy

# The miter deformation stays inside the solid end pier, away from Boolean holes.
static func join_margins(length: float, half_depth: float, slopes: Vector2) -> Vector2:
	var insets := slopes.abs() * half_depth
	var extra := minf(0.025, (length - insets.x - insets.y) * 0.25)
	return Vector2(insets.x + extra if not is_zero_approx(slopes.x) else 0.0,
		insets.y + extra if not is_zero_approx(slopes.y) else 0.0)

static func _depth(u: float, y: float, half_depth: float, pattern: Vector2, vertical := false) -> float:
	var across := pattern.x + pattern.y * u if vertical else y
	var longitudinal := y if vertical else pattern.x + pattern.y * u
	var phase := fposmod(across, BOARD_HEIGHT)
	var side_seam := maxf(0.0, 1.0 - minf(phase, BOARD_HEIGHT - phase) / SEAM_HALF_WIDTH)
	var row := floori(across / BOARD_HEIGHT + 0.000001)
	var along := longitudinal + posmod(row, 2) * BOARD_LENGTH * 0.5
	var joint := fposmod(along + BOARD_LENGTH * 0.5, BOARD_LENGTH) - BOARD_LENGTH * 0.5
	var end_seam := maxf(0.0, 1.0 - absf(joint) / SEAM_HALF_WIDTH)
	return half_depth * (1.0 - GROOVE_RATIO * maxf(side_seam, end_seam))

static func _levels(end: float, period: float, half_width: float, origin := 0.0, direction := 1.0) -> Array[float]:
	var result: Array[float] = [0.0, end]
	var first := floori(minf(origin, origin + direction * end) / period) - 1
	var last := ceili(maxf(origin, origin + direction * end) / period) + 1
	for i in range(first, last + 1):
		for offset in [-half_width, 0.0, half_width]:
			var value := (i * period + float(offset) - origin) / direction
			if value > 0.0000001 and value < end - 0.0000001: result.append(value)
	result.sort()
	return result

# Both parity rows share a grid, so their horizontal boundaries have no T junctions.
static func plank_solid(length: float, height: float, half_depth: float, slopes: Vector2, material: Material, pattern := Vector2(0, 1), vertical := false) -> ArrayMesh:
	var ys := _levels(height, BOARD_LENGTH * 0.5 if vertical else BOARD_HEIGHT, SEAM_HALF_WIDTH)
	var xs := _levels(length, BOARD_HEIGHT if vertical else BOARD_LENGTH * 0.5, SEAM_HALF_WIDTH, pattern.x, pattern.y)
	var margins := join_margins(length, half_depth, slopes)
	for u in [margins.x, length - margins.y]:
		if u > 0.0000001 and u < length - 0.0000001:
			var duplicate := false
			for old in xs:
				if absf(old-u) < 0.0000001: duplicate = true
			if not duplicate: xs.append(u)
	xs.sort()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sign_z in [-1.0, 1.0]:
		for j in ys.size() - 1:
			for i in xs.size() - 1:
				var a := _point(xs[i], ys[j], sign_z, length, half_depth, slopes, margins, pattern, vertical)
				var b := _point(xs[i+1], ys[j], sign_z, length, half_depth, slopes, margins, pattern, vertical)
				var c := _point(xs[i+1], ys[j+1], sign_z, length, half_depth, slopes, margins, pattern, vertical)
				var d := _point(xs[i], ys[j+1], sign_z, length, half_depth, slopes, margins, pattern, vertical)
				# At a crossing, follow the crease where the two V grooves are equally deep.
				var center := _depth((xs[i]+xs[i+1])*0.5, (ys[j]+ys[j+1])*0.5, half_depth, pattern, vertical)
				var ac_error := absf((absf(a.z)+absf(c.z))*0.5-center)
				var bd_error := absf((absf(b.z)+absf(d.z))*0.5-center)
				_quad(tool, a, b, c, d, sign_z > 0, bd_error < ac_error - 0.0000001)
	# End caps retain the exact shared miter plane and scaled groove profile.
	for end in 2:
		var u: float = 0.0 if end == 0 else length
		for j in ys.size() - 1:
			_quad(tool, _point(u,ys[j],-1,length,half_depth,slopes,margins,pattern,vertical),
				_point(u,ys[j],1,length,half_depth,slopes,margins,pattern,vertical),
				_point(u,ys[j+1],1,length,half_depth,slopes,margins,pattern,vertical),
				_point(u,ys[j+1],-1,length,half_depth,slopes,margins,pattern,vertical), end == 0)
	for end in 2:
		var y: float = 0.0 if end == 0 else height
		for i in xs.size() - 1:
			_quad(tool, _point(xs[i],y,-1,length,half_depth,slopes,margins,pattern,vertical),
				_point(xs[i+1],y,-1,length,half_depth,slopes,margins,pattern,vertical),
				_point(xs[i+1],y,1,length,half_depth,slopes,margins,pattern,vertical),
				_point(xs[i],y,1,length,half_depth,slopes,margins,pattern,vertical), end == 0)
	tool.set_material(material)
	return tool.commit()

static func _point(u: float, y: float, side: float, length: float, half_depth: float, slopes: Vector2, margins: Vector2, pattern: Vector2, vertical: bool) -> Vector3:
	var z := side * _depth(u,y,half_depth,pattern,vertical)
	var slope := 0.0
	if margins.x > 0: slope += slopes.x * maxf(0, 1-u/margins.x)
	if margins.y > 0: slope += slopes.y * maxf(0, 1-(length-u)/margins.y)
	return Vector3(u+slope*z, y, z)

static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, reverse: bool, alternate := false) -> void:
	if alternate:
		_triangle(tool,a,b,d,reverse)
		_triangle(tool,b,c,d,reverse)
	else:
		_triangle(tool,a,b,c,reverse)
		_triangle(tool,a,c,d,reverse)

static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, reverse: bool) -> void:
	var cross := (c-a).cross(b-a)
	if reverse:
		var temp := b
		b = c
		c = temp
		cross = -cross
	for point in [a,b,c]:
		tool.set_normal(cross.normalized())
		tool.set_uv(Vector2(point.x,point.y))
		tool.add_vertex(point)
