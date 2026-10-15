extends Node

const Paths = preload("res://scripts/storage_paths.gd")
const Files = preload("res://scripts/product_files.gd")
const STORES := {"tokens":"res://scripts/token_library_store.gd","platforms":"res://scripts/platform_library_store.gd","maps":"res://scripts/map_library_store.gd","adventures":"res://scripts/adventure_library_store.gd"}
const VERSION := 1
signal changed(kind: String)
var jobs: Dictionary = {}
var attempted: Dictionary = {}
var epochs: Dictionary = {}
var textures: Dictionary = {}
var metadata: Dictionary = {}
var preview_waiters: Dictionary = {}
var busy := false
var parsed_count := 0

func _valid_id(id: String) -> bool:
	if id.length()!=32: return false
	for c in id:
		if c not in "0123456789abcdef": return false
	return true

func _base(kind: String, id: String) -> String:
	return Paths.data_path("cache/library_catalog/"+kind+"/"+id)

func _source(kind: String, id: String) -> String:
	return Paths.data_path("products/"+kind+"/"+id+".json")

func _stamp(kind: String, id: String) -> String:
	var path := _source(kind,id)
	if not FileAccess.file_exists(path): return ""
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return "unreadable"
	var length := file.get_length()
	file.close()
	return str(FileAccess.get_modified_time(path))+":"+str(length)

func _meta(kind: String, id: String, stamp: String) -> Dictionary:
	var key := kind+":"+id
	var file := FileAccess.open(_base(kind,id)+".json",FileAccess.READ)
	if file==null:
		if metadata.has(key) and (stamp.is_empty() or metadata[key].get("stamp")==stamp): return metadata[key].duplicate(true)
		return {}
	if file.get_length()>131072: return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("version")!=VERSION or raw.get("id")!=id or (not stamp.is_empty() and raw.get("stamp")!=stamp): return {}
	if not raw.get("title") is String or not raw.get("summary") is Dictionary or not raw.get("tags") is Array: return {}
	if (kind=="tokens" and raw.get("kind") not in ["basic","advanced"]) or (kind!="tokens" and raw.get("kind")!=kind): return {}
	if raw.title.length()>128 or raw.tags.size()>32: return {}
	for tag in raw.tags:
		if not tag is String or tag.length()>40: return {}
	for value in raw.summary.values():
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0 or float(value)>10000000: return {}
	metadata[key] = raw.duplicate(true)
	return raw

func _write(kind: String, id: String, meta: Dictionary) -> bool:
	metadata[kind+":"+id] = meta.duplicate(true)
	var path := _base(kind,id)+".json"
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK: return false
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(meta))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK: return false
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(path+".tmp",path)!=OK:
		push_warning("库索引写入失败，原作品未改动。")
		return false
	return true

func _image(kind: String, id: String, revision: String) -> String:
	if revision.length()!=32 or not _valid_id(revision): return ""
	return _base(kind,id)+"-"+revision+".png"

func read_list(kind: String) -> Dictionary:
	var result := {"entries":[],"warnings":[],"error":"","pending":0}
	var listed := Files.list_json(Paths.data_path("products/"+kind))
	result.error = listed.error
	for filename: String in listed.files:
		var id := filename.trim_suffix(".json")
		if not _valid_id(id):
			result.warnings.append(filename+"：编号无效")
			continue
		var stamp := _stamp(kind,id)
		var meta := _meta(kind,id,stamp)
		if meta.is_empty():
			_enqueue(kind,id,stamp)
			meta = {"id":id,"title":"读取中 · "+id.left(6),"kind":"basic" if kind=="tokens" else kind,"tags":[],"summary":{},"pending":true}
			result.pending += 1
		elif meta.has("error"):
			result.warnings.append(filename+"："+str(meta.error))
			continue
		meta["catalog_kind"] = kind
		result.entries.append(meta)
	result.entries.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.title).naturalnocasecmp_to(str(b.title))<0)
	print("库轻量列表：%s，%d条，待建立索引%d条" % [kind,result.entries.size(),result.pending])
	return result

