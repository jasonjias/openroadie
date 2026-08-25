#!/usr/bin/env python3
"""Builds the bundled hazard dataset from NHTSA FARS (Fatality Analysis
Reporting System) — the U.S. DOT's public registry of every fatal crash,
with coordinates. https://www.nhtsa.gov/research-data/fatality-analysis-reporting-system-fars

Downloads the national CSVs for the given years, clusters fatal-crash
coordinates onto a ~150 m grid, keeps cells with >= MIN_CRASHES distinct
crashes, and writes a compact JSON the app bundles. No runtime service,
no API, works offline.

Usage: build-hazards.py [year ...]   (default: 2022 2023)
Output: OpenRoadie/Hazards/hazards.json
"""
import csv
import io
import json
import os
import ssl
import sys
import urllib.request
import zipfile

YEARS = [int(a) for a in sys.argv[1:]] or [2022, 2023]
CELL = 0.0015          # degrees, ~150 m of latitude
MIN_CRASHES = 2        # distinct fatal crashes in one cell to call it a hazard
OUT = os.path.join(os.path.dirname(__file__), "..", "OpenRoadie", "Hazards", "hazards.json")

cells = {}
for year in YEARS:
    url = f"https://static.nhtsa.gov/nhtsa/downloads/FARS/{year}/National/FARS{year}NationalCSV.zip"
    print(f"downloading {url} …")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # static.nhtsa.gov chain is incomplete for openssl
    data = urllib.request.urlopen(url, context=ctx, timeout=300).read()
    print(f"  {len(data)//1_000_000} MB")
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        name = next(n for n in zf.namelist() if n.lower().endswith("accident.csv"))
        with zf.open(name) as f:
            reader = csv.DictReader(io.TextIOWrapper(f, encoding="latin-1"))
            count = 0
            for row in reader:
                try:
                    lat = float(row.get("LATITUDE") or row.get("latitude"))
                    lon = float(row.get("LONGITUD") or row.get("longitud"))
                except (TypeError, ValueError):
                    continue
                # FARS uses 77.7777/88.8888/99.9999 as not-reported markers.
                if not (17 <= lat <= 72 and -180 <= lon <= -60):
                    continue
                key = (round(lat / CELL), round(lon / CELL))
                entry = cells.setdefault(key, [0.0, 0.0, 0])
                entry[0] += lat
                entry[1] += lon
                entry[2] += 1
                count += 1
            print(f"  {count} located fatal crashes in {year}")

hazards = sorted(
    [
        [round(lat_sum / n, 4), round(lon_sum / n, 4), n]
        for (lat_sum, lon_sum, n) in cells.values()
        if n >= MIN_CRASHES
    ],
    key=lambda h: -h[2],
)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump({"source": f"NHTSA FARS {'+'.join(map(str, YEARS))}", "cell_deg": CELL, "hazards": hazards}, f, separators=(",", ":"))
print(f"wrote {len(hazards)} hazard cells → {OUT} ({os.path.getsize(OUT)//1000} KB)")
