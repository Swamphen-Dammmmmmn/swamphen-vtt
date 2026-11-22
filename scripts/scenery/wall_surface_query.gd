extends RefCounted

const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const W = preload("res://scripts/scenery/wall_parameters.gd")

# Input and output ray points use the workspace coordinate system (world for an
# identity workspace). Hits include aperture voids: a dragged window keeps its host.
static func project(wall: Dictionary, origin: Vector3, direction: Vector3, face: int) -> Dictionary:
	if face not in [-1,1] or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx(): return Data.fail("墙面射线无效")
	var inverse: Transform3D = wall.transform.affine_inverse()
	var from: Vector3 = inverse*origin
	var ray: Vector3 = inverse.basis*direction.normalized()
	if absf(ray.z)<0.000001: return Data.fail("视线与墙面平行")
	var z := float(wall.parameters.thickness)*W.FEET*0.5*face
	var distance := (z-from.z)/ray.z
	if distance<0: return Data.fail("墙面在视线后方")
	var point := from+ray*distance
	return {"ok":true,"message":"","point_feet":Vector2(point.x,point.y)/W.FEET,
		"point":wall.transform*point,"distance":distance,"face":face,"wall_id":wall.id}

static func pick(layout: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var closest := Data.fail("未指向可布置的墙面")
	var distance := INF
	for wall in layout.walls:
		for face in [-1,1]:
			var hit := project(wall,origin,direction,face)
			if not hit.ok or hit.distance>=distance: continue
			var xy: Vector2 = hit.point_feet
			if xy.x<0 or xy.x>wall.parameters.length or xy.y<0 or xy.y>wall.parameters.height: continue
			hit["opening_id"]=""
			for item in wall.openings:
				var at := Data.anchor(wall.parameters,item.spec)
				var rect := Rect2(at-Vector2(float(item.spec.width)*0.5,0),Vector2(item.spec.width,item.spec.height))
				if rect.grow(P.OVERHANG/W.FEET).has_point(xy): hit.opening_id=item.id
			closest=hit
			distance=hit.distance
	return closest
