extends Node
signal changed
signal page_requested
signal restart_requested(action: String)
const Paths = preload("res://scripts/storage_paths.gd")
var status := ""
var state := "idle"
var latest := ""
var notes := ""
var progress := 0.0
var job := ""
var worker_pid := -1
var elapsed := 0.0
var available := false
var phase := ""
var downloaded := 0
var total := 0

func _ready() -> void:
	available = OS.has_feature("windows") and not OS.has_feature("editor") and FileAccess.file_exists(Paths.install_root().path_join("紫水鸡棋盘.exe"))
	status = "" if available else "源项目使用本地数据目录，更新在ZIP发布版本中使用。"
	var staged := Paths.install_root().path_join("cache/updates/staged.json")
	if available and FileAccess.file_exists(staged):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(staged))
		if value is Dictionary: state = "staged"; latest = str(value.get("version","")); status = "更新已就绪"
	if available and state!="staged":
		get_tree().create_timer(3.0).timeout.connect(func(): start("check"))

func busy() -> bool:
	return not job.is_empty()

func start(action: String, package := "") -> void:
	if not available or busy(): return
	job = Crypto.new().generate_random_bytes(16).hex_encode()
	var arguments := PackedStringArray(["--action",action,"--root",Paths.install_root(),"--job",job])
	if action=="import": arguments.append_array(["--package",package])
	worker_pid = OS.create_process(Paths.install_root().path_join("紫水鸡棋盘.exe"),arguments,false)
	if worker_pid<0: job = ""; state = "failed"; status = "无法启动更新任务。"
	else: state = "working"; status = "正在准备更新"; progress = 0; phase = ""; downloaded = 0; total = 0
	changed.emit()

func _process(delta: float) -> void:
	if job.is_empty(): return
	elapsed += delta
	if elapsed<0.25: return
	elapsed = 0
	var path := Paths.install_root().path_join("cache/updates/jobs/"+job+".json")
	if not FileAccess.file_exists(path):
		if not OS.is_process_running(worker_pid):
			job = ""; state = "failed"; status = "更新任务未完成，请重试。"; changed.emit()
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary: return
	state = str(value.get("state","working"))
	status = str(value.get("message",""))
	if state=="working" and not OS.is_process_running(worker_pid):
		state = "failed"
		status = "更新任务中断，请重试。当前版本已保留。"
	progress = float(value.get("progress",0))
	phase = str(value.get("phase",""))
	downloaded = int(value.get("downloaded",0))
	total = int(value.get("total",0))
	latest = str(value.get("version",latest))
	notes = str(value.get("notes",notes))
	if state!="working":
		job = ""
		DirAccess.remove_absolute(path)
	changed.emit()

func apply(action := "apply") -> Error:
	if not available or busy(): return ERR_UNAVAILABLE
	var arguments := PackedStringArray(["--action",action,"--root",Paths.install_root(),"--wait-pid",str(OS.get_process_id())])
	return OK if OS.create_process(Paths.install_root().path_join("紫水鸡棋盘.exe"),arguments,false)>0 else ERR_CANT_FORK

func has_previous() -> bool:
	var path := Paths.install_root().path_join("installation.json")
	if not FileAccess.file_exists(path): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value is Dictionary and not str(value.get("previous","")).is_empty()
