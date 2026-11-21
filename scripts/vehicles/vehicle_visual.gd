extends RefCounted
## Builds a normalised, ground-aligned copy of a vehicle model.
## Scale is chosen so the longest horizontal side matches the catalog length,
## which keeps every model inside the same kart-sized collision box.
##
## In 0.8.5 the signature Shopping Cart is built as a bespoke high-detail
## Hero Turbo Racing Shopping Cart (chrome tubular chassis, wire lattice basket,
## red corner guards & push handle, oversized racing slicks with gold rims,
## twin cyan/gold rear nitro thrusters, carbon GT wing, front aero splitter,
## LED headlights, and swaying racing pennant), and every other vehicle gets
## glossy clearcoat paint polish plus mode-matched bolt-on lighting & aero kits.

const OUTLINE_SHADER := preload("res://assets/materials/toon_outline.gdshader")


class _VehicleLiveRig extends Node3D:
	## Lightweight visual animation driver (police lightbar strobe, thruster
	## core pulse, flag sway). Stays completely dormant in headless test runs.
	var flag_pivot: Node3D
	var thruster_mats: Array[StandardMaterial3D] = []
	var police_red_mat: StandardMaterial3D
	var police_blue_mat: StandardMaterial3D
	var _t: float = 0.0

	func _ready() -> void:
		if DisplayServer.get_name() == "headless":
			set_process(false)

	func _process(delta: float) -> void:
		_t += delta
		if flag_pivot != null:
			flag_pivot.rotation.y = sin(_t * 7.2) * 0.24
			flag_pivot.rotation.z = -0.10 + cos(_t * 5.1) * 0.08
		if not thruster_mats.is_empty():
			var pulse: float = 2.1 + 0.65 * sin(_t * 14.0)
			for m: StandardMaterial3D in thruster_mats:
				if m != null:
					m.emission_energy_multiplier = pulse
		if police_red_mat != null and police_blue_mat != null:
			var phase: bool = fmod(_t * 5.2, 1.0) < 0.5
			police_red_mat.emission_energy_multiplier = 4.2 if phase else 0.25
			police_blue_mat.emission_energy_multiplier = 0.25 if phase else 4.2


