extends Control
const Modal = preload("res://ui/components/page_modal.gd")

func _ready() -> void:
	BoardUiStyle.configure()
	var raw := FileAccess.get_file_as_bytes("res://ui/theme/fonts/LICENSE.txt")
	var end := raw.find(0)
	if end >= 0: raw = raw.slice(0, end)
	var text := raw.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
	var blank_lines := RegEx.new()
	blank_lines.compile("\\n[ \\t]*\\n(?:[ \\t]*\\n)+")
	var dialog := Modal.new()
	dialog.document_variant = true
	add_child(dialog)
	dialog.configure("HarmonyOS Sans 字体许可", blank_lines.sub(text, "\n\n", true))
	dialog.add_action("关闭", dialog.dismiss)
	await get_tree().process_frame
	await get_tree().process_frame
	print("Static license dialog extent: ", dialog.panel.size)
