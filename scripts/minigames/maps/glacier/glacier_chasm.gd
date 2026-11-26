extends Node3D
## Broken Cliff Chasm Jump & Weight-Balanced Ballistic Launch / Fall-Setback System
## for Glacier Pass.
##
## Turns every 'J' (jump ramp) tile on Glacier Pass into a true broken-bridge
## mountain cliff chasm:
##   1. Surgically carves a 12.6 m physical & visual gap out of the road cell
##      immediately following each 'J' ramp (after KenneyTiles has verified seams).
##   2. Dresses both cliff lips with shattered timber beams, fractured slate
##      ledges, stone abutment piers, glowing hazard chevrons, a deep glowing
##      turquoise crevasse abyss below, and an approach speed-boost strip.
##   3. Runs a live physics controller that balances the required takeoff speed
##      and launch arc for each vehicle's mass (45 kg Shopping Cart up to
##      3,200 kg Box Truck). Cars that hit their weight-balanced target speed
##      soar across the chasm; cars that crawl up too slowly fall into the
##      abyss and get set back 38 m before the jump ramp!

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const ConceptSpectacle := preload("res://scripts/minigames/scenery/concept_spectacle.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")

const GAP_START_M: float = 0.15 ## Metres past the 'J' exit edge where the broken gap begins.
const GAP_END_M: float = 17.50 ## Metres past the 'J' exit edge where the far landing deck resumes.
const GAP_LENGTH_M: float = GAP_END_M - GAP_START_M
const SETBACK_DISTANCE_M: float = 42.0 ## How far back before the chasm lip a fallen car is set back.

var _race: Node3D = null
var _spline: RefCounted = null
var _chasm_sites: Array[Dictionary] = []
var _launch_cooldowns: Dictionary = {} ## instance_id -> cooldown seconds
var _pad_cooldowns: Dictionary = {} ## instance_id -> cooldown seconds
var _active_jumpers: Dictionary = {} ## instance_id -> {fw: Vector3, horiz_speed: float, timer: float}