func request_preview(entry: Dictionary, view: TextureRect) -> void:
	var kind: String = entry.catalog_kind
	var id: String = entry.id
	view.set_meta("catalog_entry",kind+":"+id)
	view.texture = null
	var path := _image(kind,id,str(entry.get("preview_revision","")))
	if not path.is_empty() and FileAccess.file_exists(path):
		if not textures.has(path):
			var image := _read_image(path)
			if image!=null:
				if textures.size()>=128: textures.erase(textures.keys()[0])
				textures[path] = ImageTexture.create_from_image(image)
		if textures.has(path): view.texture = textures[path]; return
	var key := kind+":"+id
	if not preview_waiters.has(key): preview_waiters[key] = {"kind":kind,"id":id,"views":[]}
	preview_waiters[key].views.append(weakref(view))

func _read_image(path: String) -> Image:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>1048576: return null
	var bytes := file.get_buffer(file.get_length())
	if bytes.size()<24 or bytes.slice(0,8).hex_encode()!="89504e470d0a1a0a": return null
	# PNG dimensions are big-endian, reject large or malformed cache images before decoding.
	if bytes.slice(16,24).hex_encode()!="00000140000000c8": return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes)==OK else null

func _enqueue(kind: String, id: String, stamp: String, record: Dictionary = {}) -> void:
	var key := kind+":"+id
	if attempted.get(key)==stamp and record.is_empty(): return
	if not jobs.has(key): jobs[key] = {"kind":kind,"id":id,"stamp":stamp,"record":record}
	elif not record.is_empty(): jobs[key] = {"kind":kind,"id":id,"stamp":stamp,"record":record}

func record_saved(kind: String, id: String, record: Dictionary = {}) -> void:
	var key := kind+":"+id
	epochs[key] = int(epochs.get(key,0))+1
	attempted.erase(key)
	if not record.is_empty(): _store(kind,record)
	else:
		var loaded: Dictionary = load(STORES[kind]).get_record(id)
		if loaded.ok: _store(kind,loaded.record)
	changed.emit.call_deferred(kind)

func removed(kind: String, id: String) -> void:
	var key := kind+":"+id
	epochs[key] = int(epochs.get(key,0))+1
	jobs.erase(key)
	attempted.erase(key)
	var meta := _meta(kind,id,"")
	var image_path := _image(kind,id,str(meta.get("preview_revision","")))
	if not image_path.is_empty() and FileAccess.file_exists(image_path):
		DirAccess.remove_absolute(image_path)
		textures.erase(image_path)
	var path := _base(kind,id)+".json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	metadata.erase(key)
	changed.emit.call_deferred(kind)

func _stored_image(record: Dictionary) -> Image:
	var image: Image = record.get("thumbnail")
	if load("res://scripts/platform_library_store.gd").preview_missing(image): return null
	return image

