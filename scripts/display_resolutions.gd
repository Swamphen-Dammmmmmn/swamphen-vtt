extends RefCounted

# Keep the original order solely for migration of older index-based saves.
const LEGACY := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1920, 1200), Vector2i(2560, 1600), Vector2i(3440, 1440)]
const GROUPS := [
	["16:9", [[1280,720],[1360,768],[1366,768],[1600,900],[1920,1080],[2048,1152],[2304,1296],[2560,1440],[2880,1620],[3200,1800],[3840,2160]]],
	["16:10", [[1280,800],[1440,900],[1680,1050],[1920,1200],[2240,1400],[2560,1600],[2880,1800],[3072,1920],[3200,2000],[3840,2400]]],
	["3:2", [[1440,960],[1920,1280],[2160,1440],[2256,1504],[2400,1600],[2496,1664],[2736,1824],[2880,1920],[3000,2000],[3240,2160],[3456,2304],[3600,2400]]],
	["4:3 / 5:4", [[1024,768],[1152,864],[1280,960],[1280,1024],[1400,1050],[1600,1200],[1920,1440],[2048,1536],[2560,1920],[2800,2100],[3200,2400]]],
	["超宽屏 / 电影规格", [[1720,720],[1920,800],[2560,1080],[2880,1200],[3440,1440],[3840,1600],[3840,1800],[3840,1080],[3840,1200],[4096,2160]]]
]

static func catalog() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for group in GROUPS:
		for pair in group[1]:
			var size := Vector2i(pair[0], pair[1])
			if not result.has(size): result.append(size)
	if DisplayServer.get_name() != "headless":
		for screen in range(DisplayServer.get_screen_count()):
			var size := DisplayServer.screen_get_size(screen)
			if allowed(size) and not result.has(size): result.append(size)
	return result

static func allowed(size: Vector2i) -> bool:
	return size.x >= 1024 and size.y >= 720 and size.x <= 4096 and size.y <= 2400

static func ratio(size: Vector2i) -> String:
	if size.y <= 0: return "其他"
	var value := float(size.x) / size.y
	for entry in [["16:9", 16.0/9.0], ["16:10", 1.6], ["3:2", 1.5], ["4:3", 4.0/3.0], ["5:4", 1.25]]:
		if absf(value - entry[1]) < 0.015: return entry[0]
	return "超宽" if value > 2.0 else "其他"

static func groups(sizes: Array[Vector2i]) -> Array:
	var result: Array = []
	var used: Array[Vector2i] = []
	for group in GROUPS:
		var items: Array[Vector2i] = []
		for pair in group[1]:
			var size := Vector2i(pair[0], pair[1])
			if sizes.has(size) and not used.has(size):
				items.append(size)
				used.append(size)
		items.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
		result.append([group[0], items])
	var other: Array[Vector2i] = []
	for size in sizes:
		if not used.has(size): other.append(size)
	if not other.is_empty(): result.append(["其他屏幕规格", other])
	return result
