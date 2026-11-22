extends Node

const P = preload("res://scripts/scenery/opening_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const OUTPUT := "res://artifacts/opening-closure-2026-10-25/"
var _errors: Array[String] = []
var _recipes := 0
var _poses := 0
var _collisions := 0
var _rejected := 0
const EPS := 0.000005

func _ready() -> void:
	for preset in ["wood_door","wood_window"]:
		var spec := P.defaults(preset)
		var hole := Rect2(0.2,0,0.6,float(spec.height)*0.2)
		var data := Builder.new().build(spec,hole,0.1)
		if not data.ok:
			_errors.append(data.message)
			continue
		var leaf: Rect2 = data.leaf_rect
		var actual_gap := leaf.position.x-hole.position.x-P.FRAME
		_check(actual_gap<=0.00201,"Closing side gap exceeds 3.1 mm: "+str(actual_gap*1524)+"mm")
		var stops := 0
		var planks := AABB()
		var have_planks := false
		for part in data.parts:
			if part.name.begins_with("Stop"): stops+=1
			if part.name.begins_with("DoorPlank"):
				planks=planks.merge(part.bounds) if have_planks else part.bounds
				have_planks=true
		_check(stops==(4 if preset=="wood_window" else 3),"Missing closure stops: "+preset)
		if have_planks:
			_check(absf(planks.size.x-leaf.size.x)<0.000001,"Outer door boards subtract extra clearance")
	for preset in ["wood_door","wood_window"]:
		for width in [1.0,3.0,6.0]:
			for side in ["left","right"]:
				for swing in ["front","back"]:
					for mounting in ["front","center","back"]:
						for thickness in [0.05,0.30]:
							var spec := P.defaults(preset)
							spec.width=width
							spec.hinge=side
							spec.swing=swing
							spec.mounting=mounting
							var data := Builder.new().build(spec,Rect2(Vector2(0.37,0.6),Vector2(width,spec.height)*0.2),thickness)
							if not data.ok:
								_errors.append(data.message)
								continue
							_recipes+=1
							var label := "%s width=%s %s/%s/%s t=%s"%[preset,width,side,swing,mounting,thickness]
							_stop_coverage(data,label)
							for angle in range(0,111,2):
								if angle>float(data.max_open_angle):
									var invalid := spec.duplicate(true)
									invalid.angle=angle
									_check(not Builder.new().build(invalid,data.hole,thickness).ok,label+": unsafe angle accepted")
									_rejected+=1
									continue
								_check_pose(data,angle,label)
	_check(_recipes==144,"Asset construction did not finish all recipes")
	var file := FileAccess.open(OUTPUT+"closure-check.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":_errors.is_empty(),"recipes":_recipes,"poses":_poses,"invalid_poses_rejected":_rejected,"collisions":_collisions,"error_count":_errors.size(),"errors":_errors},"\t"))
	file.close()
	if not _errors.is_empty(): push_error(_errors[0])
	print("OPENING_CLOSURE_CHECK ok=",_errors.is_empty()," errors=",_errors.size())
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value: _errors.append(message)

func _stop_coverage(data: Dictionary, label: String) -> void:
	var clear := P.frame_opening(data.hole,data.spec)
	var gap: float = data.leaf_rect.position.x-clear.position.x
	var points: Array[Vector2] = [Vector2(clear.position.x+gap*0.95,clear.get_center().y),Vector2(clear.end.x-gap*0.95,clear.get_center().y),
		Vector2(clear.get_center().x,clear.end.y-P.GAP*0.5)]
	if data.spec.preset=="wood_window": points.append(Vector2(clear.get_center().x,clear.position.y+P.GAP*0.5))
	for point in points:
		var covered := false
		for part in data.parts:
			if not part.name.begins_with("Stop"): continue
			var box: AABB = part.bounds
			if Rect2(Vector2(box.position.x,box.position.y),Vector2(box.size.x,box.size.y)).has_point(point): covered=true
		_check(covered,label+": closing clearance has no timber stop behind it")

# Offline OBB geometry at authored poses. No physics world or input events.
func _check_pose(data: Dictionary, angle: float, label: String) -> void:
	_poses+=1
	var sign_y := -1.0 if data.spec.hinge=="left" else 1.0
	if data.spec.swing=="back": sign_y=-sign_y
	var pose := Transform3D(Basis(Vector3.UP,deg_to_rad(angle)*sign_y),data.hinge)
	for moving in data.moving_shapes:
		var t: Transform3D = pose*moving.transform
		var size: Vector3 = moving.shape.size
		var broad := t*AABB(-size*0.5,size)
		for fixed in data.fixed_shapes:
			var fixed_size: Vector3 = fixed.shape.size
			if not broad.intersects(fixed.transform*AABB(-fixed_size*0.5,fixed_size)): continue
			if _overlap(t,size,fixed.transform,fixed_size):
				_collisions+=1
				_errors.append(label+": %s intersects %s at %s degrees"%[moving.get("name","moving"),fixed.get("name","fixed"),angle])
				return

func _overlap(a: Transform3D, a_size: Vector3, b: Transform3D, b_size: Vector3) -> bool:
	var axes: Array[Vector3] = [a.basis.x,a.basis.y,a.basis.z,b.basis.x,b.basis.y,b.basis.z]
	for i in 3:
		for j in 3:
			var cross := a.basis[i].cross(b.basis[j])
			if cross.length_squared()>0.0000001: axes.append(cross.normalized())
	var delta := b.origin-a.origin
	for axis in axes:
		var ra := 0.0
		var rb := 0.0
		for i in 3:
			ra+=absf(axis.dot(a.basis[i]))*a_size[i]*0.5
			rb+=absf(axis.dot(b.basis[i]))*b_size[i]*0.5
		if ra+rb-absf(axis.dot(delta))<=EPS: return false
	return true