static func build(holder: Node3D, race: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {"chasms": 0, "objects": 0, "draws": 0}
	if holder == null or race == null or spline == null:
		return stats
	if holder.has_node("GlacierChasms"):
		return stats
	var node := new()
	node.name = "GlacierChasms"
	holder.add_child(node)
	return node._setup(race, spline)


func _setup(race: Node3D, spline: RefCounted) -> Dictionary:
	_race = race
	_spline = spline
	_chasm_sites = _discover_sites(spline)
	if _chasm_sites.is_empty():
		return {"chasms": 0, "objects": 0, "draws": 0}

	_carve_road_gaps(race, _chasm_sites)
	var dress_stats: Dictionary = _dress_chasms(_chasm_sites)
	set_physics_process(true)
	return {
		"chasms": _chasm_sites.size(),
		"objects": int(dress_stats.get("objects", 0)),
		"draws": int(dress_stats.get("draws", 0)),
	}


static func _discover_sites(spline: RefCounted) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	var raw_tiles: Variant = spline.get("tiles")
	if not (raw_tiles is Array):
		return sites
	var tiles: Array = raw_tiles as Array
	var total: float = maxf(float(spline.total_length), 1.0)
	for idx in tiles.size():
		if not (tiles[idx] is Dictionary):
			continue
		var t: Dictionary = tiles[idx] as Dictionary
		if str(t.get("tile", "")) != "J":
			continue
		var next_t: Dictionary = tiles[(idx + 1) % tiles.size()] as Dictionary
		var s_takeoff: float = float(t.get("to", 0.0))
		var frame: Dictionary = spline.sample(s_takeoff)
		var lip_pos: Vector3 = frame["position"] as Vector3
		var fw: Vector3 = frame["forward"] as Vector3
		fw.y = 0.0
		if fw.length_squared() < 0.001:
			continue
		fw = fw.normalized()
		var right: Vector3 = fw.cross(Vector3.UP).normalized()
		var yaw: float = atan2(-fw.x, -fw.z)
		sites.append({
			"index": sites.size(),
			"jump_cell": t.get("cell", Vector2i.ZERO),
			"gap_cell": next_t.get("cell", Vector2i.ZERO),
			"s_ramp_start": float(t.get("from", 0.0)),
			"s_takeoff": s_takeoff,
			"s_landing": fposmod(s_takeoff + GAP_END_M, total),
			"s_setback": fposmod(s_takeoff - SETBACK_DISTANCE_M, total),
			"deck_y": float(t.get("height_out", lip_pos.y)) + KenneyTiles.ROAD_SURFACE,
			"lip_pos": Vector3(lip_pos.x, float(t.get("height_out", lip_pos.y)) + KenneyTiles.ROAD_SURFACE, lip_pos.z),
			"forward": fw,
			"right": right,
			"yaw": yaw,
		})
	return sites


static func _point_in_any_gap(pt: Vector3, sites: Array[Dictionary],
		margin_along: float = 0.0, extra_lat: float = 3.5) -> bool:
	var max_lat: float = TileKit.ROAD_HALF + extra_lat
	for site: Dictionary in sites:
		var lip: Vector3 = site["lip_pos"] as Vector3
		var fw: Vector3 = site["forward"] as Vector3
		var right: Vector3 = site["right"] as Vector3
		var rel: Vector3 = pt - lip
		var along: float = rel.x * fw.x + rel.z * fw.z
		if along < GAP_START_M - margin_along or along > GAP_END_M + margin_along:
			continue
		var lat: float = absf(rel.x * right.x + rel.z * right.z)
		if lat <= max_lat:
			return true
	return false


static func _carve_array_mesh_gaps(mi: MeshInstance3D, sites: Array[Dictionary],
		margin_along: float = -0.15, extra_lat: float = 3.2) -> void:
	if mi == null or not (mi.mesh is ArrayMesh):
		return
	var old_mesh: ArrayMesh = mi.mesh as ArrayMesh
	var new_mesh := ArrayMesh.new()
	for surf in old_mesh.get_surface_count():
		var arr: Array = old_mesh.surface_get_arrays(surf)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var uvs := PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
			uvs = arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		var cols := PackedColorArray()
		if arr[Mesh.ARRAY_COLOR] is PackedColorArray:
			cols = arr[Mesh.ARRAY_COLOR] as PackedColorArray
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_uv := PackedVector2Array()
		var out_c := PackedColorArray()
		var has_uv: bool = uvs.size() == verts.size()
		var has_c: bool = cols.size() == verts.size()
		var has_n: bool = norms.size() == verts.size()
		var tri_cnt: int = verts.size() / 3
		for ti in tri_cnt:
			var i0: int = ti * 3
			var a: Vector3 = verts[i0]
			var b: Vector3 = verts[i0 + 1]
			var c: Vector3 = verts[i0 + 2]
			var mid: Vector3 = (a + b + c) / 3.0
			if _point_in_any_gap(mid, sites, margin_along, extra_lat) \
					or _point_in_any_gap(a.lerp(mid, 0.5), sites, margin_along, extra_lat) \
					or _point_in_any_gap(b.lerp(mid, 0.5), sites, margin_along, extra_lat) \
					or _point_in_any_gap(c.lerp(mid, 0.5), sites, margin_along, extra_lat):
				continue
			out_v.append(a)
			out_v.append(b)
			out_v.append(c)
			if has_n:
				out_n.append(norms[i0])
				out_n.append(norms[i0 + 1])
				out_n.append(norms[i0 + 2])
			if has_uv:
				out_uv.append(uvs[i0])
				out_uv.append(uvs[i0 + 1])
				out_uv.append(uvs[i0 + 2])
			if has_c:
				out_c.append(cols[i0])
				out_c.append(cols[i0 + 1])
				out_c.append(cols[i0 + 2])
		if not out_v.is_empty():
			var new_arr: Array = []
			new_arr.resize(Mesh.ARRAY_MAX)
			new_arr[Mesh.ARRAY_VERTEX] = out_v
			if has_n:
				new_arr[Mesh.ARRAY_NORMAL] = out_n
			if has_uv:
				new_arr[Mesh.ARRAY_TEX_UV] = out_uv
			if has_c:
				new_arr[Mesh.ARRAY_COLOR] = out_c
			var s_idx: int = new_mesh.get_surface_count()
			new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arr)
			new_mesh.surface_set_material(s_idx, old_mesh.surface_get_material(surf))
	mi.mesh = new_mesh


