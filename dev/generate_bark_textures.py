"""Bake 64 original bark surfaces, four structures with 16 specimens each.

Open longitudinal fissures, forks and rough fibres are authored
procedurally. No photography, third-party textures or pre-existing wood images.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from generate_plank_textures import import_array, soft_noise

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/scenery/textures/bark"
EVIDENCE = ROOT / "artifacts/bark-log-wall-2026-10-24"
WIDTH, HEIGHT, COUNT = 512, 128, 64
FAMILIES = ["疏纵裂", "细密裂", "断续裂", "分叉裂"]
REFERENCE = np.array([109, 101, 87], dtype=float)


def bark(index):
    family = index % 4
    seed = 24102471 + index * 104729
    rng = np.random.default_rng(seed)
    u, v = np.meshgrid((np.arange(WIDTH) + 0.5) / WIDTH * 10.0,
                       (np.arange(HEIGHT) + 0.5) / HEIGHT * 1.5)
    slow = soft_noise(rng, 7, 5)
    fibers = soft_noise(rng, 14, 75)
    grit = soft_noise(rng, 65, 48)
    wander = soft_noise(rng, 5, 9)
    fissures = np.zeros_like(u)
    shoulders = np.zeros_like(u)
    count = [9, 15, 11, 13][family] + int(rng.integers(-1, 2))
    # Open, mostly longitudinal cracks. No cellular/Voronoi outlines or closed scales.
    positions = np.cumsum(rng.uniform(0.7, 1.4, count + 1))
    positions = (positions / positions[-1] * 1.7) - 0.1
    for j, centre in enumerate(positions[:-1]):
        line = centre + np.sin(u * rng.uniform(0.45, 1.25) + rng.uniform(0, 6.28)) * rng.uniform(0.018, 0.05)
        line += wander * rng.uniform(0.012, 0.03)
        if family == 3:
            line += 0.035 * np.sin(u * 0.3 + j * 0.8)
        width = rng.uniform(0.006, 0.014) * (0.7 if family == 1 else 1.0)
        broken = 0.72 + 0.28 * np.sin(u * rng.uniform(1.0, 2.2) + rng.uniform(0, 6.28)) ** 2
        if family in (2, 3):
            start = rng.uniform(-1.0, 3.5)
            finish = start + rng.uniform(3.0, 7.0)
            broken *= np.clip((u - start) * 2.0, 0, 1) * np.clip((finish - u) * 2.0, 0, 1)
        distance = (v - line) / width
        fissures = np.maximum(fissures, np.exp(-distance ** 2) * broken)
        shoulders = np.maximum(shoulders, np.exp(-(distance / 3.5) ** 2) * broken)
        # Occasional short forks remain open; never connect into a plate grid.
        if family in (0, 3) and j % 3 == 0:
            cx = rng.uniform(1.0, 8.5)
            spread = np.clip((u - cx) / 1.5, 0, 1) * rng.uniform(0.035, 0.07)
            envelope = np.clip((u - cx) * 3.0, 0, 1) * np.clip((cx + 1.5 - u) * 3.0, 0, 1)
            fork = np.exp(-((v - line - spread) / (width * 0.55)) ** 2) * envelope * 0.65
            fissures = np.maximum(fissures, fork)
    # Fibrous, uneven strips give roughness between fissures without painting wood rings.
    relief = -fissures * 0.55 - shoulders * 0.10 + fibers * 0.07 + grit * 0.025 + slow * 0.08
    shade = 1.025 - fissures * 0.34 - shoulders * 0.045 + fibers * 0.075 + grit * 0.025 + slow * 0.055
    tint = np.array([rng.uniform(0.98, 1.025), rng.uniform(0.985, 1.02), rng.uniform(0.975, 1.035)])
    rgb = np.rint(np.clip(REFERENCE * shade[..., None] * tint * rng.uniform(0.975, 1.025), 0, 255)).astype(np.uint8)
    dy, dx = np.gradient(relief, 0.30 / HEIGHT, 2.0 / WIDTH)
    nx, ny = -dx * 0.0013, -dy * 0.0013
    norm = np.sqrt(nx * nx + ny * ny + 1.0)
    roughness = np.clip(0.90 + fissures * 0.065 + grit * 0.025 - fibers * 0.025, 0.85, 0.99)
    detail = np.rint(np.clip(np.stack([nx / norm * 0.5 + 0.5, ny / norm * 0.5 + 0.5, roughness], -1), 0, 1) * 255).astype(np.uint8)
    return rgb, detail, {"index": index, "family": FAMILIES[family], "seed": seed,
                         "main_fissures": count, "open_cracks_only": True}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    color_atlas = Image.new("RGB", (WIDTH * 8, HEIGHT * 8))
    detail_atlas = Image.new("RGB", color_atlas.size)
    font = ImageFont.truetype(str(ROOT / "ui/theme/fonts/HarmonyOS_Sans_SC_Regular.ttf"), 20)
    samples = []
    records = []
    for index in range(COUNT):
        rgb, detail, spec = bark(index)
        samples.append(Image.fromarray(rgb))
        color_atlas.paste(samples[-1], (index % 8 * WIDTH, index // 8 * HEIGHT))
        detail_atlas.paste(Image.fromarray(detail), (index % 8 * WIDTH, index // 8 * HEIGHT))
        spec["color_sha256"] = hashlib.sha256(rgb.tobytes()).hexdigest()
        spec["detail_sha256"] = hashlib.sha256(detail.tobytes()).hexdigest()
        records.append(spec)
    for family in range(4):
        sheet = Image.new("RGB", (WIDTH * 2 + 72, (HEIGHT + 42) * 8 + 32), "#f3f1ec")
        pen = ImageDraw.Draw(sheet)
        for order, index in enumerate(range(family, COUNT, 4)):
            x, y = 24 + order % 2 * (WIDTH + 24), 16 + order // 2 * (HEIGHT + 42)
            pen.text((x, y), f"{index + 1:02}  {FAMILIES[family]}", fill="#30271e", font=font)
            sheet.paste(samples[index], (x, y + 30))
        sheet.save(EVIDENCE / f"family_{family}.png", optimize=True)
    sheet = Image.new("RGB", ((WIDTH + 24) * 4 + 24, (HEIGHT + 42) * 16 + 32), "#f3f1ec")
    pen = ImageDraw.Draw(sheet)
    for index, sample in enumerate(samples):
        x, y = 24 + index % 4 * (WIDTH + 24), 16 + index // 4 * (HEIGHT + 42)
        pen.text((x, y), f"{index + 1:02}  {FAMILIES[index % 4]}", fill="#30271e", font=font)
        sheet.paste(sample, (x, y + 30))
    sheet.save(EVIDENCE / "texture_samples.png", optimize=True)
    for name, atlas, data in [("bark_colors.png", color_atlas, False), ("bark_detail.png", detail_atlas, True)]:
        path = OUTPUT / name
        atlas.save(path, optimize=True)
        import_array(path, 8, 8, data=data)
    manifest = {"version": 2, "generator": "dev/generate_bark_textures.py", "count": COUNT,
                "size": [WIDTH, HEIGHT], "atlas_grid": [8, 8], "reference_color": "6d6557",
                "surface_feet": [10, 1.5], "mipmaps": True,
                "color_space": "color=sRGB; detail=linear RG tangent normal XY, B roughness", "surfaces": records}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    assert len({r["color_sha256"] for r in records}) == COUNT
    assert len({r["detail_sha256"] for r in records}) == COUNT
    for index in [0, 7, 63]:
        rgb, detail, _ = bark(index)
        assert hashlib.sha256(rgb.tobytes()).hexdigest() == records[index]["color_sha256"]
        assert hashlib.sha256(detail.tobytes()).hexdigest() == records[index]["detail_sha256"]
    print("BARK_TEXTURE_BAKE_COMPLETE layers=64 families=4 each=16 unique_colors=true unique_details=true deterministic=true size=512x128")


if __name__ == "__main__":
    main()
