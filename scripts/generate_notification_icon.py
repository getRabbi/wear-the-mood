"""Regenerate the Android notification SMALL icon from the brand app icon.

Run with: python scripts/generate_notification_icon.py


Android >= 5.0 draws the small icon from its ALPHA CHANNEL ONLY, so handing it
a full-colour opaque launcher icon renders a solid white blob — which is the
"blank logo" users reported. This produces what the platform actually wants:
the brand monogram as a white-on-transparent silhouette at the five density
buckets.

Brightness alone cannot isolate the mark: the artwork's magenta corner glow
peaks at 231 against the glyph's 255. So the mask is thresholded generously and
then reduced to the largest connected component that does NOT touch the image
border — the monogram is inset, every glow bleeds off an edge.
"""
from PIL import Image
from collections import deque
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "app" / "assets" / "icon" / "app_icon.png"
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
DENSITIES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
CONTENT_FRACTION = 20 / 24   # 2dp margin inside the 24dp box (Material)
LO, HI = 150, 220            # soft ramp, so the mark keeps its antialiasing
CC = 256                     # resolution of the connected-component pass

src = Image.open(SRC).convert("RGB")
w, h = src.size

soft = Image.new("L", (w, h))
sp, ap = src.load(), soft.load()
for y in range(h):
    for x in range(w):
        r, g, b = sp[x, y]
        v = max(r, g, b)
        ap[x, y] = 0 if v <= LO else 255 if v >= HI else int(255 * (v - LO) / (HI - LO))

# ── keep only the inset shape ────────────────────────────────────────────────
small = soft.resize((CC, CC), Image.LANCZOS)
binary = [[1 if small.getpixel((x, y)) > 96 else 0 for x in range(CC)] for y in range(CC)]
seen = [[False] * CC for _ in range(CC)]
kept, dropped = [], 0
MIN_COMPONENT = 40  # ignore stray specks from the soft ramp
for y0 in range(CC):
    for x0 in range(CC):
        if not binary[y0][x0] or seen[y0][x0]:
            continue
        q, comp, touches_border = deque([(x0, y0)]), [], False
        seen[y0][x0] = True
        while q:
            x, y = q.popleft()
            comp.append((x, y))
            if x in (0, CC - 1) or y in (0, CC - 1):
                touches_border = True
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < CC and 0 <= ny < CC and binary[ny][nx] and not seen[ny][nx]:
                    seen[ny][nx] = True
                    q.append((nx, ny))
        # The monogram is drawn as SEPARATE strokes, so keep every inset
        # component, not just the biggest one. Anything bleeding off an edge is
        # the artwork's corner glow.
        if touches_border or len(comp) < MIN_COMPONENT:
            dropped += len(comp)
            continue
        kept.append(comp)

best = [p for comp in kept for p in comp]
best_size = len(best)
print(f"kept {len(kept)} component(s), {best_size} px; dropped {dropped} px")

if not best:
    raise SystemExit("no inset component found — check the thresholds")

keep = Image.new("L", (CC, CC), 0)
kp = keep.load()
for x, y in best:
    kp[x, y] = 255
# Grow slightly before upscaling so the soft edge is not clipped away.
keep = keep.resize((w, h), Image.BILINEAR)
kp = keep.load()
for y in range(h):
    for x in range(w):
        if kp[x, y] < 40:
            ap[x, y] = 0

box = soft.getbbox()
glyph = soft.crop(box)
gw, gh = glyph.size
print("glyph bbox", box, "size", (gw, gh), "aspect", round(gw / gh, 3))

master = 512
content = int(master * CONTENT_FRACTION)
scale = min(content / gw, content / gh)
tw, th = max(1, round(gw * scale)), max(1, round(gh * scale))
canvas = Image.new("L", (master, master), 0)
canvas.paste(glyph.resize((tw, th), Image.LANCZOS), ((master - tw) // 2, (master - th) // 2))

white = Image.new("RGBA", (master, master), (255, 255, 255, 0))
white.putalpha(canvas)

for bucket, size in DENSITIES.items():
    out_dir = RES / f"drawable-{bucket}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "ic_stat_wtm.png"
    white.resize((size, size), Image.LANCZOS).save(out, optimize=True)
    print(f"{out.stat().st_size:>6} bytes  drawable-{bucket}/ic_stat_wtm.png")