static func _carve_road_gaps(race: Node3D, sites: Array[Dictionary]) -> void:
	var road_holder := race.get_node_or_null(KenneyTiles.HOLDER_NAME) as Node3D
	if road_holder == null:
		road_holder = race.get_node_or_null("KenneyTilesRoad") as Node3D
	if road_holder == null:
		return

	# 1. Carve visual road mesh & painted kerb detail triangles inside each chasm gap
	var road_mi := road_holder.get_node_or_null("Road") as MeshInstance3D
	_carve_array_mesh_gaps(road_mi, sites, -0.05, 3.8)
	var detail_holder := race.get_node_or_null("KenneyTrackDetail") as Node3D
	if detail_holder != null:
		var detail_mi := detail_holder.get_node_or_null("TrackDetail") as MeshInstance3D
		_carve_array_mesh_gaps(detail_mi, sites, -0.05, 5.5)

	# The RampDetail lip/walls are built by KenneyTiles from the same measured
	# surface the collider uses, so they are left untouched here. They used to be
	# squashed by 0.22x along with the Ramps collider, which put both the paint
	# and the physics inside the 2.86 m visible kicker.

	# 2. Carve RoadCollision ConcavePolygonShape3D & under-deck BoxShape3D fill blocks.
	#    The jump ramps' own collider is NOT touched: KenneyTiles built it from the
	#    measured surface of the visible kicker, so mesh and collider already agree.
	#    (An earlier 0.22x compression here assumed a 0.70 m crest and left the
	#    collider inside a 2.86 m ramp: karts drove straight through the art.)
	var col_body := road_holder.get_node_or_null("RoadCollision") as StaticBody3D
	if col_body != null:
		for child: Node in col_body.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			if cs.name == "RoadSurface" and cs.shape is ConcavePolygonShape3D:
				var concave := cs.shape as ConcavePolygonShape3D
				var faces: PackedVector3Array = concave.get_faces()
				var kept := PackedVector3Array()
				var tri_cnt: int = faces.size() / 3
				for ti in tri_cnt:
					var i0: int = ti * 3
					var mid: Vector3 = (faces[i0] + faces[i0 + 1] + faces[i0 + 2]) / 3.0
					if _point_in_any_gap(mid, sites, -0.05, 3.8):
						continue
					kept.append(faces[i0])
					kept.append(faces[i0 + 1])
					kept.append(faces[i0 + 2])
				var new_concave := ConcavePolygonShape3D.new()
				new_concave.set_faces(kept)
				new_concave.backface_collision = true
				cs.shape = new_concave
			elif cs.shape is BoxShape3D:
				# Under-deck fill box on the gap cell: remove it so a falling car
				# drops into the chasm instead of landing on an under-road cube!
				for site: Dictionary in sites:
					var gcell: Vector2i = site["gap_cell"] as Vector2i
					var cell_center := Vector3((float(gcell.x) + 0.5) * TileKit.TILE_SIZE, 0.0,
						(float(gcell.y) + 0.5) * TileKit.TILE_SIZE)
					if Vector2(cs.position.x - cell_center.x, cs.position.z - cell_center.z).length() < 4.5:
						cs.queue_free()
						break
		# Add solid landing deck collider for the remaining 4.55 m of the 22 m gap cell (GAP_END_M..22.05 m)
		var apron_len: float = maxf(TileKit.TILE_SIZE - GAP_END_M + 0.1, 1.5)
		for site: Dictionary in sites:
			var lip: Vector3 = site["lip_pos"] as Vector3
			var yaw: float = float(site["yaw"])
			var xf := Transform3D(Basis(Vector3.UP, yaw), lip)
			var apron_box := BoxShape3D.new()
			apron_box.size = Vector3(TileKit.ROAD_HALF * 2.1, 0.5, apron_len)
			var apron_cs := CollisionShape3D.new()
			apron_cs.name = "ChasmLandingApron"
			apron_cs.shape = apron_box
			apron_cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.25, -(GAP_END_M + apron_len * 0.5)))
			col_body.add_child(apron_cs)

	# 3. Hide any BridgeSupports instance standing directly inside the carved chasm cell
	for child: Node in road_holder.get_children():
		if str(child.name).begins_with("BridgeSupports") and child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.multimesh == null:
				continue
			var mesh_center := Vector3.ZERO
			if mmi.multimesh.mesh != null:
				mesh_center = mmi.multimesh.mesh.get_aabb().get_center()
			for idx in mmi.multimesh.instance_count:
				var xf: Transform3D = mmi.multimesh.get_instance_transform(idx)
				var world_center: Vector3 = xf * mesh_center
				for site: Dictionary in sites:
					var gcell: Vector2i = site["gap_cell"] as Vector2i
					var cell_center := Vector3((float(gcell.x) + 0.5) * TileKit.TILE_SIZE, 0.0,
						(float(gcell.y) + 0.5) * TileKit.TILE_SIZE)
					if Vector2(world_center.x - cell_center.x, world_center.z - cell_center.z).length() < 9.5 \
							or Vector2(xf.origin.x - cell_center.x, xf.origin.z - cell_center.z).length() < 9.5:
						mmi.multimesh.set_instance_transform(idx,
							Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0.0, -50.0, 0.0)))

	# 4. Break safety rails / guardrails cleanly across the open chasm gap
	var dressing := race.get_node_or_null("GlacierDressing") as Node3D
	if dressing != null:
		for child: Node in dressing.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := child as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			if not (str(mmi.name).contains("Barrier") or str(mmi.name).contains("Rail") or str(mmi.name).contains("Post")):
				continue
			for idx in mmi.multimesh.instance_count:
				var xf: Transform3D = mmi.multimesh.get_instance_transform(idx)
				if _point_in_any_gap(xf.origin, sites, -0.5, 6.5):
					mmi.multimesh.set_instance_transform(idx,
						Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3(0.0, -50.0, 0.0)))


