"""Bake original, non-tiling single-board wood textures. NumPy + Pillow only.

No seams or lighting are painted into the source: the wall supplies actual grooves.
Each board is five by one feet. Four families use separate growth-ring structures.
The approved pilot is retained as layers 0-15. The current collection is 64 layers.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/scenery/textures/planks"
WIDTH, HEIGHT = 512, 128
FAMILIES = ["直纹", "山形纹", "结疤纹", "混合纹"]
REFERENCE = np.array([152, 96, 57], dtype=float)


def soft_noise(rng, cells_x, cells_y):
    values = rng.uniform(-1, 1, (cells_y, cells_x)).astype(np.float32)
    return np.asarray(Image.fromarray(values).resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC))


def board(index):
    family = index % 4
    seed = 24102400 + index * 7919
    rng = np.random.default_rng(seed)
    u, v = np.meshgrid((np.arange(WIDTH) + 0.5) / WIDTH * 5,
                       (np.arange(HEIGHT) + 0.5) / HEIGHT)
    slow = soft_noise(rng, 5, 4)
    fibers = soft_noise(rng, 8, 70)
    warp = soft_noise(rng, 4, 7) * rng.uniform(0.018, 0.045)
    drift = rng.uniform(0.025, 0.07) * np.sin(u * rng.uniform(0.45, 1.4) + rng.uniform(0, 6.28))
    coordinate = v + drift + warp
    knots = []
    if family == 1:
        # Long ellipses produce flat-sawn cathedral arcs, rather than parallel sine waves.
        cx, cy = rng.uniform(1.8, 3.2), rng.uniform(-0.30, -0.08)
        coordinate = np.sqrt(((u - cx) * rng.uniform(0.12, 0.22)) ** 2
                             + (v - cy + warp) ** 2)
    elif family in (2, 3):
        count = 1 if family == 2 else 2
        for _ in range(count):
            cx, cy = rng.uniform(0.7, 4.3), rng.uniform(0.2, 0.8)
            rx, ry = rng.uniform(0.23, 0.46), rng.uniform(0.065, 0.13)
            distance = ((u - cx) / (rx * 2.4)) ** 2 + ((v - cy) / (ry * 3.0)) ** 2
            # Fibres split and flow around knots; their shape is not just a dark oval.
            coordinate += ry * 0.9 * np.tanh((v - cy) / (ry * 0.8)) * np.exp(-distance)
            knots.append((cx, cy, rx, ry))
    density = rng.uniform(8, 14) if family != 3 else rng.uniform(12, 18)
    phase = coordinate * density
    phase += 0.31 * np.sin(phase * 1.23 + rng.uniform(0, 6.28)) + slow * 0.15
    ridge = np.exp(-(np.sin(np.pi * phase) / rng.uniform(0.20, 0.31)) ** 2)
    latewood = ridge * (0.7 + 0.3 * np.clip(fibers, -1, 1))
    relief = -latewood * 0.16 + slow * 0.035 + fibers * 0.014
    tone = 1.035 - latewood * 0.16 + slow * 0.035 + fibers * 0.014
    for cx, cy, rx, ry in knots:
        radius = np.sqrt(((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2)
        envelope = np.exp(-radius ** 2 * 0.32)
        rings = np.exp(-(np.sin(radius * rng.uniform(6, 9)) / 0.3) ** 2)
        heart = np.exp(-radius ** 2 * 10)
        tone -= envelope * rings * 0.10 + heart * 0.24
        relief -= envelope * rings * 0.07 + heart * 0.10
    if family == 3:
        center, extent = rng.uniform(1.1, 3.9), rng.uniform(0.45, 1.0)
        crack_y = rng.uniform(0.2, 0.8) + 0.018 * np.sin(u * rng.uniform(3, 6)) + warp * 0.3
        taper = np.clip(1 - ((u - center) / extent) ** 2, 0, 1)
        crack = np.exp(-((v - crack_y) / (0.004 * taper + 0.00001)) ** 2) * taper
        tone -= crack * 0.24
        relief -= crack * 0.22
    brightness = rng.uniform(0.96, 1.045)
    tint = np.array([rng.uniform(0.99, 1.015), rng.uniform(0.985, 1.015), rng.uniform(0.98, 1.02)])
    rgb = np.rint(np.clip(REFERENCE * tone[..., None] * brightness * tint, 0, 255)).astype(np.uint8)
    # Sub-millimetre fibre relief, expressed in the board's physical UV dimensions.
    dy, dx = np.gradient(relief, 0.2 / HEIGHT, 1.0 / WIDTH)
    nx, ny = -dx * 0.00028, -dy * 0.00028
    norm = np.sqrt(nx * nx + ny * ny + 1)
    roughness = np.clip(0.81 + latewood * 0.055 - slow * 0.025, 0.73, 0.92)
    detail = np.rint(np.clip(np.stack([nx / norm * 0.5 + 0.5,
                                      ny / norm * 0.5 + 0.5, roughness], -1), 0, 1) * 255).astype(np.uint8)
    return rgb, detail, {"index": index, "family": FAMILIES[family], "seed": seed,
                         "ring_density": float(density), "knots": len(knots)}


def import_array(path, columns, rows, data=False):
    config = path.with_suffix(path.suffix + ".import")
    # Preserve Godot-generated remap/UID data when regenerating existing assets.
    if config.exists():
        text = config.read_text(encoding="utf-8")
        import re
        for key, value in [("slices/horizontal", columns), ("slices/vertical", rows)]:
            text = re.sub(rf"^{key}=.*$", f"{key}={value}", text, flags=re.M)
        config.write_text(text, encoding="utf-8")
        return
    relative = "res://" + path.relative_to(ROOT).as_posix()
    config.write_text(f'''[remap]
importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]
source_file="{relative}"

[params]
compress/mode=2
compress/high_quality=true
compress/channel_pack={1 if data else 0}
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal={columns}
slices/vertical={rows}
''', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=64, choices=[16, 64, 128])
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    evidence = ROOT / "artifacts" / ("plank-texture-pilot-2026-10-24" if args.count == 16 else f"plank-textures-{args.count}-2026-10-24")
    evidence.mkdir(parents=True, exist_ok=True)
    columns = 4 if args.count == 16 else 8
    rows = args.count // columns
    color_atlas = Image.new("RGB", (WIDTH * columns, HEIGHT * rows))
    detail_atlas = Image.new("RGB", color_atlas.size)
    sheet_columns = 2 if args.count == 16 else 4
    sheet = Image.new("RGB", ((WIDTH + 24) * sheet_columns + 24, (HEIGHT + 42) * (args.count // sheet_columns) + 32), "#f3f1ec")
    pen = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(ROOT / "ui/theme/fonts/HarmonyOS_Sans_SC_Regular.ttf"), 20)
    records = []
    for index in range(args.count):
        rgb, detail, spec = board(index)
        color_atlas.paste(Image.fromarray(rgb), (index % columns * WIDTH, index // columns * HEIGHT))
        detail_atlas.paste(Image.fromarray(detail), (index % columns * WIDTH, index // columns * HEIGHT))
        spec["color_sha256"] = hashlib.sha256(rgb.tobytes()).hexdigest()
        spec["detail_sha256"] = hashlib.sha256(detail.tobytes()).hexdigest()
        records.append(spec)
        x, y = 24 + index % sheet_columns * (WIDTH + 24), 16 + index // sheet_columns * (HEIGHT + 42)
        pen.text((x, y), f'{index + 1:02}  {spec["family"]}', fill="#30271e", font=font)
        sheet.paste(Image.fromarray(rgb), (x, y + 30))
    color_path, detail_path = OUTPUT / "board_colors.png", OUTPUT / "board_detail.png"
    color_atlas.save(color_path, optimize=True)
    detail_atlas.save(detail_path, optimize=True)
    import_array(color_path, columns, rows)
    import_array(detail_path, columns, rows, data=True)
    sheet.save(evidence / "texture_samples.png", optimize=True)
    # Full-resolution family sheets remain readable without shrinking 64 boards into one view.
    for family, title in enumerate(FAMILIES):
        family_count = args.count // 4
        family_rows = (family_count + 1) // 2
        family_sheet = Image.new("RGB", (WIDTH * 2 + 72, (HEIGHT + 42) * family_rows + 32), "#f3f1ec")
        family_pen = ImageDraw.Draw(family_sheet)
        for order, index in enumerate(range(family, args.count, 4)):
            x, y = 24 + order % 2 * (WIDTH + 24), 16 + order // 2 * (HEIGHT + 42)
            family_pen.text((x, y), f"{index + 1:02}  {title}", fill="#30271e", font=font)
            family_sheet.paste(color_atlas.crop((index % columns * WIDTH, index // columns * HEIGHT,
                                                (index % columns + 1) * WIDTH, (index // columns + 1) * HEIGHT)), (x, y + 30))
        family_sheet.save(evidence / f"family_{family}.png", optimize=True)
    manifest = {"version": 1, "generator": "dev/generate_plank_textures.py", "count": args.count,
                "size": [WIDTH, HEIGHT], "board_feet": [5, 1], "atlas_grid": [columns, rows],
                "color_space": "color=sRGB; detail=linear RG tangent normal XY, B roughness",
                "reference_color": "986039", "mipmaps": True, "boards": records}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    assert len({r["color_sha256"] for r in records}) == args.count
    assert len({r["detail_sha256"] for r in records}) == args.count
    for index in [0, 5, args.count - 1]:
        repeated = board(index)
        assert hashlib.sha256(repeated[0].tobytes()).hexdigest() == records[index]["color_sha256"]
    print(f"PLANK_TEXTURE_BAKE_COMPLETE layers={args.count} unique_colors=true unique_details=true deterministic=true size={WIDTH}x{HEIGHT}")


if __name__ == "__main__":
    main()