func _store(kind: String, record: Dictionary, supplied: Image = null, schedule_missing := true) -> void:
	var id: String = record.id
	var stamp := _stamp(kind,id)
	if stamp.is_empty(): return
	var data: Dictionary = record.parameters
	var summary := {}
	match kind:
		"platforms":
			for field in ["width_feet","length_feet","thickness_feet"]: summary[field] = data[field]
		"maps": summary["platform_count"] = data.platforms.size()
		"adventures": summary["map_count"] = data.maps.size()
	var before := _meta(kind,id,"")
	var meta := {"version":VERSION,"id":id,"title":record.title,"kind":record.get("kind",kind),"tags":record.get("tags",[]),"summary":summary,"stamp":stamp,"preview_revision":""}
	if kind=="tokens": meta["visual_key"] = TokenPreviews._key(data)
	var image: Image = supplied if supplied!=null else _stored_image(record)
	if image!=null and not image.is_empty():
		var small: Image = image.duplicate()
		small.convert(Image.FORMAT_RGBA8)
		var scale := minf(320.0/small.get_width(),200.0/small.get_height())
		small.resize(maxi(1,roundi(small.get_width()*scale)),maxi(1,roundi(small.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
		var framed := Image.create(320,200,false,Image.FORMAT_RGBA8)
		framed.fill(Color("e5e7eb"))
		framed.blit_rect(small,Rect2i(Vector2i.ZERO,small.get_size()),(Vector2i(320,200)-small.get_size())/2)
		var revision := Crypto.new().generate_random_bytes(16).hex_encode()
		var path := _image(kind,id,revision)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if framed.save_png(path+".tmp.png")==OK and DirAccess.rename_absolute(path+".tmp.png",path)==OK: meta.preview_revision = revision
	elif kind=="tokens":
		if before.get("visual_key")==meta.visual_key: meta.preview_revision = before.get("preview_revision","")
	if _write(kind,id,meta):
		var old_path := _image(kind,id,str(before.get("preview_revision","")))
		var new_path := _image(kind,id,str(meta.preview_revision))
		if old_path!=new_path and not old_path.is_empty() and FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
			textures.erase(old_path)
	if schedule_missing and str(meta.preview_revision).is_empty(): _enqueue(kind,id,stamp,record)

func _process(_delta: float) -> void:
	if busy: return
	for waiting_key: String in preview_waiters.keys():
		var pending: Dictionary = preview_waiters[waiting_key]
		for reference: WeakRef in pending.views.duplicate():
			var view = reference.get_ref()
			if view==null: pending.views.erase(reference)
			elif TokenPreviews._visible(view):
				_enqueue(pending.kind,pending.id,_stamp(pending.kind,pending.id))
				preview_waiters.erase(waiting_key)
				break
		if pending.views.is_empty(): preview_waiters.erase(waiting_key)
	if jobs.is_empty(): return
	var key: String = jobs.keys()[0]
	var job: Dictionary = jobs[key]
	jobs.erase(key)
	busy = true
	_repair(key,job)

func _repair(key: String, job: Dictionary) -> void:
	var generation := int(epochs.get(key,0))
	attempted[key] = job.stamp
	var loaded: Dictionary = {"ok":true,"record":job.record}
	if job.record.is_empty():
		parsed_count += 1
		print("库索引/缺图按需解析："+key)
		loaded = load(STORES[job.kind]).get_record(job.id)
	if not loaded.ok and generation==int(epochs.get(key,0)) and _stamp(job.kind,job.id)==job.stamp and not str(job.stamp).is_empty():
		var meta := {"version":VERSION,"id":job.id,"title":job.id,"kind":"basic" if job.kind=="tokens" else job.kind,"tags":[],"summary":{},"stamp":job.stamp,"error":loaded.message}
		_write(job.kind,job.id,meta)
	elif loaded.ok and generation==int(epochs.get(key,0)) and _stamp(job.kind,job.id)==job.stamp:
		var record: Dictionary = loaded.record
		var image: Image = _stored_image(record)
		if image==null or image.is_empty(): image = await _render(job.kind,record)
		if generation==int(epochs.get(key,0)) and _stamp(job.kind,job.id)==job.stamp: _store(job.kind,record,image,false)
	busy = false
	changed.emit.call_deferred(str(job.kind))

func _render(kind: String, record: Dictionary) -> Image:
	var renderer: Control
	var data: Dictionary = record.parameters
	if kind=="tokens": renderer = load("res://ui/components/token_thumbnail.gd").new()
	elif kind=="platforms": renderer = load("res://ui/components/platform_preview.gd").new()
	else: renderer = load("res://ui/components/map_preview.gd").new()
	add_child(renderer)
	renderer.position = Vector2(-10000,-10000)
	renderer.size = Vector2(320,200)
	if kind=="tokens": renderer.configure(data)
	elif kind=="platforms":
		renderer.configure(data,true)
		var origin: Vector2 = data.grid_origin_feet/5.0
		for token: Dictionary in data.get("tokens",[]):
			var actor: Node3D = load("res://scripts/token_instance.gd").build(token)
			renderer.actor.add_child(actor)
			var cell: Vector2i = token.cell
			var extent: Vector2i = load("res://scripts/token_footprint.gd").dimensions(token)
			actor.position = Vector3(origin.x+cell.x+extent.x/2.0,float(data.top_feet)/5.0,origin.y+cell.y+extent.y/2.0)
	else:
		if kind=="adventures":
			if data.maps.is_empty(): renderer.queue_free(); return null
			data = data.maps[0].data
		for item: Dictionary in data.platforms: renderer.add_platform(item)
		renderer.frame_all()
		renderer.apply_weather(data.environment)
	for frame in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = renderer.viewport.get_texture().get_image()
	renderer.queue_free()
	return image
