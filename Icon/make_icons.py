#!/usr/bin/env python3
"""App icon for Uninstaller: 間 (ma), "the space between".

The kanji 間 is a gate 門 with the sun 日 inside it. Here the gate stays and the
sun dissolves into pixels that drift up and out behind it, leaving the empty
space (ma) behind: the app is gone and the space is clean.

Draws one SVG per variant (light, dark, tinted), rasterizes every macOS/iOS
size, writes an AppIcon.appiconset (with Any/Dark/Tinted appearances), an .icns
per variant, a preview sheet, and transparent layers for Icon Composer.

    pip install cairosvg pillow
    python3 make_icons.py            # icons, appiconset, icns, preview -> build/
    python3 make_icons.py --layers   # Icon Composer layers -> icon-composer-layers/
"""
import json, os, random, shutil, sys
import cairosvg
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "build")
CANVAS = 1024
# Apple macOS icon grid: 824 pt square centred on a 1024 canvas, radius ≈ 185.
SQ, R = 824, 185
OFF = (CANVAS - SQ) // 2

VARIANTS = {
    # name: (bg_top, bg_bottom, gate, pixels, transparent_bg)
    "light":  ("#2A2B30", "#17181B", "#ECEBE6", "#FF6A3D", False),
    "dark":   ("#1E1F23", "#0C0C0E", "#E4E2DC", "#FF6A3D", False),
    # Tinted icons are grayscale on transparent; macOS/iOS apply the user's tint.
    "tinted": (None, None, "#FFFFFF", "#A8A8A8", True),
}

# ---- geometry ---------------------------------------------------------------
GATE_T = 38                      # stroke weight of the gate
X0, X1, Y0, Y1 = 300, 724, 292, 752
BOX_W, BOX_H = 168, 190
SUN = dict(t=30, cx=512, y0=520, w=150, h=190)
CELL = 15                        # pixel grid of the dissolving sun
BASE = 0.2                       # fraction of the sun (from the bottom) still solid
SEED = 11                        # fixed, so the pixel scatter is identical every run


def gate_rects(t=GATE_T):
    """Geometric 門 as (x, y, w, h) rects: two posts, each topped by a 日-like box."""
    r = [(X0, Y0, t, Y1 - Y0),                                  # left post
         (X0, Y0, BOX_W, t), (X0 + BOX_W - t, Y0, t, BOX_H),
         (X0, Y0 + BOX_H / 2 - t / 2, BOX_W, t), (X0, Y0 + BOX_H - t, BOX_W, t)]
    rx = X1 - BOX_W
    r += [(X1 - t, Y0, t, Y1 - Y0 - 30),                        # right post
          (rx, Y0, BOX_W, t), (rx, Y0, t, BOX_H),
          (rx, Y0 + BOX_H / 2 - t / 2, BOX_W, t), (rx, Y0 + BOX_H - t, BOX_W, t)]
    return r


def hook_path(t=GATE_T):
    """Small leftward flick at the foot of the right post."""
    return (f"M{X1} {Y1-60} L{X1} {Y1-14} Q{X1} {Y1} {X1-14} {Y1} "
            f"Q{X1-40} {Y1} {X1-58} {Y1-26} L{X1-t} {Y1-t*0.55} L{X1-t} {Y1-60} Z")


def gate_svg(fill):
    rects = "".join(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="4" fill="{fill}"/>'
                    for x, y, w, h in gate_rects())
    return rects + f'<path d="{hook_path()}" fill="{fill}"/>'


def pixels_svg(fill):
    """The sun 日 rasterised into squares: the base stays, the rest lifts and fades."""
    random.seed(SEED)
    s = SUN
    x0 = s["cx"] - s["w"] / 2
    sun = [(x0, s["y0"], s["t"], s["h"]), (x0 + s["w"] - s["t"], s["y0"], s["t"], s["h"]),
           (x0, s["y0"], s["w"], s["t"]), (x0, s["y0"] + s["h"] / 2 - s["t"] / 2, s["w"], s["t"]),
           (x0, s["y0"] + s["h"] - s["t"], s["w"], s["t"])]
    inside = lambda x, y: any(a <= x < a + w and b <= y < b + h for a, b, w, h in sun)
    top, bot = s["y0"], s["y0"] + s["h"]
    solid = bot - BASE * (bot - top)
    out, size = [], CELL - 3
    for gy in range(top, bot, CELL):
        for gx in range(int(x0), int(x0 + s["w"]), CELL):
            cx, cy = gx + CELL / 2, gy + CELL / 2
            if not inside(cx, cy):
                continue
            if cy >= solid:
                out.append(f'<rect x="{gx}" y="{gy}" width="{size}" height="{size}" rx="2" fill="{fill}"/>')
                continue
            k = ((solid - cy) / (solid - top)) ** 1.6       # 0 at the solid line, 1 at the top
            dy = k * random.uniform(170, 300)
            dx = k * random.uniform(10, 70)
            op = max(0.0, 1 - k * random.uniform(0.55, 1.0))
            if op < 0.06:
                continue
            out.append(f'<rect x="{gx+dx:.1f}" y="{gy-dy:.1f}" width="{size}" height="{size}" rx="2" '
                       f'fill="{fill}" fill-opacity="{op:.2f}"/>')
    return "".join(out)


