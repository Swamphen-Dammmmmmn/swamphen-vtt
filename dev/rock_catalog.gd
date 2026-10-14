extends RefCounted

const CATEGORIES := ["风化巨石", "棱角岩块", "扁平卧石"]
const SHORT_NAMES := ["风化", "棱角", "卧石"]
const PROFILES := ["自然块体", "斜顶楔形", "双斜顶", "大斜面", "偏侧肩部", "收窄顶部", "三角轮廓", "斜切薄片", "偏移上部", "缺角块体"]
const PROFILES_BY_KIND := [[0, 1, 4, 5, 8], [2, 3, 4, 6, 9], [0, 1, 3, 7, 9]]
const DIMENSIONS := [
	[[12,10,7], [15,8,6], [10,9,10], [14,12,8], [11,8,8]],
	[[12,8,9], [13,12,8], [10,9,11], [14,9,6], [9,10,8]],
	[[14,10,3], [18,8,4], [12,14,4], [19,7,3], [15,11,5]]
]

# Five deliberately different structures per category, each with five variations.
# These remain review candidates, not a production asset library.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind in range(3):
		for group in range(5):
			for variant in range(5):
				var number := group * 5 + variant + 1
				var size_values: Array = DIMENSIONS[kind][group]
				var profile := int(PROFILES_BY_KIND[kind][group])
				var parameters := {"shape": kind, "seed": 1001 + kind * 10000 + group * 997 + variant * 137,
					"profile": profile,
					"width": snappedf(float(size_values[0]) * (0.88 + variant * 0.07), 0.5),
					"depth": snappedf(float(size_values[1]) * (1.16 - variant * 0.075), 0.5),
					"height": snappedf(float(size_values[2]) * (0.8 + ((variant * 2 + group) % 5) * 0.1), 0.5),
					"variation": 0.48 + float((variant + group) % 5) * 0.11,
					"rounding": _rounding(kind, group, variant), "burial": 0.10,
					"color": Color("858a86"), "color_variation": 0.12, "roughness": 0.88}
				var structure: String = PROFILES[profile]
				result.append({"id": "rock_%d_%02d" % [kind, number],
					"title": "%s %02d" % [SHORT_NAMES[kind], number], "category": CATEGORIES[kind],
					"structure": structure, "parameters": parameters})
	return result

static func _rounding(kind: int, group: int, variant: int) -> float:
	match kind:
		0: return clampf(0.65 + variant * 0.06 - group * 0.025, 0, 1)
		1: return 0.03 + float((variant + group) % 5) * 0.05
		2: return 0.25 + float((variant * 2 + group) % 5) * 0.14
		_: return 0.55
