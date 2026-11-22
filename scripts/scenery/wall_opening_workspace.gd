extends Node3D

# Public editing seam. The host owns camera/input/save/permissions; this node owns
# transactional layouts, generated scene replacement, previews and bounded history.
signal layout_changed(layout: Dictionary, reason: String, revision: int)
signal selection_changed(opening_id: String)
signal preview_changed(preview: Dictionary)
signal busy_changed(busy: bool)
signal operation_failed(message: String)

const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const Query = preload("res://scripts/scenery/wall_surface_query.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const HISTORY_LIMIT := 64

var _layout := Data.empty()
var _selection := ""
var _revision := 0
var _busy := false
var _build_token := 0
var _visual: Node3D
var _history: Array[Dictionary] = []
var _cursor := -1
var _session: Dictionary = {}
var _preview: Dictionary = {}
var _id_serial := 0

func snapshot() -> Dictionary:
	return _layout.duplicate(true)

func revision() -> int:
	return _revision

func is_busy() -> bool:
	return _busy

func selected_id() -> String:
	return _selection

func selected_record() -> Dictionary:
	var location := Data.find_opening(_layout,_selection)
	if location.x<0: return {}
	var entry: Dictionary = _layout.walls[location.x]
	return {"id":_selection,"wall_id":entry.id,"spec":entry.openings[location.y].spec.duplicate(true),
		"anchor":Data.anchor(entry.parameters,entry.openings[location.y].spec)}

func select_opening(id: String) -> Dictionary:
	if _busy or not _session.is_empty(): return _failure("请先结束当前编辑")
	if not id.is_empty() and Data.find_opening(_layout,id).x<0: return _failure("门窗不存在")
	_set_selection(id)
	return {"ok":true,"message":""}

func can_undo() -> bool:
	return not _busy and _session.is_empty() and _cursor>0

func can_redo() -> bool:
	return not _busy and _session.is_empty() and _cursor>=0 and _cursor<_history.size()-1

func has_preview() -> bool:
	return not _session.is_empty()

func preview() -> Dictionary:
	return _preview.duplicate(true)

func export_json() -> Dictionary:
	return Data.to_json(_layout)

func import_json(text: String) -> Dictionary:
	var parsed := Data.from_json(text)
	if not parsed.ok: return _failure(parsed.message)
	return await replace_layout(parsed.layout,"导入布局")

# Initial load uses reset_history=true; subsequent replacements are one undo entry.
func replace_layout(layout: Dictionary, reason := "替换布局", reset_history := false) -> Dictionary:
	if _busy or has_preview(): return _failure("当前正在编辑或生成")
	return await _commit(layout.duplicate(true),reason,_selection,reset_history,-1)

# Commands are strict dictionaries. See docs for exact command keys. No direct
# scene mutation is needed; changing the host wall retains all attached openings.
func execute(command: Dictionary, expected_revision := -1) -> Dictionary:
	if _busy or has_preview(): return _failure("当前正在编辑或生成")
	if expected_revision>=0 and expected_revision!=_revision: return _failure("布局版本已变化，请重新读取后修改")
	var proposal := _propose(command)
	if not proposal.ok: return _failure(proposal.message)
	return await _commit(proposal.layout,str(command.op),proposal.selection,false,-1)

func check_command(command: Dictionary) -> Dictionary:
	# Pure candidate check; this does not reserve an edit or run CSG.
	return _propose(command)

func undo() -> Dictionary:
	if not can_undo(): return _failure("当前不能撤销")
	var index := _cursor-1
	return await _commit(_history[index].layout.duplicate(true),"撤销",_history[index].selection,false,index)

func redo() -> Dictionary:
	if not can_redo(): return _failure("当前不能重做")
	var index := _cursor+1
	return await _commit(_history[index].layout.duplicate(true),"重做",_history[index].selection,false,index)

# Cancel a pending async build without destroying the last committed scene.
# Busy clears only when the existing build returns, preventing concurrent CSG writes.
func cancel_pending() -> void:
	_build_token+=1
	cancel_preview()

func pick_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	var ray := _local_ray(origin,direction)
	var hit := Query.pick(_layout,ray.origin,ray.direction)
	if hit.ok:
		hit.point=global_transform*hit.point
		hit.distance=origin.distance_to(hit.point)
	return hit

# A formal game's physics ray may hit an open leaf outside the original aperture.
# Map its collision body back to stable IDs without knowing generated node paths.
func identify_collider(collider: Node) -> Dictionary:
	if collider==null or not is_ancestor_of(collider): return Data.fail("碰撞体不属于此布局")
	var opening_id := ""
	var wall_id := ""
	var cursor: Node = collider
	while cursor!=self:
		if cursor.has_meta("layout_opening_id"): opening_id=str(cursor.get_meta("layout_opening_id"))
		if cursor.has_meta("layout_wall_id"): wall_id=str(cursor.get_meta("layout_wall_id"))
		cursor=cursor.get_parent()
	if wall_id.is_empty(): return Data.fail("不是墙体或门窗碰撞体")
	return {"ok":true,"message":"","wall_id":wall_id,"opening_id":opening_id}

# Start create, then aim_ray as pointer moves; host decides when to commit.
func begin_create(spec: Dictionary) -> Dictionary:
	if _busy or has_preview(): return _failure("当前正在编辑或生成")
	var error := P.validate(spec)
	if not error.is_empty(): return _failure(error)
	_session={"mode":"create","id":_new_id(),"spec":spec.duplicate(true),"revision":_revision}
	_preview={"ok":false,"message":"请指向墙面","active":true}
	preview_changed.emit(preview())
	return {"ok":true,"message":""}

# Ray passed at press time defines the offset and locks the host plane. Movement
# stays on that plane even when the pointer crosses an aperture or another wall.
func begin_move(id: String, origin: Vector3, direction: Vector3, face: int) -> Dictionary:
	if _busy or has_preview(): return _failure("当前正在编辑或生成")
	var at := Data.find_opening(_layout,id)
	if at.x<0: return _failure("门窗不存在")
	var wall: Dictionary = _layout.walls[at.x]
	var ray := _local_ray(origin,direction)
	var hit := Query.project(wall,ray.origin,ray.direction,face)
	if not hit.ok: return _failure(hit.message)
	var spec: Dictionary = wall.openings[at.y].spec
	_session={"mode":"move","id":id,"spec":spec.duplicate(true),"wall_id":wall.id,"face":face,
		"grab_offset":Data.anchor(wall.parameters,spec)-hit.point_feet,"start_anchor":Data.anchor(wall.parameters,spec),"revision":_revision}
	_set_selection(id)
	return aim_ray(origin,direction,0.0)

# step_feet=0 is free placement. Snapping affects preview only, never exact commands.
func aim_ray(origin: Vector3, direction: Vector3, step_feet := 0.0) -> Dictionary:
	if _busy or _session.is_empty(): return Data.fail("没有正在编辑的门窗")
	if not is_finite(step_feet) or step_feet<0: return _invalid_preview("吸附步长无效")
	var ray := _local_ray(origin,direction)
	var hit: Dictionary
	if _session.mode=="create":
		hit=Query.pick(_layout,ray.origin,ray.direction)
	else:
		var wi := Data.find_wall(_layout,_session.wall_id)
		hit=Query.project(_layout.walls[wi],ray.origin,ray.direction,_session.face)
	if not hit.ok: return _invalid_preview(hit.message)
	var point: Vector2 = hit.point_feet+_session.get("grab_offset",Vector2.ZERO)
	if step_feet>0:
		var base: Vector2 = _session.get("start_anchor",Vector2.ZERO)
		point=base+(point-base).snapped(Vector2.ONE*step_feet)
	var wi := Data.find_wall(_layout,hit.wall_id)
	var spec := Data.at_anchor(_layout.walls[wi].parameters,_session.spec,point)
	if _session.mode=="create": spec.mounting="front" if hit.face==1 else "back"
	var command: Dictionary
	if _session.mode=="create":
		command={"op":"add_opening","wall_id":hit.wall_id,"id":_session.id,"spec":spec}
	else:
		command={"op":"update_opening","id":_session.id,"wall_id":hit.wall_id,"spec":spec}
	var proposed := _propose(command)
	_preview={"active":true,"ok":proposed.ok,"message":proposed.message,"wall_id":hit.wall_id,"id":_session.id,
		"spec":spec,"anchor":point,"face":hit.face,"command":command,"wall":_layout.walls[wi].duplicate(true)}
	preview_changed.emit(preview())
	return preview()

func commit_preview() -> Dictionary:
	if _busy or _session.is_empty() or not _preview.get("ok",false): return _failure("当前预览不能提交")
	if _session.revision!=_revision: return _failure("布局已变化，请重新放置")
	var proposal := _propose(_preview.command)
	if not proposal.ok: return _failure(proposal.message)
	return await _commit(proposal.layout,"放置/移动门窗",proposal.selection,false,-1)

func cancel_preview() -> void:
	_session.clear()
	_preview.clear()
	preview_changed.emit({})

func _invalid_preview(message: String) -> Dictionary:
	_preview={"active":true,"ok":false,"message":message}
	preview_changed.emit(preview())
	return preview()

func _local_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	var inverse := global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()
	return {"origin":inverse*origin,"direction":inverse.basis*direction}

func _new_id() -> String:
	while true:
		_id_serial+=1
		var id := "opening-%d"%_id_serial
		if Data.find_wall(_layout,id)<0 and Data.find_opening(_layout,id).x<0: return id
	return ""

func _propose(command: Dictionary) -> Dictionary:
	var keys := {"add_opening":["op","wall_id","id","spec"],"update_opening":["op","id","wall_id","spec"],
		"remove_opening":["op","id"],"add_wall":["op","wall"],"update_wall":["op","id","parameters","transform"],"remove_wall":["op","id"]}
	if not command.get("op") is String or not keys.has(command.op) or not Data.exact(command,keys[command.op]): return Data.fail("编辑命令字段无效")
	var next := snapshot()
	var selection := _selection
	match command.op:
		"add_opening","update_opening":
			if not command.id is String or not command.wall_id is String or not command.spec is Dictionary: return Data.fail("门窗命令类型无效")
			var target := Data.find_wall(next,command.wall_id)
			if target<0: return Data.fail("目标墙体不存在")
			if command.op=="update_opening":
				var at := Data.find_opening(next,command.id)
				if at.x<0: return Data.fail("门窗不存在")
				if at.x==target:
					next.walls[target].openings[at.y].spec=command.spec.duplicate(true)
				else:
					next.walls[at.x].openings.remove_at(at.y)
					next.walls[target].openings.append({"id":command.id,"spec":command.spec.duplicate(true)})
			else:
				next.walls[target].openings.append({"id":command.id,"spec":command.spec.duplicate(true)})
			selection=command.id
		"remove_opening":
			if not command.id is String: return Data.fail("门窗编号无效")
			var at := Data.find_opening(next,command.id)
			if at.x<0: return Data.fail("门窗不存在")
			next.walls[at.x].openings.remove_at(at.y)
			if selection==command.id: selection=""
		"add_wall":
			if not command.wall is Dictionary: return Data.fail("墙体记录无效")
			next.walls.append(command.wall.duplicate(true))
		"update_wall":
			if not command.id is String: return Data.fail("墙体编号无效")
			var at := Data.find_wall(next,command.id)
			if at<0: return Data.fail("墙体不存在")
			if not command.parameters is Dictionary: return Data.fail("墙体参数无效")
			var error := preload("res://scripts/scenery/wall_parameters.gd").validate(command.parameters)
			if not error.is_empty(): return Data.fail(error)
			# Keep the left-origin mounting coordinates when changing wall length.
			for item in next.walls[at].openings:
				item.spec=Data.at_anchor(command.parameters,item.spec,Data.anchor(next.walls[at].parameters,item.spec))
			next.walls[at].parameters=command.parameters.duplicate(true)
			next.walls[at].transform=command.transform
		"remove_wall":
			if not command.id is String: return Data.fail("墙体编号无效")
			var at := Data.find_wall(next,command.id)
			if at<0: return Data.fail("墙体不存在")
			next.walls.remove_at(at)
	var result := Data.validate(next)
	if not result.ok: return result
	if Data.find_opening(next,selection).x<0: selection=""
	return {"ok":true,"message":"","layout":next,"selection":selection}

func _commit(next: Dictionary, reason: String, selection: String, reset: bool, history_index: int) -> Dictionary:
	if not is_inside_tree(): return _failure("编辑工作区须先加入场景树")
	var checked := Data.validate(next)
	if not checked.ok: return _failure(checked.message)
	# Establish the write guard before emitting preview/busy signals: listeners
	# cannot start a second transaction between clearing the draft and building.
	_busy=true
	_build_token+=1
	var token := _build_token
	busy_changed.emit(true)
	if has_preview(): cancel_preview()
	if token!=_build_token:
		_finish_busy()
		return _failure("生成已取消")
	if next==_layout and not reset:
		_set_selection(selection)
		_finish_busy()
		return {"ok":true,"message":"没有变化","changed":false}
	var generated := await Joiner.build(checked.descriptors)
	if token!=_build_token or not is_inside_tree():
		_finish_busy()
		return _failure("生成已取消")
	if not generated.ok:
		_finish_busy()
		return _failure(generated.message)
	var replacement := Node3D.new()
	replacement.name="GeneratedLayout"
	for i in next.walls.size():
		var ids: Array[String] = []
		for item in next.walls[i].openings: ids.append(item.id)
		var wall := Assembly.instantiate(generated.parts[i],ids)
		if wall==null:
			replacement.free()
			_finish_busy()
			return _failure("墙体与门窗实例创建失败")
		wall.name="Wall_"+next.walls[i].id
		wall.transform=next.walls[i].transform
		wall.set_meta("layout_wall_id",next.walls[i].id)
		replacement.add_child(wall)
	if _visual!=null:
		remove_child(_visual)
		_visual.queue_free()
	_visual=replacement
	add_child(_visual)
	var before := snapshot()
	var before_selection := _selection
	_layout=next.duplicate(true)
	_revision+=1
	if Data.find_opening(_layout,selection).x<0: selection=""
	_selection=selection
	if reset:
		_history.clear()
		_cursor=-1
	if history_index>=0:
		_cursor=history_index
	else:
		if _history.is_empty() and not reset:
			# Also retain an empty workspace when the first operation is add_wall.
			_history.append({"layout":before,"selection":before_selection})
			_cursor=0
		_history.resize(_cursor+1)
		_history.append({"layout":snapshot(),"selection":_selection})
		if _history.size()>HISTORY_LIMIT: _history.pop_front()
		_cursor=_history.size()-1
	# Signals still see busy=true; synchronous reentrant edits are rejected.
	layout_changed.emit(snapshot(),reason,_revision)
	selection_changed.emit(_selection)
	var committed_revision := _revision
	_finish_busy()
	return {"ok":true,"message":"","changed":true,"revision":committed_revision}

func _set_selection(id: String) -> void:
	if _selection==id: return
	_selection=id
	selection_changed.emit(id)

func _finish_busy() -> void:
	_busy=false
	busy_changed.emit(false)

func _failure(message: String) -> Dictionary:
	operation_failed.emit(message)
	return Data.fail(message)

func _exit_tree() -> void:
	_build_token+=1
	_session.clear()
