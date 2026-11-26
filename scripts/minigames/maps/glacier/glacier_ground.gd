extends RefCounted
## Flat cartoon snow field for Glacier Pass.
##
## The race scene's meadow ground is a photo-scanned grass material; the glacier
## map has to read as cold snow, so the theme hides that mesh and lays one flat,
## texture-free plane in its place. The plane owns no collider: the race scene's
## GroundCollision still carries the karts off the road and the grid engine owns
## the road collider.
##
## One draw call, no shadows, no textures. The 5 mm lift keeps the snow above
## any other flat ground a future race scene may lay at y = 0 without a visible
## step under a kart wheel.

const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")

const NODE_NAME: String = "GlacierSnowGround"
## The meadow mesh grass_race builds for every map. It is hidden only when the
## node exists, so a race scene that already stopped building it is untouched.
const MEADOW_NODE: String = "MeadowGround"
const SIZE: float = 2800.0
const HEIGHT: float = 0.005


## Adds the snow field under `race`. Returns 1 when it was built, 0 when the
## race is missing or a previous build already owns the node.
static func build(race: Node3D, preset: Dictionary) -> int:
	if race == null or race.has_node(NODE_NAME):
		return 0
	_hide_meadow(race)
	var SceneryKitRes := preload("res://scripts/minigames/scenery/scenery_kit.gd")
	var cool_drift := Color("cce6fa")
	var mid_snow := Color("e4f3ff")
	var warm_frost := Color("f5fbff")
	var node := MeshInstance3D.new()
	node.name = NODE_NAME
	node.mesh = SceneryKitRes.build_blended_ground(
		Vector2(-SIZE * 0.5, -SIZE * 0.5), Vector2(SIZE * 0.5, SIZE * 0.5),
		56, 0.0, func(wx: float, wz: float) -> Color:
			var drift: float = 0.5 + 0.5 * sin(wx * 0.018 + wz * 0.012) * cos(wz * 0.015 - wx * 0.01)
			var fine: float = 0.5 + 0.5 * sin(wx * 0.045 - wz * 0.038)
			var c_base: Color = cool_drift.lerp(mid_snow, smoothstep(0.15, 0.85, drift))
			return c_base.lerp(warm_frost, smoothstep(0.35, 0.90, fine) * 0.65)
	)
	node.position = Vector3(240.0, HEIGHT, 180.0)
	node.material_override = SceneryKitRes.fluid_ground_material(
		Color(0.94, 0.98, 1.04), Color(1.02, 1.01, 1.00), 0.022, 0.12, 0.78)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	race.add_child(node)
	return 1


## The realistic grass scan has no place on a snow map. Collision is a separate
## body, so hiding the visual cannot change the driving surface.
static func _hide_meadow(race: Node3D) -> void:
	var meadow: Node = race.get_node_or_null(MEADOW_NODE)
	if meadow is MeshInstance3D:
		(meadow as MeshInstance3D).visible = false


## Flat, rough snow. The cold blue-grey shadow the brief asks for comes from
## the sky ambient, not from a texture, so the albedo stays a single colour.
static func _material(preset: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = GlacierSurface.ground_color(preset)
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material