func _dress_chasms(sites: Array[Dictionary]) -> Dictionary:
	var rock_batch := PropBatch.new()
	var glow_batch := PropBatch.new()
	var crystal_batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260850
	var objects: int = 0

	var slate_dark := Color("1c2f52")
	var slate_mid := Color("2e4d7d")
	var slate_ice := Color("598bc2")
	var snow_white := Color("eaf6ff")
	var timber_dark := Color("4a3121")
	var timber_broken := Color("6e4930")
	var hazard_gold := Color("ffb928")
	var hazard_red := Color("ff3d47")
	var road_half: float = TileKit.ROAD_HALF
	var ramp_crest_y: float = KenneyTiles.ramp_top_height("J")

	for site: Dictionary in sites:
		var lip: Vector3 = site["lip_pos"] as Vector3
		var yaw: float = float(site["yaw"])
		var deck_y: float = float(site["deck_y"])
		# Local frame at takeoff lip: -Z is forward along the chasm jump!
		var xf := Transform3D(Basis(Vector3.UP, yaw), lip)

		# 1. Shattered Takeoff & Landing Cliff Edges + Broken Timber Planks
		for end_idx in 2:
			var is_takeoff: bool = end_idx == 0
			var z_edge: float = -GAP_START_M if is_takeoff else -GAP_END_M
			var dir_sign: float = -1.0 if is_takeoff else 1.0
			var lip_y_off: float = ramp_crest_y if is_takeoff else 0.0

			# Jagged snow-crusted slate rock shelf under the broken road lip
			rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -2.4, z_edge - dir_sign * 1.1)),
				Vector3(road_half * 2.15, 4.8, 2.4), slate_mid)
			rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -7.2, z_edge - dir_sign * 1.6)),
				Vector3(road_half * 2.35, 9.6, 3.2), slate_dark)
			# Snow lip cornice overhanging the broken edge
			rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, lip_y_off - 0.14, z_edge)),
				Vector3(road_half * 2.04, 0.30, 0.95), snow_white)
			if not is_takeoff:
				var apron_len: float = maxf(TileKit.TILE_SIZE - GAP_END_M + 0.08, 1.5)
				rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.22, z_edge - apron_len * 0.5)),
					Vector3(road_half * 1.98, 0.44, apron_len), Color("7b8794"))
				for k_side: float in [-1.0, 1.0]:
					rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(k_side * (road_half + 0.35), -0.10, z_edge - apron_len * 0.5)),
						Vector3(0.75, 0.32, apron_len), snow_white)

			# 7 Splintered timber bridge beams jutting out over the abyss
			for b_i in 7:
				var bx: float = lerpf(-road_half * 0.84, road_half * 0.84, float(b_i) / 6.0)
				var jut: float = rng.randf_range(1.15, 2.65)
				var pitch_droop: float = rng.randf_range(-0.20, -0.06) * dir_sign
				var yaw_j: float = rng.randf_range(-0.08, 0.08)
				var beam_xf := xf * Transform3D(
					Basis(Vector3.UP, yaw_j) * Basis(Vector3.RIGHT, pitch_droop),
					Vector3(bx, lip_y_off - 0.22, z_edge + dir_sign * (jut * 0.5))
				)
				rock_batch.add_box(beam_xf, Vector3(0.62, 0.30, jut + 0.7),
					timber_dark if b_i % 2 == 0 else timber_broken)
				objects += 1

			# Twin Stone & Ice Bridge Abutment Towers flanking the road (outside BARRIER_CLEARANCE!)
			for side: float in [-1.0, 1.0]:
				var px: float = side * (road_half + 2.85)
				var pier_xf := xf * Transform3D(Basis.IDENTITY, Vector3(px, lip_y_off * 0.5 - 3.5, z_edge))
				rock_batch.add_box(pier_xf, Vector3(3.2, 11.5 + lip_y_off, 3.4), slate_mid)
				rock_batch.add_box(pier_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, (11.5 + lip_y_off) * 0.5 + 0.15, 0.0)),
					Vector3(3.6, 0.65, 3.8), snow_white)
				# Timber hazard sign post + Glowing Solar-Gold Chevron Warning Board
				rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(px, lip_y_off + 2.8, z_edge)),
					Vector3(2.5, 1.45, 0.28), slate_dark)
				glow_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(px, lip_y_off + 2.8, z_edge - dir_sign * 0.18)),
					Vector3(2.25, 1.15, 0.12), hazard_gold if is_takeoff else Color("38e8ff"))
				# Pulsing crimson/gold beacon lantern atop the abutment tower
				glow_batch.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(px, lip_y_off + 3.95, z_edge)),
					0.36, 0.65, 8, hazard_red if is_takeoff else hazard_gold)
				objects += 4

		# 2. Deep Glacial Crevasse Floor & Glowing Turquoise Abyss Crystals below the gap
		var z_mid: float = -(GAP_START_M + GAP_END_M) * 0.5
		var abyss_drop: float = minf(deck_y + 3.5, 11.5)
		# Dark chasm walls flanking the crevasse
		for side: float in [-1.0, 1.0]:
			var wx: float = side * (road_half + 3.4)
			rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(wx, -abyss_drop * 0.5, z_mid)),
				Vector3(3.6, abyss_drop, GAP_LENGTH_M + 2.0), slate_dark)
			rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(wx - side * 1.2, -abyss_drop * 0.35, z_mid)),
				Vector3(1.8, abyss_drop * 0.65, GAP_LENGTH_M * 0.85), slate_ice)
		# Glowing deep turquoise fissure floor at the bottom of the chasm
		rock_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -abyss_drop, z_mid)),
			Vector3(road_half * 2.4, 0.8, GAP_LENGTH_M + 3.0), Color("102544"))
		glow_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -abyss_drop + 0.45, z_mid)),
			Vector3(road_half * 1.65, 0.15, GAP_LENGTH_M * 0.78), Color("2de2ff"))

		# Giant glowing ice crystal clusters erupting out of the chasm abyss walls
		for c_side: float in [-1.0, 1.0]:
			for c_idx in 2:
				var cz: float = lerpf(-GAP_START_M - 2.6, -GAP_END_M + 2.6, float(c_idx))
				var c_world: Vector3 = xf * Vector3(c_side * (road_half + 3.8), -abyss_drop * 0.55, cz)
				ConceptSpectacle.add_crystal_cluster(crystal_batch, c_world, 1.35, rng, rock_batch)
				objects += 5

		# 3. Approach Solar-Gold Speed Boost Strip (28 m before the 'J' takeoff lip!)
		var s_pad: float = fposmod(float(site["s_takeoff"]) - 28.0, float(_spline.total_length))
		var p_frame: Dictionary = _spline.sample(s_pad)
		var p_pos: Vector3 = p_frame["position"] as Vector3
		var p_fw: Vector3 = (p_frame["forward"] as Vector3)
		p_fw.y = 0.0
		if p_fw.length_squared() > 0.001:
			p_fw = p_fw.normalized()
			var p_yaw: float = atan2(-p_fw.x, -p_fw.z)
			var p_xf := Transform3D(Basis(Vector3.UP, p_yaw), p_pos + Vector3(0.0, KenneyTiles.ROAD_SURFACE + 0.04, 0.0))
			rock_batch.add_box(p_xf, Vector3(7.4, 0.05, 8.6), Color("1b2238"))
			for ch_i in 4:
				var cz_off: float = -3.0 + float(ch_i) * 2.0
				for side: float in [-1.0, 1.0]:
					var wing_xf := p_xf * Transform3D(Basis(Vector3.UP, -side * 0.55),
						Vector3(side * 1.45, 0.03, cz_off))
					glow_batch.add_box(wing_xf, Vector3(3.1, 0.04, 0.56), hazard_gold)
			objects += 9

	var draws: int = 0
	if rock_batch. flush_to(self, "ChasmAbutmentsAndBeams", false, SceneryKit.vertex_material()) != null:
		draws += 1
	var glow_mat := StandardMaterial3D.new()
	glow_mat.vertex_color_use_as_albedo = true
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.emission_enabled = true
	glow_mat.emission = Color("ffc842")
	glow_mat.emission_energy_multiplier = 2.4
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow_batch.flush_to(self, "ChasmHazardGlow", false, glow_mat) != null:
		draws += 1
	if crystal_batch.flush_to(self, "ChasmAbyssCrystals", false, ConceptSpectacle.crystal_material()) != null:
		draws += 1
	return {"objects": objects, "draws": draws}


