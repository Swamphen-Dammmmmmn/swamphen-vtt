extends RefCounted

# Image bytes are content, not a UI surface. Background/radius belong to the card.
const VERSION := 2
const MAX_SIZE := Vector2i(320, 200)
const MAX_BYTES := 1048576

static func prepare(source: Image) -> Image:
	if source == null or source.is_empty(): return null
	var image := source.duplicate() as Image
	image.set_meta("legacy_library_frame", source.get_meta("legacy_library_frame", false))
	image.convert(Image.FORMAT_RGBA8)
	var ratio := minf(1.0, minf(float(MAX_SIZE.x) / image.get_width(), float(MAX_SIZE.y) / image.get_height()))
	if ratio < 1.0:
		image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	return image

static func decode(bytes: PackedByteArray, stored_thumbnail := true) -> Image:
	if bytes.size() < 24 or bytes.size() > MAX_BYTES or bytes.slice(0, 8).hex_encode() != "89504e470d0a1a0a": return null
	var width := _dimension(bytes, 16)
	var height := _dimension(bytes, 20)
	if width < 1 or height < 1 or width > MAX_SIZE.x or height > MAX_SIZE.y: return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK: return null
	# Historical thumbnails did not store their original image extent. Never guess
	# a crop from colors; a potentially framed old thumbnail must be regenerated.
	image.set_meta("legacy_library_frame", stored_thumbnail and image.get_size() == MAX_SIZE)
	return image

static func _dimension(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])
