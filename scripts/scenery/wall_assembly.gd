extends RefCounted

const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Openings = preload("res://scripts/scenery/opening_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const Instance = preload("res://scripts/scenery/opening_instance.gd")
const Wall = preload("res://scripts/scenery/wall_parameters.gd")

# A fresh build from the retained ORIGINAL wall plus current opening definitions.
# No cutting a previously baked result. Failure never mutates an existing instance.
static func build(wall: Dictionary, specs: Array, slopes := Vector2.ZERO, placement := Transform3D.IDENTITY, log_joins: Array = []) -> Dictionary:
	var error := Wall.validate(wall)
	if not error.is_empty(): return {"ok":false,"message":error}
	if not slopes.is_finite(): return {"ok":false,"message":"转角参数无效"}
	if not placement.is_finite(): return {"ok":false,"message":"墙体位置无效"}
	var layout := Openings.resolve(wall,specs)
	if not layout.ok: return layout
	# Wall generator validates the complete join context before we read its values.
	var result := await Generator.build(wall,slopes,placement,log_joins,layout.rects)
	if not result.ok: return result
	var insets: Vector2 = result.end_slopes.abs()*float(wall.thickness)*Wall.FEET*0.5
	if result.log_joins.size()==2:
		for end in 2:
			if result.log_joins[end].has("half_depth"):
				insets[end]=maxf(insets[end],float(result.log_joins[end].half_depth))
	if not insets.is_zero_approx():
		layout=Openings.resolve(wall,specs,insets)
		if not layout.ok: return layout
	var attachments: Array[Dictionary] = []
	for i in specs.size():
		var attachment := Builder.new().build(layout.specs[i],layout.rects[i],float(wall.thickness)*Wall.FEET)
		if not attachment.ok: return attachment
		attachments.append(attachment)
	result["attachments"]=attachments
	result["opening_specs"]=layout.specs
	result["assembly_version"]=Openings.VERSION
	return result

# Works for both old wall-generator results and new complete assemblies.
static func instantiate(result: Dictionary, opening_ids: Array[String] = []) -> Node3D:
	if not opening_ids.is_empty() and opening_ids.size()!=result.get("attachments",[]).size():
		push_error("门窗编号数量与组装结果不匹配")
		return null
	var root := Node3D.new()
	root.name="WallAssembly"
	root.add_child(Generator.instantiate_wall(result))
	for data in result.get("attachments",[]):
		var opening := Instance.new()
		opening.name="Opening%d"%root.get_child_count()
		opening.configure(data)
		if not opening_ids.is_empty(): opening.set_meta("layout_opening_id",opening_ids[root.get_child_count()-1])
		root.add_child(opening)
	root.set_meta("opening_specs",result.get("opening_specs",[]).duplicate(true))
	return root
