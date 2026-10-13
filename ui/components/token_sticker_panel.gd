extends "res://ui/components/token_transform_panel.gd"

func _ready() -> void:
	super._ready()
	intervals = {"position": "1", "rotation": "5", "scale": "1"}

func open_sticker(next_mode: String, values: Array, at: Vector2, face_name: String) -> void:
	open_transform(next_mode, values, at)
	$Shell/Header/Row/Title.text = ("正面图片 · " if face_name == "front" else "背面图片 · ") + ("位置" if mode == "position" else "旋转")
	labels[0].text = "水平 · %" if mode == "position" else "角度 · °"
	labels[1].text = "竖直 · %"
	rows[1].visible = mode == "position"
	rows[2].hide()
	interval_label.text = "拖动间隔 · %" if mode == "position" else "拖动间隔 · °"
	reset_button.text = "恢复居中" if mode == "position" else "重置旋转"
	_publish_value_status()
	fit_to_window.call_deferred()
