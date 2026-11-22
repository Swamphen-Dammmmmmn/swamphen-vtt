extends Node

const Bark = preload("res://scripts/scenery/bark_texture_bank.gd")
const Wood = preload("res://scripts/scenery/plank_texture_bank.gd")
const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const OUTPUT := "res://artifacts/bark-log-wall-2026-10-24/"

func _ready() -> void:
	var bytes := 0
	for texture in [Bark.COLORS,Bark.DETAIL]:
		if not _require(texture is CompressedTexture2DArray and texture.get_layers()==64 and texture.get_width()==512 and texture.get_height()==128 and texture.has_mipmaps(),"Bark must have 64 compressed 512x128 mipmapped layers"): return
		var hashes: Dictionary = {}
		for layer in 64:
			var image: Image = texture.get_layer_data(layer)
			if not _require(image!=null and image.is_compressed(),"Bark layer not GPU compressed"): return
			bytes+=image.get_data_size()
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(image.get_data())
			hashes[hash.finish().hex_encode()]=true
		if not _require(hashes.size()==64,"Compressed bark layers repeat"): return
	var layers: Dictionary = {}
	for piece in 64: layers[Wood.layer_for(piece,0,0,0)]=true
	if not _require(layers.size()==64 and Bark.COLORS!=Wood.COLORS and Bark.DETAIL!=Wood.DETAIL,"Bark bank not independent / unreachable layers"): return
	var p := Parameters.defaults(0,"logs_bark")
	var wall := await Generator.build(p)
	if not _require(wall.ok,"Bark wall did not build"): return
	var material := wall.mesh.surface_get_material(0) as ShaderMaterial
	if not _require(material.get_shader_parameter("board_colors")==Bark.COLORS and material.get_shader_parameter("board_detail")==Bark.DETAIL and material.get_shader_parameter("bark_mode")==true and p.color==Bark.REFERENCE_COLOR,"Bark material did not use its own resources/default"): return
	var tinted := Generator.recolor(wall,Color("667744"))
	if not _require(tinted.ok and material.get_shader_parameter("surface_color")==p.color and tinted.mesh.surface_get_material(0).get_shader_parameter("board_colors")==Bark.COLORS,"Recolor duplicated arrays / changed existing wall"): return
	var bare := await Generator.build(Parameters.defaults(0,"logs_round"))
	if not _require(bare.ok and bare.mesh.surface_get_material(0).get_shader_parameter("board_colors")==Wood.COLORS and bare.parameters.color==Color("8b7a65"),"Bare wood bank / neutral default changed incorrectly"): return
	var file := FileAccess.open(OUTPUT+"texture-bank-check.json",FileAccess.WRITE)
	if not _require(file!=null,"Cannot save bark bank report"): return
	file.store_string(JSON.stringify({"layers":64,"dimensions":[512,128],"compressed_texture_bytes":bytes,"mipmaps":true,"unique_compressed_layers":true,
		"independent_bark_bank":true,"all_layers_reachable":true,"shared_arrays":true,"recolor_isolated":true,"bare_default":"8b7a65","mobile_tested":false},"\t"))
	print("BARK_TEXTURE_ASSET_CHECK_COMPLETE layers=64 independent=true unique=true shared=true texture_bytes=",bytes)
	get_tree().quit()

func _require(condition: bool,message: String) -> bool:
	if condition: return true
	push_error("BARK_TEXTURE_ASSET_CHECK_FAILED "+message)
	get_tree().quit(1)
	return false
