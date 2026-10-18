extends RefCounted

static var _textures: Dictionary = {}

# 编辑器尚未导入新增SVG时，也从同一矢量源显示；避免每张卡重复栅格化。
static func texture(path: String) -> Texture2D:
	if _textures.has(path): return _textures[path]
	var result: Texture2D
	if ResourceLoader.exists(path):
		result = load(path)
	elif path.ends_with(".svg") and FileAccess.file_exists(path):
		var bitmap := Image.new()
		if bitmap.load_svg_from_string(FileAccess.get_file_as_string(path)) == OK:
			result = ImageTexture.create_from_image(bitmap)
	if result == null: push_error("库图标无法读取：" + path)
	else: _textures[path] = result
	return result