static func build(entry: Dictionary) -> Node3D:
	var id: String = str(entry.get("id", ""))
	var holder := Node3D.new()
	holder.name = "VehicleVisual"
	holder.set_meta("engine_audio_profile", engine_audio_profile(entry))

	if id == "shopping_cart":
		_build_hero_shopping_cart(holder, entry)
		holder.rotation.y = deg_to_rad(float(entry.get("yaw", 0.0)))
		return holder

	var scene_path: String = str(entry.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("Vehicle model missing: " + scene_path)
		_add_fallback_body(holder, entry)
		return holder

	var inner := Node3D.new()
	holder.add_child(inner)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		_add_fallback_body(holder, entry)
		return holder
	inner.add_child(instance)

	var acc: Array = []
	_measure(instance, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		_add_fallback_body(holder, entry)
		return holder
	var bounds: AABB = acc[0]
	var footprint: float = maxf(bounds.size.x, bounds.size.z)
	var target: float = float(entry.get("length", 2.4))
	var scale_factor: float = target / maxf(footprint, 0.01)
	inner.scale = Vector3.ONE * scale_factor

	var center: Vector3 = bounds.get_center() * scale_factor
	inner.position = Vector3(-center.x, -bounds.position.y * scale_factor, -center.z)

	var yaw_deg: float = float(entry.get("yaw", 180.0))
	holder.rotation.y = deg_to_rad(yaw_deg)
	_force_visible_materials(instance, true)
	_apply_custom_paint(instance, entry)

	var scaled_size: Vector3 = bounds.size * scale_factor
	_add_vehicle_upgrades(holder, id, scaled_size, yaw_deg)
	return holder


# --------------------------------------------------------------------------
# Bespoke Hero Turbo Racing Shopping Cart (front = -Z, rear = +Z, ground y = 0)


static func _mat(color: Color, roughness: float = 0.42, metallic: float = 0.0,
		clearcoat: float = 0.0, emission: Color = Color(0, 0, 0, 0),
		emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if clearcoat > 0.01:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.16
	if emission_energy > 0.01:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_cyl(parent: Node3D, top_r: float, bot_r: float, height: float,
		pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO,
		segs: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_strut(parent: Node3D, a: Vector3, b: Vector3, radius: float,
		mat: Material, segs: int = 10) -> MeshInstance3D:
	var diff: Vector3 = b - a
	var length: float = diff.length()
	if length < 0.002:
		return null
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	var up: Vector3 = diff.normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(up.y) > 0.96 else Vector3.UP
	var x_axis: Vector3 = ref.cross(up).normalized()
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	mi.basis = Basis(x_axis, up, z_axis)
	parent.add_child(mi)
	return mi


static func _build_hero_shopping_cart(holder: Node3D, entry: Dictionary) -> void:
	var target_len: float = float(entry.get("length", 1.8))
	var scale_k: float = target_len / 1.80
	var root := Node3D.new()
	root.name = "HeroShoppingCart"
	root.scale = Vector3.ONE * scale_k
	holder.add_child(root)

	var rig := _VehicleLiveRig.new()
	rig.name = "LiveRig"
	root.add_child(rig)

	# Palette matching our new app icon & paddock key art.
	var mat_chrome := _mat(Color("eef3fb"), 0.16, 0.88, 0.40)
	var mat_steel := _mat(Color("b6c2d6"), 0.28, 0.78)
	var mat_carbon := _mat(Color("1c2030"), 0.34, 0.25, 0.35)
	var mat_red := _mat(Color("e6323c"), 0.24, 0.12, 0.70)
	var mat_gold := _mat(Color("ffbe26"), 0.22, 0.82, 0.45)
	var mat_cyan := _mat(Color("22d6ff"), 0.20, 0.35, 0.65)
	var mat_tire := _mat(Color("1a1b26"), 0.86, 0.04)
	var mat_caliper := _mat(Color("ff2e44"), 0.30, 0.20)
	var mat_headlight := _mat(Color("fff9df"), 0.12, 0.0, 0.0, Color("fff2b8"), 3.2)
	var mat_taillight := _mat(Color("ff2a3c"), 0.18, 0.0, 0.0, Color("ff1f38"), 2.6)
	var mat_jet_glow := _mat(Color("7ff2ff"), 0.10, 0.0, 0.0, Color("2be4ff"), 2.6)
	rig.thruster_mats.append(mat_jet_glow)

	# ---- 1. Four Oversized Racing Slick Wheels (touching y = 0) ----
	var wheel_specs: Array[Array] = [
		[-0.44, 0.21, -0.58, 0.21, 0.18], # Front-left
		[ 0.44, 0.21, -0.58, 0.21, 0.18], # Front-right
		[-0.48, 0.25,  0.54, 0.25, 0.23], # Rear-left (chunkier slicks!)
		[ 0.48, 0.25,  0.54, 0.25, 0.23], # Rear-right
	]
	for w: Array in wheel_specs:
		var wx: float = float(w[0])
		var wy: float = float(w[1])
		var wz: float = float(w[2])
		var wr: float = float(w[3])
		var ww: float = float(w[4])
		var side_sign: float = signf(wx)
		# Rubber slick tire
		_add_cyl(root, wr, wr, ww, Vector3(wx, wy, wz), mat_tire, Vector3(0, 0, 90), 20)
		# Deep-dish gold rim barrel
		_add_cyl(root, wr * 0.64, wr * 0.64, ww + 0.015, Vector3(wx, wy, wz), mat_gold, Vector3(0, 0, 90), 16)
		# Dark inner dish + chrome center lug
		_add_cyl(root, wr * 0.42, wr * 0.42, ww + 0.025, Vector3(wx, wy, wz), mat_carbon, Vector3(0, 0, 90), 12)
		_add_cyl(root, wr * 0.18, wr * 0.18, ww + 0.042, Vector3(wx, wy, wz), mat_chrome, Vector3(0, 0, 90), 10)
		# Red racing brake caliper peeking on inside upper hub
		_add_box(root, Vector3(0.05, wr * 0.46, wr * 0.42),
			Vector3(wx - side_sign * (ww * 0.36), wy + wr * 0.26, wz - 0.03), mat_caliper)
		# Heavy chrome caster/suspension fork joining wheel to chassis
		_add_strut(root, Vector3(wx - side_sign * 0.04, wy + 0.02, wz),
			Vector3(wx * 0.80, 0.42, wz * 0.94), 0.030, mat_steel, 10)

	# ---- 2. Tubular Chrome Lower Chassis & Front Aero Splitter ----
	# Twin lower side rails sweeping back and rising into rear frame
	for sx: float in [-1.0, 1.0]:
		_add_strut(root, Vector3(sx * 0.36, 0.36, -0.78), Vector3(sx * 0.40, 0.40, 0.68), 0.032, mat_chrome, 12)
		# Rear A-frame uprights from lower rail up to basket & push handle
		_add_strut(root, Vector3(sx * 0.40, 0.40, 0.66), Vector3(sx * 0.44, 1.24, 0.72), 0.030, mat_chrome, 12)
		# Diagonal racing cross-brace
		_add_strut(root, Vector3(sx * 0.38, 0.38, -0.20), Vector3(sx * 0.42, 0.98, 0.66), 0.024, mat_chrome, 10)
		# Front basket support strut
		_add_strut(root, Vector3(sx * 0.36, 0.38, -0.64), Vector3(sx * 0.34, 0.74, -0.76), 0.024, mat_chrome, 10)
	# Cross-axles & lower cargo tray
	_add_strut(root, Vector3(-0.46, 0.21, -0.58), Vector3(0.46, 0.21, -0.58), 0.026, mat_steel, 10)
	_add_strut(root, Vector3(-0.50, 0.25,  0.54), Vector3(0.50, 0.25,  0.54), 0.032, mat_steel, 10)
	_add_box(root, Vector3(0.68, 0.035, 1.26), Vector3(0.0, 0.36, -0.02), mat_carbon)
	# Front carbon aero splitter with yellow-gold lip + glowing LED headlights
	_add_box(root, Vector3(0.96, 0.055, 0.24), Vector3(0.0, 0.26, -0.82), mat_carbon)
	_add_box(root, Vector3(1.00, 0.028, 0.08), Vector3(0.0, 0.24, -0.92), mat_gold)
	for sx: float in [-1.0, 1.0]:
		# Splitter endplate winglets
		_add_box(root, Vector3(0.04, 0.14, 0.26), Vector3(sx * 0.49, 0.31, -0.82), mat_red)
		# Headlight pod + glowing LED lens
		_add_cyl(root, 0.075, 0.082, 0.12, Vector3(sx * 0.30, 0.43, -0.80), mat_carbon, Vector3(90, 0, 0), 12)
		_add_cyl(root, 0.062, 0.062, 0.03, Vector3(sx * 0.30, 0.43, -0.86), mat_headlight, Vector3(90, 0, 0), 12)

	# ---- 3. Tapered Chrome Wire Basket (sloped racing wedge profile) ----
	# Basket corner coordinates: wider/higher at rear (+Z), sleeker/lower at front (-Z)
	var b_fl := Vector3(-0.34, 0.66, -0.78)
	var b_fr := Vector3( 0.34, 0.66, -0.78)
	var b_rl := Vector3(-0.42, 0.72,  0.60)
	var b_rr := Vector3( 0.42, 0.72,  0.60)

	var t_fl := Vector3(-0.39, 1.06, -0.84)
	var t_fr := Vector3( 0.39, 1.06, -0.84)
	var t_rl := Vector3(-0.45, 1.24,  0.64)
	var t_rr := Vector3( 0.45, 1.24,  0.64)

	# Perimeter heavy chrome rails (top + bottom + 4 corner ribs)
	for seg: Array in [
		[t_fl, t_fr], [t_rl, t_rr], [t_fl, t_rl], [t_fr, t_rr],
		[b_fl, b_fr], [b_rl, b_rr], [b_fl, b_rl], [b_fr, b_rr],
		[b_fl, t_fl], [b_fr, t_fr], [b_rl, t_rl], [b_rr, t_rr],
	]:
		_add_strut(root, seg[0] as Vector3, seg[1] as Vector3, 0.022, mat_chrome, 10)

	# Side horizontal wire rails (3 rows) + vertical wire ribs (6 columns per side)
	for row in range(1, 4):
		var ty: float = float(row) / 4.0
		_add_strut(root, b_fl.lerp(t_fl, ty), b_rl.lerp(t_rl, ty), 0.011, mat_steel, 6)
		_add_strut(root, b_fr.lerp(t_fr, ty), b_rr.lerp(t_rr, ty), 0.011, mat_steel, 6)
		_add_strut(root, b_fl.lerp(t_fl, ty), b_fr.lerp(t_fr, ty), 0.011, mat_steel, 6)
		_add_strut(root, b_rl.lerp(t_rl, ty), b_rr.lerp(t_rr, ty), 0.011, mat_steel, 6)
	for col in range(1, 6):
		var tz: float = float(col) / 6.0
		_add_strut(root, b_fl.lerp(b_rl, tz), t_fl.lerp(t_rl, tz), 0.010, mat_steel, 6)
		_add_strut(root, b_fr.lerp(b_rr, tz), t_fr.lerp(t_rr, tz), 0.010, mat_steel, 6)
		# Floor lattice bars
		_add_strut(root, b_fl.lerp(b_rl, tz), b_fr.lerp(b_rr, tz), 0.011, mat_steel, 6)
	for fcol in range(1, 4):
		var tx: float = float(fcol) / 4.0
		_add_strut(root, b_fl.lerp(b_fr, tx), t_fl.lerp(t_fr, tx), 0.010, mat_steel, 6)
		_add_strut(root, b_fl.lerp(b_fr, tx), b_rl.lerp(b_rr, tx), 0.010, mat_steel, 6)

	# Red racing nose bumper guards & sporty side number plates
	for sx: float in [-1.0, 1.0]:
		_add_box(root, Vector3(0.08, 0.14, 0.11), Vector3(sx * 0.39, 1.05, -0.84), mat_red)
		_add_box(root, Vector3(0.03, 0.16, 0.44), Vector3(sx * 0.435, 0.96, -0.14), mat_red, Vector3(6.0, 0.0, 0.0))
		_add_box(root, Vector3(0.036, 0.07, 0.36), Vector3(sx * 0.438, 0.96, -0.14), mat_gold, Vector3(6.0, 0.0, 0.0))

	# Red foldable racing bucket / child seat flap inside rear of basket
	_add_box(root, Vector3(0.76, 0.045, 0.28), Vector3(0.0, 0.95, 0.40), mat_red, Vector3(14.0, 0.0, 0.0))
	_add_box(root, Vector3(0.76, 0.24, 0.045), Vector3(0.0, 1.08, 0.26), mat_red, Vector3(-16.0, 0.0, 0.0))

	# ---- 4. Chunky Red Padded Racing Push Handle ----
	var h_left := Vector3(-0.46, 1.32, 0.78)
	var h_right := Vector3(0.46, 1.32, 0.78)
	_add_strut(root, t_rl, h_left, 0.026, mat_chrome, 10)
	_add_strut(root, t_rr, h_right, 0.026, mat_chrome, 10)
	_add_cyl(root, 0.042, 0.042, 0.94, Vector3(0.0, 1.32, 0.78), mat_red, Vector3(0, 0, 90), 14)
	for sx: float in [-1.0, 1.0]:
		_add_cyl(root, 0.048, 0.048, 0.07, Vector3(sx * 0.47, 1.32, 0.78), mat_gold, Vector3(0, 0, 90), 12)

	# ---- 5. Twin Cyan & Gold Rear Nitro Turbo Thrusters (100% coaxial!) ----
	var nozzle_tips: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		var tx: float = sx * 0.24
		var ty: float = 0.57
		var tz: float = 0.62
		var thruster := Node3D.new()
		thruster.name = "TurboThrusterL" if sx < 0.0 else "TurboThrusterR"
		thruster.position = Vector3(tx, ty, tz)
		# Local +Y points straight aft (+Z) with a slight 6 deg upward racing kick.
		thruster.rotation_degrees = Vector3(84.0, 0.0, 0.0)
		root.add_child(thruster)
		# Main electric-cyan turbo cylinder
		_add_cyl(thruster, 0.122, 0.116, 0.46, Vector3(0.0, 0.0, 0.0), mat_cyan, Vector3.ZERO, 16)
		# Front intake cap
		_add_cyl(thruster, 0.110, 0.070, 0.07, Vector3(0.0, -0.25, 0.0), mat_carbon, Vector3.ZERO, 14)
		# Brushed gold mounting collars
		_add_cyl(thruster, 0.136, 0.136, 0.055, Vector3(0.0, -0.12, 0.0), mat_gold, Vector3.ZERO, 16)
		_add_cyl(thruster, 0.136, 0.136, 0.055, Vector3(0.0,  0.12, 0.0), mat_gold, Vector3.ZERO, 16)
		# Dark cone exhaust bell + glowing cyan plasma core coaxially aligned along +Y
		_add_cyl(thruster, 0.138, 0.108, 0.15, Vector3(0.0,  0.29, 0.0), mat_carbon, Vector3.ZERO, 16)
		_add_cyl(thruster, 0.072, 0.095, 0.08, Vector3(0.0,  0.34, 0.0), mat_jet_glow, Vector3.ZERO, 14)
		# Mounting bracket strut locking thruster cleanly to rear chassis frame
		_add_strut(root, Vector3(tx, ty + 0.02, tz - 0.10),
			Vector3(sx * 0.40, 0.50, 0.66), 0.024, mat_steel, 8)
		# Record exact exhaust mouth world-offset in holder space for boost flames
		var tip_local: Vector3 = (thruster.transform * Vector3(0.0, 0.37, 0.0)) * scale_k
		nozzle_tips.append(tip_local)
	holder.set_meta("exhaust_nozzles", nozzle_tips)
	# Rear crimson LED brake light strip between the thrusters
	_add_box(root, Vector3(0.56, 0.055, 0.05), Vector3(0.0, 0.78, 0.65), mat_taillight)

	# ---- 6. Rear Carbon GT Wing Spoiler ----
	for sx: float in [-1.0, 1.0]:
		_add_box(root, Vector3(0.032, 0.24, 0.10), Vector3(sx * 0.26, 1.38, 0.68), mat_gold, Vector3(-16.0, 0.0, 0.0))
	_add_box(root, Vector3(1.06, 0.042, 0.24), Vector3(0.0, 1.49, 0.72), mat_carbon, Vector3(10.0, 0.0, 0.0))
	_add_box(root, Vector3(1.04, 0.018, 0.07), Vector3(0.0, 1.515, 0.80), mat_gold, Vector3(10.0, 0.0, 0.0))
	for sx: float in [-1.0, 1.0]:
		_add_box(root, Vector3(0.034, 0.19, 0.30), Vector3(sx * 0.54, 1.48, 0.72), mat_red)

	# ---- 7. Swaying SlopMart Racing Pennant Flag ----
	_add_strut(root, Vector3(0.45, 1.24, 0.64), Vector3(0.48, 1.72, 0.70), 0.011, mat_chrome, 8)
	var flag_pivot := Node3D.new()
	flag_pivot.position = Vector3(0.48, 1.66, 0.70)
	root.add_child(flag_pivot)
	_add_box(flag_pivot, Vector3(0.016, 0.14, 0.24), Vector3(0.0, 0.0, 0.12), mat_gold)
	_add_box(flag_pivot, Vector3(0.020, 0.06, 0.12), Vector3(0.0, 0.03, 0.07), mat_red)
	_add_box(flag_pivot, Vector3(0.020, 0.06, 0.12), Vector3(0.0, -0.03, 0.18), mat_carbon)
	rig.flag_pivot = flag_pivot


# --------------------------------------------------------------------------
# Bolt-on upgrades & glossy automotive finish for Kenney road & race vehicles


static func _add_vehicle_upgrades(holder: Node3D, id: String,
		scaled_size: Vector3, yaw_deg: float) -> void:
	## Attach lights, exhausts, spoilers, and role hardware in normalized
	## forward=-Z space (undoing holder's yaw_deg so coords are always consistent).
	var kit := Node3D.new()
	kit.name = "UpgradeKit"
	kit.rotation.y = deg_to_rad(-yaw_deg)
	holder.add_child(kit)

	var rig := _VehicleLiveRig.new()
	rig.name = "LiveRig"
	kit.add_child(rig)

	var half_w: float = maxf(scaled_size.x * 0.5, 0.45)
	var half_l: float = maxf(scaled_size.z * 0.5, 0.90)
	var top_y: float = maxf(scaled_size.y, 0.60)
	var is_race: bool = id == "race_car" or id.begins_with("race_car_")

	var mat_headlight := _mat(Color("fff8dc"), 0.12, 0.0, 0.0, Color("fff0b4"), 2.8)
	var mat_taillight := _mat(Color("ff2638"), 0.16, 0.0, 0.0, Color("ff1a32"), 2.4)
	var mat_chrome := _mat(Color("e8eef8"), 0.18, 0.88, 0.35)
	var mat_carbon := _mat(Color("1a1d2b"), 0.32, 0.25, 0.38)
	var mat_gold := _mat(Color("ffbe26"), 0.22, 0.80, 0.40)

	# 1. Glowing LED Headlights & Crimson Taillights
	var light_y: float = top_y * (0.34 if is_race else 0.38)
	var light_x: float = half_w * (0.58 if is_race else 0.64)
	var light_w: float = clampf(half_w * 0.28, 0.14, 0.24)
	for sx: float in [-1.0, 1.0]:
		_add_box(kit, Vector3(light_w, 0.085, 0.05),
			Vector3(sx * light_x, light_y, -half_l - 0.005), mat_headlight)
		_add_box(kit, Vector3(light_w * 1.15, 0.08, 0.05),
			Vector3(sx * light_x, light_y + 0.04, half_l + 0.005), mat_taillight)

	# 2. Twin Chrome Exhaust Pipes under rear bumper
	var ex_x: float = half_w * 0.38
	for sx: float in [-1.0, 1.0]:
		_add_cyl(kit, 0.052, 0.052, 0.20,
			Vector3(sx * ex_x, 0.18, half_l - 0.02), mat_chrome, Vector3(90, 0, 0), 12)

	# 3. Vehicle-specific bespoke styling upgrades
	if id == "sports":
		# Sleek Carbon GT Rear Wing + Gold Endplate Trim
		var wing_y: float = top_y * 0.86
		var wing_z: float = half_l * 0.78
		for sx: float in [-1.0, 1.0]:
			_add_box(kit, Vector3(0.035, 0.22, 0.09), Vector3(sx * half_w * 0.50, wing_y - 0.08, wing_z), mat_carbon)
			_add_box(kit, Vector3(0.032, 0.16, 0.26), Vector3(sx * (half_w * 0.98), wing_y + 0.03, wing_z + 0.02), mat_gold)
		_add_box(kit, Vector3(half_w * 1.96, 0.04, 0.22), Vector3(0.0, wing_y + 0.04, wing_z + 0.02), mat_carbon, Vector3(9.0, 0.0, 0.0))
	elif is_race:
		# Glowing cyan rear diffuser strip + gold aero mirrors
		var mat_neon := _mat(Color("3ae6ff"), 0.12, 0.0, 0.0, Color("22dcff"), 2.4)
		_add_box(kit, Vector3(half_w * 1.08, 0.045, 0.05),
			Vector3(0.0, 0.16, half_l + 0.015), mat_neon)
		rig.thruster_mats.append(mat_neon)
	elif id == "police":
		# Animated Flashing Red/Blue Roof Lightbar + Front Push Bumper
		var bar_y: float = top_y + 0.055
		var mat_p_red := _mat(Color("ff2233"), 0.15, 0.0, 0.0, Color("ff1428"), 3.6)
		var mat_p_blue := _mat(Color("2288ff"), 0.15, 0.0, 0.0, Color("1a7cff"), 0.4)
		_add_box(kit, Vector3(half_w * 1.05, 0.05, 0.16), Vector3(0.0, bar_y - 0.03, -0.06), mat_carbon)
		_add_box(kit, Vector3(half_w * 0.46, 0.09, 0.14), Vector3(-half_w * 0.28, bar_y + 0.03, -0.06), mat_p_red)
		_add_box(kit, Vector3(half_w * 0.46, 0.09, 0.14), Vector3( half_w * 0.28, bar_y + 0.03, -0.06), mat_p_blue)
		_add_box(kit, Vector3(half_w * 1.24, 0.16, 0.08), Vector3(0.0, 0.34, -half_l - 0.05), mat_carbon)
		rig.police_red_mat = mat_p_red
		rig.police_blue_mat = mat_p_blue
	elif id == "taxi":
		# Glowing Amber TAXI Roof Beacon
		var mat_taxi := _mat(Color("ffd93b"), 0.20, 0.0, 0.0, Color("ffbe18"), 2.4)
		_add_box(kit, Vector3(0.56, 0.14, 0.20), Vector3(0.0, top_y + 0.06, -0.06), mat_taxi)
	elif id == "van" or id == "truck":
		# Heavy Chrome Bullbar + Roof Utility Rack
		_add_box(kit, Vector3(half_w * 1.38, 0.065, 0.07), Vector3(0.0, 0.44, -half_l - 0.05), mat_chrome)
		_add_box(kit, Vector3(half_w * 1.38, 0.065, 0.07), Vector3(0.0, 0.28, -half_l - 0.05), mat_chrome)
		for sx: float in [-1.0, 1.0]:
			_add_box(kit, Vector3(0.06, 0.28, 0.07), Vector3(sx * half_w * 0.56, 0.36, -half_l - 0.05), mat_chrome)
		if id == "van":
			for sx: float in [-1.0, 1.0]:
				_add_box(kit, Vector3(0.05, 0.06, half_l * 1.25), Vector3(sx * half_w * 0.72, top_y + 0.03, 0.08), mat_carbon)
			_add_box(kit, Vector3(half_w * 1.48, 0.04, 0.07), Vector3(0.0, top_y + 0.05, -0.35), mat_chrome)
			_add_box(kit, Vector3(half_w * 1.48, 0.04, 0.07), Vector3(0.0, top_y + 0.05,  0.48), mat_chrome)


static func _force_visible_materials(node: Node, apply_clearcoat: bool = false) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D:
					var opaque := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
					opaque.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					opaque.albedo_color.a = 1.0
					opaque.cull_mode = BaseMaterial3D.CULL_DISABLED
					opaque.no_depth_test = false
					opaque.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
					if apply_clearcoat and opaque.roughness < 0.82:
						opaque.clearcoat_enabled = true
						opaque.clearcoat = 0.42
						opaque.clearcoat_roughness = 0.20
						opaque.roughness = clampf(opaque.roughness * 0.82, 0.16, 0.72)
					mesh_instance.set_surface_override_material(surface, opaque)
	for child: Node in node.get_children():
		_force_visible_materials(child, apply_clearcoat)


static func _apply_custom_paint(root: Node, entry: Dictionary) -> void:
	## Applies custom glossy automotive paint to the PRO RACER body surface.
	if not bool(entry.get("custom_paint", false)) and not entry.has("paint_color"):
		return
	var paint_col: Color = Color("e63946")
	var raw_paint: Variant = entry.get("paint_color", null)
	if raw_paint is Color:
		paint_col = raw_paint as Color
	elif raw_paint is String and not (raw_paint as String).is_empty():
		paint_col = Color.from_string(str(raw_paint), paint_col)
	else:
		var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameSettings") if Engine.get_main_loop() is SceneTree else null
		if gs != null and gs.has_method("racer_color_value"):
			paint_col = gs.call("racer_color_value") as Color
		elif entry.get("base_paint", null) is Color:
			paint_col = entry["base_paint"] as Color

	var target_node: String = str(entry.get("paint_node", "body")).to_lower()
	var target_surf: int = int(entry.get("paint_surface", 1))
	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = paint_col
	paint_mat.roughness = 0.22
	paint_mat.metallic = 0.14
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.65
	paint_mat.clearcoat_roughness = 0.14
	paint_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and (target_node == "" or mi.name.to_lower().contains(target_node)):
				if target_surf >= 0 and target_surf < mi.mesh.get_surface_count():
					mi.set_surface_override_material(target_surf, paint_mat)
		for child: Node in n.get_children():
			queue.append(child)


static func _add_fallback_body(holder: Node3D, entry: Dictionary) -> void:
	## A missing/unreadable model must never become an invisible kart. The
	## collider still works, so this fallback gives the player something solid
	## to see and aim at.
	var body := MeshInstance3D.new()
	body.name = "FallbackBody"
	var box := BoxMesh.new()
	box.size = Vector3(float(entry.get("width", 1.5)), float(entry.get("height", 1.2)),
		float(entry.get("length", 2.4)))
	body.mesh = box
	var material := StandardMaterial3D.new()
	var stock_paint: Variant = entry.get("base_paint", null)
	material.albedo_color = stock_paint as Color if stock_paint is Color \
		else Color(0.82, 0.28, 0.22)
	material.roughness = 0.72
	body.material_override = material
	body.position.y = box.size.y * 0.5
	holder.add_child(body)


static func _add_outline(node: Node) -> void:
	## Inverted-hull ink line around the cart. This is the 3D version of the
	## thick navy outline the menus and AI art already use, and it is what
	## stops the photo-textured models from looking pasted onto the flat UI.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.get_active_material(surface)
				if material == null:
					continue
				var copy: Material = material.duplicate()
				var outline := ShaderMaterial.new()
				outline.shader = OUTLINE_SHADER
				outline.set_shader_parameter("thickness", 0.018)
				copy.next_pass = outline
				mesh_instance.set_surface_override_material(surface, copy)
	for child: Node in node.get_children():
		_add_outline(child)


static func _measure(node: Node, xform: Transform3D, acc: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var box: AABB = local * mesh_instance.mesh.get_aabb()
			if acc.is_empty():
				acc.append(box)
			else:
				acc[0] = (acc[0] as AABB).merge(box)
	for child in node.get_children():
		_measure(child, local, acc)


static func engine_audio_profile(entry: Dictionary) -> Dictionary:
	## Per-livery identity for the shared racing loop (no new assets). Pitch
	## and span come from the catalog; cutoff is the low-pass brightness that
	## keeps each kit distinct on the same sports_loop.wav: green rumbles low,
	## red sits in the middle, orange bites brighter, white screams on top.
	var cutoff: float = float(entry.get("loop_filter_cutoff", 0.0))
	if cutoff <= 0.0:
		match str(entry.get("id", "")):
			"race_car":
				cutoff = 5800.0
			"race_car_red":
				cutoff = 5200.0
			"race_car_green":
				cutoff = 3800.0
			"race_car_orange":
				cutoff = 6500.0
			"race_car_white":
				cutoff = 7800.0
			_:
				cutoff = 5200.0
	return {
		"pitch": float(entry.get("loop_pitch", 1.0)),
		"span": float(entry.get("loop_pitch_span", 0.9)),
		"cutoff": cutoff,
	}
