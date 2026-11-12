extends RefCounted
## Race-circuit theme for the default map.
##
## The foundation phase loads this script and calls build(race, spline) once,
## after the road, barriers and start gates exist. It replaces the meadow
## dressing with a purpose-built circuit: asphalt verge, concrete pit lane and
## paddock, kerbs on every corner, armco down the straights, tyre walls at the
## fast corners, two grandstands, a start gantry, floodlights, numbered corner
## boards and a solid pit wall with a service lane. Distant noise ridges and
## depth haze close the horizon.
##
## One route analysis feeds every builder, so the kerbs, boards, grandstands
## and barriers agree about where each corner starts and which side is its
## outside. Every solid piece gets a CollisionLayers.WORLD body. The road
## surface itself is never touched: this script only dresses around it.
##
## The build is idempotent; a second call with the holder already present is a
## no-op, so a scene reload can never double the props.

const CircuitLayout := preload(
	"res://scripts/minigames/maps/circuit/circuit_layout.gd")
const CircuitGround := preload(
	"res://scripts/minigames/maps/circuit/circuit_ground.gd")
const CircuitFurniture := preload(
	"res://scripts/minigames/maps/circuit/circuit_furniture.gd")
const HorizonBuilder := preload(
	"res://scripts/minigames/scenery/horizon_builder.gd")

const HOLDER_NAME: String = "CircuitTheme"


## Builds the whole circuit theme under `race`. `spline` is the race scene's
## TrackSpline; the signature is the map-theme hook the race controller calls.
static func build(race: Node3D, spline) -> void:
	if race == null or spline == null:
		return
	if race.has_node(HOLDER_NAME):
		return
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var plan: Dictionary = CircuitLayout.analyse(spline)
	CircuitGround.build(holder, spline)
	var stats: Dictionary = CircuitFurniture.build(holder, spline, plan)
	# The meadow horizon was a ring of grassy spheres. This shared builder
	# replaces it with four noise bands and a depth-fog curve, which reads as
	# distant ridges through haze from the chase camera and costs four draws.
	HorizonBuilder.build(race, {})
	var corners: Array = plan["corners"]
	var straights: Array = plan["straights"]
	print("CIRCUIT theme: %d corners, %d straights, %d kerb runs, %d armco runs" % [
		corners.size(), straights.size(), int(stats["kerbs"]),
		int(stats["barriers"])])
	print("CIRCUIT theme: %d tyre walls, %d stands, %d boards, %d lights, %d pit bays" % [
		int(stats["tyre_walls"]), int(stats["stands"]), int(stats["boards"]),
		int(stats["floodlights"]), int(stats["pit_bays"])])
