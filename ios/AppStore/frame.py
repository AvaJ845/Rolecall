#!/usr/bin/env python3
"""
Frame raw simulator captures into App Store deliverables, per the ASO playbook:
authentic functional UI, a caption read faster than the screen, the real
differentiator first.

    # 1. capture the raw screens (iPhone 6.9" Pro Max + iPad 13") with a clean 9:41 bar
    ios/AppStore/capture.sh
    #   -> writes 0N-*.png into ios/AppStore/raw/iphone/ and raw/ipad/

    # 2. frame them
    python3 ios/AppStore/frame.py

Output:
    ios/AppStore/screenshots/iphone-6.9/*.png    1320 x 2868   (App Store "6.9-inch")
    ios/AppStore/screenshots/iphone-6.5/*.png    1242 x 2688   (App Store "6.5-inch")
    ios/AppStore/screenshots/ipad-13/*.png       2048 x 2732   (App Store "13-inch iPad")

Final order: 01 board -> 02 verified detail -> 03 applications -> 04 filter ->
05 icon variants (composited from the shipped 1024s) -> 06 privacy.
"""
import pathlib
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE / "screenshots"
ICONS = HERE.parent / "Design" / "AppIcon"

PAPER = (246, 243, 236)
INK = (44, 40, 35)
MUTED = (107, 99, 87)
ACCENT = (170, 92, 74)

SERIF = "/System/Library/Fonts/NewYork.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# --- caption copy (shared across device classes) --------------------------
# name: (headline, subline, accent-phrase-in-headline) — every headline accents
# exactly one payoff phrase in terracotta.
CAPTIONS = {
    "01-board": ("Every design job,\nverified live.",
                 "Straight from the company. No ghost jobs, no dead links.",
                 "verified live."),
    "02-verified": ("Rechecked before\nyou ever see it.",
                    "Rolecall opens the posting and confirms the role is really there.",
                    "Rechecked"),
    "03-applications": ("Track every application\nthrough to the offer.",
                        "Recruiter screen, hiring manager, final round, offer — one place.",
                        "offer."),
    "04-filter": ("Your discipline.\nNothing else.",
                  "Product, UX, brand, design systems, research. US and remote.",
                  "Nothing else."),
    "05-icons": ("Made for the people\nwho'll judge it hardest.",
                 "Three icons, dark mode, Dynamic Type, VoiceOver — all first-pass.",
                 "hardest."),
    "06-privacy": ("No account.\nNo trackers. Ever.",
                   "Your whole search stays on your device. Nothing is sent anywhere.",
                   "Ever."),
}

# The three shipped alternate icons, left-to-right on the icon frame.
ICON_VARIANTS = [
    ("Classic", "Rolecall_AppIcon_Light_1024.png"),
    ("Midnight", "Rolecall_AppIcon_Midnight_1024.png"),
    ("Mono", "Rolecall_AppIcon_Mono_1024.png"),
]

# --- device presets ------------------------------------------------------
PRESETS = {
    "iphone-6.9": dict(
        src="iphone", W=1320, H=2868,
        head_px=96, head_lh=112, sub_px=42,
        head_xy=(96, 96), sub_dy=18,
        caption_zone=486, shot_w=1168, radius=56,
        icon_px=356, icon_gap=46, icon_label_px=40,
        crop={"01-board": 132, "02-verified": 132, "03-applications": 132,
              "04-filter": 356, "06-privacy": 452},
        crop_bottom={"02-verified": 880, "06-privacy": 92},
        shots=["01-board", "02-verified", "03-applications", "04-filter", "05-icons", "06-privacy"],
    ),
    "iphone-6.5": dict(
        src="iphone", W=1242, H=2688,
        head_px=88, head_lh=104, sub_px=40,
        head_xy=(90, 92), sub_dy=18,
        caption_zone=452, shot_w=1104, radius=52,
        icon_px=336, icon_gap=42, icon_label_px=38,
        # per-shot top crop of the raw 1320x2868 capture
        crop={"01-board": 132, "02-verified": 132, "03-applications": 132,
              "04-filter": 356, "06-privacy": 452},
        crop_bottom={"02-verified": 880, "06-privacy": 92},
        shots=["01-board", "02-verified", "03-applications", "04-filter", "05-icons", "06-privacy"],
    ),
    "ipad-13": dict(
        src="ipad", W=2048, H=2732,
        head_px=118, head_lh=138, sub_px=52,
        head_xy=(150, 122), sub_dy=26,
        caption_zone=560, shot_w=1600, radius=64,
        icon_px=452, icon_gap=76, icon_label_px=48,
        # raw is 2064x2752. crop_bottom_default trims the last rows (already off-screen)
        # and, with the corner rounding, the display's rounded-corner arc with them —
        # the artefact the old preset cropped around by hand.
        crop={"01-board": 72, "02-verified": 72, "03-applications": 72, "04-filter": 72},
        crop_bottom={"02-verified": 1600},
        crop_bottom_default=36,
        # Settings on iPad is a small centred form-sheet over a dimmed board — it does
        # not frame as a trust beat, so the privacy shot is iPhone-only.
        shots=["01-board", "02-verified", "03-applications", "04-filter", "05-icons"],
    ),
}


