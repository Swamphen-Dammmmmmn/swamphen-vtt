extends Node

# GPU asset comparison: static initial states only, no simulated player operations.
const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
@export_dir var output_directory := "res://artifacts/plank-textures-64-2026-10-24/"
@export var surface := "planks_horizontal"

func _ready() -> void:
	var single := Parameters.defaults(0,surface)
	single.length = 10.0
	var wall := await Generator.build(single)
	if not _require(wall.ok,"Cannot build long comparison wall"): return
	var normal: Array[Dictionary] = [
		{"parameters":Parameters.defaults(0,surface),"transform":Transform3D.IDENTITY},
		{"parameters":Parameters.defaults(0,surface),"transform":Transform3D(Basis.IDENTITY,Vector3(1,0,0))}]
	var reversed: Array[Dictionary] = [normal[0],
		{"parameters":Parameters.defaults(0,surface),"transform":Transform3D(Basis(Vector3.UP,PI),Vector3(2,0,0))}]
	var images: Array[Image] = []
	for case in 3:
		var parts: Array = [wall]
		var transforms: Array[Transform3D] = [Transform3D.IDENTITY]
		if case != 0:
			var descriptors := normal if case == 1 else reversed
			var joined := await Joiner.build(descriptors)
			if not _require(joined.ok,"Cannot join comparison wall"): return
			parts = joined.parts
			transforms = []
			for descriptor in descriptors: transforms.append(descriptor.transform)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1024,1024)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for i in parts.size():
			var mesh := MeshInstance3D.new()
			mesh.mesh = parts[i].mesh
			mesh.transform = transforms[i]
			var material := parts[i].mesh.surface_get_material(0).duplicate() as ShaderMaterial
			material.set_shader_parameter("showcase_unlit",true)
			mesh.material_override = material
			viewport.add_child(mesh)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.2
		camera.current = true
		camera.position = Vector3(1,1,5)
		viewport.add_child(camera)
		camera.look_at(Vector3(1,1,0))
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if not _require(image != null,"No GPU comparison image"): return
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(output_directory.path_join("mapping_%d.png"%case))
		images.append(image)
		viewport.queue_free()
	var comparisons: Array = []
	for case in [1,2]:
		var first := images[0].get_data()
		var second := images[case].get_data()
		var sum := 0.0
		var bad := 0
		var pixels := 0
		for y in range(48,976,3):
			for x in range(48,976,3):
				var offset := (y*1024+x)*4
				var maximum := 0
				for channel in 3:
					var delta := absi(int(first[offset+channel])-int(second[offset+channel]))
					sum += delta
					maximum = maxi(maximum,delta)
				if maximum > 8: bad += 1
				pixels += 1
		var mean := sum/(pixels*3)
		var fraction := float(bad)/pixels
		comparisons.append({"case":case,"mean_rgb_byte_error":mean,"bad_pixel_fraction":fraction})
		if not _require(mean < 0.3 and fraction < 0.002,"Module split / reversal changed board appearance: "+str(comparisons.back())): return
	var file := FileAccess.open(output_directory.path_join("gpu-mapping-check.json"),FileAccess.WRITE)
	if not _require(file != null,"Cannot save GPU mapping report"): return
	file.store_string(JSON.stringify({"comparisons":comparisons,"shader_rendered":true,"gameplay_input_tested":false},"\t"))
	print("PLANK_GPU_MAPPING_CHECK_COMPLETE normal_and_reversed=true comparisons=",comparisons)
	get_tree().quit()

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("PLANK_GPU_MAPPING_CHECK_FAILED "+message)
	get_tree().quit(1)
	return false
