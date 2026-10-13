extends RefCounted

static var failure := ""
static var migration_notice := ""
static var _root := ""

static func install_root() -> String:
	if not _root.is_empty(): return _root
	if OS.has_feature("android") or OS.has_feature("ios"):
		_root = OS.get_user_data_dir().get_base_dir()
	elif OS.has_feature("editor"):
		_root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	else:
		var executable := OS.get_executable_path().get_base_dir()
		_root = executable.get_base_dir().get_base_dir() if executable.get_base_dir().get_file()=="versions" else executable
	return _root

static func data_root() -> String:
	return OS.get_user_data_dir() if OS.has_feature("android") or OS.has_feature("ios") else install_root().path_join("userdata")

static func data_path(relative: String) -> String:
	return data_root().path_join(relative)

static func initialize() -> bool:
	for path in [data_root(),install_root().path_join("logs"),install_root().path_join("cache/updates/jobs")]:
		if OS.has_feature("android") or OS.has_feature("ios"): path = data_root()
		var error := DirAccess.make_dir_recursive_absolute(path)
		if error!=OK:
			failure = "无法创建数据目录，请将整个程序目录移动到可写位置。\n"+path
			return false
	var probe := data_path(".write-check")
	var file := FileAccess.open(probe,FileAccess.WRITE)
	if file==null:
		failure = "数据目录不可写，请将整个程序目录移动到可写位置。\n"+data_root()
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	if OS.has_feature("android") or OS.has_feature("ios"): return true
	var marker := data_path(".portable-layout-v1")
	if FileAccess.file_exists(marker): return true
	var lock_directory := data_path(".migration-lock")
	var deadline := Time.get_ticks_msec()+60000
	while DirAccess.make_dir_absolute(lock_directory)!=OK:
		if FileAccess.file_exists(marker): return true
		var owner := lock_directory.path_join("owner")
		if FileAccess.file_exists(owner):
			var pid := int(FileAccess.get_file_as_string(owner))
			if pid>0 and not OS.is_process_running(pid):
				DirAccess.remove_absolute(owner)
				DirAccess.remove_absolute(lock_directory)
		elif Time.get_ticks_msec()>deadline-59000:
			# Empty lock directories can remain after a process exits before writing its owner.
			DirAccess.remove_absolute(lock_directory)
		if Time.get_ticks_msec()>deadline:
			failure = "另一实例正在迁入旧资料，请稍后重新启动。原资料保留。"
			return false
		OS.delay_msec(100)
	var owner_file := FileAccess.open(lock_directory.path_join("owner"),FileAccess.WRITE)
	if owner_file==null:
		DirAccess.remove_absolute(lock_directory)
		failure = "无法记录数据初始化锁，请检查目录权限。"
		return false
	owner_file.store_string(str(OS.get_process_id()))
	owner_file.close()
	var complete := _initialize_migration(marker)
	DirAccess.remove_absolute(lock_directory.path_join("owner"))
	DirAccess.remove_absolute(lock_directory)
	return complete

static func _initialize_migration(marker: String) -> bool:
	var previous := OS.get_user_data_dir()
	if previous.simplify_path()!=data_root().simplify_path() and DirAccess.dir_exists_absolute(previous):
		var copied := _copy_tree(previous.path_join("products"),data_path("products"))
		for name in ["identity.json","identity.json.bak","identity.json.tmp","graphics_settings.cfg","ui_preferences.cfg","camera_preferences.cfg","campaign_settings.cfg","network.cfg"]:
			copied = _copy_missing(previous.path_join(name),data_path(name)) and copied
		if not copied:
			failure = "旧资料迁入未完成，原文件及已复制的文件均已保留。请检查磁盘和目录权限后重新启动。"
			return false
		migration_notice = "已迁入旧目录中缺失的资料，原文件保留。"
	var ready := FileAccess.open(marker,FileAccess.WRITE)
	if ready==null: failure = "无法记录数据目录初始化状态。"; return false
	ready.store_string("1\n")
	ready.flush()
	if ready.get_error()!=OK:
		failure = "无法完成数据目录初始化记录。原资料已保留。"
		return false
	return true

static func _copy_missing(source: String, target: String) -> bool:
	if not FileAccess.file_exists(source) or FileAccess.file_exists(target): return true
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error!=OK: return false
	var temporary := target+".migrating"
	error = DirAccess.copy_absolute(source,temporary)
	if error!=OK: return false
	if FileAccess.get_sha256(source)!=FileAccess.get_sha256(temporary): return false
	return DirAccess.rename_absolute(temporary,target)==OK

static func _copy_tree(source: String, target: String) -> bool:
	if not DirAccess.dir_exists_absolute(source): return true
	var directory := DirAccess.open(source)
	if directory==null: return false
	directory.include_hidden = true
	if directory.list_dir_begin()!=OK: return false
	var complete := true
	var name := directory.get_next()
	while not name.is_empty():
		if not name.begins_with(".") or name==".builtin_tokens_v1":
			var ok := _copy_tree(source.path_join(name),target.path_join(name)) if directory.current_is_dir() else _copy_missing(source.path_join(name),target.path_join(name))
			complete = ok and complete
		name = directory.get_next()
	directory.list_dir_end()
	return complete

static func import_certificate(source: String) -> String:
	if source.begins_with("res://"): return source
	if source.begins_with("certificates/"): return source
	if not FileAccess.file_exists(source): return ""
	var hash := FileAccess.get_sha256(source)
	var name := "certificates/"+hash+".crt"
	if not _copy_missing(source,data_path(name)): return ""
	return name

static func certificate_path(path: String) -> String:
	return data_path(path) if path.begins_with("certificates/") and not path.contains("..") else path
