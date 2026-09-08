#!/usr/bin/env python3
"""
Frame the raw simulator screenshots into App Store deliverables (6.9", 1320x2868)
per the ASO playbook: authentic functional UI, bold caption read faster than the
screen, lead with the real differentiator.

    # 1. capture the raw screens
    xcodebuild test -project ios/Rolecall.xcodeproj -scheme Rolecall \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
      -only-testing:RolecallUITests/ScreenshotTests -resultBundlePath /tmp/rc.xcresult
    xcrun xcresulttool export attachments --path /tmp/rc.xcresult --output-path /tmp/rc-att
    # (copy the 5 shot-*.png into ios/AppStore/raw/)

    # 2. frame them
    python3 ios/AppStore/frame.py
"""
import pathlib
from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE / "screenshots"
OUT.mkdir(exist_ok=True)

W, H = 1320, 2868
PAPER = (246, 243, 236)
INK = (44, 40, 35)
MUTED = (107, 99, 87)
ACCENT = (170, 92, 74)

SERIF = "/System/Library/Fonts/NewYork.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# (raw file, headline, subline, accent-word-in-headline or None, top_crop)
SHOTS = [
    ("01-board", "Every design job,\nverified live.",
     "Straight from the company. No ghost jobs, no dead links.", "verified live.", 132),
    ("02-verified", "We check it's still open\nbefore you tap through.",
     "Rolecall opens the posting and confirms the role is really there.", None, 132),
    ("03-applications", "Track every application\nthrough to the offer.",
     "Recruiter screen, hiring manager, offer — all in one place.", "offer.", 132),
    ("04-filter", "Your discipline.\nNothing else.",
     "Product, UX, brand, design systems, research. US and remote.", None, 360),
    ("05-privacy", "No account.\nNo trackers. Ever.",
     "Your whole search stays on your device. Nothing is sent anywhere.", None, 360),
]

CAPTION_ZONE = 486     # top band height
SHOT_W = 1168          # framed screenshot width
RADIUS = 56


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


def draw_headline(d, text, accent_word):
    head = font(SERIF, 96, "Bold")
    line_h = 112
    y = 96
    for line in text.split("\n"):
        if accent_word and accent_word in line:
            before, _, after = line.partition(accent_word)
            x = 96
            for seg, col in ((before, INK), (accent_word, ACCENT), (after, INK)):
                if seg:
                    d.text((x, y), seg, font=head, fill=col)
                    x += d.textlength(seg, font=head)
        else:
            d.text((96, y), line, font=head, fill=INK)
        y += line_h
    return y


def build(raw_name, headline, subline, accent_word, top_crop):
    canvas = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(canvas)

    y = draw_headline(d, headline, accent_word)
    sub = font(SANS, 42, "Regular")
    d.text((98, y + 18), subline, font=sub, fill=MUTED)

    raw = Image.open(RAW / f"{raw_name}.png").convert("RGB")
    raw = raw.crop((0, top_crop, raw.width, raw.height))
    scale = SHOT_W / raw.width
    shot = raw.resize((SHOT_W, int(raw.height * scale)), Image.LANCZOS)
    shot = rounded(shot, RADIUS)

    x = (W - SHOT_W) // 2
    sy = CAPTION_ZONE
    # soft shadow
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, sy + 10, x + SHOT_W, sy + shot.height + 10], radius=RADIUS, fill=(30, 24, 20, 55))
    shadow = shadow.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(28))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"), (0, 0))
    canvas.paste(shot, (x, sy), shot)

    out = OUT / f"{raw_name}.png"
    canvas.save(out)
    print(f"  {out.name}  ({canvas.width}x{canvas.height})")


def main():
    if not RAW.exists() or not list(RAW.glob("*.png")):
        print(f"put the raw shot-*.png files in {RAW}/ first")
        return
    print("framing App Store screenshots:")
    for raw_name, head, sub, acc, crop in SHOTS:
        if (RAW / f"{raw_name}.png").exists():
            build(raw_name, head, sub, acc, crop)
        else:
            print(f"  (skip {raw_name} — no raw file)")


if __name__ == "__main__":
    main()
