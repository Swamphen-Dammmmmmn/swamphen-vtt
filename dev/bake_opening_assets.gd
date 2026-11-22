extends Node

const P = preload("res://scripts/scenery/opening_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const Asset = preload("res://scripts/scenery/opening_asset.gd")
const OUTPUT := "res://assets/scenery/openings/"

func _ready() -> void:
	if DirAccess.make_dir_recursive_absolute(OUTPUT)!=OK:
		push_error("Cannot create opening asset directory")
		get_tree().quit(1)
		return
	var catalog: Array[Dictionary] = []
	for preset in ["wood_door","wood_window"]:
		var spec := P.defaults(preset)
		var result := Builder.new().build(spec,Rect2(Vector2.ZERO,Vector2(spec.width,spec.height)*0.2),0.5*0.2)
		if not result.ok:
			push_error(result.message)
			get_tree().quit(1)
			return
		var suffix := "%02d"%P.VERSION
		var path: String = OUTPUT+preset+"_"+suffix+".tres"
		if FileAccess.file_exists(path):
			var previous = load(path)
			if previous.generator_version!=P.VERSION or previous.parameters()!=spec:
				push_error("Existing opening asset differs; choose explicit new version instead of overwriting")
				get_tree().quit(1)
				return
		else:
			var asset := Asset.new()
			asset.generator_version=P.VERSION
			asset.generated=result
			if ResourceSaver.save(asset,path)!=OK:
				push_error("Cannot save "+path)
				get_tree().quit(1)
				return
		var restored = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var instance = restored.instantiate()
		if instance==null or restored.parameters()!=spec or restored.generated.fixed_mesh.get_faces()!=result.fixed_mesh.get_faces() or restored.generated.moving_mesh.get_faces()!=result.moving_mesh.get_faces():
			push_error("Opening asset round trip failed")
			get_tree().quit(1)
			return
		instance.free()
		catalog.append({"id":"opening_"+preset+"_"+suffix,"path":path,"preset":preset,"generator_version":P.VERSION,
			"hole_width_feet":spec.width,"hole_height_feet":spec.height,"reference_wall_thickness_feet":0.5,
			"triangles":(result.fixed_mesh.get_faces().size()+result.moving_mesh.get_faces().size()+result.glass_mesh.get_faces().size())/3})
	var file := FileAccess.open(OUTPUT+"catalog.json",FileAccess.WRITE)
	if file==null:
		push_error("Cannot write opening catalog")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"format_version":1,"generator_version":P.VERSION,"origin":"hole_left_bottom","world_units_per_foot":0.2,
		"resizing":"rebuild from parameters with wall_assembly; never scale nodes","assets":catalog},"\t"))
	file.close()
	# Preserve earlier authored generations and confirm each remains loadable.
	for version in range(1,P.VERSION):
		for preset in ["wood_door","wood_window"]:
			var legacy = load(OUTPUT+preset+"_%02d.tres"%version)
			var legacy_instance = legacy.instantiate() if legacy!=null else null
			if legacy_instance==null:
				push_error("Legacy opening asset cannot load: %s_%02d"%[preset,version])
				get_tree().quit(1)
				return
			legacy_instance.free()
	print("OPENING_LEGACY_LOADED versions=",range(1,P.VERSION))
	print("OPENING_PRODUCTS_SAVED count=2 readback=true no_gameplay=true")
	get_tree().quit()
