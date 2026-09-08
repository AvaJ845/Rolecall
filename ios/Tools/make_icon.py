"""Generate the Rolecall placeholder app icon: a single 1024x1024 opaque PNG.

Calm, warm-neutral ground with one minimal geometric mark evoking a checkmark
("roll call answered"). No alpha channel (iOS app icons must be opaque).

Production icon is still a launch blocker — this is a considered placeholder only.
"""
from PIL import Image, ImageDraw
import pathlib

S = 1024
SS = S * 4  # supersample for clean edges

GROUND = (233, 226, 213)      # warm sand / paper
GROUND_LOW = (223, 214, 198)  # a touch deeper, for a soft vertical settle
MARK = (47, 43, 38)           # near-black warm ink

img = Image.new("RGB", (SS, SS), GROUND)
draw = ImageDraw.Draw(img)

# Very soft vertical gradient so the ground is not a dead flat fill.
for y in range(SS):
    t = y / SS
    r = int(GROUND[0] + (GROUND_LOW[0] - GROUND[0]) * t)
    g = int(GROUND[1] + (GROUND_LOW[1] - GROUND[1]) * t)
    b = int(GROUND[2] + (GROUND_LOW[2] - GROUND[2]) * t)
    draw.line([(0, y), (SS, y)], fill=(r, g, b))

# One checkmark, geometric, drawn as a thick rounded polyline.
# Points chosen for a calm, slightly understated tick centred in the frame.
cx, cy = SS * 0.5, SS * 0.54
scale = SS * 0.30
p1 = (cx - scale * 0.95, cy - scale * 0.02)
p2 = (cx - scale * 0.30, cy + scale * 0.62)
p3 = (cx + scale * 1.00, cy - scale * 0.72)

w = int(SS * 0.052)  # stroke width

def stroke(a, b):
    draw.line([a, b], fill=MARK, width=w)

stroke(p1, p2)
stroke(p2, p3)
for pt in (p1, p2, p3):
    draw.ellipse([pt[0] - w / 2, pt[1] - w / 2, pt[0] + w / 2, pt[1] + w / 2], fill=MARK)

img = img.resize((S, S), Image.LANCZOS)
out = pathlib.Path(__file__).resolve().parent.parent / "Rolecall/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
out.parent.mkdir(parents=True, exist_ok=True)
img.save(out, "PNG")
print("wrote", out, img.size, img.mode)
