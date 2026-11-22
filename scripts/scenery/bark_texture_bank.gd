extends RefCounted

# Independent bark collection; the accepted bare-wood arrays stay unchanged.
const COLORS: TextureLayered = preload("res://assets/scenery/textures/bark/bark_colors.png")
const DETAIL: TextureLayered = preload("res://assets/scenery/textures/bark/bark_detail.png")
const REFERENCE_COLOR := Color("6d6557")
const WOOD_COLOR := Color("986039")
const FAMILY_TITLES := ["疏纵裂","细密裂","断续裂","分叉裂"]

static func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("board_colors",COLORS)
	material.set_shader_parameter("board_detail",DETAIL)
	material.set_shader_parameter("board_count",COLORS.get_layers())
	material.set_shader_parameter("wood_reference",WOOD_COLOR)
	material.set_shader_parameter("bark_reference",REFERENCE_COLOR)
	material.set_shader_parameter("bark_mode",true)
