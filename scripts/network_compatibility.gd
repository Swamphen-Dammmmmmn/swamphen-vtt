extends RefCounted

# Shared with signaling.py. Product version comes from the running project.
static func local_version() -> Dictionary:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/network/contract.json"))
	return {"app":str(ProjectSettings.get_setting("application/config/version","")),"protocol":int(contract["protocol"]),"data_schema":int(contract["data_schema"])}

static func mismatch(remote: Variant) -> String:
	var expected := local_version()
	if not remote is Dictionary or remote.size()!=expected.size():
		return "对方缺少有效的联机版本声明，请更新软件或中继服务。"
	for key in expected:
		if not remote.has(key):
			return "对方联机版本声明缺少字段，请更新软件或中继服务。"
		if (key=="app" and not remote[key] is String) or (key!="app" and (typeof(remote[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(remote[key])) or float(remote[key])!=floorf(float(remote[key])))):
			return "对方联机版本声明无效，请更新软件或中继服务。"
		if remote[key]!=expected[key]:
			return "联机版本不一致：本机 %s（协议 %s，数据 %s），对方 %s（协议 %s，数据 %s）。请使用完全相同的软件版本。" % [expected["app"],expected["protocol"],expected["data_schema"],remote.get("app","未知"),remote.get("protocol","未知"),remote.get("data_schema","未知")]
	return ""
