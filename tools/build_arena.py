"""Generates scenes/dev/driving_test.tscn - the sandbox arena.

Layout is on a 140 x 140 m pad, walls at +/-70, driving direction -Z.

  z = +66   spawn / start line at +60, 10 m wide lane
  z = +50   speed bump A          z = +38  speed bump B
  z = +56   boost pad             z = +24  boost pad (before the jump)
  z = +18   jump ramp (8 x 9)     z =  +2  landing pad (12 x 14)
  x = +32   slalom cones          x = +34  cone field (4 x 4)
  x = -36   drift pad r=9         x = -36  bowl pad
  z = -24   crate pyramid         x = +48  cliff ramp + platform

Run:  python tools/build_arena.py
"""

from __future__ import annotations

import math
import os

OUT = os.path.join("scenes", "dev", "driving_test.tscn")
TAU = math.tau

# --------------------------------------------------------------------------
# helpers


def transform(pos=(0, 0, 0), yaw=0.0, pitch=0.0) -> str:
    """Row-major Transform3D with optional X pitch then Y yaw."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    # R = Ry * Rx
    m = [
        [cy, sy * sp, sy * cp],
        [0.0, cp, -sp],
        [-sy, cy * sp, cy * cp],
    ]
    vals = [f"{v:.6f}" for row in m for v in row]
    vals += [f"{v:.6f}" for v in pos]
    return "Transform3D(" + ", ".join(vals) + ")"


def node(name: str, type_: str, parent: str = ".", **props) -> str:
    groups = props.pop("groups", None)
    head = f'[node name="{name}" type="{type_}" parent="{parent}"'
    if groups is not None:
        head += f" groups={groups}"
    head += "]"
    lines = [head]
    for key, value in props.items():
        lines.append(f"{key} = {value}")
    return "\n".join(lines)


def static_body(name: str, pos, shape: str, mesh: str, pitch: float = 0.0) -> list[str]:
    return [
        node(name, "StaticBody3D", transform=transform(pos, pitch=pitch)),
        node("CollisionShape3D", "CollisionShape3D", parent=name, shape=f'SubResource("{shape}")'),
        node("MeshInstance3D", "MeshInstance3D", parent=name, mesh=f'SubResource("{mesh}")'),
    ]


def prop(name: str, model_id: str, shape: str, pos, mass: float, shape_y: float) -> list[str]:
    return [
        node(name, "RigidBody3D", parent=".", groups='["pushable"]', transform=transform(pos),
             collision_layer=4, collision_mask=5,
             mass=mass, continuous_cd="true", can_sleep="true",
             physics_material_override='SubResource("prop_phys")'),
        f'[node name="Model" parent="{name}" instance=ExtResource("{model_id}")]',
        node("CollisionShape3D", "CollisionShape3D", parent=name,
             transform=transform((0, shape_y, 0)), shape=f'SubResource("{shape}")'),
    ]


# --------------------------------------------------------------------------
# header

header = """[gd_scene load_steps=36 format=3]

[ext_resource type="Script" path="res://scripts/driving_test.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/player/cart_player.tscn" id="2"]
[ext_resource type="PackedScene" path="res://assets/models/kenney_car-kit/Models/GLB format/cone.glb" id="3"]
[ext_resource type="PackedScene" path="res://assets/models/kenney_car-kit/Models/GLB format/box.glb" id="4"]
[ext_resource type="PackedScene" path="res://scenes/track/boost_pad.tscn" id="5"]
[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="6"]
[ext_resource type="PackedScene" path="res://scenes/ui/pause_menu.tscn" id="7"]
[ext_resource type="Shader" path="res://assets/materials/checker.gdshader" id="8_checker"]

