"""Fixed-seed seamless data texture: facet slopes, roughness, crystal rank."""
from pathlib import Path
import numpy as np
from PIL import Image

SIZE = 1024
CELL = 8
rng = np.random.default_rng(470241)
data = np.empty((SIZE, SIZE, 4), dtype=np.float32)
data[:] = [0.5, 0.5, 0.92, 0.0]
color_rng = np.random.default_rng(470242)
color_data = np.empty((SIZE, SIZE, 3), dtype=np.float32)
color_data[:] = [0.5, 0.5, 0.0]
for y in range(0, SIZE, CELL):
    for x in range(0, SIZE, CELL):
        cx, cy = np.array([x, y]) + rng.uniform(1.5, 6.5, 2)
        radius = rng.uniform(1.8, 3.3)
        tilt = rng.uniform(-0.65, 0.65, 2)
        roughness = rng.uniform(0.72, 0.94)
        rank = rng.random()
        xs = np.arange(x - 3, x + CELL + 3)
        ys = np.arange(y - 3, y + CELL + 3)
        dx, dy = np.meshgrid(xs - cx, ys - cy)
        d = np.sqrt(dx * dx + dy * dy) / radius
        shape = np.clip((1 - d) * 2.5, 0, 1)
        idx = np.ix_(ys % SIZE, xs % SIZE)
        previous = data[idx].copy()
        wins = shape * rank > previous[:, :, 3]
        slopes = np.stack([tilt[0] * shape, tilt[1] * shape], axis=-1)
        values = np.empty_like(previous)
        values[:, :, :2] = 0.5 + slopes * 0.5
        values[:, :, 2] = 0.92 + (roughness - 0.92) * shape
        values[:, :, 3] = rank * shape
        data[idx] = np.where(wins[:, :, None], values, previous)
        tone = color_rng.uniform(-0.43, 0.38)
        warmth = color_rng.uniform(-0.35, 0.65)
        color_values = np.stack([0.5 + tone * shape, 0.5 + warmth * shape * 0.5, shape], axis=-1)
        color_data[idx] = np.where(wins[:, :, None], color_values, color_data[idx])
target = Path(__file__).resolve().parents[1] / "assets/ground/sand_microstructure.png"
Image.fromarray(np.round(np.clip(data, 0, 1) * 255).astype(np.uint8)).save(target, optimize=True)
print(f"Generated {target.name}: {SIZE}x{SIZE}, RG slopes / B roughness / A crystal rank")

color_target = target.with_name("sand_grain_color.png")
Image.fromarray(np.round(np.clip(color_data, 0, 1) * 255).astype(np.uint8)).save(color_target, optimize=True)
print(f"Generated {color_target.name}: {SIZE}x{SIZE}, R tone / G warmth / B grain coverage")
