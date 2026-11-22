extends Node

const P = preload("res://scripts/scenery/opening_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
@export_dir var output_directory := "res://artifacts/opening-frame-alignment-2026-10-25/"
var _errors: Array[String] = []

func _ready() -> void:
	var count := 0
	for preset in ["wood_door","wood_window"]:
		for width in [1.0,3.0,6.0]:
			for thickness in [0.05,0.30]:
				var spec := P.defaults(preset)
				spec.width=width
				var hole := Rect2(Vector2(0.37,0.6),Vector2(width,spec.height)*0.2)
				var data := Builder.new().build(spec,hole,thickness)
				if not data.ok:
					_errors.append(data.message)
					continue
				for face in [-1,1]:
					var parts: Dictionary = {}
					for part in data.parts: parts[part.name]=part.bounds
					var left: AABB = parts["TrimSide0_%d"%face]
					var right: AABB = parts["TrimSide1_%d"%face]
					for name in ["TrimHead%d"%face]+(["TrimFoot%d"%face] if preset=="wood_window" else []):
						var horizontal: AABB = parts[name]
						if absf(horizontal.position.x-left.position.x)>0.000001 or absf(horizontal.end.x-right.end.x)>0.000001:
							_errors.append("%s %s width=%s: horizontal_right=%s vertical_right=%s"%[preset,name,width,horizontal.end.x,right.end.x])
				count+=1
	var report := {"ok":_errors.is_empty(),"recipes":count,"errors":_errors}
	var file := FileAccess.open(output_directory.path_join("alignment-check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if not _errors.is_empty(): push_error(_errors[0])
	print("OPENING_FRAME_ALIGNMENT ok=",_errors.is_empty()," recipes=",count," errors=",_errors.size())
	get_tree().quit(0 if _errors.is_empty() else 1)
