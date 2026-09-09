#!/usr/bin/env python3
"""
Frame raw simulator captures into App Store deliverables, per the ASO playbook:
authentic functional UI, a caption read faster than the screen, the real
differentiator first.

    # 1. capture the raw screens (iPhone 6.9" Pro Max + iPad 13")
    xcodebuild test -project ios/Rolecall.xcodeproj -scheme Rolecall \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
      -only-testing:RolecallUITests/ScreenshotTests/test_captureAppStoreScreens \
      -resultBundlePath /tmp/rc-iphone.xcresult
    xcrun xcresulttool export attachments --path /tmp/rc-iphone.xcresult --output-path /tmp/rc-iphone
    #   -> copy 0N-*.png into ios/AppStore/raw/iphone/  and the iPad run into raw/ipad/

    # 2. frame them
    python3 ios/AppStore/frame.py

Output:
    ios/AppStore/screenshots/iphone-6.5/*.png   1242 x 2688   (App Store "6.5-inch")
    ios/AppStore/screenshots/ipad-13/*.png      2048 x 2732   (App Store "13-inch iPad")
"""
import pathlib
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE / "screenshots"

PAPER = (246, 243, 236)
INK = (44, 40, 35)
MUTED = (107, 99, 87)
ACCENT = (170, 92, 74)

SERIF = "/System/Library/Fonts/NewYork.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# --- caption copy (shared across device classes) --------------------------
# name: (headline, subline, accent-word-in-headline or None)
CAPTIONS = {
    "01-board": ("Every design job,\nverified live.",
                 "Straight from the company. No ghost jobs, no dead links.", "verified live."),
    "02-verified": ("We check it's still open\nbefore you tap through.",
                    "Rolecall opens the posting and confirms the role is really there.", None),
    "03-applications": ("Track every application\nthrough to the offer.",
                        "Recruiter screen, hiring manager, offer — all in one place.", "offer."),
    "04-filter": ("Your discipline.\nNothing else.",
                  "Product, UX, brand, design systems, research. US and remote.", None),
    "05-privacy": ("No account.\nNo trackers. Ever.",
                   "Your whole search stays on your device. Nothing is sent anywhere.", None),
}

# --- device presets ------------------------------------------------------
PRESETS = {
    "iphone-6.9": dict(
        src="iphone", W=1320, H=2868,
        head_px=96, head_lh=112, sub_px=42,
        head_xy=(96, 96), sub_dy=18,
        caption_zone=486, shot_w=1168, radius=56,
        crop={"01-board": 132, "02-verified": 132, "03-applications": 132,
              "04-filter": 356, "05-privacy": 356},
        shots=["01-board", "02-verified", "03-applications", "04-filter", "05-privacy"],
    ),
    "iphone-6.5": dict(
        src="iphone", W=1242, H=2688,
        head_px=88, head_lh=104, sub_px=40,
        head_xy=(90, 92), sub_dy=18,
        caption_zone=452, shot_w=1104, radius=52,
        # per-shot top crop of the raw 1320x2868 capture
        crop={"01-board": 132, "02-verified": 132, "03-applications": 132,
              "04-filter": 356, "05-privacy": 356},
        shots=["01-board", "02-verified", "03-applications", "04-filter", "05-privacy"],
    ),
    "ipad-13": dict(
        src="ipad", W=2048, H=2732,
        head_px=118, head_lh=138, sub_px=52,
        head_xy=(150, 122), sub_dy=26,
        caption_zone=560, shot_w=1600, radius=44,
        # raw is 2064x2752; ~92px trims the status bar. crop_bottom drops the last row
        # (already cut off) and, with it, a stray simulator corner artifact.
        crop={"01-board": 92, "03-applications": 92, "04-filter": 92},
        crop_bottom=132,
        shots=["01-board", "03-applications", "04-filter"],
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


def build(name, p, out_dir):
    headline, subline, accent = CAPTIONS[name]
    canvas = Image.new("RGB", (p["W"], p["H"]), PAPER)
    d = ImageDraw.Draw(canvas)

    y = draw_headline(d, headline, accent, p)
    sub = font(SANS, p["sub_px"], "Regular")
    d.text((p["head_xy"][0] + 2, y + p["sub_dy"]), subline, font=sub, fill=MUTED)

    raw = Image.open(RAW / p["src"] / f"{name}.png").convert("RGB")
    raw = raw.crop((0, p["crop"].get(name, 92),
                    raw.width, raw.height - p.get("crop_bottom", 0)))
    scale = p["shot_w"] / raw.width
    shot = raw.resize((p["shot_w"], int(raw.height * scale)), Image.LANCZOS)
    shot = rounded(shot, p["radius"])

    x = (p["W"] - p["shot_w"]) // 2
    sy = p["caption_zone"]

    shadow = Image.new("RGBA", (p["W"], p["H"]), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, sy + 12, x + p["shot_w"], sy + shot.height + 12],
        radius=p["radius"], fill=(30, 24, 20, 55))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"), (0, 0))
    canvas.paste(shot, (x, sy), shot)

    out = out_dir / f"{name}.png"
    canvas.save(out)
    print(f"  {out.relative_to(OUT)}  ({canvas.width}x{canvas.height})")


def main():
    made = 0
    for preset_name, p in PRESETS.items():
        src_dir = RAW / p["src"]
        if not src_dir.exists() or not list(src_dir.glob("*.png")):
            print(f"(skip {preset_name} — no raw captures in {src_dir}/)")
            continue
        out_dir = OUT / preset_name
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"{preset_name}:")
        for name in p["shots"]:
            if (src_dir / f"{name}.png").exists():
                build(name, p, out_dir)
                made += 1
            else:
                print(f"  (skip {name} — no raw file)")
    if not made:
        print(f"put raw 0N-*.png captures in {RAW}/iphone/ and {RAW}/ipad/ first")


if __name__ == "__main__":
    main()
