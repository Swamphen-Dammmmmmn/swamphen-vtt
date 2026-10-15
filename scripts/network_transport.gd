extends Node
const Compatibility = preload("res://scripts/network_compatibility.gd")

signal room_ready(code: String)
signal peer_ready(peer: int)
signal peer_left(peer: int)
signal message_received(peer: int, message: Dictionary)
signal image_received(peer: int, id: String, bytes: PackedByteArray)
signal failed(reason: String)
signal room_ended(active_close: bool)

const CHUNK := 12000
const MAX_MESSAGE := 8*1024*1024
const MAX_QUEUE := 32*1024*1024
var socket := WebSocketPeer.new()
var peers: Dictionary = {}
var assemblies: Dictionary = {}
var hosting := false
var room := ""
var started := false
var opened := false
var ice: Array = []
var transfer_id := 1
var connect_at := 0
var last_signal := 0
var closing_sockets: Array = []

func start(host: bool, address: String, certificate: String, code := "") -> Error:
	stop()
	var chain := X509Certificate.new()
	var error := chain.load(certificate)
	if error!=OK: return error
	if not address.begins_with("wss://"): return ERR_INVALID_PARAMETER
	hosting = host
	room = code.strip_edges().to_upper()
	started = true
	connect_at = Time.get_ticks_msec()
	error = socket.connect_to_url(address,TLSOptions.client(chain))
	if error!=OK: started = false
	return error

func stop(host_closed := false) -> void:
	var previous := socket
	var state := previous.get_ready_state()
	previous.close(1000,"host_closed" if host_closed and hosting and opened else "")
	if state in [WebSocketPeer.STATE_OPEN,WebSocketPeer.STATE_CLOSING]:
		closing_sockets.append({"socket":previous,"deadline":Time.get_ticks_msec()+2000})
	started = false
	opened = false
	socket = WebSocketPeer.new()
	for id in peers: peers[id]["connection"].close()
	peers.clear()
	assemblies.clear()

func wait_for_close() -> void:
	while not closing_sockets.is_empty():
		await get_tree().process_frame

func _poll_closing() -> void:
	for item: Dictionary in closing_sockets.duplicate():
		var previous: WebSocketPeer = item["socket"]
		previous.poll()
		if previous.get_ready_state()==WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec()>=item["deadline"]:
			previous.close()
			closing_sockets.erase(item)

func kick(peer: int) -> void:
	_signal({"type":"kick","peer":peer})
	_drop(peer)

func send_message(peer: int, message: Dictionary) -> bool:
	if _queue(peer,0,JSON.stringify(message).to_utf8_buffer()): return true
	if hosting: kick(peer)
	else: _fatal("同步待发送队列已满，请重新加入")
	return false

func send_image(peer: int, id: String, bytes: PackedByteArray) -> bool:
	if id.length()!=64 or bytes.size()>2500000: return false
	var payload := id.to_utf8_buffer()
	payload.append_array(bytes)
	return _queue(peer,1,payload)

func _queue(peer: int, channel: int, bytes: PackedByteArray) -> bool:
	if not peers.has(peer) or bytes.size()>MAX_MESSAGE: return false
	var record: Dictionary = peers[peer]
	if record["queued"]+bytes.size()>MAX_QUEUE: return false
	record["queued"] += bytes.size()
	transfer_id = (transfer_id+1)%2147483647
	for offset in range(0,bytes.size(),CHUNK):
		var frame := PackedByteArray()
		frame.resize(13)
		frame[0] = channel
		frame.encode_u32(1,transfer_id)
		frame.encode_u32(5,offset)
		frame.encode_u32(9,bytes.size())
		frame.append_array(bytes.slice(offset,mini(offset+CHUNK,bytes.size())))
		record["queues"][channel].append(frame)
	return true

