extends Node
const Compatibility = preload("res://scripts/network_compatibility.gd")
const Transport = preload("res://scripts/network_transport.gd")
const Wire = preload("res://scripts/network_wire.gd")
const Ops = preload("res://scripts/network_operations.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Identity = preload("res://scripts/local_identity.gd")
const Settings = preload("res://scripts/network_settings.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Data = preload("res://scripts/adventure_data.gd")
const Runtime = preload("res://scripts/adventure_runtime.gd")
signal status_changed(message: String)
var application: Node
var transport: Transport
var active := false
var hosting := false
var connected := false
var online_members: Array = []
var password := ""
var room_code := ""
var status := "未开放联机"
var revision := 0
var elapsed := 0.0
var last_signature := ""
var baseline: Dictionary = {}
var peer_members: Dictionary = {}
var admitted: Dictionary = {}
var nonces: Dictionary = {}
var accessible: Array = []
var locked: Array = []
var tool_owners: Dictionary = {}
var snapshot_pending: Dictionary = {}
var pending_images: Dictionary = {}
var upload_requested: Dictionary = {}
var sent_manifest: Dictionary = {}
var operation_pending := false
var request_number := 0
var processed: Dictionary = {}
var request_results: Dictionary = {}
var receive_rates: Dictionary = {}
var required_revision := 0
var incoming_snapshot: Dictionary = {}
var waiting_images: Dictionary = {}
var upload_manifest: Dictionary = {}
var waiting_operation: Dictionary = {}
var pending_since := 0
var awaiting_snapshot := false
var requested_images: Dictionary = {}
var retired_images: Dictionary = {}
var last_operation_error := ""
var disconnect_epoch := 0

func _ready() -> void:
	transport = Transport.new()
	add_child(transport)
	transport.room_ready.connect(func(code: String): room_code = code; _status("已开放联机 · "+code))
	transport.peer_ready.connect(_peer_ready)
	transport.peer_left.connect(_peer_left)
	transport.message_received.connect(_message)
	transport.image_received.connect(_image)
	transport.failed.connect(_failure)
	transport.room_ended.connect(_room_ended)

func open_host(secret: String) -> Error:
	if application.adventure.is_empty() or secret.length()>128: return ERR_INVALID_PARAMETER
	close()
	hosting = true
	password = secret
	active = true
	var policy: Dictionary = application.adventure["network"]
	accessible = policy["visible_maps"].duplicate() if policy["configured"] else ([application.current_map_id] if not application.current_map_id.is_empty() else [])
	locked = policy["locked_maps"].duplicate()
	tool_owners = policy["tool_owners"].duplicate(true)
	policy["configured"] = true
	policy["visible_maps"] = accessible.duplicate()
	last_signature = ""
	var settings := Settings.read()
	var error := transport.start(true,settings["address"],settings["certificate"])
	if error!=OK: active = false; _status("无法连接服务，请检查地址和公开证书")
	else: _status("正在开放联机")
	return error

func join(code: String, secret: String) -> Error:
	var identity := Identity.read()
	if not identity["ok"]: _status(identity["message"]); return ERR_INVALID_DATA
	close()
	hosting = false
	active = true
	room_code = code.strip_edges().to_upper()
	password = secret
	var settings := Settings.read()
	var error := transport.start(false,settings["address"],settings["certificate"],room_code)
	if error!=OK: active = false; _status("无法连接服务，请检查地址和公开证书")
	else: _status("正在连接DM")
	return error

func close(notify_host_close := true) -> void:
	disconnect_epoch += 1
	if is_instance_valid(transport): transport.stop(notify_host_close and active and hosting)
	for peer in peer_members: Members.release_connection(application.member_connections,peer_members[peer],str(peer))
	active = false
	connected = false
	online_members.clear()
	accessible.clear()
	locked.clear()
	tool_owners.clear()
	last_signature = ""
	revision = 0
	elapsed = 0.0
	password = ""
	room_code = ""
	peer_members.clear()
	admitted.clear()
	nonces.clear()
	processed.clear()
	request_results.clear()
	receive_rates.clear()
	required_revision = 0
	snapshot_pending.clear()
	pending_images.clear()
	upload_requested.clear()
	sent_manifest.clear()
	operation_pending = false
	awaiting_snapshot = false
	requested_images.clear()
	retired_images.clear()
	last_operation_error = ""
	incoming_snapshot.clear()
	waiting_images.clear()
	upload_manifest.clear()
	waiting_operation.clear()
	baseline.clear()
	_status("未开放联机")

func _status(message: String) -> void:
	status = message
	status_changed.emit(message)
	if application.board!=null: application.board.ui.show_network_notice(message)

func _peer_ready(peer: int) -> void:
	if hosting:
		var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
		nonces[peer] = {"nonce":nonce,"time":Time.get_ticks_msec()}
		transport.send_message(peer,{"type":"challenge","version":Compatibility.local_version(),"nonce":nonce})

func _peer_left(peer: int) -> void:
	if hosting:
		if peer_members.has(peer):
			Members.release_connection(application.member_connections,peer_members[peer],str(peer))
		peer_members.erase(peer)
		admitted.erase(peer)
		nonces.erase(peer)
		pending_images.erase(peer)
		upload_requested.erase(peer)
		sent_manifest.erase(peer)
		processed.erase(peer)
		request_results.erase(peer)
		receive_rates.erase(peer)
		_broadcast()
		application.refresh_network_map_collection()
	elif peer==1 and active:
		# The data channel can close before the coordinator delivers the reason.
		connected = false
		if application.board!=null: application.board.set_application_active(false,true)
		var epoch := disconnect_epoch
		await get_tree().create_timer(2.5).timeout
		if active and epoch==disconnect_epoch: _failure("与DM的连接已断开，可使用原身份码重新加入")

func _room_ended(active_close: bool) -> void:
	if not active or hosting: return
	close(false)
	application.remote_session_ended.call_deferred(active_close)

func _failure(reason: String) -> void:
	var was_host := hosting
	close(false)
	_status(reason)
	if not was_host and application.session_role=="pl":
		if application.board!=null: application.board.set_application_active(false,true)
		application._navigate("session_menu")

func _process(delta: float) -> void:
	if not active: return
	elapsed += delta
	if elapsed<0.5: return
	elapsed = 0.0
	if hosting:
		for peer in nonces.keys():
			if Time.get_ticks_msec()-nonces[peer]["time"]>20000: nonces.erase(peer); transport.kick(peer)
		_capture()
		var signature := Data.signature(application.adventure)
		if signature!=last_signature:
			last_signature = signature
			revision += 1
			_broadcast()
	else:
		_finish_snapshot()
		if awaiting_snapshot or not connected:
			if pending_since>0 and Time.get_ticks_msec()-pending_since>60000: _failure("场景同步超时，请重新加入")
			return
		if operation_pending:
			if Time.get_ticks_msec()-pending_since>30000: _failure("操作确认超时，请重新加入以恢复母机状态")
			return
		if not connected or baseline.is_empty() or not _idle(): return
		_capture()
		if Wire.state_signature(application.adventure)==Wire.state_signature(baseline): return
		var changes := Wire.changes(baseline,application.adventure,application.current_map_id)
		if not Wire.has_changes(baseline,changes): return
		request_number += 1
		changes["type"] = "operation"
		changes["base"] = revision
		changes["request"] = request_number
		operation_pending = true
		last_operation_error = ""
		_status("正在等待母机确认")
		pending_since = Time.get_ticks_msec()
		waiting_operation = changes
		var manifest := {}
		for item in changes["changed"]:
			var decoded := Ops.Instance.decode(item["token"])
			if not decoded["ok"]: _failure(decoded["message"]); return
			for id: String in Ops.Instance.images(decoded["parameters"]):
				var loaded := Images.load_image(id)
				if not loaded["ok"]: _failure(loaded["message"]); return
				manifest[id] = loaded["data"].size()
		application.board.network_readonly = true
		transport.send_message(1,{"type":"upload_offer","manifest":manifest})

func _idle() -> bool:
	if application.board==null: return false
	if not hosting and application.current_route not in ["board","session_maps","session_menu"]: return false
	if is_instance_valid(application.token_edit_layer) or is_instance_valid(application.session_modal) or application.tray_controller.blocked(): return false
	var board: Node3D = application.board
	return board.tool not in [2,4] and not board.ui.get_node("TokenCreate").visible and not board.measure_creating and board.measurement.editing_index<0 and not board.shape_plan.dirty() and not board.ui.rename_open() and not board.ui.notes_editing() and not board.turn_control.dragging

func _exit_tree() -> void:
	if is_instance_valid(transport): transport.stop()

func _capture() -> void:
	if application.board==null or not _idle(): return
	# Observe only committed state; never cancel a gesture for network polling.
	application.board.export_session_tokens()
	application.adventure["runtime"]["maps"][application.current_map_id] = Runtime.capture(application.board)
	application.adventure["party"] = Members.normalized(application.adventure)
	application.board.session_party = application.adventure["party"]

func _message(peer: int, message: Dictionary) -> void:
	if not active: return
	if hosting:
		var now := Time.get_ticks_msec()
		var bucket: Dictionary = receive_rates.get(peer,{"time":now,"count":0})
		if now-bucket["time"]>=1000: bucket = {"time":now,"count":0}
		bucket["count"] += 1
		receive_rates[peer] = bucket
		if bucket["count"]>16: transport.kick(peer); return
	var kind: Variant = message.get("type")
	if hosting:
		if kind=="authenticate":
			_authenticate(peer,message)
			return
		if not admitted.has(peer): transport.kick(peer); return
		var actor: String = peer_members[peer]
		match kind:
			"images_needed": _send_images(peer,message)
			"upload_offer": _offer(peer,message)
			"operation": _operation(peer,actor,message)
			"switch_map":
				if not message.get("map") is String or message["map"] not in accessible:
					_send_snapshot(peer)
					return
				Members.set_map(application.adventure,actor,message["map"])
				_send_snapshot(peer)
				_broadcast()
			"leave": transport.kick(peer)
	else:
		if peer!=1: return
		match kind:
			"challenge":
				var mismatch := Compatibility.mismatch(message.get("version"))
				if not mismatch.is_empty(): _failure(mismatch); return
				if not message.get("nonce") is String: _failure("联机验证消息无效"); return
				var identity := Identity.read()
				if not identity["ok"]: _failure(identity["message"]); return
				transport.send_message(1,{"type":"authenticate","nonce":message["nonce"],"password":password,"code":identity["data"]["code"],"nickname":identity["data"]["nickname"],"version":Compatibility.local_version()})
				password = ""
			"rejected": _failure(str(message.get("reason","DM拒绝加入")))
			"snapshot": _snapshot(message)
			"upload_needed":
				if not operation_pending or not message.get("ids") is Array or message["ids"].size()>128: return
				for id in message["ids"]:
					var loaded := Images.load_image(id)
					if not loaded["ok"]: _failure(loaded["message"]); return
					if not transport.send_image(1,id,loaded["data"]): _failure("图片待发送队列已满"); return
			"upload_ready":
				if operation_pending: transport.send_message(1,waiting_operation)
			"operation_result":
				if int(message.get("request",-1))!=request_number: return
				operation_pending = false
				awaiting_snapshot = true
				required_revision = int(message.get("revision",revision))
				waiting_operation.clear()
				if not message.get("ok",false):
					last_operation_error = str(message.get("reason","操作未生效"))
					_status(last_operation_error)

func _authenticate(peer: int, message: Dictionary) -> void:
	if admitted.has(peer) or not nonces.has(peer): transport.kick(peer); return
	var mismatch := Compatibility.mismatch(message.get("version"))
	if not mismatch.is_empty():
		nonces.erase(peer)
		transport.send_message(peer,{"type":"rejected","reason":mismatch})
		return
	var valid: bool = message.get("nonce")==nonces[peer]["nonce"] and message.get("password") is String and message["password"]==password
	nonces.erase(peer)
	if not valid:
		transport.send_message(peer,{"type":"rejected","reason":"密码或联机验证信息错误"})
		return
	if not message.get("code") is String or not message.get("nickname") is String: transport.kick(peer); return
	var joined := Members.join(application.adventure,message["code"],message["nickname"],str(peer),application.member_connections)
	if not joined["ok"]:
		transport.send_message(peer,{"type":"rejected","reason":joined["message"]})
		return
	peer_members[peer] = joined["member_id"]
	admitted[peer] = true
	processed[peer] = 0
	var map_id: String = application.adventure["party"]["positions"].get(joined["member_id"],"")
	if map_id not in accessible: map_id = str(accessible[0]) if not accessible.is_empty() else ""
	if not map_id.is_empty(): Members.set_map(application.adventure,joined["member_id"],map_id)
	_send_snapshot(peer)
	if is_instance_valid(application.tray_controller.panel): application.tray_controller._refresh()
	application.refresh_network_map_collection()

func _send_snapshot(peer: int) -> void:
	if not admitted.has(peer): return
	var actor: String = peer_members[peer]
	var filtered := Wire.view(application.adventure,actor,accessible)
	filtered["runtime"]["current_map_id"] = application.adventure["party"]["positions"].get(actor,"")
	var packed := Wire.pack(filtered,application.adventure_id)
	if not packed["ok"]: transport.send_message(peer,{"type":"rejected","reason":packed["message"]}); return
	sent_manifest[peer] = packed["manifest"]
	transport.send_message(peer,{"type":"snapshot","revision":revision,"actor":actor,"record":packed["record"],"manifest":packed["manifest"],"online":peer_members.values(),"locked":filtered["network"]["locked_maps"],"tool_owners":filtered["network"]["tool_owners"]})

func _broadcast() -> void:
	for peer in admitted.keys(): _send_snapshot(peer)

func _send_images(peer: int, message: Dictionary) -> void:
	if not message.get("ids") is Array or message["ids"].size()>128 or not sent_manifest.has(peer): return
	for id in message["ids"]:
		if not id is String: transport.kick(peer); return
		if not sent_manifest[peer].has(id): _send_snapshot(peer); return
		var loaded := Images.load_image(id)
		if not loaded["ok"] or not transport.send_image(peer,id,loaded["data"]): transport.kick(peer); return

func _offer(peer: int, message: Dictionary) -> void:
	var manifest: Variant = message.get("manifest")
	if not _valid_manifest(manifest): transport.kick(peer); return
	pending_images[peer] = {}
	upload_requested[peer] = {}
	var needed: Array = []
	for id in manifest:
		if not Images.load_image(id)["ok"]:
			needed.append(id)
			pending_images[peer][id] = manifest[id]
	_request_upload(peer)
	if needed.is_empty(): transport.send_message(peer,{"type":"upload_ready"})

func _valid_manifest(manifest: Variant) -> bool:
	if not manifest is Dictionary or manifest.size()>128: return false
	var bytes := 0
	for id in manifest:
		if not Images.valid_id(id) or not Runtime.number(manifest[id],1,2500000): return false
		bytes += int(manifest[id])
	return bytes<=64*1024*1024

func _image(peer: int, id: String, bytes: PackedByteArray) -> void:
	var expected: Dictionary = pending_images.get(peer,{}) if hosting else requested_images
	if not hosting and retired_images.has(id): expected = retired_images
	if not active or (hosting and not admitted.has(peer)) or (not hosting and peer!=1) or not expected.has(id) or bytes.size()!=int(expected[id]) or Images.content_id(bytes)!=id: transport.kick(peer); return
	var header := Images._header(bytes)
	var free_memory := int(OS.get_memory_info().get("free",-1))
	if header.is_empty() or free_memory>0 and float(header["width"])*float(header["height"])*16.0>free_memory*0.5:
		_status("图片格式无效或当前可用内存不足，未解码该图片。")
		return
	var saved := Images.save_image(bytes)
	if not saved["ok"]: _status(saved["message"]); return
	expected.erase(id)
	if hosting:
		upload_requested.get(peer,{}).erase(id)
		if expected.is_empty(): transport.send_message(peer,{"type":"upload_ready"})
		else: _request_upload(peer)
	else:
		waiting_images.erase(id)
		_request_images()
		_finish_snapshot()

func _operation(peer: int, actor: String, message: Dictionary) -> void:
	var request: Variant = message.get("request")
	if not Runtime.number(request,1,2147483646) or float(request)!=int(request): transport.kick(peer); return
	if int(request)<=int(processed.get(peer,0)):
		_send_snapshot(peer)
		var cached: Dictionary = request_results.get(peer,{"ok":false,"reason":"请求已过期"}) if int(request)==int(processed.get(peer,0)) else {"ok":false,"reason":"请求已过期"}
		transport.send_message(peer,{"type":"operation_result","request":request,"ok":cached["ok"],"reason":cached.get("reason",""),"revision":revision})
		return
	_capture()
	var signature := Data.signature(application.adventure)
	if signature!=last_signature:
		last_signature = signature
		revision += 1
	var result: Dictionary
	if not _idle(): result = Ops.error("DM正在编辑，本次操作未生效，请稍后重试。")
	elif message.get("base")!=revision: result = Ops.error("母机状态已更新，本次操作未生效。")
	elif message.get("map") in locked: result = Ops.error("该地图已锁定操作。")
	else: result = Ops.apply(application.adventure,actor,accessible,message,tool_owners)
	processed[peer] = int(request)
	if result["ok"]:
		application.adventure = result["data"]
		tool_owners = result["tool_owners"]
		application.adventure["network"]["tool_owners"] = tool_owners
		revision += 1
		last_signature = Data.signature(application.adventure)
		application.reload_network_board()
	request_results[peer] = {"ok":result["ok"],"reason":result.get("message","")}
	transport.send_message(peer,{"type":"operation_result","request":request,"ok":result["ok"],"reason":result.get("message",""),"revision":revision})
	_broadcast()

func _snapshot(message: Dictionary) -> void:
	if not message.get("record") is Dictionary or not message.get("actor") is String or not _valid_manifest(message.get("manifest")): _failure("母机场景数据无效"); return
	if not Runtime.number(message.get("revision"),0,2147483647) or int(message["revision"])<required_revision: return
	for id in requested_images.keys():
		if not message["manifest"].has(id):
			retired_images[id] = requested_images[id]
			requested_images.erase(id)
	while retired_images.size()>128: retired_images.erase(retired_images.keys()[0])
	incoming_snapshot = message
	pending_since = Time.get_ticks_msec()
	waiting_images = {}
	var needed: Array = []
	for id in message["manifest"]:
		var loaded := Images.load_image(id)
		if not loaded["ok"]:
			needed.append(id)
			waiting_images[id] = message["manifest"][id]
	_request_images()
	_finish_snapshot()

func _finish_snapshot() -> void:
	if incoming_snapshot.is_empty() or not waiting_images.is_empty() or operation_pending: return
	if int(incoming_snapshot.get("revision",0))<required_revision:
		incoming_snapshot.clear()
		return
	if application.session_role=="pl" and not _idle() and application.board!=null: return
	if connected and not awaiting_snapshot and not baseline.is_empty():
		_capture()
		if Wire.state_signature(application.adventure)!=Wire.state_signature(baseline): return
	var snapshot := incoming_snapshot
	incoming_snapshot = {}
	var loaded := Wire.unpack(snapshot["record"],snapshot["manifest"])
	if not loaded["ok"]: _failure(loaded["message"]); return
	if not loaded["record"]["parameters"]["party"]["members"].has(snapshot["actor"]) or snapshot["actor"]=="dm": _failure("母机成员数据无效"); return
	application.adventure = loaded["record"]["parameters"]
	application.adventure_id = loaded["record"]["id"]
	application.session_actor = snapshot["actor"]
	application.session_role = "pl"
	application.current_map_id = application.adventure["runtime"]["current_map_id"]
	revision = int(snapshot.get("revision",0))
	online_members = snapshot.get("online",[])
	tool_owners = snapshot.get("tool_owners",{})
	locked = snapshot.get("locked",[])
	baseline = application.adventure.duplicate(true)
	connected = true
	awaiting_snapshot = false
	application.reload_network_board()
	_status("已加入团" if last_operation_error.is_empty() else last_operation_error)

func switch_map(id: String) -> void:
	if not hosting and connected and not operation_pending:
		awaiting_snapshot = true
		pending_since = Time.get_ticks_msec()
		if application.board!=null: application.board.network_readonly = true
		transport.send_message(1,{"type":"switch_map","map":id})

func set_map_access(id: String, visible: bool) -> void:
	if not hosting: return
	if visible and id not in accessible: accessible.append(id)
	elif not visible: accessible.erase(id)
	for actor in peer_members.values():
		if application.adventure["party"]["positions"].get(actor) not in accessible:
			application.adventure["party"]["positions"][actor] = str(accessible[0]) if not accessible.is_empty() else ""
	application.adventure["network"]["visible_maps"] = accessible.duplicate()
	_broadcast()

func set_map_locked(id: String, value: bool) -> void:
	if not hosting: return
	if value and id not in locked: locked.append(id)
	elif not value: locked.erase(id)
	application.adventure["network"]["locked_maps"] = locked.duplicate()
	_broadcast()

func _request_images() -> void:
	var ids: Array = []
	for id in waiting_images:
		if requested_images.has(id): continue
		if requested_images.size()>=2: break
		requested_images[id] = waiting_images[id]
		ids.append(id)
	if not ids.is_empty(): transport.send_message(1,{"type":"images_needed","ids":ids})

func _request_upload(peer: int) -> void:
	var ids: Array = []
	var requested: Dictionary = upload_requested.get(peer,{})
	for id in pending_images.get(peer,{}):
		if requested.has(id): continue
		if requested.size()>=2: break
		requested[id] = true
		ids.append(id)
	if not ids.is_empty(): transport.send_message(peer,{"type":"upload_needed","ids":ids})
