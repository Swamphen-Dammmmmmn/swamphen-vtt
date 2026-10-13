"""Generate project-owned periodic RGB masks; requires NumPy and Pillow.

R: light flecks, G: soft mottling, B: darker grains. No baked lighting.
Pixels represent a periodic signal, not duplicated edge rows.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

SIZE = 512
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "ground"


def smooth_noise(rng, radius):
    noise = rng.standard_normal((SIZE, SIZE))
    f = np.fft.fftfreq(SIZE)
    weights = np.exp(-2 * np.pi**2 * radius**2 * (f[:, None]**2 + f[None, :]**2))
    field = np.fft.ifft2(np.fft.fft2(noise) * weights).real
    return np.clip(0.5 + field / max(field.std(), 1e-9) * 0.17, 0, 1)


def flecks(rng, count, radius, elongation, density):
    result = np.zeros((SIZE, SIZE), dtype=np.float64)
    for _ in range(count):
        cx, cy = rng.uniform(0, SIZE, 2)
        if rng.random() > 0.25 + 0.75 * density[int(cy), int(cx)]:
            continue
        rx = rng.uniform(*radius)
        ry = rx * rng.uniform(*elongation)
        angle = rng.uniform(0, np.pi)
        reach = int(np.ceil(max(rx, ry))) + 2
        xs = np.arange(int(cx) - reach, int(cx) + reach + 1)
        ys = np.arange(int(cy) - reach, int(cy) + reach + 1)
        dx, dy = np.meshgrid(xs - cx, ys - cy)
        x = dx * np.cos(angle) + dy * np.sin(angle)
        y = -dx * np.sin(angle) + dy * np.cos(angle)
        distance = np.sqrt((x / rx)**2 + (y / ry)**2)
        # Feather only the edge; retains small readable flecks rather than white noise.
        shape = np.clip((1 - distance) * 3.0, 0, 1) * rng.uniform(0.45, 1)
        indices = np.ix_(ys % SIZE, xs % SIZE)
        result[indices] = np.maximum(result[indices], shape)
    return result


def write(name, channels):
    data = np.round(np.clip(np.stack(channels, axis=-1), 0, 1) * 255).astype(np.uint8)
    Image.fromarray(data).save(OUTPUT / name, optimize=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    specs = {
        "grass": [(1500, (2, 5), (0.5, 1.2), 22), (2200, (1.5, 3.5), (0.4, 0.8), 32),
                  (1000, (3, 6), (0.7, 1.5), 16), (1900, (2, 4), (0.5, 1), 42)],
        "sand": [(6500, (0.7, 1.5), (0.8, 1.2), 30), (4400, (1, 2), (0.7, 1.3), 42),
                 (8000, (0.6, 1.2), (0.8, 1.2), 20), (5200, (0.8, 1.8), (0.6, 1.4), 55)],
    }
    for kind, variants in specs.items():
        for index, (count, radius, stretch, blotch_radius) in enumerate(variants):
            rng = np.random.default_rng(470210 + (0 if kind == "grass" else 100) + index)
            density = smooth_noise(rng, 45)
            light = flecks(rng, count, radius, stretch, density)
            dark = flecks(rng, count // 3, radius, (0.8, 1.2), 1 - density)
            write(f"{kind}_{index}.png", [light, smooth_noise(rng, blotch_radius), dark])
    rng = np.random.default_rng(90210)
    write("macro.png", [smooth_noise(rng, 18), smooth_noise(rng, 32), smooth_noise(rng, 55)])
    manifest = {"version": 1, "size": SIZE, "variants_per_type": 4,
                "generator": "dev/generate_ground_textures.py", "units": "RGB masks; not color artwork",
                "channels": {"R": "light flecks", "G": "soft mottling", "B": "dark grains"}}
    manifest_path = OUTPUT / "manifest.json"
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
        for key in ("microstructure", "grain_color"):
            if key in previous:
                manifest[key] = previous[key]
        manifest["version"] = max(manifest["version"], previous.get("version", 1))
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Generated 8 detail masks and 1 macro mask in {OUTPUT}")


if __name__ == "__main__":
    main()