def font(path, size, weight=None):
    f = ImageFont.truetype(path, size)
    if weight:
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
    return f


def rounded(img, r):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius=r, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def draw_headline(d, text, accent_word, p):
    head = font(SERIF, p["head_px"], "Bold")
    x0, y = p["head_xy"]
    for line in text.split("\n"):
        if accent_word and accent_word in line:
            before, _, after = line.partition(accent_word)
            x = x0
            for seg, col in ((before, INK), (accent_word, ACCENT), (after, INK)):
                if seg:
                    d.text((x, y), seg, font=head, fill=col)
                    x += d.textlength(seg, font=head)
        else:
            d.text((x0, y), line, font=head, fill=INK)
        y += p["head_lh"]
    return y


def paste_with_shadow(canvas, img, x, y, radius):
    """Drop a rounded image onto the canvas with the same soft shadow the device
    shots use."""
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, y + 12, x + img.width, y + img.height + 12],
        radius=radius, fill=(30, 24, 20, 55))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    merged = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    canvas.paste(merged, (0, 0))
    canvas.paste(img, (x, y), img)


def caption_block(canvas, name, p):
    d = ImageDraw.Draw(canvas)
    headline, subline, accent = CAPTIONS[name]
    y = draw_headline(d, headline, accent, p)
    sub = font(SANS, p["sub_px"], "Regular")
    d.text((p["head_xy"][0] + 2, y + p["sub_dy"]), subline, font=sub, fill=MUTED)


def build_device_shot(name, p, out_dir):
    canvas = Image.new("RGB", (p["W"], p["H"]), PAPER)
    caption_block(canvas, name, p)

    raw = Image.open(RAW / p["src"] / f"{name}.png").convert("RGB")
    top = p["crop"].get(name, 92)
    bottom = p.get("crop_bottom", {}).get(name, p.get("crop_bottom_default", 0))
    raw = raw.crop((0, top, raw.width, raw.height - bottom))
    scale = p["shot_w"] / raw.width
    shot = rounded(raw.resize((p["shot_w"], int(raw.height * scale)), Image.LANCZOS), p["radius"])

    x = (p["W"] - p["shot_w"]) // 2
    # A shot cropped short of the caption zone height (02, 06) is centred in the
    # space below the caption so the paper margin reads as deliberate, not a gap;
    # a full-height shot still starts flush under the caption.
    avail = p["H"] - p["caption_zone"]
    y = p["caption_zone"] + max(0, (avail - shot.height) // 2)
    paste_with_shadow(canvas, shot, x, y, p["radius"])
    _save(canvas, name, out_dir)


def build_icon_shot(name, p, out_dir):
    canvas = Image.new("RGB", (p["W"], p["H"]), PAPER)
    caption_block(canvas, name, p)

    size = p["icon_px"]
    gap = p["icon_gap"]
    corner = int(size * 0.2237)          # iOS icon superellipse, close enough for a squircle
    label_font = font(SANS, p["icon_label_px"], "Medium")
    label_gap = int(p["icon_label_px"] * 0.9)

    group_w = size * 3 + gap * 2
    x0 = (p["W"] - group_w) // 2
    # sit the icon + label block a little above the centre of the space below the
    # caption — the same optical weight as a device shot pinned under the headline
    block_h = size + label_gap + p["icon_label_px"]
    y0 = p["caption_zone"] + int((p["H"] - p["caption_zone"] - block_h) * 0.42)

    d = ImageDraw.Draw(canvas)
    for i, (label, filename) in enumerate(ICON_VARIANTS):
        icon = Image.open(ICONS / filename).convert("RGB").resize((size, size), Image.LANCZOS)
        icon = rounded(icon, corner)
        x = x0 + i * (size + gap)
        paste_with_shadow(canvas, icon, x, y0, corner)
        # a hairline ring so the near-white "Mono" icon still has an edge on paper
        d.rounded_rectangle([x, y0, x + size, y0 + size], radius=corner,
                            outline=(190, 182, 168), width=2)
        tw = d.textlength(label, font=label_font)
        d.text((x + (size - tw) / 2, y0 + size + label_gap), label, font=label_font, fill=MUTED)

    _save(canvas, name, out_dir)


def _save(canvas, name, out_dir):
    out = out_dir / f"{name}.png"
    canvas.save(out)
    print(f"  {out.relative_to(OUT)}  ({canvas.width}x{canvas.height})")


def build(name, p, out_dir):
    if name == "05-icons":
        build_icon_shot(name, p, out_dir)
    else:
        build_device_shot(name, p, out_dir)


def main():
    made = 0
    for preset_name, p in PRESETS.items():
        src_dir = RAW / p["src"]
        have_raw = src_dir.exists() and any(src_dir.glob("*.png"))
        out_dir = OUT / preset_name
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"{preset_name}:")
        for name in p["shots"]:
            if name == "05-icons":
                build(name, p, out_dir)
                made += 1
            elif have_raw and (src_dir / f"{name}.png").exists():
                build(name, p, out_dir)
                made += 1
            else:
                print(f"  (skip {name} — no raw file)")
    if not made:
        print(f"put raw 0N-*.png captures in {RAW}/iphone/ and {RAW}/ipad/ first")


if __name__ == "__main__":
    main()