def svg(variant, parts=("background", "pixels", "gate")):
    bg_top, bg_bot, gate, px, transparent = VARIANTS[variant]
    defs = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{bg_top or "#000"}"/><stop offset="1" stop-color="{bg_bot or "#000"}"/>'
            f'</linearGradient>'
            f'<filter id="blur" x="-10%" y="-10%" width="120%" height="130%"><feGaussianBlur stdDeviation="14"/></filter>'
            f'<clipPath id="clip"><rect x="{OFF}" y="{OFF}" width="{SQ}" height="{SQ}" rx="{R}"/></clipPath>')
    body = ""
    if "background" in parts and not transparent:
        body += (f'<!-- shadow --><rect x="{OFF}" y="{OFF + 12}" width="{SQ}" height="{SQ}" rx="{R}" '
                 f'fill="#000" opacity="0.28" filter="url(#blur)"/>'
                 f'<!-- plate --><rect x="{OFF}" y="{OFF}" width="{SQ}" height="{SQ}" rx="{R}" fill="url(#bg)"/>')
    # pixels pass BEHIND the gate, so they read as leaving through it
    if "pixels" in parts:
        body += f'<!-- pixels --><g clip-path="url(#clip)">{pixels_svg(px)}</g>'
    if "gate" in parts:
        body += f'<!-- gate --><g>{gate_svg(gate)}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
            f'viewBox="0 0 {CANVAS} {CANVAS}"><defs>{defs}</defs>{body}</svg>')


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    iconset = os.path.join(OUT, "AppIcon.appiconset")
    os.makedirs(iconset)
    images = []

    for v in VARIANTS:
        path = os.path.join(OUT, f"icon-{v}.svg")
        with open(path, "w") as f:
            f.write(svg(v))
        png1024 = os.path.join(OUT, f"icon-{v}-1024.png")
        cairosvg.svg2png(url=path, write_to=png1024, output_width=1024, output_height=1024)

        big = Image.open(png1024).convert("RGBA")
        # .icns per variant (Pillow writes these on any platform)
        big.save(os.path.join(OUT, f"Uninstaller-{v}.icns"), format="ICNS",
                 sizes=[(s, s) for s in [16, 32, 64, 128, 256, 512, 1024]])

        for pt in [16, 32, 128, 256, 512]:
            for scale in (1, 2):
                px = pt * scale
                name = f"mac-{v}-{pt}x{pt}@{scale}x.png"
                big.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
                entry = {"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"}
                if v != "light":
                    entry["appearances"] = [{"appearance": "luminosity", "value": v}]
                images.append(entry)

        name = f"ios-{v}-1024.png"
        big.save(os.path.join(iconset, name))
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if v != "light":
            entry["appearances"] = [{"appearance": "luminosity", "value": v}]
        images.append(entry)

    with open(os.path.join(iconset, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)

    # Preview sheet: the three variants side by side on a neutral background
    sheet = Image.new("RGBA", (3 * 1024 + 160, 1024 + 80), (235, 235, 240, 255))
    for i, v in enumerate(VARIANTS):
        im = Image.open(os.path.join(OUT, f"icon-{v}-1024.png")).convert("RGBA")
        if v == "tinted":
            # show the tinted variant the way the system would: tinted over a dark tile
            tile = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
            ImageDraw.Draw(tile).rounded_rectangle((OFF, OFF, OFF + SQ, OFF + SQ), R, fill=(40, 40, 46, 255))
            lum = im.convert("L")
            alpha = Image.eval(im.split()[3], lambda a: a)
            tint = Image.new("RGBA", (1024, 1024), (120, 170, 255, 255))
            tint.putalpha(Image.composite(lum, Image.new("L", (1024, 1024), 0), alpha))
            tile.alpha_composite(tint)
            im = tile
        sheet.alpha_composite(im, (40 + i * (1024 + 40), 40))
    sheet.save(os.path.join(OUT, "preview.png"))
    print("Wrote", OUT)


# ---- Icon Composer layers -------------------------------------------------
# Icon Composer (Xcode 26+) wants transparent artwork per layer; it supplies the
# background fill and derives Dark / Tinted / Clear itself. Two layers:
#   1-pixels (the dissolving sun), 2-gate
def layers():
    out = os.path.join(HERE, "icon-composer-layers")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for name, part in (("1-pixels", "pixels"), ("2-gate", "gate")):
        p = os.path.join(out, name + ".svg")
        open(p, "w").write(svg("light", parts=(part,)))
        cairosvg.svg2png(url=p, write_to=os.path.join(out, name + ".png"),
                         output_width=1024, output_height=1024)
    open(os.path.join(out, "background-colors.txt"), "w").write(
        "Light fill: linear #2A2B30 (top) -> #17181B (bottom)\n"
        "Dark fill:  linear #1E1F23 (top) -> #0C0C0E (bottom)\n"
        "Gate: #ECEBE6   Pixels: #FF6A3D\n")
    print("Wrote", out)


if __name__ == "__main__":
    if "--layers" in sys.argv:
        layers()
    else:
        main()