func _process(_delta: float) -> void:
	_poll_closing()
	if not started: return
	socket.poll()
	var state := socket.get_ready_state()
	if state==WebSocketPeer.STATE_OPEN:
		if not opened:
			opened = true
			_signal({"type":"create","version":Compatibility.local_version()} if hosting else {"type":"join","room":room,"version":Compatibility.local_version()})
		while socket.get_available_packet_count()>0:
			var bytes := socket.get_packet()
			if bytes.size()>65536: _fatal("连接协调消息超出限制"); return
			var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if not raw is Dictionary: _fatal("连接协调消息无效"); return
			_handle_signal(raw)
			if not started: return
	elif state==WebSocketPeer.STATE_CLOSED and opened:
		_fatal("连接协调服务已断开")
		return
	elif Time.get_ticks_msec()-connect_at>20000 and not opened:
		_fatal("连接服务超时，请检查地址和公开证书")
		return
	for id in peers.keys():
		if not peers.has(id): continue
		var record: Dictionary = peers[id]
		record["connection"].poll()
		if record["connection"].get_connection_state()==WebRTCPeerConnection.STATE_CONNECTED: record["last_connected"] = Time.get_ticks_msec()
		elif record["ready"] and Time.get_ticks_msec()-record["last_connected"]>15000:
			_drop(id)
			continue
		if record["connection"].get_connection_state() in [WebRTCPeerConnection.STATE_FAILED,WebRTCPeerConnection.STATE_CLOSED]:
			_drop(id)
			continue
		if not record["ready"] and record["channels"][0].get_ready_state()==WebRTCDataChannel.STATE_OPEN:
			record["ready"] = true
			peer_ready.emit(id)
		if not record["ready"] and Time.get_ticks_msec()-record["started"]>30000:
			_drop(id)
			continue
		for channel in range(2):
			var data: WebRTCDataChannel = record["channels"][channel]
			if data.get_ready_state()!=WebRTCDataChannel.STATE_OPEN: continue
			for _packet in range(4 if channel==0 else 1):
				if record["queues"][channel].is_empty() or data.get_buffered_amount()>65536: break
				var frame: PackedByteArray = record["queues"][channel][0]
				if data.put_packet(frame)!=OK: break
				record["queued"] -= frame.size()-13
				record["queues"][channel].pop_front()
			var budget := 32
			while data.get_available_packet_count()>0 and budget>0:
				budget -= 1
				_receive(id,channel,data.get_packet())
				if not peers.has(id): break
	for key in assemblies.keys():
		if not assemblies.has(key): continue
		if Time.get_ticks_msec()-assemblies[key]["time"]>30000:
			_drop(assemblies[key]["peer"])

func _signal(data: Dictionary) -> void:
	if socket.get_ready_state()==WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify(data))

func _handle_signal(data: Dictionary) -> void:
	match data.get("type",""):
		"created", "joined":
			var mismatch := Compatibility.mismatch(data.get("version"))
			if not mismatch.is_empty(): _fatal(mismatch); return
			if not data.get("ice_servers") is Array: _fatal("连接配置无效"); return
			ice = data["ice_servers"]
			if hosting:
				room = str(data.get("room",""))
				room_ready.emit(room)
			else: _create_peer(1,false)
		"peer_joined":
			if hosting and typeof(data.get("peer")) in [TYPE_INT,TYPE_FLOAT]: _create_peer(int(data["peer"]),true)
		"peer_left": _drop(int(data.get("peer",0)))
		"room_closed":
			var reason: Variant = data.get("reason","host_disconnected")
			if reason not in ["host_closed","host_disconnected"]: _fatal("房间关闭消息无效"); return
			stop()
			room_ended.emit(reason=="host_closed")
		"error":
			if data.get("reason")=="version_mismatch": _fatal(Compatibility.mismatch(data.get("version"))); return
			if data.get("reason")=="version_required":
				var required: Dictionary = data.get("contract",{}) if data.get("contract") is Dictionary else {}
				_fatal("中继拒绝此联机版本：需要协议 %s、数据结构 %s。请更新软件或中继服务。" % [str(required.get("protocol","未知")),str(required.get("data_schema","未知"))])
				return
			_fatal({"missing":"邀请码不存在或房间已关闭","full":"房间连接已满","busy":"连接服务暂时繁忙"}.get(data.get("reason"),"连接服务拒绝请求"))
		"forward":
			var id := int(data.get("peer",0))
			if not peers.has(id) or not data.get("data") is Dictionary: return
			var payload: Dictionary = data["data"]
			var connection: WebRTCPeerConnection = peers[id]["connection"]
			if payload.get("kind")=="description":
				if connection.set_remote_description(payload.get("description_type",""),payload.get("sdp",""))!=OK: _drop(id); return
				peers[id]["remote_description"] = true
				for candidate: Dictionary in peers[id]["candidates"]: connection.add_ice_candidate(candidate["mid"],int(candidate["index"]),candidate["candidate"])
				peers[id]["candidates"].clear()
			elif payload.get("kind")=="candidate":
				if not peers[id]["remote_description"]:
					if peers[id]["candidates"].size()>=128: _drop(id); return
					peers[id]["candidates"].append(payload)
				else: connection.add_ice_candidate(payload.get("mid",""),int(payload.get("index",0)),payload.get("candidate",""))

