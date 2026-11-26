extends Node
## Two-process in-game latency probe for the WS4 netcode investigation.
##
## Host:   CSGP_PING_ROLE=host godot --headless --path godot_project res://scripts/tools/net_ping_probe.tscn
## Client: CSGP_PING_ROLE=client CSGP_PING_CODE=<CODE> godot --headless --path godot_project res://scripts/tools/net_ping_probe.tscn
##
## Host prints the room code (grep "PING_PROBE code=") and its own HUD ping
## (`host_ping_ms`, an HTTP probe to the relay). The client prints the in-game
## `latency_ms` (ENet `_net_ping`/`_net_pong` through the host) once a second.
## Both use the real Pi room path, exactly like the shipped game.

var _role: String = "host"
var _samples: Array[int] = []
var _t: float = 0.0
var _elapsed: float = 0.0
var _code: String = ""
var _quit_at: float = 26.0
var _http_mode: bool = false


func _ready() -> void:
	_role = OS.get_environment("CSGP_PING_ROLE").strip_edges().to_lower()
	if _role == "http":
		_role = "host"
		_http_mode = true
		_run_http_measure.call_deferred()
		return
	if _role != "client":
		_role = "host"
	if _role == "host":
		Network.host_started.connect(func(code: String) -> void:
			_code = code
			print("PING_PROBE code=%s relay_base=%s public=%s" % [
				code, Network.relay_base, str(Network.relay_base_public)])
			print("PING_PROBE host local_ip=%s port=%d direct=%s" % [
				Network.local_address, Network.port,
				str(Network.is_direct_link())])
		)
		Network.host_failed.connect(func(reason: String) -> void:
			print("PING_PROBE host_failed=" + reason)
			get_tree().quit(2))
		Network.host_game("pi")
	else:
		var code: String = OS.get_environment("CSGP_PING_CODE").strip_edges().to_upper()
		Network.join_succeeded.connect(func() -> void:
			print("PING_PROBE client joined direct=%s relay=%s" % [
				str(Network.is_direct_link()), Network.relay_base]))
		Network.join_failed.connect(func(reason: String) -> void:
			print("PING_PROBE client_failed=" + reason)
			get_tree().quit(2))
		Network.join_game(code)


func _run_http_measure() -> void:
	## Isolate the HTTP probe path: discover the relay, then time alternating
	## keep-alive and HTTPRequest GETs. Used to verify the persistent-connection
	## fix (the old path paid a TCP handshake per probe).
	if not await Network._discover_relay():
		print("PING_PROBE http no_relay")
		get_tree().quit(3)
		return
	print("PING_PROBE http relay=%s public=%s" % [
		Network.relay_base, str(Network.relay_base_public)])
	var keepalive: Array[int] = []
	for i in 6:
		var t0: int = Time.get_ticks_msec()
		var data: Dictionary = await Network._keepalive_json(
			HTTPClient.METHOD_GET, "/api/ping?t=%d" % t0, {}, 2000)
		keepalive.append(Time.get_ticks_msec() - t0)
		if data.is_empty():
			keepalive[keepalive.size() - 1] = -1
	var pooled: Array[int] = []
	for i in 4:
		var t0: int = Time.get_ticks_msec()
		var data: Dictionary = await Network._relay_get("/api/ping?t=%d" % t0, 2.0)
		pooled.append(Time.get_ticks_msec() - t0)
		if data.is_empty():
			pooled[pooled.size() - 1] = -1
	print("PING_PROBE http keepalive_ms=%s pooled_httprequest_ms=%s" % [
		str(keepalive), str(pooled)])
	get_tree().quit(0)


func _process(delta: float) -> void:
	_t += delta
	_elapsed += delta
	if _role == "host":
		if _t >= 2.0 and Network.is_host and Network.is_session_active():
			_t = 0.0
			print("PING_PROBE host peers=%d http_ping=%d relay_rtt=%d direct=%s" % [
				Network.peer_count(), Network.host_ping_ms,
				Network.relay_rtt_ms, str(Network.is_direct_link())])
	else:
		if _t >= 1.0 and Network.is_client and Network.is_session_active():
			_t = 0.0
			_samples.append(Network.latency_ms)
			print("PING_PROBE client latency_ms=%d relay_rtt=%d n=%d" % [
				Network.latency_ms, Network.relay_rtt_ms, _samples.size()])
	if _elapsed >= _quit_at:
		if _role == "client" and not _samples.is_empty():
			var sorted: Array[int] = _samples.duplicate()
			sorted.sort()
			print("PING_PROBE client summary n=%d min=%d p50=%d max=%d" % [
				sorted.size(), sorted[0], sorted[sorted.size() / 2],
				sorted[sorted.size() - 1]])
		get_tree().quit(0)
