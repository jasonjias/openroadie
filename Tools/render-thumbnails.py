#!/usr/bin/env python3
"""Pre-render picker thumbnails for every bundled vehicle model.

Wraps each vehicle .usda in a stage that yaws it to a front-three-quarter
hero angle, then renders with `xcrun usdrecord` (transparent background,
textures resolved relative to the source file). Output: thumb-<model>.png
next to the models. The procedural classic car has no .usda — its
thumbnail is captured from the app itself (see repo history).

Usage: python3 Tools/render-thumbnails.py
"""

import glob
import os
import subprocess
import tempfile

VEHICLES = "OpenRoadie/Vehicles"
SIZE = "512"

def main():
    models = sorted(glob.glob(os.path.join(VEHICLES, "vehicle-*.usda")))
    for path in models:
        name = os.path.splitext(os.path.basename(path))[0]
        out = os.path.join(VEHICLES, f"thumb-{name}.png")
        wrapper = f"""#usda 1.0
(
    defaultPrim = "Thumb"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "Thumb" (
    references = @{os.path.abspath(path)}@
)
{{
    float3 xformOp:rotateXYZ = (8, -35, 0)
    uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
}}
"""
        with tempfile.NamedTemporaryFile("w", suffix=".usda", delete=False) as f:
            f.write(wrapper)
            stage = f.name
        try:
            subprocess.run(
                ["xcrun", "usdrecord", "--imageWidth", SIZE, stage, out],
                check=True, capture_output=True,
            )
            print(f"wrote {out}")
        finally:
            os.unlink(stage)

if __name__ == "__main__":
    main()
