extends Node
const Paths = preload("res://scripts/storage_paths.gd")
const Thumbnail = preload("res://ui/components/token_thumbnail.gd")
var memory: Dictionary = {}
var jobs: Dictionary = {}
var renderer: Control
var rendering := false
var generated_count := 0
var cached_count := 0

func _key(params: Dictionary) -> String:
	var visual := {}
	for key in ["size","width","length","base","color","materials","components"]:
		if params.has(key): visual[key] = params[key]
	return ("token-preview-v1:"+JSON.stringify(visual)).sha256_text()
func _path(key: String) -> String:
	return Paths.data_path("cache/token_previews/"+key+".png")
func request(params: Dictionary, view: TextureRect) -> void:
	var key := _key(params)
	view.set_meta("token_preview_key",key)
	view.texture = null
	if memory.has(key): view.texture = memory[key]; return
	_enqueue(key,params,weakref(view),false)
func _enqueue(key: String, params: Dictionary, watcher: WeakRef, force: bool) -> void:
	if not jobs.has(key): jobs[key] = {"params":params.duplicate(true),"watchers":[],"force":force}
	jobs[key]["force"] = jobs[key]["force"] or force
	if watcher!=null: jobs[key]["watchers"].append(watcher)
func refresh_saved(id: String) -> void:
	var loaded: Dictionary = load("res://scripts/token_library_store.gd").get_record(id)
	if not loaded["ok"]: return
	var params: Dictionary = loaded["record"]["parameters"]
	var key := _key(params)
	if memory.has(key) or FileAccess.file_exists(_path(key)): return
	_enqueue(key,params,null,true)
func _visible(view: Control) -> bool:
	if not view.is_visible_in_tree(): return false
	var area := view.get_global_rect().intersection(get_viewport().get_visible_rect())
	var ancestor := view.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents: area = area.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return area.has_area()
func _process(_delta: float) -> void:
	if rendering: return
	for key: String in jobs.keys():
		var job: Dictionary = jobs[key]
		var visible: bool = job["force"]
		for reference: WeakRef in job["watchers"].duplicate():
			var view = reference.get_ref()
			if view==null: job["watchers"].erase(reference)
			elif _visible(view): visible = true
		if job["watchers"].is_empty() and not job["force"]: jobs.erase(key); continue
		if visible:
			_render(key,job)
			break
func _render(key: String, job: Dictionary) -> void:
	rendering = true
	if FileAccess.file_exists(_path(key)):
		var cached := Image.load_from_file(_path(key))
		if cached!=null and not cached.is_empty():
			cached_count += 1
			print("棋子缩略图缓存命中："+key.left(12))
			_publish(key,job,cached)
			jobs.erase(key)
			rendering = false
			return
	if not is_instance_valid(renderer):
		renderer = Thumbnail.new()
		add_child(renderer)
		renderer.position = Vector2(-10000,-10000)
		renderer.size = Vector2(320,220)
	renderer.configure(job["params"])
	for frame in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = renderer.viewport.get_texture().get_image()
	if image!=null and not image.is_empty():
		var directory := _path(key).get_base_dir()
		if DirAccess.make_dir_recursive_absolute(directory)==OK:
			var temporary := _path(key)+".tmp.png"
			if image.save_png(temporary)==OK:
				if FileAccess.file_exists(_path(key)): DirAccess.remove_absolute(_path(key))
				DirAccess.rename_absolute(temporary,_path(key))
		generated_count += 1
		print("棋子缩略图生成："+key.left(12))
		_publish(key,job,image)
	renderer.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	jobs.erase(key)
	rendering = false

func _publish(key: String, job: Dictionary, image: Image) -> void:
	if memory.size()>=128: memory.erase(memory.keys()[0])
	memory[key] = ImageTexture.create_from_image(image)
	for reference: WeakRef in job["watchers"]:
		var view = reference.get_ref()
		if view!=null and view.get_meta("token_preview_key","")==key: view.texture = memory[key]