## Weight-normalized target takeoff speed (m/s) for any CartPlayer.
## Heavy vehicles (3,200 kg Box Truck, 2,150 kg Van) have lower catalog top
## speeds and heavier inertia on alpine climbs, so their required takeoff speed
## is balanced to ~58% of their max_speed, while nimble racers (750 kg Pro Racer,
## 45 kg Shopping Cart) require ~65% of their max_speed.
static func required_speed_for(cart: Node3D) -> float:
	if cart == null:
		return 15.0
	var mass: float = clampf(float(cart.call("get_mass")) if cart.has_method("get_mass") else 1200.0, 45.0, 3500.0)
	var weight_t: float = clampf((mass - 45.0) / (3200.0 - 45.0), 0.0, 1.0)
	var top_spd: float = maxf(float(cart.get("max_speed")), 16.0)
	return top_spd * lerpf(0.65, 0.57, weight_t)


func _physics_process(delta: float) -> void:
	if _race == null or not is_instance_valid(_race) or _chasm_sites.is_empty():
		return
	# Tick cooldowns
	for key: int in _launch_cooldowns.keys():
		var rem: float = float(_launch_cooldowns[key]) - delta
		if rem <= 0.0:
			_launch_cooldowns.erase(key)
		else:
			_launch_cooldowns[key] = rem
	for key: int in _pad_cooldowns.keys():
		var rem: float = float(_pad_cooldowns[key]) - delta
		if rem <= 0.0:
			_pad_cooldowns.erase(key)
		else:
			_pad_cooldowns[key] = rem
	for key: int in _active_jumpers.keys():
		var jinfo: Dictionary = _active_jumpers[key] as Dictionary
		var rem: float = float(jinfo.get("timer", 0.0)) - delta
		if rem <= 0.0:
			_active_jumpers.erase(key)
		else:
			jinfo["timer"] = rem

	var carts: Array[CharacterBody3D] = []
	var player_cart: CharacterBody3D = _race.get("_cart") as CharacterBody3D
	if player_cart != null and is_instance_valid(player_cart) and not bool(player_cart.get("remote_mode")):
		carts.append(player_cart)
	var rivals: Variant = _race.get("_rivals")
	if rivals is Array:
		for entry: Variant in rivals as Array:
			if entry is Dictionary:
				var rc: CharacterBody3D = (entry as Dictionary).get("node") as CharacterBody3D
				if rc != null and is_instance_valid(rc) and not bool(rc.get("remote_mode")):
					carts.append(rc)

	var road_half: float = TileKit.ROAD_HALF
	for cart: CharacterBody3D in carts:
		var cid: int = cart.get_instance_id()
		var pos: Vector3 = cart.global_position
		if _active_jumpers.has(cid):
			var jinfo: Dictionary = _active_jumpers[cid] as Dictionary
			var jfw: Vector3 = jinfo["fw"] as Vector3
			var jspd: float = float(jinfo["horiz_speed"])
			var cur_fwd: float = cart.velocity.dot(jfw)
			if cur_fwd < jspd:
				cart.velocity += jfw * (jspd - cur_fwd)
		for site: Dictionary in _chasm_sites:
			var lip: Vector3 = site["lip_pos"] as Vector3
			var fw: Vector3 = site["forward"] as Vector3
			var right: Vector3 = site["right"] as Vector3
			var deck_y: float = float(site["deck_y"])
			var rel: Vector3 = pos - lip
			var along: float = rel.x * fw.x + rel.z * fw.z
			var lat: float = rel.x * right.x + rel.z * right.z
			if absf(lat) > road_half + 4.0:
				continue

			# 1. AI Bot Chasm Approach Intelligence: engage boost on approach so AI
			#    rivals charge the cliff jump at full speed!
			if bool(cart.get("ai_mode")) and along >= -48.0 and along <= 1.0:
				cart.set("ai_boost", true)
				cart.set("ai_throttle", 1.0)
				cart.set("ai_brake", 0.0)

			# 2. Approach Speed Boost Strip (-32..-23 m before lip)
			if along >= -32.5 and along <= -23.5 and absf(lat) <= 4.2 \
					and absf(pos.y - deck_y) < 2.2 and not _pad_cooldowns.has(cid):
				_pad_cooldowns[cid] = 1.2
				var boost_target: float = maxf(float(cart.get("max_speed")) * 1.22, required_speed_for(cart) * 1.28)
				var cur_fwd: float = cart.velocity.dot(fw)
				if cur_fwd < boost_target:
					cart.velocity += fw * (boost_target - cur_fwd)
				cart.set("_pad_burst_timer", 0.65)

			# 3. Takeoff Lip Ballistic Launch Check (-2.6..1.0 m from lip)
			if along >= -2.6 and along <= 1.0 and pos.y >= deck_y - 0.65 \
					and not _launch_cooldowns.has(cid):
				var raw_fwd: float = cart.velocity.dot(fw)
				var fwd_speed: float = Vector2(maxf(raw_fwd, 0.0), maxf(cart.velocity.y, 0.0)).length() if raw_fwd > 0.0 else raw_fwd
				var req_speed: float = required_speed_for(cart)
				_launch_cooldowns[cid] = 1.4
				if fwd_speed >= req_speed:
					# Weight-compensated ballistic launch across the 17.35 m chasm!
					var mass: float = clampf(float(cart.call("get_mass")) if cart.has_method("get_mass") else 1200.0, 45.0, 3500.0)
					var weight_t: float = clampf((mass - 45.0) / (3200.0 - 45.0), 0.0, 1.0)
					var target_horiz: float = maxf(fwd_speed * lerpf(1.36, 1.68, weight_t), 28.4)
					var lat_vel: Vector3 = cart.velocity - fw * raw_fwd
					lat_vel.y = 0.0
					var launch_vy: float = maxf(cart.velocity.y, lerpf(9.4, 10.2, weight_t))
					# No forced lift: the ramp collider now reaches the same 2.86 m
					# crest as the visible kicker (KenneyTiles measures both from the
					# GLB), so the kart is already at crest height on the lip and the
					# launch only has to add the ballistic arc.
					cart.set("_pad_burst_timer", 0.80)
					cart.velocity = fw * target_horiz + lat_vel * 0.25 + Vector3.UP * launch_vy
					_active_jumpers[cid] = {
						"fw": fw,
						"horiz_speed": target_horiz,
						"timer": 0.74,
					}
					if cart == player_cart and _race.has_method("_toast"):
						_race.call("_toast", "CLIFF CHASM LEAP!  ·  %.0f KM/H" % (fwd_speed * 3.6), 1.4)
				elif fwd_speed > 0.5:
					# Too slow for this vehicle's weight! Tip the car off the broken timber lip
					# into the carved chasm gap so it drops into the crevasse.
					_active_jumpers.erase(cid)
					var drop_pos: Vector3 = lip + fw * 2.25 + right * clampf(lat, -road_half * 0.7, road_half * 0.7)
					drop_pos.y = deck_y + 0.45
					cart.global_position = drop_pos
					cart.velocity = fw * clampf(fwd_speed, 5.5, 9.0) + Vector3.UP * -6.0

			# 4. Chasm Fall Detection & Setback Penalty!
			#    If a car didn't have enough speed and drops below the broken deck
			#    inside the gap, set it back 40 m before the jump ramp!
			if along >= GAP_START_M - 0.3 and along <= GAP_END_M + 0.8 \
					and pos.y < deck_y - 1.15:
				_setback_fallen_cart(cart, player_cart, site)
				break


