extends Node3D

signal pose_changed(angle: float)

var _spec: Dictionary
var _moving: StaticBody3D
var _angle := 0.0
var _max_angle := 110.0

# Configure once, before entering a tree. Assembly owns construction/replacement.
func configure(data: Dictionary) -> void:
	assert(_spec.is_empty(),"Opening instances are configured only once")
	_spec=data.spec.duplicate(true)
	_max_angle=float(data.get("max_open_angle",110.0))
	var fixed := StaticBody3D.new()
	fixed.name="FixedFrame"
	add_child(fixed)
	_mesh(fixed,data.fixed_mesh,"FrameMesh")
	_shapes(fixed,data.fixed_shapes)
	_moving=StaticBody3D.new()
	_moving.name="LeafPivot"
	_moving.position=data.hinge
	add_child(_moving)
	_mesh(_moving,data.moving_mesh,"LeafMesh")
	_mesh(_moving,data.glass_mesh,"GlassMesh")
	_shapes(_moving,data.moving_shapes)
	set_open_angle(float(_spec.angle))
	set_meta("opening_preset",_spec.preset)

func set_open_angle(angle: float) -> bool:
	if _spec.is_empty() or not is_finite(angle) or angle<0 or angle>_max_angle or (not _spec.leaf and not is_zero_approx(angle)):
		return false
	var sign_y := -1.0 if _spec.hinge=="left" else 1.0
	if _spec.swing=="back": sign_y=-sign_y
	_moving.rotation.y=deg_to_rad(angle)*sign_y
	var changed := not is_equal_approx(_angle,angle)
	_angle=angle
	if changed: pose_changed.emit(angle)
	return true

func get_open_angle() -> float:
	return _angle

func get_max_open_angle() -> float:
	return _max_angle

func parameters() -> Dictionary:
	var copy := _spec.duplicate(true)
	copy.angle=_angle
	return copy

func _mesh(parent: Node3D, mesh: ArrayMesh, label: String) -> void:
	if mesh.get_surface_count()==0: return
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.name=label
	visible_mesh.mesh=mesh
	if label=="GlassMesh": visible_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visible_mesh)

func _shapes(parent: StaticBody3D, shapes: Array) -> void:
	for entry in shapes:
		var collider := CollisionShape3D.new()
		collider.shape=entry.shape
		collider.transform=entry.transform
		parent.add_child(collider)
