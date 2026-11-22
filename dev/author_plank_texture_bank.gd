extends Node

# Independent asset checks only: no gameplay input, simulated camera or save access.
const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const BASELINE := "res://artifacts/wall-vertical-grooves-2026-10-24/wood/geometry-report.json"
@export_file("*.json") var report_path := "res://artifacts/plank-textures-64-2026-10-24/asset-check.json"
const EXPECTED_LAYERS := 64

func _ready() -> void:
	if not _require(Bank.COLORS.get_layers() == EXPECTED_LAYERS and Bank.DETAIL.get_layers() == EXPECTED_LAYERS,"Collection must contain 64 layers"): return
	var bytes := 0
	for texture in [Bank.COLORS,Bank.DETAIL]:
		if not _require(texture is CompressedTexture2DArray and texture.get_width() == 512 and texture.get_height() == 128 and texture.has_mipmaps(),"Wrong imported texture array dimensions / mipmaps / resource type"): return
		var hashes: Dictionary = {}
		for layer in texture.get_layers():
			var image: Image = texture.get_layer_data(layer)
			if not _require(image != null and image.is_compressed(),"Layer did not use VRAM compression"): return
			bytes += image.get_data_size()
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data())
			hashes[hash.finish().hex_encode()] = true
		if not _require(hashes.size() == EXPECTED_LAYERS,"Compressed layers are duplicates"): return
	for entry in [[0,0,0,0,0],[1,0,0,0,5],[-1,0,0,0,59],[0,1,0,0,7],[0,4,0,0,34]]:
		if not _require(Bank.layer_for(entry[0],entry[1],entry[2],entry[3]) == entry[4],"Known board-layer mapping changed"): return
	for row in range(-8,32):
		for piece in range(-64,64):
			for face in 2:
				var layer := Bank.layer_for(piece,row,face,-7)
				if not _require(layer != Bank.layer_for(piece+1,row,face,-7),"Horizontal neighbours repeat"): return
				for offset in [-1,0,1]:
					if not _require(layer != Bank.layer_for(piece+offset,row+1,face,-7),"Overlapping adjacent rows repeat"): return
	var covered: Dictionary = {}
	for piece in EXPECTED_LAYERS: covered[Bank.layer_for(piece,0,0,0)] = true
	if not _require(covered.size() == EXPECTED_LAYERS,"Layer selection does not reach all 64 boards"): return
	var left := Bank.board_at(0.95,0.3,1,0)
	var right := Bank.board_at(1.05,0.3,1,0)
	if not _require(left.layer == right.layer and left.piece == right.piece and absf((right.uv.x-left.uv.x)-0.1) < 0.00001,"Module boundary restarted a single board"): return
	if not _require(Bank.board_at(0.49,0.3,1,0).layer != Bank.board_at(0.51,0.3,1,0).layer,"True board joint did not change texture"): return
	var baseline_file := FileAccess.open(BASELINE,FileAccess.READ)
	if not _require(baseline_file != null,"Geometry baseline is missing"): return
	var baseline: Dictionary = JSON.parse_string(baseline_file.get_as_text())
	var checked := 0
	for record in baseline.candidates:
		var p := Parameters.defaults(int(record.kind),"planks_horizontal")
		p.thickness = record.thickness_feet
		var wall := await Generator.build(p)
		if not _require(wall.ok,"Textured wall did not build"): return
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]: hash.update(wall.mesh.surface_get_arrays(0)[slot].to_byte_array())
		if not _require(hash.finish().hex_encode() == record.geometry_sha256,"Texture work changed accepted wall geometry"): return
		var material := wall.mesh.surface_get_material(0) as ShaderMaterial
		if not _require(material.get_shader_parameter("board_colors") == Bank.COLORS and material.get_shader_parameter("board_detail") == Bank.DETAIL and material.get_shader_parameter("board_count") == EXPECTED_LAYERS,"Wall did not use shared arrays"): return
		var tinted := Generator.recolor(wall,Color("668877"))
		if not _require(tinted.ok and material.get_shader_parameter("surface_color") == p.color and tinted.mesh.surface_get_material(0).get_shader_parameter("board_colors") == Bank.COLORS,"Recolor mutated a placed wall / duplicated shared bank"): return
		checked += 1
	var report := {"layers":EXPECTED_LAYERS,"dimensions":[512,128],"compressed_texture_bytes":bytes,"mipmaps":true,
		"unique_layers":true,"all_layers_reachable":true,"neighbour_permutation":true,"cross_module_identity":true,"geometry_matches_baseline":checked,
		"shared_arrays":true,"recolor_isolated":true,"gameplay_input_tested":false,"mobile_tested":false}
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if not _require(file != null,"Cannot save asset report"): return
	file.store_string(JSON.stringify(report,"\t"))
	print("PLANK_TEXTURE_ASSET_CHECK_COMPLETE layers=64 neighbours=true cross_module=true unchanged_geometry=",checked," texture_bytes=",bytes)
	get_tree().quit()

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("PLANK_TEXTURE_ASSET_CHECK_FAILED "+message)
	get_tree().quit(1)
	return false
