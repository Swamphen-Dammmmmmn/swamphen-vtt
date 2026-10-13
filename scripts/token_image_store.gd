extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

static var DIRECTORY := StoragePaths.data_path("products/images")
const MAX_BYTES := 2500000
static var textures: Dictionary = {}

static func valid_id(id: Variant) -> bool:
	if not id is String or id.length() != 64: return false
	for character in id:
		if not character in "0123456789abcdef": return false
	return true

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _be(bytes: PackedByteArray, at: int, count: int) -> int:
	var value := 0
	for index in range(count): value = (value << 8) | bytes[at + index]
	return value

static func _header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() >= 33 and bytes.slice(0, 8).hex_encode() == "89504e470d0a1a0a" and bytes.slice(12, 16).get_string_from_ascii() == "IHDR":
		return {"format": "png", "width": _be(bytes, 16, 4), "height": _be(bytes, 20, 4)}
	if bytes.size() < 4 or bytes[0] != 255 or bytes[1] != 216: return {}
	var at := 2
	while at + 4 <= bytes.size():
		if bytes[at] != 255: return {}
		while at < bytes.size() and bytes[at] == 255: at += 1
		if at >= bytes.size(): return {}
		var marker := bytes[at]
		at += 1
		if marker in [216, 1] or (marker >= 208 and marker <= 215): continue
		if marker in [217, 218] or at + 2 > bytes.size(): return {}
		var length := _be(bytes, at, 2)
		if length < 2 or at + length > bytes.size(): return {}
		if marker in [192, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207] and length >= 8:
			return {"format": "jpg", "width": _be(bytes, at + 5, 2), "height": _be(bytes, at + 3, 2)}
		at += length
	return {}

static func _decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return _error("图片文件须不超过 2.5 MB。")
	var header := _header(bytes)
	if header.is_empty(): return _error("图片格式无效，仅支持 PNG、JPG。")
	var width: int = header["width"]
	var height: int = header["height"]
	if width <= 0 or height <= 0:
		return _error("图片尺寸无效。")
	var image := Image.new()
	var error := image.load_png_from_buffer(bytes) if header["format"] == "png" else image.load_jpg_from_buffer(bytes)
	if error != OK or image.is_empty(): return _error("无法解码图片，文件可能损坏或超出当前引擎与设备可处理范围，原有图片已保留。")
	if image.get_width() != width or image.get_height() != height: return _error("图片尺寸与文件信息不一致。")
	image.convert(Image.FORMAT_RGBA8)
	return {"ok": true, "image": image, "bytes": bytes.size(), "data": bytes}

static func import_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg"]: return _error("请选择 PNG、JPG 图片。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("无法打开所选图片。")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _error("所选图片超过 2.5 MB，请先压缩。")
	var bytes := file.get_buffer(file.get_length())
	var error := file.get_error()
	file.close()
	if error != OK: return _error("读取图片失败。")
	return _decode(bytes)

static func content_id(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

static func load_image(id: String) -> Dictionary:
	if not valid_id(id): return _error("图片资源编号无效。")
	var file := FileAccess.open(DIRECTORY.path_join(id + ".img"), FileAccess.READ)
	if file == null: return _error("图片资源缺失，请重新导入或移除贴图。")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _error("图片资源超过大小限制。")
	var bytes := file.get_buffer(file.get_length())
	var error := file.get_error()
	file.close()
	if error != OK or content_id(bytes) != id: return _error("图片资源损坏，请重新导入或移除贴图。")
	return _decode(bytes)

static func save_image(bytes: PackedByteArray) -> Dictionary:
	var decoded := _decode(bytes)
	if not decoded["ok"]: return decoded
	if decoded["image"].is_invisible(): return _error("图片全部透明，请选择包含可见画面的图片。")
	var id := content_id(bytes)
	var path := DIRECTORY.path_join(id + ".img")
	if FileAccess.file_exists(path) and load_image(id)["ok"]: return {"ok": true, "id": id}
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK: return _error("无法创建图片资源目录。")
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _error("无法写入图片资源，原有图片已保留。")
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK and FileAccess.get_file_as_bytes(temporary) != bytes: error = ERR_FILE_CORRUPT
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _error("图片资源保存失败，原有图片已保留。")
	textures.erase(id)
	return {"ok": true, "id": id}

static func texture(id: String) -> Texture2D:
	if textures.has(id): return textures[id]
	var loaded := load_image(id)
	if not loaded["ok"]: return null
	var image: Image = loaded["image"]
	var used := image.get_used_rect()
	image.fix_alpha_edges()
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	result.set_meta("used_rect", used)
	if textures.size() >= 32: textures.erase(textures.keys()[0])
	textures[id] = result
	return result
