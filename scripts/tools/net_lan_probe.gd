extends Node
## Headless LAN/relay diagnostic for the WS4 latency investigation.
##
## Run from the workspace root:
##   godot --headless --path godot_project res://scripts/tools/net_lan_probe.tscn
##
## It prints the facts the lobby/join path bases its address decisions on, then
## measures the relay HTTP path twice: once through the pooled HTTPRequest (the
## game path) and once with a fresh connection per request. A large gap means
## every pooled probe is paying a TCP handshake.
##
## It never fails the run for "no network": this is a diagnostic, not a gate.
## The permanent assertions live in net_mac_smoke.gd.

const PING_SAMPLES: int = 6


func _ready() -> void:
	_run()


func _run() -> void:
	var net: Node = Network  # autoload
	print("== local interfaces ==")
	for iface_value: Variant in IP.get_local_interfaces():
		if not (iface_value is Dictionary):
			continue
		var iface: Dictionary = iface_value as Dictionary
		var addresses: PackedStringArray = PackedStringArray()
		for addr_value: Variant in (iface.get("addresses", []) as Array):
			addresses.append(str(addr_value))
		print("  score=%-5d name=%-28s friendly=%-34s %s" % [
			net._interface_score(iface), str(iface.get("name", "")),
			str(iface.get("friendly", "")), ", ".join(addresses)])
	var candidates: PackedStringArray = net._lan_address_candidates()
	print("== candidates: %s" % ", ".join(candidates))
	print("== _local_ip(): %s" % net._local_ip())
	print("== discovery targets: %s" % ", ".join(net._discovery_targets()))

	print("== relay discovery ==")
	net.set_relay_server("")
	var started: int = Time.get_ticks_msec()
	var discovered: bool = await net._discover_relay()
	print("  discovered=%s in %d ms" % [discovered, Time.get_ticks_msec() - started])
	print("  relay_base=%s base_public=%s lan_ip=%s server_host=%s" % [
		net.relay_base, net.relay_base_public, net.relay_lan_ip,
		net.relay_server_host])
	if not discovered:
		print("  (no relay reachable - nothing else to measure)")
		get_tree().quit(0)
		return
	var status: Dictionary = await net._relay_get("/api/status", 3.0)
	print("  /api/status: version=%s" % str(status.get("version", "<none>")))
	print("== pooled HTTP RTT (game path) ==")
	var pooled: Array[int] = []
	var t0: int = Time.get_ticks_msec()
	for i in PING_SAMPLES:
		var start: int = Time.get_ticks_msec()
		var data: Dictionary = await net._relay_get("/api/ping?t=%d" % start, 2.0)
		var rtt: int = maxi(Time.get_ticks_msec() - start, 0)
		if data.is_empty():
			print("  sample %d: <no response>" % i)
			continue
		pooled.append(rtt)
		print("  sample %d: %d ms" % [i, rtt])
	print("  total %d ms for %d samples" % [Time.get_ticks_msec() - t0, pooled.size()])
	print("== fresh-socket HTTP RTT (new connection EVERY request) ==")
	var fresh: Array[int] = []
	for i in PING_SAMPLES:
		var http := HTTPRequest.new()
		add_child(http)
		var start: int = Time.get_ticks_msec()
		var err: Error = http.request(net.relay_base + "/api/ping?t=%d" % start,
			[], HTTPClient.METHOD_GET)
		if err != OK:
			print("  sample %d: request error %d" % [i, err])
			http.queue_free()
			continue
		var response: Array = await http.request_completed
		var rtt: int = maxi(Time.get_ticks_msec() - start, 0)
		http.queue_free()
		if int(response[1]) != 200:
			print("  sample %d: status %d" % [i, int(response[1])])
			continue
		fresh.append(rtt)
		print("  sample %d: %d ms" % [i, rtt])
	if pooled.size() >= 3 and fresh.size() >= 3:
		pooled.sort()
		fresh.sort()
		print("== summary: pooled p50=%d ms, fresh p50=%d ms, reconnect penalty=%d ms ==" % [
			pooled[pooled.size() / 2], fresh[fresh.size() / 2],
			fresh[fresh.size() / 2] - pooled[pooled.size() / 2]])
	get_tree().quit(0)
