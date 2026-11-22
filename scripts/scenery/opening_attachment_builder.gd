extends RefCounted

const P = preload("res://scripts/scenery/opening_parameters.gd")
const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const TimberShader = preload("res://assets/scenery/materials/opening_timber.gdshader")
const DOOR_RAIL_LEVELS := [0.22,0.78]
const DOOR_STRAP := 0.10 * Wall.FEET
const HINGE_RADIUS := P.GAP * 0.65 # pin stays clear of the actual fitting gap
const MAX_STRETCH := 1.6 # members up to 1.6 tiles are scaled into one tile; longer ones mirror-fold

# One build creates material-batched meshes, not one display node per plank.
# Shapes stay separate primitives, directly parented to their own body at instantiate.
var _tools: Dictionary = {}
var _shapes := {"fixed":[],"moving":[]}
var _parts: Array[Dictionary] = []
var _spec: Dictionary
var _materials: Dictionary
var _piece := 0
var _pivot_offset := Vector3.ZERO
var _side_gap := P.GAP
var _stop_lip := P.STOP_LIP

func build(spec: Dictionary, hole: Rect2, thickness: float) -> Dictionary:
	var error := P.validate(spec)
	if not error.is_empty(): return {"ok":false,"message":error}
	if not hole.position.is_finite() or not hole.size.is_finite() or not is_finite(thickness) or thickness<=0:
		return {"ok":false,"message":"附加件的洞口或墙厚无效"}
	if not hole.size.is_equal_approx(Vector2(spec.width,spec.height)*Wall.FEET):
		return {"ok":false,"message":"附加件尺寸与洞口定义不一致"}
	if spec.angle>P.max_open_angle(spec):
		return {"ok":false,"message":"当前安装深度最多开启90度；超过90度请改为向安装面开启"}
	_tools.clear()
	_shapes={"fixed":[],"moving":[]}
	_parts.clear()
	_piece=0
	_pivot_offset=Vector3.ZERO
	_spec=spec.duplicate(true)
	_side_gap=P.side_gap(hole,spec)
	_stop_lip=P.stop_lip(hole,spec)
	_materials=_make_materials(spec)
	var window: bool = spec.preset.ends_with("window")
	var f := P.FRAME
	var bottom := f if window else (0.10*Wall.FEET if spec.threshold else 0.0)
	if spec.frame:
		for side in 2:
			_box("Jamb%d"%side,"fixed","wood",Vector3(hole.position.x+f*0.5+(hole.size.x-f)*side,hole.position.y+(hole.size.y-f+bottom)*0.5,0),
				Vector3(f,hole.size.y-f-bottom,thickness+0.002),1)
		_box("Lintel","fixed","wood",Vector3(hole.get_center().x,hole.end.y-f*0.5,0),Vector3(hole.size.x,f,thickness+0.002),0)
	if window and spec.frame or spec.threshold:
		_box("BottomFrame","fixed","wood",Vector3(hole.get_center().x,hole.position.y+bottom*0.5,0),Vector3(hole.size.x,bottom,thickness+0.002),0)
	if spec.trim: _trim(hole,thickness,window)
	if spec.sill_board:
		_box("Sill","fixed","wood",Vector3(hole.get_center().x,hole.position.y-0.06*Wall.FEET,0.10*Wall.FEET),
			Vector3(hole.size.x+2*P.SILL_OVERHANG,0.12*Wall.FEET,thickness+0.7*Wall.FEET),0)
	var leaf := P.leaf_rect(hole,spec)
	var depth := P.WINDOW_DEPTH if window else P.DOOR_DEPTH
	if spec.frame and spec.leaf: _stops(hole,thickness,window,depth)
	# Pivot lies on the visible barrel axis; offset the leaf geometry around it.
	var back_ledge := P.DOOR_RAIL_DEPTH if not window and spec.swing=="back" else 0.0
	var hinge_offset := (depth*0.5+back_ledge+P.HINGE_OFFSET)*(1.0 if spec.swing=="front" else -1.0)
	var hinge := Vector3(leaf.position.x if spec.hinge=="left" else leaf.end.x,leaf.position.y,P.mounting_z(thickness,spec)+hinge_offset)
	_pivot_offset=Vector3(0,0,hinge_offset)
	if spec.leaf:
		var direction := 1.0 if spec.hinge=="left" else -1.0
		if window: _window(leaf.size,direction)
		else: _door(leaf.size,direction)
		if spec.hardware: _hardware(leaf.size,direction,window,hinge,thickness)
	var meshes := {"fixed":ArrayMesh.new(),"moving":ArrayMesh.new()}
	var glass := ArrayMesh.new()
	for key in _tools:
		var tool: SurfaceTool = _tools[key]
		tool.generate_tangents()
		var group: String = key.get_slice(":",0)
		var material_key: String = key.get_slice(":",1)
		tool.set_material(_materials[material_key])
		tool.commit(glass if material_key=="glass" else meshes[group])
	return {"ok":true,"message":"","fixed_mesh":meshes.fixed,"moving_mesh":meshes.moving,"glass_mesh":glass,
		"fixed_shapes":_shapes.fixed.duplicate(true),"moving_shapes":_shapes.moving.duplicate(true),
		"parts":_parts.duplicate(true),"hinge":hinge,"spec":spec.duplicate(true),"hole":hole,"thickness":thickness,
		"leaf_rect":leaf,"max_open_angle":P.max_open_angle(spec),"version":P.VERSION}

