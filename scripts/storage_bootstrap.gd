extends Node
const Paths = preload("res://scripts/storage_paths.gd")

func _enter_tree() -> void:
	if not Paths.initialize():
		push_error(Paths.failure)
		OS.alert(Paths.failure,"无法初始化数据目录")
		get_tree().quit(1)
