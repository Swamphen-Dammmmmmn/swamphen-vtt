extends RefCounted
const Paths = preload("res://scripts/storage_paths.gd")
signal changed
static var instance: RefCounted
var side := "auto"
var inset_dp := -1.0
var side_rotation := 0
var error := ""
static func shared() -> RefCounted:
	if instance == null:
		instance = load("res://scripts/mobile_preferences.gd").new()
		var config := ConfigFile.new()
		if config.load(Paths.data_path("mobile_display.cfg"))==OK:
			instance.side = str(config.get_value("display","camera_side","auto"))
			if instance.side not in ["auto","left","right"]: instance.side = "auto"
			var amount: Variant = config.get_value("display","camera_inset_dp",-1)
			if typeof(amount) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(amount)):
				instance.inset_dp = clampf(float(amount),-1,96)
			var rotation: Variant = config.get_value("display","side_rotation",0)
			if typeof(rotation) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(rotation)):
				instance.side_rotation = posmod(int(rotation),4)
	return instance
func change(new_side: String, amount: float, rotation: int) -> void:
	side = new_side if new_side in ["auto","left","right"] else "auto"
	inset_dp = clampf(amount,-1,96) if is_finite(amount) else -1.0
	side_rotation = posmod(rotation,4)
	var config := ConfigFile.new()
	config.set_value("display","camera_side",side)
	config.set_value("display","camera_inset_dp",inset_dp)
	config.set_value("display","side_rotation",side_rotation)
	var result := config.save(Paths.data_path("mobile_display.cfg"))
	error = "显示设置已生效，但未能保存。" if result!=OK else ""
	changed.emit()