func _trim(hole: Rect2, thickness: float, window: bool) -> void:
	var width := P.FRAME+P.OVERHANG
	for face in [-1.0,1.0]:
		var z: float = face*(thickness*0.5+P.TRIM_DEPTH*0.5)
		var side_height := hole.size.y-P.FRAME*(2.0 if window else 1.0)
		for side in 2:
			# Anchor each jamb to ITS opening edge. Both extend OVERHANG outwards;
			# offsetting the second by size.x-FRAME omitted the right overhang.
			var x := hole.position.x+(P.FRAME-P.OVERHANG)*0.5 if side==0 else hole.end.x+(P.OVERHANG-P.FRAME)*0.5
			_box("TrimSide%d_%d"%[side,int(face)],"fixed","wood",
				Vector3(x,hole.position.y+(P.FRAME if window else 0.0)+side_height*0.5,z),
				Vector3(width,side_height,P.TRIM_DEPTH),1)
		_box("TrimHead%d"%int(face),"fixed","wood",Vector3(hole.get_center().x,hole.end.y+(P.OVERHANG-P.FRAME)*0.5,z),
			Vector3(hole.size.x+2*P.OVERHANG,width,P.TRIM_DEPTH),0)
		if window:
			_box("TrimFoot%d"%int(face),"fixed","wood",Vector3(hole.get_center().x,hole.position.y+(P.FRAME-P.OVERHANG)*0.5,z),
				Vector3(hole.size.x+2*P.OVERHANG,width,P.TRIM_DEPTH),0)

# A real fixed timber rebate, behind the closing face; it covers the fitting
# clearance without enlarging the sash or blocking its opening direction.
func _stops(hole: Rect2, thickness: float, window: bool, depth: float) -> void:
	var clear := P.frame_opening(hole,_spec)
	var sign_z := 1.0 if _spec.swing=="front" else -1.0
	var z := P.mounting_z(thickness,_spec)-sign_z*(depth*0.5+P.STOP_CLEARANCE+P.STOP_DEPTH*0.5)
	var embed := P.FRAME*0.5
	var bottom_stop: bool = window or _spec.threshold
	var start_y := clear.position.y+(_stop_lip if bottom_stop else 0.0)
	var end_y := clear.end.y-_stop_lip
	for side in 2:
		var x := clear.position.x+(_stop_lip-embed)*0.5 if side==0 else clear.end.x+(embed-_stop_lip)*0.5
		_box("StopSide%d"%side,"fixed","wood",Vector3(x,(start_y+end_y)*0.5,z),Vector3(embed+_stop_lip,end_y-start_y,P.STOP_DEPTH),1)
	_box("StopHead","fixed","wood",Vector3(clear.get_center().x,clear.end.y+(embed-_stop_lip)*0.5,z),
		Vector3(clear.size.x+2*embed,embed+_stop_lip,P.STOP_DEPTH),0)
	if bottom_stop:
		_box("StopFoot","fixed","wood",Vector3(clear.get_center().x,clear.position.y+(_stop_lip-embed)*0.5,z),
			Vector3(clear.size.x+2*embed,embed+_stop_lip,P.STOP_DEPTH),0)

