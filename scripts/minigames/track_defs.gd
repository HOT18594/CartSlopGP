extends RefCounted
## Registry of every race map. A map is data: the spline shape, its elevation
## profile and the grip zones are all declared here, so the race scene no
## longer hard-codes a single circuit.
##
## `elevation` is an array of {at, height} keys. `at` is a lap fraction in
## 0..1 and `height` is metres above the flat world plane. A single key (or an
## empty array) means a flat lap.
##
## `surfaces` is an array of {kind, from, to} spans, also in lap fractions.
## Kinds are `normal`, `wet` and `ice`; a fraction outside every span is normal.
## A span whose `to` is lower than `from` wraps across the start line.

const DEFAULT_ID: String = "circuit"

## Grip multiplier applied by CartPlayer.surface_grip for each surface kind.
## 1.0 leaves the dry-road handling untouched.
const SURFACE_GRIPS: Dictionary = {
	"normal": 1.0,
	"wet": 0.80,
	"ice": 0.40,
}

const PRESETS: Array[Dictionary] = [
	{
		"id": "circuit",
		"name": "MEADOW LOOP",
		"desc": "Farms, ponds and pine ridges. Hit the boost pads and two dirt ramps, then outdrive the field.",
		"preview": "meadow_loop.png",
		# The original circuit, unchanged: these are the constants the race
		# scene used before maps became data.
		"control_points": 24,
		"samples_per_segment": 20,
		"base_radius": 64.0,
		"lobe_a": 0.24,
		"lobe_b": 0.045,
		"lobe_c": 0.022,
		"lobe_d": 0.09,
		"stretch_x": 1.25,
		"stretch_z": 1.05,
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 1.0},
		],
	},
	{
		"id": "dockyard",
		"name": "DOCKYARD DASH",
		"desc": "Rain-slick asphalt and worn concrete. The harbour hairpins are quick until the wet patches arrive.",
		"preview": "dockyard.png",
		# Tighter and longer than the meadow, with an open middle section.
		"control_points": 22,
		"samples_per_segment": 20,
		"base_radius": 58.0,
		"lobe_a": 0.20,
		"lobe_b": 0.060,
		"lobe_c": 0.028,
		"lobe_d": 0.12,
		"stretch_x": 1.38,
		"stretch_z": 0.96,
		"elevation": [
			{"at": 0.0, "height": 0.0},
		],
		"surfaces": [
			{"kind": "wet", "from": 0.0, "to": 0.18},
			{"kind": "normal", "from": 0.18, "to": 0.46},
			{"kind": "wet", "from": 0.46, "to": 0.68},
			{"kind": "normal", "from": 0.68, "to": 0.86},
			{"kind": "wet", "from": 0.86, "to": 1.0},
		],
	},
	{
		"id": "alpine",
		"name": "ALPINE SLIDE",
		"desc": "Snow-covered climbs and long descents. Ice between the pines rewards a gentle right foot.",
		"preview": "alpine.png",
		# A rounder, faster loop with more radius so the climbs can breathe.
		"control_points": 26,
		"samples_per_segment": 20,
		"base_radius": 70.0,
		"lobe_a": 0.28,
		"lobe_b": 0.055,
		"lobe_c": 0.018,
		"lobe_d": 0.10,
		"stretch_x": 1.12,
		"stretch_z": 1.16,
		"elevation": [
			{"at": 0.0, "height": 0.0},
			{"at": 0.16, "height": 2.6},
			{"at": 0.34, "height": 0.6},
			{"at": 0.52, "height": 3.4},
			{"at": 0.70, "height": 1.0},
			{"at": 0.86, "height": 3.8},
		],
		"surfaces": [
			{"kind": "normal", "from": 0.0, "to": 0.34},
			{"kind": "ice", "from": 0.34, "to": 0.56},
			{"kind": "normal", "from": 0.56, "to": 0.76},
			{"kind": "ice", "from": 0.76, "to": 0.92},
			{"kind": "normal", "from": 0.92, "to": 1.0},
		],
	},
]


## Every preset id in registry order.
static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for preset: Dictionary in PRESETS:
		ids.append(str(preset.get("id", DEFAULT_ID)))
	return ids


## The preset for `id`, or the default circuit when the id is unknown. The
## legacy `meadow_loop` id maps to `circuit` so old saves keep working.
static func get_preset(id: String) -> Dictionary:
	var key: String = "circuit" if id == "meadow_loop" else id
	for preset: Dictionary in PRESETS:
		if str(preset.get("id", "")) == key:
			return preset
	return PRESETS[0]


## Registry index for `id`, or 0 for an unknown/legacy id.
static func index_of(id: String) -> int:
	var ids: PackedStringArray = all_ids()
	var found: int = ids.find(str(get_preset(id).get("id", DEFAULT_ID)))
	return maxi(found, 0)


## Surface kind at a lap fraction. `lap_fraction` may be any real value; it is
## wrapped into 0..1. Spans that cross the start line are supported.
static func surface_at(preset: Dictionary, lap_fraction: float) -> String:
	var fraction: float = fposmod(lap_fraction, 1.0)
	var raw: Variant = preset.get("surfaces", [])
	if not (raw is Array):
		return "normal"
	var surfaces: Array = raw as Array
	for entry: Variant in surfaces:
		if not (entry is Dictionary):
			continue
		var span: Dictionary = entry as Dictionary
		var from: float = clampf(float(span.get("from", 0.0)), 0.0, 1.0)
		var to: float = clampf(float(span.get("to", 1.0)), 0.0, 1.0)
		var inside: bool = (fraction >= from and fraction < to) if from <= to \
			else (fraction >= from or fraction < to)
		if not inside:
			continue
		var kind: String = str(span.get("kind", "normal")).to_lower()
		return kind if SURFACE_GRIPS.has(kind) else "normal"
	return "normal"


## Grip multiplier for a surface kind. Unknown kinds behave like dry road.
static func surface_grip(kind: String) -> float:
	return float(SURFACE_GRIPS.get(kind, 1.0))


## Convenience: grip multiplier at a lap fraction for `preset`.
static func grip_at(preset: Dictionary, lap_fraction: float) -> float:
	return surface_grip(surface_at(preset, lap_fraction))
