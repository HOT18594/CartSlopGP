extends RefCounted
## Lobby pre-game reactions: the catalog and the client-side rate limiter.
##
## Five canned, one-tap emotes that sync to every player in the room while
## waiting for the match to start (stream-chat style). Deliberately tiny and
## text-only so the feature needs no new art, works offline, and cannot bloat
## the Web build. `lobby_menu.gd` owns the buttons/bubbles; `network.gd` owns
## the reliable RPC relay and its server-side throttle; this file owns the
## shared data + the pure timing rules so both paths agree.
##
## IDs are short lowercase tokens (validated again by Network before any RPC).
## `accent` is the sender-independent reaction colour; each bubble also carries
## the sender's tag colour/name so players can tell who sent what.

const ID_GG: String = "gg"
const ID_START: String = "start"
const ID_HEART: String = "heart"
const ID_SLOP: String = "slop"
const ID_HONK: String = "honk"

const REACTIONS: Array[Dictionary] = [
	{"id": ID_GG, "label": "GG!", "accent": "4cd964", "hint": "Good game"},
	{"id": ID_START, "label": "START!", "accent": "ffd22e", "hint": "Ask the host to start"},
	# Drawn procedurally in the bubble/button icon slot: no Unicode glyph
	# dependency, so the Web/Windows/macOS fallback fonts can never show tofu.
	{"id": ID_HEART, "label": "LOVE", "accent": "f26ca7", "hint": "Send some love",
		"icon": "heart"},
	{"id": ID_SLOP, "label": "SLOP!", "accent": "38d6f0", "hint": "Pure cart slop energy"},
	{"id": ID_HONK, "label": "HONK!", "accent": "ff922b", "hint": "Cart horn"},
]

## One reaction per player per this many ms (client side). The buttons are
## click/key/gamepad reachable, so a held Enter must not spray the room.
const COOLDOWN_MS: int = 900
## While a send is cooling down, at most this many extra presses are buffered
## (then the oldest is dropped). Keeps key repeat from growing an unbounded list.
const PENDING_CAP: int = 3
## A buffered press older than this is discarded instead of sent late.
const PENDING_MAX_AGE_MS: int = 2500
## How long one floating bubble lives, and how many may be on screen at once.
const BUBBLE_LIFETIME: float = 2.9
const MAX_BUBBLES: int = 10
## Bubble rise distance in px over its lifetime (reduce-motion uses a plain fade).
const BUBBLE_RISE: float = 96.0


static func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for reaction: Dictionary in REACTIONS:
		out.append(str(reaction["id"]))
	return out


static func is_valid(reaction_id: String) -> bool:
	return index_of(reaction_id) >= 0


static func index_of(reaction_id: String) -> int:
	for index in REACTIONS.size():
		if str(REACTIONS[index]["id"]) == reaction_id:
			return index
	return -1


static func find(reaction_id: String) -> Dictionary:
	var index: int = index_of(reaction_id)
	return REACTIONS[index] if index >= 0 else {}


static func label_for(reaction_id: String) -> String:
	var entry: Dictionary = find(reaction_id)
	return str(entry.get("label", "")) if not entry.is_empty() else ""


static func accent_for(reaction_id: String) -> Color:
	var entry: Dictionary = find(reaction_id)
	if entry.is_empty():
		return Color.WHITE
	return Color(str(entry.get("accent", "ffffff")))


static func can_send(now_ms: int, last_sent_ms: int) -> bool:
	## Pure cooldown test. A backwards clock (system time sync, sleep/resume)
	## is treated as "ready": the UI must never lock the player out of a fun
	## emote because the wall clock jumped.
	if last_sent_ms < 0:
		return true
	var diff: int = now_ms - last_sent_ms
	if diff < 0:
		return true
	return diff >= COOLDOWN_MS


static func push_pending(pending: Array, reaction_id: String, now_ms: int,
		cap: int = PENDING_CAP) -> bool:
	## Buffer one press while cooling down. Returns false when the id is invalid
	## or no buffer is allowed; never grows past `cap` (oldest press is dropped).
	if not is_valid(reaction_id):
		return false
	prune_pending(pending, now_ms)
	if cap <= 0:
		pending.clear()
		return false
	while pending.size() >= cap:
		pending.remove_at(0)
	pending.append({"id": reaction_id, "at": now_ms})
	return true


static func prune_pending(pending: Array, now_ms: int) -> void:
	var index: int = pending.size() - 1
	while index >= 0:
		var entry: Variant = pending[index]
		var age: int = now_ms - int((entry as Dictionary).get("at", now_ms)) \
			if entry is Dictionary else 0
		if age > PENDING_MAX_AGE_MS or age < -1000:
			pending.remove_at(index)
		index -= 1


static func next_pending(pending: Array, now_ms: int) -> String:
	## Pop the oldest still-fresh buffered reaction ("" when none is ready).
	prune_pending(pending, now_ms)
	if pending.is_empty():
		return ""
	var entry: Dictionary = pending[0] as Dictionary
	pending.remove_at(0)
	return str(entry.get("id", ""))