func _door(size: Vector2, direction: float) -> void:
	var count := maxi(3,ceili(size.x/(0.65*Wall.FEET)))
	var pitch := size.x/count
	for i in count:
		# Board joints are internal only; do not deduct another half-joint from
		# the outside edges after leaf_rect already reserved its fitting gap.
		var start := i*pitch+(0.006*Wall.FEET if i>0 else 0.0)
		var end := (i+1)*pitch-(0.006*Wall.FEET if i<count-1 else 0.0)
		_box("DoorPlank%d"%i,"moving","wood",Vector3(direction*(start+end)*0.5,size.y*0.5,0),Vector3(end-start,size.y,P.DOOR_DEPTH),1)
	var rail_depth := P.DOOR_RAIL_DEPTH
	# Keep back ledges out of the stop lip and within the lock-jamb sweep radius.
	var sweep_z := P.DOOR_DEPTH+P.HINGE_OFFSET+rail_depth
	var sweep_x := sqrt(maxf(0.0,pow(size.x+_side_gap-_stop_lip,2)-sweep_z*sweep_z))
	var inset := maxf(_stop_lip-_side_gap+P.STOP_CLEARANCE,size.x-sweep_x+P.STOP_CLEARANCE)
	var rail_width := minf(size.x*0.90,size.x-inset*2)
	for level in DOOR_RAIL_LEVELS:
		_box("DoorRail%s"%level,"moving","wood",Vector3(direction*size.x*0.5,size.y*level,-(P.DOOR_DEPTH+rail_depth)*0.5),
			Vector3(rail_width,P.DOOR_RAIL,rail_depth),0)
	var brace_width := 0.16*Wall.FEET
	var delta := Vector2(direction*minf(size.x*0.72,size.x-2*inset-brace_width),size.y*0.56-P.DOOR_RAIL)
	_box("DoorBrace","moving","wood",Vector3(direction*size.x*0.5,size.y*0.5,-(P.DOOR_DEPTH+rail_depth)*0.5),
		Vector3(delta.length(),brace_width,rail_depth),0,atan2(delta.y,delta.x))

func _window(size: Vector2, direction: float) -> void:
	var rail := P.SASH_RAIL
	for side in 2:
		_box("SashSide%d"%side,"moving","wood",Vector3(direction*(rail*0.5+(size.x-rail)*side),size.y*0.5,0),Vector3(rail,size.y,P.WINDOW_DEPTH),1)
	for side in 2:
		_box("SashRail%d"%side,"moving","wood",Vector3(direction*size.x*0.5,rail*0.5+(size.y-rail)*side,0),Vector3(size.x-rail*2,rail,P.WINDOW_DEPTH),0)
	var bar := 0.075*Wall.FEET if _spec.mullions else 0.0
	if _spec.mullions:
		_box("MullionVertical","moving","wood",Vector3(direction*size.x*0.5,size.y*0.5,0),Vector3(bar,size.y-rail*2,P.WINDOW_DEPTH*0.75),1)
		for side in 2:
			_box("MullionHorizontal%d"%side,"moving","wood",Vector3(direction*(rail+(size.x-rail*2-bar)*0.25+(size.x-rail*2+bar)*0.5*side),size.y*0.5,0),
				Vector3((size.x-rail*2-bar)*0.5,bar,P.WINDOW_DEPTH*0.75),0)
	if _spec.glass:
		var count := 2 if _spec.mullions else 1
		var pane := (size-Vector2.ONE*(rail*2+bar))/count
		for x in count:
			for y in count:
				_box("Glass%d_%d"%[x,y],"moving","glass",Vector3(direction*(rail+pane.x*0.5+x*(pane.x+bar)),rail+pane.y*0.5+y*(pane.y+bar),0),
					Vector3(pane.x,pane.y,0.018*Wall.FEET),0)

