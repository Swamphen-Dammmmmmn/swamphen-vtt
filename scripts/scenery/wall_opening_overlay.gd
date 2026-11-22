extends Node3D

# Reusable 3D feedback. No input or authority over layout; never adds collision.
const P = preload("res://scripts/scenery/opening_parameters.gd")
const W = preload("res://scripts/scenery/wall_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
var _preview_root: Node3D
var _selected: MeshInstance3D

func show_selection(layout: Dictionary, id: String) -> void:
	if _selected!=null:
		_selected.queue_free()
		_selected=null
	var at := Data.find_opening(layout,id)
	if at.x<0: return
	var wall: Dictionary = layout.walls[at.x]
	var spec: Dictionary = wall.openings[at.y].spec
	_selected=_outline(wall,spec,T.BRAND)
	add_child(_selected)

func show_preview(preview: Dictionary) -> void:
	if _preview_root!=null:
		remove_child(_preview_root)
		_preview_root.queue_free()
		_preview_root=null
	if preview.is_empty() or not preview.has_all(["wall","spec"]): return
	var wall: Dictionary = preview.wall
	var spec: Dictionary = preview.spec
	var color: Color = T.SUCCESS if preview.ok else T.DANGER
	_preview_root=Node3D.new()
	add_child(_preview_root)
	_preview_root.add_child(_outline(wall,spec,color))
	if not P.validate(spec).is_empty(): return
	var hole := Rect2((Data.anchor(wall.parameters,spec)-Vector2(float(spec.width)*0.5,0))*W.FEET,Vector2(spec.width,spec.height)*W.FEET)
	var generated := Builder.new().build(spec,hole,float(wall.parameters.thickness)*W.FEET)
	if not generated.ok: return
	var pose := Node3D.new()
	pose.transform=wall.transform
	_preview_root.add_child(pose)
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(color,0.42)
	var hinge := Node3D.new()
	hinge.position=generated.hinge
	var sign_y := -1.0 if spec.hinge=="left" else 1.0
	if spec.swing=="back": sign_y=-sign_y
	hinge.rotation.y=deg_to_rad(float(spec.angle))*sign_y
	pose.add_child(hinge)
	for key in ["fixed_mesh","moving_mesh","glass_mesh"]:
		if generated[key].get_surface_count()==0: continue
		var piece := MeshInstance3D.new()
		piece.mesh=generated[key]
		piece.material_override=material
		piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(pose if key=="fixed_mesh" else hinge).add_child(piece)

func _outline(wall: Dictionary, spec: Dictionary, color: Color) -> MeshInstance3D:
	var at := Data.anchor(wall.parameters,spec)*W.FEET
	var left := at.x-float(spec.width)*W.FEET*0.5
	var right := left+float(spec.width)*W.FEET
	var bottom := at.y
	var top := bottom+float(spec.height)*W.FEET
	var depth := float(wall.parameters.thickness)*W.FEET*0.5+0.008
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for z in [-depth,depth]:
		var points := [Vector3(left,bottom,z),Vector3(right,bottom,z),Vector3(right,top,z),Vector3(left,top,z)]
		for i in 4:
			mesh.surface_add_vertex(points[i])
			mesh.surface_add_vertex(points[(i+1)%4])
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	var result := MeshInstance3D.new()
	result.mesh=mesh
	result.transform=wall.transform
	result.material_override=material
	result.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result
