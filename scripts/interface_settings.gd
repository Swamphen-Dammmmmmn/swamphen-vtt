extends Node

const Preferences = preload("res://scripts/ui_preferences.gd")
const FLOATING_COMPONENTS := ["action_bar.gd", "overlap_actions.gd", "token_actions.gd", "shape_actions.gd", "rename_dialog.gd", "stats_dialog.gd", "token_delete_dialog.gd", "route_card.gd", "token_turn_control.gd"]
const FLOATING_SCENES := ["distance_chip.tscn", "segment_label.tscn"]
var preferences: RefCounted

func _ready() -> void:
	preferences = Preferences.shared()
	preferences.changed.connect(apply)
	get_tree().node_added.connect(_node_added)
	apply()

func _node_added(node: Node) -> void:
	if not node is Control: return
	var script := node.get_script() as Script
	if (script != null and script.resource_path.get_file() in FLOATING_COMPONENTS) or node.scene_file_path.get_file() in FLOATING_SCENES:
		node.set_meta("floating_text_root", true)
	var parent: Node = node
	while parent != null:
		if parent.has_meta("floating_text_root"):
			if not parent.has_meta("floating_apply_pending"):
				parent.set_meta("floating_apply_pending", true)
				_apply_reference.call_deferred(weakref(parent))
			break
		parent = parent.get_parent()

func _apply_reference(reference: WeakRef) -> void:
	_finish_apply.call_deferred(reference)

func _finish_apply(reference: WeakRef) -> void:
	var root = reference.get_ref()
	if root != null:
		root.remove_meta("floating_apply_pending")
		_fonts(root)

func _fonts(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit or node is TextEdit:
		if not node.has_meta("floating_base_font"): node.set_meta("floating_base_font", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("floating_base_font")) * preferences.floating_text))
	for child in node.get_children(): _fonts(child)

func _walk(node: Node) -> void:
	if node.has_meta("floating_text_root"):
		_fonts(node)
		return
	for child in node.get_children(): _walk(child)

func apply() -> void:
	get_tree().root.content_scale_factor = preferences.ui_scale
	_walk(get_tree().root)