func _hardware(size: Vector2, direction: float, window: bool, hinge: Vector3, thickness: float) -> void:
	var depth := P.WINDOW_DEPTH if window else P.DOOR_DEPTH
	var hinge_face := 1.0 if _spec.swing=="front" else -1.0
	var plate := 0.025*Wall.FEET
	# Window hinges are compact butts sized from the sash stile; doors keep strap hinges.
	var knuckle := minf(0.28*Wall.FEET,size.y*0.3) if window else 0.22*Wall.FEET
	var fixed_length := P.SASH_RAIL*0.7 if window else 0.14*Wall.FEET
	# Fixed leaves lie on the frame/trim/reveal face across the mounting gap, within its depth.
	var frame_face := hinge.x-direction*_side_gap
	# Six-sided cylinder's X support is cos(30°)*radius, not its circumradius.
	var fixed_plate := _side_gap-HINGE_RADIUS*cos(PI/6.0)
	var cover := thickness*0.5+(P.TRIM_DEPTH if _spec.trim else 0.0)
	var reach := Vector2(hinge.z,hinge.z-hinge_face*fixed_length)
	var z_range := Vector2(maxf(minf(reach.x,reach.y),-cover),minf(maxf(reach.x,reach.y),cover))
	for i in 2:
		var y := _hinge_level(size,i,window)
		# Six-sided barrels on the pivot axis; radius stays inside the gap so they clear the frame.
		_cylinder("Hinge%d"%i,"moving",Vector3(0,y,_pivot_offset.z),HINGE_RADIUS,knuckle)
		if window:
			_box("HingeLeaf%d"%i,"moving","metal",Vector3(direction*P.SASH_RAIL*0.35,y,hinge_face*(depth+plate)*0.5),
				Vector3(P.SASH_RAIL*0.7,knuckle,plate),1,0,false)
		else:
			_box("HingeStrap%d"%i,"moving","metal",Vector3(direction*(0.012*Wall.FEET+size.x*0.15),y,hinge_face*(depth+plate)*0.5),
				Vector3(size.x*0.30,DOOR_STRAP,plate),0,0,false)
			# Bent neck bridges the small pin to its strap; back-swinging doors
			# also need to clear the thickness of the back ledges.
			var seat := hinge_face*depth*0.5
			_box("HingeNeck%d"%i,"moving","metal",Vector3(direction*0.02*Wall.FEET,y,(seat+_pivot_offset.z)*0.5),
				Vector3(0.04*Wall.FEET,DOOR_STRAP,absf(seat-_pivot_offset.z)),2,0,false)
		if z_range.y-z_range.x>0.001:
			_box("HingeFixedLeaf%d"%i,"fixed","metal",Vector3(frame_face+direction*fixed_plate*0.5,hinge.y+y,(z_range.x+z_range.y)*0.5),
				Vector3(fixed_plate,knuckle,z_range.y-z_range.x),2,0,false)
	for face in [-1.0,1.0]:
		if window:
			# Casement fastener: base centred on the lock stile, short stem, lever hanging inside the stile.
			var lock_x := direction*(size.x-P.SASH_RAIL*0.5)
			var lock_y := size.y*0.48
			_box("HandlePlate%d"%int(face),"moving","metal",Vector3(lock_x,lock_y,face*(depth*0.5+0.01*Wall.FEET)),
				Vector3(P.SASH_RAIL*0.6,0.24*Wall.FEET,0.02*Wall.FEET),1,0,false)
			_box("HandleStem%d"%int(face),"moving","metal",Vector3(lock_x,lock_y,face*(depth*0.5+0.045*Wall.FEET)),
				Vector3(0.04*Wall.FEET,0.04*Wall.FEET,0.09*Wall.FEET),2,0,false)
			_box("HandleGrip%d"%int(face),"moving","metal",Vector3(lock_x,lock_y-0.06*Wall.FEET,face*(depth*0.5+0.11*Wall.FEET)),
				Vector3(0.05*Wall.FEET,0.18*Wall.FEET,0.04*Wall.FEET),1,0,false)
			continue
		# Door handle keeps its proportions; plate and stem now seat on the plank face exactly.
		var x := direction*(size.x-0.22*Wall.FEET)
		_box("HandlePlate%d"%int(face),"moving","metal",Vector3(x,size.y*0.48,face*(depth+plate)*0.5),Vector3(0.11*Wall.FEET,0.30*Wall.FEET,plate),1,0,false)
		_box("HandleStem%d"%int(face),"moving","metal",Vector3(x,size.y*0.48,face*(depth*0.5+0.08*Wall.FEET)),Vector3(0.05*Wall.FEET,0.05*Wall.FEET,0.16*Wall.FEET),2,0,false)
		_box("HandleGrip%d"%int(face),"moving","metal",Vector3(x-direction*0.06*Wall.FEET,size.y*0.48,face*(depth*0.5+0.18*Wall.FEET)),
			Vector3(0.19*Wall.FEET,0.065*Wall.FEET,0.06*Wall.FEET),0,0,false)

