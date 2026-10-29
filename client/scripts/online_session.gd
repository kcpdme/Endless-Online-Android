extends Node
## TCP JSON-lines for local development, or ws/wss JSON messages through the world gateway.
## Every gateway connection owns one real encrypted EO session. TLS uses normal certificate checks.
signal transport_connected
signal message_received(message: Dictionary)
signal transport_closed(reason: String)

const MAX_RESPONSE_BYTES: int = 4 * 1024 * 1024
const HEARTBEAT_INTERVAL: float = 5.0
const HEARTBEAT_TIMEOUT: float = 20.0
const REQUEST_TIMEOUT:float=30.0
var idle_seconds: float = 0.0
var peer: StreamPeerTCP = StreamPeerTCP.new()
var websocket: WebSocketPeer = WebSocketPeer.new()
var websocket_mode: bool = false
var receive_buffer: PackedByteArray = PackedByteArray()
var connecting: bool = false
var connected: bool = false
var deadline: float = 0.0
var serial: int = 0
var pending: Dictionary = {}

func open(host: String, port: int) -> Error:
	close()
	websocket_mode = host.begins_with("ws://") or host.begins_with("wss://")
	var error: Error = OK
	if websocket_mode:
		websocket = WebSocketPeer.new()
		websocket.inbound_buffer_size = MAX_RESPONSE_BYTES
		websocket.outbound_buffer_size = 64 * 1024
		error = websocket.connect_to_url(host)
	else:
		peer = StreamPeerTCP.new()
		error = peer.connect_to_host(host, port)
	if error != OK: return error
	connecting = true
	deadline = 0.0
	return OK

func close() -> void:
	peer.disconnect_from_host()
	if websocket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		websocket.close()
		websocket.poll()
	connecting = false
	connected = false
	receive_buffer.clear()
	pending.clear()
	idle_seconds = 0.0

func request(operation: String, fields: Dictionary = {}) -> int:
	if not connected: return -1
	serial += 1
	var message: Dictionary = fields.duplicate(true)
	message["id"] = serial
	message["op"] = operation
	var encoded: String = JSON.stringify(message)
	if encoded.to_utf8_buffer().size() > 64 * 1024:
		_fail("This request exceeds the connection limit.")
		return -1
	var error: Error = websocket.send_text(encoded) if websocket_mode else peer.put_data((encoded + "\n").to_utf8_buffer())
	if error != OK:
		_fail("Connection write failed.")
		return -1
	pending[serial] = {"op": operation, "age": 0.0}
	return serial

func _process(delta: float) -> void:
	if not connecting and not connected:return
	for raw_id:Variant in pending.keys():
		var record:Dictionary=pending[raw_id] as Dictionary
		record.age=float(record.age)+delta
	if connected:idle_seconds+=delta
	# Drain queued replies first. A slow render/background frame must not reject
	# a response that has already arrived on the healthy connection.
	if websocket_mode:_poll_websocket(delta)
	else:_poll_tcp(delta)
	if not connected:return
	for record:Dictionary in pending.values():
		if float(record.age)>(HEARTBEAT_TIMEOUT if str(record.op)=="ping" else REQUEST_TIMEOUT):
			_fail("The game server did not answer in time. Please reconnect.");return
	if pending.is_empty() and idle_seconds>=HEARTBEAT_INTERVAL:
		idle_seconds=0.0
		request("ping")

func _poll_tcp(delta:float)->void:
	peer.poll()
	var status: int = peer.get_status()
	if connecting:
		deadline += delta
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_mark_connected()
		elif status == StreamPeerTCP.STATUS_ERROR or deadline > 15.0:
			_fail("Could not reach the game server. Check its address and connection.")
			return
	elif status != StreamPeerTCP.STATUS_CONNECTED:
		_fail("The game server disconnected.")
		return
	var available: int = peer.get_available_bytes()
	if available <= 0: return
	var result: Array = peer.get_data(available)
	if int(result[0]) != OK:
		_fail("The server connection could not be read.")
		return
	receive_buffer.append_array(result[1] as PackedByteArray)
	if receive_buffer.size() > MAX_RESPONSE_BYTES:
		_fail("The server sent an oversized response.")
		return
	while true:
		var newline: int = receive_buffer.find(10)
		if newline < 0: break
		var line: String = receive_buffer.slice(0, newline).get_string_from_utf8()
		receive_buffer = receive_buffer.slice(newline + 1)
		if not _consume_message(line): return

func _poll_websocket(delta: float) -> void:
	websocket.poll()
	var state: int = websocket.get_ready_state()
	if connecting:
		deadline += delta
		if state == WebSocketPeer.STATE_OPEN: _mark_connected()
		elif state == WebSocketPeer.STATE_CLOSED or deadline > 15.0:
			_fail("Could not reach the game server securely. Check its address and connection.")
			return
	elif state != WebSocketPeer.STATE_OPEN:
		_fail("The game server disconnected.")
		return
	while websocket.get_available_packet_count() > 0:
		var packet: PackedByteArray = websocket.get_packet()
		if websocket.get_packet_error() != OK or not websocket.was_string_packet():
			_fail("The game server sent an invalid message.")
			return
		if packet.size() > MAX_RESPONSE_BYTES:
			_fail("The server sent an oversized response.")
			return
		if not _consume_message(packet.get_string_from_utf8()): return

func _mark_connected() -> void:
	connecting = false
	connected = true
	if not websocket_mode: peer.set_no_delay(true)
	transport_connected.emit()

func _consume_message(line: String) -> bool:
	var parsed: Variant = JSON.parse_string(line)
	if not parsed is Dictionary:
		_fail("The server response was invalid.")
		return false
	var message: Dictionary = parsed as Dictionary
	pending.erase(int(message.get("id", -1)))
	message_received.emit(message)
	idle_seconds = 0.0
	return true

func _fail(reason: String) -> void:
	close()
	transport_closed.emit(reason)

func is_idle() -> bool:
	for record: Variant in pending.values():
		if str(record.get("op","")) != "ping": return false
	return true

func has_blocking_requests() -> bool:
	for record: Variant in pending.values():
		if str(record.get("op", "")) not in ["ping", "move", "face", "strike", "collect", "spell_cast", "spell_cancel", "potion_use", "shortcuts_set"]: return true
	return false
