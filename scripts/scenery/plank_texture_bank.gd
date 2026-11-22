extends RefCounted

# One shared pair of compressed arrays, never one material or node per board.
const COLORS: TextureLayered = preload("res://assets/scenery/textures/planks/board_colors.png")
const DETAIL: TextureLayered = preload("res://assets/scenery/textures/planks/board_detail.png")
const REFERENCE_COLOR := Color("986039")
const BOARD_LENGTH := 1.0
const BOARD_HEIGHT := 0.2

static func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("board_colors", COLORS)
	material.set_shader_parameter("board_detail", DETAIL)
	material.set_shader_parameter("board_count", COLORS.get_layers())
	material.set_shader_parameter("wood_reference", REFERENCE_COLOR)

# Public asset-inspection counterpart of the small integer permutation in the shader.
# 5 is coprime to 16, 64 and 128: neighbours never select the same layer.
static func layer_for(piece: int, row: int, face: int, line_seed: int) -> int:
	return posmod(piece*5 + row*7 + floori(float(row)/4)*6 + face*8 + line_seed*11, COLORS.get_layers())

static func board_at(along: float, height: float, face: int, line_seed: int, vertical := false) -> Dictionary:
	if vertical:
		var swap := along
		along = height
		height = swap
	var row := floori(height/BOARD_HEIGHT + 0.000001)
	var position := along/BOARD_LENGTH + posmod(row,2)*0.5
	var piece := floori(position)
	return {"piece": piece, "row": row, "uv": Vector2(position-piece, height/BOARD_HEIGHT-row),
		"layer": layer_for(piece,row,face,line_seed)}
