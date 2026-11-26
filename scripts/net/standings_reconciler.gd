extends RefCounted
## Deterministic, host-authoritative competition standings for ranked modes.
##
## The owner-visible bug this exists to kill: every peer used to compute final
## standings independently from its own (unreliable, differently delayed) view
## of the field, so two players watching the same race could see a different
## finishing order - especially for close finishes, or when a late "I finished"
## packet was dropped. There was no canonical source at all outside a Pi server
## race.
##
## Contract:
##  * The HOST builds the canonical rows (one per competitor) and broadcasts a
##    revisioned snapshot over a reliable RPC.
##  * Clients only render the newest accepted snapshot; they never merge their
##    own guesses above it. Accepting is strictly monotonic: a newer epoch wins
##    outright, the same epoch accepts a strictly higher revision only.
##  * Ordering is fully deterministic (finished by crossing time, then racing by
##    distance, then a stable integer id), so even two hosts that computed the
##    rows in different orders end up with the identical list.
##
## Row format (RPC/JSON-safe Dictionary):
##   id          int    > 0 = peer id, < 0 = bot slot (-1 - index)
##   name        String display name
##   finished    bool   crossed the finish line
##   finish_time float  race-clock seconds at the crossing, -1.0 while racing
##   progress    float  absolute track distance in metres (host view)
##   total       float  total race time for a finisher, -1.0 when unknown
##   best        float  best lap for a competitor, -1.0 when unknown
##   place       int    1-based rank, always recomputed here
##
## Snapshot format:
##   epoch int, rev int, final bool, rows Array[Dictionary]

const MAX_ROWS: int = 16
const FINISH_TIME_EPSILON: float = 0.0005


static func new_snapshot(epoch: int = 0) -> Dictionary:
	return {"epoch": epoch, "rev": 0, "final": false, "rows": []}


static func sanitize_row(raw: Variant) -> Dictionary:
	## Every field is clamped/typed here: rows arrive over the network and a
	## hostile or buggy host must not be able to put NaN into the HUD or make a
	## competitor vanish. Returns {} for a row that cannot be trusted at all.
	if not (raw is Dictionary):
		return {}
	var source: Dictionary = raw as Dictionary
	var id: int = int(source.get("id", 0))
	if id == 0:
		return {}
	var name: String = str(source.get("name", "")).strip_edges()
	if name.length() > 24:
		name = name.substr(0, 24)
	var finished: bool = bool(source.get("finished", false))
	var finish_time: float = float(source.get("finish_time", -1.0))
	if not is_finite(finish_time) or finish_time < 0.0 or finish_time > 86400.0:
		finish_time = -1.0
	if finish_time >= 0.0:
		finished = true
	else:
		finished = false
	var progress: float = float(source.get("progress", 0.0))
	if not is_finite(progress) or progress < 0.0:
		progress = 0.0
	progress = clampf(progress, 0.0, 1000000.0)
	var total: float = float(source.get("total", -1.0))
	if not is_finite(total) or total < 0.0 or total > 86400.0:
		total = -1.0
	var best: float = float(source.get("best", -1.0))
	if not is_finite(best) or best < 0.0 or best > 86400.0:
		best = -1.0
	return {
		"id": id,
		"name": name,
		"finished": finished,
		"finish_time": finish_time,
		"progress": progress,
		"total": total,
		"best": best,
		"place": 0,
	}


static func sort_rows(rows: Array) -> Array[Dictionary]:
	## Deterministic rank order, returns a copy with `place` assigned.
	var clean: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in rows:
		var row: Dictionary = sanitize_row(raw)
		if row.is_empty():
			continue
		var id: int = int(row["id"])
		if seen.has(id):
			continue
		seen[id] = true
		clean.append(row)
		if clean.size() >= MAX_ROWS:
			break
	clean.sort_custom(_before)
	for index in clean.size():
		clean[index]["place"] = index + 1
	return clean


static func _before(a: Dictionary, b: Dictionary) -> bool:
	## Matches the mode scripts' old local sort, with every tie broken by id so
	## the same rows always produce the same order on every machine.
	var a_finished: bool = bool(a.get("finished", false))
	var b_finished: bool = bool(b.get("finished", false))
	if a_finished != b_finished:
		return a_finished
	if a_finished:
		var a_time: float = float(a.get("finish_time", -1.0))
		var b_time: float = float(b.get("finish_time", -1.0))
		if a_time >= 0.0 and b_time >= 0.0 \
				and absf(a_time - b_time) > FINISH_TIME_EPSILON:
			return a_time < b_time
	var a_progress: float = float(a.get("progress", 0.0))
	var b_progress: float = float(b.get("progress", 0.0))
	if not is_equal_approx(a_progress, b_progress):
		return a_progress > b_progress
	return int(a.get("id", 0)) < int(b.get("id", 0))


static func build(epoch: int, rev: int, rows: Array, final: bool) -> Dictionary:
	## Host-only: sanitise, order and stamp one canonical snapshot.
	return {
		"epoch": int(epoch),
		"rev": maxi(int(rev), 1),
		"final": bool(final),
		"rows": sort_rows(rows),
	}


static func accept(previous: Dictionary, incoming: Dictionary) -> Dictionary:
	## Client-side reconciliation. Returns the snapshot the caller should keep:
	## the previous one when the packet is stale/duplicate/malformed, otherwise
	## the incoming one. An epoch change is a new race and resets revisions.
	if incoming.is_empty():
		return previous
	var epoch: int = int(incoming.get("epoch", 0))
	var rev: int = int(incoming.get("rev", 0))
	if rev <= 0:
		return previous
	var rows: Array = []
	var raw_rows: Variant = incoming.get("rows", [])
	if not (raw_rows is Array):
		return previous
	rows = raw_rows as Array
	var sorted: Array[Dictionary] = sort_rows(rows)
	if sorted.is_empty():
		return previous
	var final: bool = bool(incoming.get("final", false))
	var prev_epoch: int = int(previous.get("epoch", epoch))
	var prev_rev: int = int(previous.get("rev", 0))
	if previous.is_empty() or epoch != prev_epoch:
		return {"epoch": epoch, "rev": rev, "final": final, "rows": sorted}
	if bool(previous.get("final", false)) and not final:
		# A final snapshot is terminal for its epoch: a late non-final revision
		# must never reopen a rendered result screen.
		return previous
	if rev <= prev_rev:
		return previous
	return {"epoch": epoch, "rev": rev, "final": final, "rows": sorted}


static func places(snapshot: Dictionary) -> Dictionary:
	## id -> place, for the mode's own position label.
	var out: Dictionary = {}
	for row_value: Variant in (snapshot.get("rows", []) as Array):
		if row_value is Dictionary:
			var row: Dictionary = row_value as Dictionary
			out[int(row.get("id", 0))] = int(row.get("place", 0))
	return out


static func rows_by_id(snapshot: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for row_value: Variant in (snapshot.get("rows", []) as Array):
		if row_value is Dictionary:
			var row: Dictionary = row_value as Dictionary
			out[int(row.get("id", 0))] = row
	return out
