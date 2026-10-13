extends Node3D

signal direction_changed(azimuth: float, altitude: float)
var camera: Camera3D
var radius := 12.0
var center := Vector3.ZERO
var marker: MeshInstance3D
var cage: MeshInstance3D
var dragging := false
var azimuth := 10.2
var altitude := 39.704
var follow_marker := false

func _ready() -> void:
	marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	marker.material_override = _material(Color("ffce55"))
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	cage = MeshInstance3D.new()
	cage.material_override = _material(Color("e9bd61"))
	cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cage)
	hide()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	return material

func configure(at: Vector3, extent: float, direction: float, elevation: float) -> void:
	center = at
	radius = maxf(8.0,extent)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for latitude in [0.0,30.0,60.0]:
		for step in range(96):
			mesh.surface_add_vertex(_point(step*TAU/96.0,deg_to_rad(latitude)))
			mesh.surface_add_vertex(_point((step+1)*TAU/96.0,deg_to_rad(latitude)))
	for longitude in range(8):
		for step in range(24):
			mesh.surface_add_vertex(_point(longitude*TAU/8.0,step*PI/48.0))
			mesh.surface_add_vertex(_point(longitude*TAU/8.0,(step+1)*PI/48.0))
	mesh.surface_end()
	cage.mesh = mesh
	sync(direction,elevation)

func _point(direction: float, elevation: float) -> Vector3:
	return center+Vector3(sin(direction)*cos(elevation),sin(elevation),cos(direction)*cos(elevation))*radius

func sync(direction: float, elevation: float) -> void:
	azimuth = direction
	altitude = elevation
	marker.position = _point(deg_to_rad(azimuth),deg_to_rad(altitude))
	# The sun marker keeps an accessible size when the camera moves.
	var scale_factor := maxf(0.2,camera.global_position.distance_to(marker.position)*0.025)
	marker.scale = Vector3.ONE*scale_factor

func start(point: Vector2) -> bool:
	if not visible: return false
	follow_marker = not camera.is_position_behind(marker.position) and camera.unproject_position(marker.position).distance_to(point)<=24.0
	var picked = _sphere_hit(point)
	if picked==null: return false
	dragging = true
	_update(picked)
	return true

func drag(point: Vector2) -> void:
	var picked = _sphere_hit(point)
	if picked!=null: _update(picked)

func _sphere_hit(point: Vector2) -> Variant:
	var origin := camera.project_ray_origin(point)-center
	var direction := camera.project_ray_normal(point)
	var b := origin.dot(direction)
	var discriminant := b*b-origin.length_squared()+radius*radius
	if discriminant<0.0: return null
	var hits: Array[Vector3] = []
	for distance_to_hit in [-b-sqrt(discriminant),-b+sqrt(discriminant)]:
		if distance_to_hit<0.0: continue
		var hit: Vector3 = origin+direction*float(distance_to_hit)
		if hit.y>=-0.001: hits.append(hit.normalized())
	if hits.is_empty(): return null
	if follow_marker and hits.size()==2:
		var current := (marker.position-center).normalized()
		return hits[0] if current.dot(hits[0])>=current.dot(hits[1]) else hits[1]
	return hits[0]

func _update(direction: Vector3) -> void:
	var next_azimuth := fposmod(rad_to_deg(atan2(direction.x,direction.z)),360.0)
	var next_altitude := clampf(rad_to_deg(asin(clampf(direction.y,0.0,1.0))),0.0,90.0)
	sync(next_azimuth,next_altitude)
	direction_changed.emit(next_azimuth,next_altitude)

func finish() -> void:
	dragging = false
	hide()