func _setback_fallen_cart(cart: CharacterBody3D, player_cart: CharacterBody3D,
		site: Dictionary) -> void:
	var s_setback: float = float(site["s_setback"])
	var s_takeoff: float = float(site["s_takeoff"])
	var cid: int = cart.get_instance_id()
	_launch_cooldowns[cid] = 1.0
	_pad_cooldowns.erase(cid)
	_active_jumpers.erase(cid)

	if cart == player_cart:
		if _race.has_method("_safe_respawn_transform"):
			cart.global_transform = _race.call("_safe_respawn_transform", s_setback) as Transform3D
		cart.call("reset_for_respawn")
		cart.velocity = Vector3.ZERO
		var rig: Node = cart.get_node_or_null("CameraArm")
		if rig != null and rig.has_method("reset_camera"):
			rig.call("reset_camera")
		# Rewind the player's unwrapped lap distance by the setback so falling
		# genuinely sets them back instead of advancing them past the jump!
		var cur_unwrapped: float = float(_race.get("_unwrapped"))
		var delta_back: float = SETBACK_DISTANCE_M + 8.0
		_race.set("_unwrapped", maxf(cur_unwrapped - delta_back, 0.0))
		_race.set("_prev_s", s_setback)
		_race.set("_skip_progress", true)
		_race.set("_off_timer", 0.0)
		_race.set("_air_time", 0.0)
		_race.set("_fall_speed", 0.0)
		var req_kmh: float = required_speed_for(cart) * 3.6
		if _race.has_method("_toast"):
			_race.call("_toast",
				"FELL IN THE CLIFF CHASM!  ·  NEED %.0f+ KM/H TO CLEAR!" % req_kmh, 2.4)
		return

	# AI rival fell into the chasm: set the rival back 40 m before the jump too!
	var rivals: Variant = _race.get("_rivals")
	if rivals is Array:
		for entry: Variant in rivals as Array:
			if entry is Dictionary and (entry as Dictionary).get("node") == cart:
				var r_dict: Dictionary = entry as Dictionary
				var lateral: float = float(r_dict.get("offset", 0.0))
				if _race.has_method("_track_transform"):
					cart.global_transform = _race.call("_track_transform", s_setback, lateral, 0.25) as Transform3D
				cart.call("reset_for_respawn")
				cart.velocity = Vector3.ZERO
				var r_prog: float = float(r_dict.get("progress", s_takeoff))
				r_dict["progress"] = maxf(r_prog - (SETBACK_DISTANCE_M + 8.0), 0.0)
				break
