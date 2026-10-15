extends RefCounted
const Numbers = preload("res://scripts/serialized_number.gd")

# One instance structure for decoded records, trays and board construction.
# Local scene references and placement envelopes are not instance parameters.
const VERSION := 1
const FIELDS := ["instance_version","title","kind","size","width","length","base","color",
	"hp","max_hp","ac","tags","components","materials","component_version",
	"temp_hp","notes","quarter_turn","model_yaw_deg"]
const ENVELOPE_FIELDS := ["id","cell"]
const SCENE_DEFAULTS := {"temp_hp":0,"notes":"","quarter_turn":0,"model_yaw_deg":0.0}

static func check_record(data: Dictionary) -> String:
	for key in data:
		if key not in FIELDS and key not in ENVELOPE_FIELDS:
			return "棋子实例包含未支持的字段：%s。请核对客户端版本。" % str(key)
	var version: Variant = data.get("instance_version",VERSION)
	if not Numbers.is_one_of(version,[VERSION]):
		return "棋子实例数据版本不支持。"
	var kind: String = str(data.get("kind","basic"))
	var component_version: Variant = data.get("component_version",2 if kind=="advanced" else 0)
	var supported := [1,2] if kind=="advanced" else [0]
	if not Numbers.is_one_of(component_version,supported):
		return "棋子组件数据版本不支持。"
	return ""

static func complete(data: Dictionary) -> Dictionary:
	# Preserve all supplied values. Legacy missing fields acquire documented defaults;
	# unknown fields remain visible to record validation, never filtered out here.
	var result := data.duplicate(true)
	var kind: String = str(result.get("kind","basic"))
	result["kind"] = kind
	result["instance_version"] = result.get("instance_version",VERSION)
	if Numbers.is_one_of(result["instance_version"],[VERSION]): result["instance_version"] = int(result["instance_version"])
	result["width"] = result.get("width",result.get("size",1))
	result["length"] = result.get("length",result.get("size",1))
	result["components"] = result.get("components",{})
	result["component_version"] = result.get("component_version",2 if kind=="advanced" else 0)
	if Numbers.is_one_of(result["component_version"],[1,2] if kind=="advanced" else [0]): result["component_version"] = int(result["component_version"])
	result["tags"] = result.get("tags",[])
	if not result.has("materials"):
		result["materials"] = {} if kind=="advanced" else preload("res://scripts/token_surface.gd").basic_defaults(result["color"])
	for key in SCENE_DEFAULTS:
		if not result.has(key): result[key] = SCENE_DEFAULTS[key]
	return result
