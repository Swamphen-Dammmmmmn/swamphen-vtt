extends Resource

const P = preload("res://scripts/scenery/opening_parameters.gd")
const Instance = preload("res://scripts/scenery/opening_instance.gd")
const SUPPORTED_GENERATORS := [1,2,3,4] # Baked earlier generations retain their authored geometry.

# Fixed first-round product. Editing dimensions uses parameters() with Assembly;
# loading this resource preserves the original authored mesh without regenerating.
@export var generator_version := 1
@export var generated: Dictionary = {}

func instantiate() -> Node3D:
	if generator_version not in SUPPORTED_GENERATORS or not generated.has_all(["spec","fixed_mesh","moving_mesh","glass_mesh","fixed_shapes","moving_shapes","hinge"]):
		push_error("门窗资产版本或内容不受支持")
		return null
	var error := P.validate(generated.spec)
	if not error.is_empty():
		push_error(error)
		return null
	var instance := Instance.new()
	instance.configure(generated)
	return instance

func parameters() -> Dictionary:
	return generated.get("spec",{}).duplicate(true)
