#!/usr/bin/env python3
"""
Render the Rolecall "roll-call tick" into the icon variants the app offers in Settings.
Same geometry as the master SVG (viewBox 1024, path 218,520 -> 292,594 -> 686,208,
stroke 104, round caps + joins). Supersampled 4x then downsampled for clean edges.

    python3 generate_variants.py
"""
import json
import pathlib
from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent.parent / "Rolecall" / "Resources" / "Assets.xcassets"

SS = 4
N = 1024 * SS
PTS = [(218, 520), (292, 594), (686, 208)]
STROKE = 104
CAP = STROKE // 2

# The primary AppIcon (Light/Dark) ships from the user's icon package and is NOT
# regenerated here. These are the two Settings alternates only.
VARIANTS = {
    "Midnight": ("#1F1C1A", "#F3EEE3"),
    "Mono":     ("#FFFFFF", "#000000"),
}


def render(ground, mark):
    img = Image.new("RGB", (N, N), ground)
    d = ImageDraw.Draw(img)
    pts = [(x * SS, y * SS) for x, y in PTS]
    d.line(pts, fill=mark, width=STROKE * SS, joint="curve")
    for x, y in pts:
        r = CAP * SS
        d.ellipse((x - r, y - r, x + r, y + r), fill=mark)
    return img.resize((1024, 1024), Image.LANCZOS)


def image_entry(filename, appearance=None):
    e = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    if appearance:
        e["appearances"] = [{"appearance": "luminosity", "value": appearance}]
    return e


def write_set(setname, entries):
    d = ASSETS / f"{setname}.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    (d / "Contents.json").write_text(json.dumps(
        {"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def main():
    for alt, (g, m) in VARIANTS.items():
        img = render(g, m)
        img.save(HERE / f"Rolecall_AppIcon_{alt}_1024.png")
        (ASSETS / f"AppIcon-{alt}.appiconset").mkdir(parents=True, exist_ok=True)
        img.save(ASSETS / f"AppIcon-{alt}.appiconset" / f"Rolecall_AppIcon_{alt}_1024.png")
        write_set(f"AppIcon-{alt}", [image_entry(f"Rolecall_AppIcon_{alt}_1024.png")])

    print("wrote AppIcon-Midnight, AppIcon-Mono ->", ASSETS)


if __name__ == "__main__":
    main()
