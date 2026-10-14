extends Node

const Catalog = preload("res://dev/rock_catalog.gd")
const Generator = preload("res://dev/rock_generator.gd")
const SurfaceShader = preload("res://assets/scenery/rocks/rock_surface.gdshader")
const OUTPUT := "res://assets/scenery/rocks"

# Explicit developer authoring step, never invoked by the interactive sandbox.
func _ready() -> void:
	var error := DirAccess.make_dir_recursive_absolute(OUTPUT)
	if error != OK:
		_fail("Cannot create asset directory: %s" % error_string(error))
		return
	var entries: Array[Dictionary] = Catalog.entries()
	var records: Array[Dictionary] = []
	for entry in entries:
		var data: Dictionary = entry.parameters.duplicate(true)
		data.color = data.color.to_html(false)
		var path := OUTPUT + "/" + str(entry.id) + ".res"
		var mesh: ArrayMesh
		if FileAccess.file_exists(path):
			mesh = ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
			if mesh == null or mesh.get_meta("asset_parameters", {}) != data:
				_fail("Existing asset differs; refused to overwrite: " + path)
				return
		else:
			mesh = Generator.build(entry.parameters)
			mesh.resource_name = entry.title
			mesh.set_meta("asset_id", entry.id)
			mesh.set_meta("asset_parameters", data)
			mesh.set_meta("generator_version", 2)
			var material := ShaderMaterial.new()
			material.shader = SurfaceShader
			material.set_shader_parameter("stone_color", entry.parameters.color)
			material.set_shader_parameter("variation", data.color_variation)
			material.set_shader_parameter("surface_roughness", data.roughness)
			material.set_shader_parameter("seed", float(data.seed))
			mesh.surface_set_material(0, material)
			error = ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
			if error != OK:
				_fail("Cannot save asset: " + path + ": " + error_string(error))
				return
		var bounds := mesh.get_aabb()
		records.append({"id": entry.id, "title": entry.title, "category": entry.category,
			"structure": entry.structure, "mesh": path, "parameters": data,
			"triangles": int(mesh.surface_get_array_len(0) / 3),
			"bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z],
				"size": [bounds.size.x, bounds.size.y, bounds.size.z]}})
		await get_tree().process_frame
	var manifest := {"format_version": 1, "generator_version": 2, "asset_count": records.size(),
		"feet_per_unit": 5.0, "categories": Catalog.CATEGORIES, "assets": records}
	var manifest_path := OUTPUT + "/catalog.json"
	if FileAccess.file_exists(manifest_path):
		var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not existing is Dictionary or JSON.stringify(existing, "", true) != JSON.stringify(manifest, "", true):
			_fail("Existing manifest differs; refused to overwrite.")
			return
	else:
		var file := FileAccess.open(manifest_path, FileAccess.WRITE)
		if file == null:
			_fail("Cannot save manifest.")
			return
		file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
		file.close()
	print("Saved fixed rock assets: %d, generator version 2." % records.size())
	get_tree().quit()

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