[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]
sky_top_color = Color(0.38, 0.55, 0.85, 1)
sky_horizon_color = Color(0.68, 0.72, 0.78, 1)
ground_bottom_color = Color(0.2, 0.2, 0.22, 1)
ground_horizon_color = Color(0.68, 0.72, 0.78, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")

[sub_resource type="StandardMaterial3D" id="ground_mat"]
albedo_color = Color(0.63, 0.67, 0.74, 1)

[sub_resource type="StandardMaterial3D" id="wall_mat"]
albedo_color = Color(0.16, 0.2, 0.32, 1)

[sub_resource type="StandardMaterial3D" id="ramp_mat"]
albedo_color = Color(0.95, 0.66, 0.24, 1)

[sub_resource type="StandardMaterial3D" id="bump_mat"]
albedo_color = Color(1, 0.82, 0.18, 1)

[sub_resource type="StandardMaterial3D" id="lane_mat"]
albedo_color = Color(0.56, 0.85, 0.96, 1)

[sub_resource type="StandardMaterial3D" id="edge_mat"]
albedo_color = Color(0.96, 0.97, 1, 1)

[sub_resource type="StandardMaterial3D" id="pad_mat"]
albedo_color = Color(1, 0.91, 0.66, 1)

[sub_resource type="StandardMaterial3D" id="ring_mat"]
albedo_color = Color(0.95, 0.42, 0.65, 1)

[sub_resource type="StandardMaterial3D" id="bowl_mat"]
albedo_color = Color(1, 0.94, 0.78, 1)

[sub_resource type="StandardMaterial3D" id="brake_mat"]
albedo_color = Color(0.95, 0.33, 0.36, 1)

[sub_resource type="PhysicsMaterial" id="prop_phys"]
friction = 0.9
bounce = 0.15

[sub_resource type="BoxShape3D" id="ground_shape"]
size = Vector3(140, 1, 140)

[sub_resource type="BoxMesh" id="ground_mesh"]
material = SubResource("ground_mat")
size = Vector3(140, 1, 140)

[sub_resource type="BoxShape3D" id="wall_shape"]
size = Vector3(142, 2.4, 1)

[sub_resource type="BoxMesh" id="wall_mesh"]
material = SubResource("wall_mat")
size = Vector3(142, 2.4, 1)

[sub_resource type="ShaderMaterial" id="trim_mat"]
shader = ExtResource("8_checker")
shader_parameter/cells = Vector2(32, 1)

[sub_resource type="BoxMesh" id="trim_mesh"]
material = SubResource("trim_mat")
size = Vector3(142, 0.02, 0.9)

[sub_resource type="BoxMesh" id="lane_mesh"]
material = SubResource("lane_mat")
size = Vector3(10, 0.02, 64)

[sub_resource type="BoxMesh" id="edge_mesh"]
material = SubResource("edge_mat")
size = Vector3(0.2, 0.02, 64)

[sub_resource type="ShaderMaterial" id="start_mat"]
shader = ExtResource("8_checker")
shader_parameter/cells = Vector2(18, 2)

[sub_resource type="BoxMesh" id="start_mesh"]
material = SubResource("start_mat")
size = Vector3(16, 0.02, 1.2)

[sub_resource type="BoxShape3D" id="ramp_shape"]
size = Vector3(8, 0.4, 9)

[sub_resource type="BoxMesh" id="ramp_mesh"]
material = SubResource("ramp_mat")
size = Vector3(8, 0.4, 9)

[sub_resource type="BoxShape3D" id="roller_shape"]
size = Vector3(10, 0.12, 2.3)

[sub_resource type="BoxMesh" id="roller_mesh"]
material = SubResource("bump_mat")
size = Vector3(10, 0.12, 2.3)

[sub_resource type="BoxMesh" id="pad_mesh"]
material = SubResource("pad_mat")
size = Vector3(12, 0.02, 14)

[sub_resource type="CylinderMesh" id="ring_mesh"]
material = SubResource("ring_mat")
top_radius = 9.0
bottom_radius = 9.0
height = 0.02
radial_segments = 48

[sub_resource type="BoxMesh" id="bowl_mesh"]
material = SubResource("bowl_mat")
size = Vector3(16, 0.02, 18)

[sub_resource type="BoxMesh" id="brake_mesh"]
material = SubResource("brake_mat")
size = Vector3(8, 0.02, 0.5)

[sub_resource type="BoxShape3D" id="cliff_shape"]
size = Vector3(6, 0.4, 10)

[sub_resource type="BoxMesh" id="cliff_mesh"]
material = SubResource("ramp_mat")
size = Vector3(6, 0.4, 10)

[sub_resource type="BoxShape3D" id="platform_shape"]
size = Vector3(10, 0.4, 8)

[sub_resource type="BoxMesh" id="platform_mesh"]
material = SubResource("ramp_mat")
size = Vector3(10, 0.4, 8)

[sub_resource type="CylinderShape3D" id="cone_shape"]
radius = 0.2
height = 0.54

[sub_resource type="BoxShape3D" id="crate_shape"]
size = Vector3(0.67, 0.71, 0.67)

[node name="DrivingTest" type="Node3D"]
script = ExtResource("1")
"""

blocks: list[str] = [header]

blocks.append("""[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.921061, -0.279352, 0.271310, 0.000000, 0.696707, 0.717356, -0.389418, -0.660729, 0.641709, 0.000000, 0.000000, 0.000000)
shadow_enabled = true""")

# ground
blocks.append("\n\n".join([
    node("Ground", "StaticBody3D"),
    node("CollisionShape3D", "CollisionShape3D", parent="Ground",
         transform=transform((0, -0.5, 0)), shape='SubResource("ground_shape")'),
    node("MeshInstance3D", "MeshInstance3D", parent="Ground",
         transform=transform((0, -0.5, 0)), mesh='SubResource("ground_mesh")'),
]))

# walls + checkered trim
walls = [
    ("WallNorth", (0, 1.2, -70.5), 0.0),
    ("WallSouth", (0, 1.2, 70.5), 0.0),
    ("WallWest", (-70.5, 1.2, 0), math.pi / 2),
    ("WallEast", (70.5, 1.2, 0), math.pi / 2),
]
for name, pos, yaw in walls:
    blocks.append("\n\n".join([
        node(name, "StaticBody3D", transform=transform(pos, yaw=yaw)),
        node("CollisionShape3D", "CollisionShape3D", parent=name, shape='SubResource("wall_shape")'),
        node("MeshInstance3D", "MeshInstance3D", parent=name, mesh='SubResource("wall_mesh")'),
        node("Trim", "MeshInstance3D", parent=name,
             transform=transform((0, 1.21, 0)), mesh='SubResource("trim_mesh")'),
    ]))

# main straight
blocks.append("\n\n".join([
    node("LanePad", "MeshInstance3D", transform=transform((0, 0.011, 36)), mesh='SubResource("lane_mesh")'),
    node("LaneEdgeL", "MeshInstance3D", transform=transform((-5.1, 0.020, 36)), mesh='SubResource("edge_mesh")'),
    node("LaneEdgeR", "MeshInstance3D", transform=transform((5.1, 0.020, 36)), mesh='SubResource("edge_mesh")'),
    node("StartLine", "MeshInstance3D", transform=transform((0, 0.030, 60)), mesh='SubResource("start_mesh")'),
]))

# speed bumps (rotation +0.22 = low edge toward +Z)
for name, z in (("RollerA", 50.0), ("RollerB", 38.0)):
    blocks.append("\n\n".join(static_body(name, (0, 0.19, z), "roller_shape", "roller_mesh", pitch=0.22)))

# jump ramp + landing
blocks.append("\n\n".join(static_body("JumpRamp", (0, 0.55, 18), "ramp_shape", "ramp_mesh", pitch=0.19)))
blocks.append(node("LandingPad", "MeshInstance3D", transform=transform((0, 0.025, 2)),
                   mesh='SubResource("pad_mesh")'))

# brake warning strips before the jump
for index, z in enumerate((34.0, 32.4, 30.8), start=1):
    blocks.append(node(f"BrakeStrip{index}", "MeshInstance3D", transform=transform((0, 0.022, z)),
                       mesh='SubResource("brake_mesh")'))

# drift pad + bowl
blocks.append(node("DriftPad", "MeshInstance3D", transform=transform((-36, 0.011, 24)),
                   mesh='SubResource("ring_mesh")'))
blocks.append(node("BowlPad", "MeshInstance3D", transform=transform((-36, 0.011, -16)),
                   mesh='SubResource("bowl_mesh")'))

# cliff jump on the right
blocks.append("\n\n".join(static_body("CliffRamp", (48, 0.75, -26), "cliff_shape", "cliff_mesh", pitch=0.19)))
blocks.append("\n\n".join(static_body("CliffPlatform", (48, 1.7, -35), "platform_shape", "platform_mesh")))

# boost pads
for name, pos in (("BoostPadA", (0, 0.021, 56)), ("BoostPadB", (0, 0.021, 24)), ("BoostPadC", (-36, 0.021, 34))):
    blocks.append(
        f'[node name="{name}" parent="." instance=ExtResource("5")]\n'
        f'transform = {transform(pos)}'
    )

# spawn + player + UI
blocks.append("""[node name="SpawnPoint" type="Marker3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.2, 66)

[node name="CartPlayer" parent="." instance=ExtResource("2")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.2, 66)

[node name="HUD" parent="." instance=ExtResource("6")]

[node name="PauseMenu" parent="." instance=ExtResource("7")]""")

# props
cone_index = 0
crate_index = 0
props: list[str] = []

# drift ring cones
for i in range(10):
    angle = TAU * i / 10.0
    x = -36 + 10.0 * math.cos(angle)
    z = 24 + 10.0 * math.sin(angle)
    cone_index += 1
    props.append("\n\n".join(prop(f"DriftCone{cone_index}", "3", "cone_shape", (x, 0.0, z), 0.35, 0.27)))

# slalom
for i in range(8):
    z = 48.0 - i * 4.0
    x = 29.5 if i % 2 == 0 else 34.5
    cone_index += 1
    props.append("\n\n".join(prop(f"SlalomCone{i + 1}", "3", "cone_shape", (x, 0.0, z), 0.35, 0.27)))

# cone field
for zi, z in enumerate((-14.5, -11.0, -7.5, -4.0)):
    for xi, x in enumerate((28.5, 32.0, 35.5, 39.0)):
        cone_index += 1
        props.append("\n\n".join(prop(f"FieldCone{zi * 4 + xi + 1}", "3", "cone_shape", (x, 0.0, z), 0.35, 0.27)))

# bowl corners
for i, (x, z) in enumerate(((-43, -24), (-29, -24), (-43, -8), (-29, -8)), start=1):
    cone_index += 1
    props.append("\n\n".join(prop(f"BowlCone{i}", "3", "cone_shape", (x, 0.0, z), 0.35, 0.27)))

# crate pyramid
crate_row = (-6.0, -3.0, 0.0, 3.0, 6.0)
crate_slots = [(x, 0.355) for x in crate_row] + [(x, 1.065) for x in crate_row]
for index, (x, y) in enumerate(crate_slots, start=1):
    props.append("\n\n".join(prop(f"Crate{index}", "4", "crate_shape", (x, y - 0.355, -24.0), 0.8, 0.355)))

blocks.extend(props)
blocks.append("")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as handle:
    handle.write("\n".join(blocks))
print(f"wrote {OUT} ({len(blocks)} blocks, {cone_index} cones, {crate_index} crates)")
