extends RefCounted
## Shared surface data for the Glacier Pass theme.
##
## The glacier preset declares its slippery sections as `ice` spans in
## scripts/minigames/track_defs.gd, and the race reads them for grip. The theme
## reads the same spans so the ice is also visible: warning props sit on every
## boundary and the sheen module paints the spans. One resolver means the
## visual pass and the prop pass can never disagree about where the ice is.
##
## The palette is the flat cartoon colour set carried by the preset. No texture
## path is named anywhere in the glacier theme; the Kenney GLBs bring their own
## built-in materials.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")

const THEME_ID: String = "glacier"
const FALLBACK_GROUND := Color("e8f1f7")
const FALLBACK_FOG := Color("dbe8ef")

## Used only when a bare preview stage has no race preset. The real glacier
## preset always carries its spans, so this is a last-resort mirror of them.
const FALLBACK_SPANS: Array[Dictionary] = [
	{"from": 0.28, "to": 0.52},
	{"from": 0.66, "to": 0.80},
]


## The race preset that produced `race`, or the glacier registry entry when the
## caller is a bare preview stage with no `_preset` field.
static func preset_for(race: Node) -> Dictionary:
	var raw: Variant = race.get("_preset") if race != null else null
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return raw as Dictionary
	return TrackDefs.get_preset(THEME_ID)


## Flat palette dictionary from the preset, or an empty dictionary.
static func palette(preset: Dictionary) -> Dictionary:
	var raw: Variant = preset.get("palette", {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


## Snow-field colour. The glacier palette ships `e8f1f7`; this is the same
## value the menu card and the haze are tinted from.
static func ground_color(preset: Dictionary) -> Color:
	var raw: Variant = palette(preset).get("ground", FALLBACK_GROUND)
	if raw is Color:
		return raw
	return FALLBACK_GROUND


## Cold haze colour for the depth fog.
static func fog_color(preset: Dictionary) -> Color:
	var raw: Variant = palette(preset).get("haze", FALLBACK_FOG)
	if raw is Color:
		return raw
	return FALLBACK_FOG


## Ice spans as {from, to} lap fractions in ascending order. A span with a
## non-positive width is ignored; when the preset declares no ice at all the
## glacier fallback spans are used so the map still reads as the icy layout.
static func ice_spans(preset: Dictionary) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	var raw: Variant = preset.get("surfaces", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if not (entry is Dictionary):
				continue
			var span: Dictionary = entry as Dictionary
			if str(span.get("kind", "normal")).to_lower() != "ice":
				continue
			var from: float = clampf(float(span.get("from", 0.0)), 0.0, 1.0)
			var to: float = clampf(float(span.get("to", 1.0)), 0.0, 1.0)
			if to <= from:
				continue
			spans.append({"from": from, "to": to})
	if spans.is_empty():
		for fallback: Dictionary in FALLBACK_SPANS:
			spans.append(fallback.duplicate())
	return spans


## Every ice boundary as a lap fraction, in span order (entry then exit).
static func boundary_fractions(preset: Dictionary) -> PackedFloat32Array:
	var fractions := PackedFloat32Array()
	for span: Dictionary in ice_spans(preset):
		fractions.append(float(span["from"]))
		fractions.append(float(span["to"]))
	return fractions


## Total length of the ice sections as a fraction of one lap.
static func ice_fraction(preset: Dictionary) -> float:
	var covered: float = 0.0
	for span: Dictionary in ice_spans(preset):
		covered += float(span["to"]) - float(span["from"])
	return covered
