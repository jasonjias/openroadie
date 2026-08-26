#!/usr/bin/env python3
"""Kenney OBJ -> USDA for RealityKit.

ModelIO's usdc exporter drops materials and UVs, so this writes USD text
directly: one Mesh per material group, UsdPreviewSurface materials with
either the kit's colormap texture (referenced by bundle-root filename) or
the MTL's flat Kd color. Kenney kits are CC0 (kenney.nl).

Usage: convert-vehicle.py <input.obj> <output.usda> [texture-bundle-name]
"""
import os
import re
import sys


def parse_mtl(path):
    materials = {}
    current = None
    if not os.path.exists(path):
        return materials
    for line in open(path):
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "newmtl":
            current = parts[1]
            materials[current] = {"kd": (0.8, 0.8, 0.8), "map": None}
        elif parts[0] == "Kd" and current:
            # MTL colors are sRGB; USD color3f inputs are linear. Feeding
            # sRGB straight in gets gamma applied twice and washes the
            # color out (saturated orange renders as faint yellow).
            def srgb_to_linear(c):
                return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
            materials[current]["kd"] = tuple(srgb_to_linear(float(x)) for x in parts[1:4])
        elif parts[0] == "map_Kd" and current:
            materials[current]["map"] = parts[1]
    return materials


def main():
    obj_path, out_path = sys.argv[1], sys.argv[2]
    texture_name = sys.argv[3] if len(sys.argv) > 3 else None

    positions, uvs, normals = [], [], []
    groups = {}  # material name -> list of faces; face = [(vi, ti, ni), ...]
    current_material = "default"
    mtl = {}

    for line in open(obj_path):
        parts = line.split()
        if not parts:
            continue
        tag = parts[0]
        if tag == "mtllib":
            mtl = parse_mtl(os.path.join(os.path.dirname(obj_path), parts[1]))
        elif tag == "v":
            positions.append(tuple(float(x) for x in parts[1:4]))
        elif tag == "vt":
            uvs.append((float(parts[1]), float(parts[2])))
        elif tag == "vn":
            normals.append(tuple(float(x) for x in parts[1:4]))
        elif tag == "usemtl":
            current_material = parts[1]
        elif tag == "f":
            face = []
            for corner in parts[1:]:
                bits = (corner.split("/") + ["", ""])[:3]
                vi = int(bits[0]) - 1
                ti = int(bits[1]) - 1 if bits[1] else None
                ni = int(bits[2]) - 1 if bits[2] else None
                face.append((vi, ti, ni))
            groups.setdefault(current_material, []).append(face)

    def fmt3(t):
        return f"({t[0]:.6g}, {t[1]:.6g}, {t[2]:.6g})"

    def fmt2(t):
        return f"({t[0]:.6g}, {t[1]:.6g})"

    def safe(name):
        return re.sub(r"[^A-Za-z0-9_]", "_", name)

    lines = [
        "#usda 1.0",
        '(\n    defaultPrim = "Vehicle"\n    metersPerUnit = 1\n    upAxis = "Y"\n)',
        'def Xform "Vehicle" {',
    ]

    for material, faces in groups.items():
        m = safe(material)
        counts = [len(f) for f in faces]
        indices = [c[0] for f in faces for c in f]
        sts = [uvs[c[1]] if c[1] is not None and c[1] < len(uvs) else (0.0, 0.0)
               for f in faces for c in f]
        nrms = [normals[c[2]] if c[2] is not None and c[2] < len(normals) else (0.0, 1.0, 0.0)
                for f in faces for c in f]
        has_uv = any(c[1] is not None for f in faces for c in f)

        lines.append(f'    def Mesh "mesh_{m}" {{')
        lines.append(f"        int[] faceVertexCounts = [{', '.join(map(str, counts))}]")
        lines.append(f"        int[] faceVertexIndices = [{', '.join(map(str, indices))}]")
        lines.append(f"        point3f[] points = [{', '.join(fmt3(p) for p in positions)}]")
        lines.append(f'        normal3f[] normals = [{", ".join(fmt3(n) for n in nrms)}] (interpolation = "faceVarying")')
        if has_uv:
            lines.append(f'        texCoord2f[] primvars:st = [{", ".join(fmt2(s) for s in sts)}] (interpolation = "faceVarying")')
        lines.append('        uniform token subdivisionScheme = "none"')
        lines.append(f"        rel material:binding = </Vehicle/Materials/{m}>")
        lines.append("    }")

    lines.append('    def Scope "Materials" {')
    for material in groups:
        m = safe(material)
        info = mtl.get(material, {"kd": (0.8, 0.8, 0.8), "map": None})
        lines.append(f'        def Material "{m}" {{')
        lines.append(f'            token outputs:surface.connect = </Vehicle/Materials/{m}/surface.outputs:surface>')
        lines.append(f'            def Shader "surface" {{')
        lines.append('                uniform token info:id = "UsdPreviewSurface"')
        lines.append("                float inputs:roughness = 0.7")
        lines.append("                float inputs:metallic = 0")
        if info["map"] and texture_name:
            lines.append(f"                color3f inputs:diffuseColor.connect = </Vehicle/Materials/{m}/texture.outputs:rgb>")
        else:
            lines.append(f"                color3f inputs:diffuseColor = {fmt3(info['kd'])}")
        lines.append("                token outputs:surface")
        lines.append("            }")
        if info["map"] and texture_name:
            lines.append(f'            def Shader "stReader" {{')
            lines.append('                uniform token info:id = "UsdPrimvarReader_float2"')
            lines.append('                token inputs:varname = "st"')
            lines.append("                float2 outputs:result")
            lines.append("            }")
            lines.append(f'            def Shader "texture" {{')
            lines.append('                uniform token info:id = "UsdUVTexture"')
            lines.append(f'                asset inputs:file = @{texture_name}@')
            lines.append(f"                float2 inputs:st.connect = </Vehicle/Materials/{m}/stReader.outputs:result>")
            lines.append('                token inputs:wrapS = "repeat"')
            lines.append('                token inputs:wrapT = "repeat"')
            lines.append("                float3 outputs:rgb")
            lines.append("            }")
        lines.append("        }")
    lines.append("    }")
    lines.append("}")

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {out_path} ({len(positions)} verts, {sum(len(v) for v in groups.values())} faces, {len(groups)} materials)")


if __name__ == "__main__":
    main()