# Leaf-local hinge height. Door straps sit just outside the back ledges, so either swing
# keeps them on bare planks; short doors fall back to the inner side of the ledge.
func _hinge_level(size: Vector2, index: int, window: bool) -> float:
	if window: return size.y*(0.2 if index==0 else 0.8)
	var level: float = DOOR_RAIL_LEVELS[index]*size.y
	var clear := (P.DOOR_RAIL+DOOR_STRAP)*0.5+0.02*Wall.FEET
	var outward := -1.0 if index==0 else 1.0
	var y := level+outward*clear
	if y-DOOR_STRAP*0.5<0 or y+DOOR_STRAP*0.5>size.y: y=level-outward*clear
	return y

func _box(label: String, group: String, material: String, center: Vector3, size: Vector3, grain: int, rotation_z := 0.0, collidable := true) -> void:
	if group=="moving": center-=_pivot_offset
	var mesh := BoxMesh.new()
	mesh.size=size
	var transform := Transform3D(Basis(Vector3.BACK,rotation_z),center)
	_append(label,group,material,mesh,transform,grain)
	if collidable:
		var shape := BoxShape3D.new()
		shape.size=size
		_shapes[group].append({"shape":shape,"transform":transform,"name":label})

func _cylinder(label: String, group: String, center: Vector3, radius: float, height: float) -> void:
	# Barrels are metal-only and never collide, matching the previous generators.
	if group=="moving": center-=_pivot_offset
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=6
	mesh.rings=0
	_append(label,group,"metal",mesh,Transform3D(Basis.IDENTITY,center),1)

func _append(label: String, group: String, material: String, mesh: PrimitiveMesh, transform: Transform3D, grain: int) -> void:
	var key := group+":"+material
	if not _tools.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key]=surface
	var tool: SurfaceTool = _tools[key]
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var layer := Bank.layer_for(_piece,0,0,int(_spec.seed))
	var size := mesh.get_aabb().size
	# Side grain is measured from each member's own minimum end, so a repeat seam can
	# never land in the middle of a member (the old centred projection put UV 0 there).
	var tile := Vector2(Bank.BOARD_LENGTH,Bank.BOARD_HEIGHT)
	var fold := false
	var maps: Array[Vector2] = [] # per local axis: (scale, in-tile offset)
	for axis in 3:
		var extent := size[axis]
		var target := tile.x if axis==grain else tile.y
		var seed_value := _unit_hash(_piece,axis)
		if extent<=target: maps.append(Vector2(1.0,seed_value*(target-extent)))
		elif extent<=target*MAX_STRETCH: maps.append(Vector2(target/extent,0.0))
		else:
			maps.append(Vector2(1.0,seed_value*target))
			fold=true
	_piece+=1
	for i in indices:
		var normal := normals[i]
		var along := Vector3.ZERO
		along[grain]=1.0
		var end_grain := absf(normal.dot(along))>0.9
		if end_grain:
			along=Vector3.ZERO
			along[(grain+1)%3]=1.0
		var across := normal.cross(along).normalized()
		var vertex := vertices[i]
		var uv := Vector2(vertex.dot(along),vertex.dot(across))
		if not end_grain:
			var across_axis := _axis_of(across)
			var u: Vector2 = maps[grain]
			var v: Vector2 = maps[across_axis]
			uv=Vector2((uv.x+size[grain]*0.5)*u.x+u.y,(uv.y+size[across_axis]*0.5)*v.x+v.y)
		tool.set_uv(uv)
		tool.set_normal(transform.basis*normal)
		tool.set_color(Color(layer/255.0,1.0 if end_grain else 0.0,1.0 if fold and not end_grain else 0.0,1))
		tool.add_vertex(transform*vertex)
	_parts.append({"name":label,"group":group,"material":material,"bounds":transform*mesh.get_aabb(),"transform":transform,"layer":layer,"triangles":indices.size()/3})

func _unit_hash(piece: int, axis: int) -> float:
	return float(posmod(hash([int(_spec.seed),piece,axis]),10007))/10007.0

static func _axis_of(direction: Vector3) -> int:
	var value := direction.abs()
	return 0 if value.x>=value.y and value.x>=value.z else (1 if value.y>=value.z else 2)

static func _make_materials(spec: Dictionary) -> Dictionary:
	var wood := ShaderMaterial.new()
	wood.shader=TimberShader
	Bank.apply_to(wood)
	wood.set_shader_parameter("surface_color",spec.wood_color)
	var metal := StandardMaterial3D.new()
	metal.albedo_color=spec.metal_color
	metal.metallic=0.65
	metal.roughness=0.7
	var glass := StandardMaterial3D.new()
	glass.albedo_color=spec.glass_color
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness=0.18
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	return {"wood":wood,"metal":metal,"glass":glass}