func _create_peer(id: int, offer: bool) -> void:
	if peers.has(id) or peers.size()>=16: return
	var connection := WebRTCPeerConnection.new()
	if connection.initialize({"iceServers":ice})!=OK: _fatal("无法初始化WebRTC连接"); return
	connection.session_description_created.connect(func(kind: String,sdp: String):
		connection.set_local_description(kind,sdp)
		_signal({"type":"forward","peer":id,"data":{"kind":"description","description_type":kind,"sdp":sdp}})
	)
	connection.ice_candidate_created.connect(func(mid: String,index: int,candidate: String): _signal({"type":"forward","peer":id,"data":{"kind":"candidate","mid":mid,"index":index,"candidate":candidate}}))
	var control := connection.create_data_channel("control",{"negotiated":true,"id":0,"ordered":true})
	var assets := connection.create_data_channel("assets",{"negotiated":true,"id":1,"ordered":true})
	if control==null or assets==null: connection.close(); _fatal("无法创建数据通道"); return
	peers[id] = {"connection":connection,"channels":[control,assets],"queues":[[],[]],"queued":0,"ready":false,"started":Time.get_ticks_msec(),"last_connected":Time.get_ticks_msec(),"remote_description":false,"candidates":[]}
	if offer: connection.create_offer()

func _receive(peer: int, channel: int, frame: PackedByteArray) -> void:
	if frame.size()<14 or frame.size()>CHUNK+13 or frame[0]!=channel: _drop(peer); return
	var id := frame.decode_u32(1)
	var offset := frame.decode_u32(5)
	var total := frame.decode_u32(9)
	var key := "%d:%d:%d" % [peer,channel,id]
	if total<1 or total>(MAX_MESSAGE if channel==0 else 2500064): _drop(peer); return
	if not assemblies.has(key):
		var used := 0
		var count := 0
		for entry in assemblies.values():
			if entry["peer"]==peer: used += entry["total"]; count += 1
		if offset!=0 or used+total>MAX_QUEUE or count>=8: _drop(peer); return
		assemblies[key] = {"peer":peer,"total":total,"bytes":PackedByteArray(),"time":Time.get_ticks_msec()}
	var assembly: Dictionary = assemblies[key]
	if total!=assembly["total"] or offset!=assembly["bytes"].size() or offset+frame.size()-13>total: _drop(peer); return
	assembly["bytes"].append_array(frame.slice(13))
	assembly["time"] = Time.get_ticks_msec()
	if assembly["bytes"].size()!=total: return
	var payload: PackedByteArray = assembly["bytes"]
	assemblies.erase(key)
	if channel==0:
		var message: Variant = JSON.parse_string(payload.get_string_from_utf8())
		if not message is Dictionary: _drop(peer); return
		message_received.emit(peer,message)
	else:
		if payload.size()<65: _drop(peer); return
		image_received.emit(peer,payload.slice(0,64).get_string_from_utf8(),payload.slice(64))

func _drop(peer: int) -> void:
	if not peers.has(peer): return
	peers[peer]["connection"].close()
	peers.erase(peer)
	for key in assemblies.keys():
		if assemblies[key]["peer"]==peer: assemblies.erase(key)
	peer_left.emit(peer)

func _fatal(reason: String) -> void:
	stop()
	failed.emit(reason)
