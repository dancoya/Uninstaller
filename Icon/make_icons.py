#!/usr/bin/env python3
"""Art deco app icon for Uninstaller: light, dark and tinted variants.

Draws one SVG per variant, rasterizes every macOS/iOS size, writes an
AppIcon.appiconset (with Any/Dark/Tinted appearances) and an .icns per variant.
"""
import json, math, os, shutil
import cairosvg
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "build")
CANVAS = 1024
# Apple macOS icon grid: 824 pt square centred on a 1024 canvas, radius ≈ 185.
SQ, R = 824, 185
OFF = (CANVAS - SQ) // 2

VARIANTS = {
    # name: (bg_top, bg_bottom, gold_light, gold_dark, ink, transparent_bg)
    "light":  ("#1B2A4A", "#0B1322", "#F3D98B", "#B8891F", "#0B1322", False),
    "dark":   ("#15151A", "#050507", "#E9C86F", "#9E7418", "#050507", False),
    # Tinted icons are grayscale on transparent; macOS/iOS apply the user's tint.
    "tinted": (None, None, "#FFFFFF", "#9A9A9A", "#000000", True),
}


def sunburst(cx, cy, r_in, r_out, n, color, width):
    """Rays fanning from a point on the bottom edge — the signature deco motif."""
    out = []
    for i in range(n + 1):
        a = math.pi + (i / n) * math.pi  # 180° → 360° (upper half)
        x1, y1 = cx + r_in * math.cos(a), cy + r_in * math.sin(a)
        x2, y2 = cx + r_out * math.cos(a), cy + r_out * math.sin(a)
        out.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
                   f'stroke="{color}" stroke-width="{width}" stroke-linecap="round"/>')
    return "\n".join(out)


def svg(variant):
    bg_top, bg_bot, g1, g2, ink, transparent = VARIANTS[variant]
    X0, Y0 = OFF, OFF  # icon square origin
    cx = CANVAS / 2

    # Bin geometry (in canvas coords)
    body_top, body_bot = Y0 + 300, Y0 + 690
    top_w, bot_w = 360, 300
    lid_y = Y0 + 230

    band_top, band_bot = body_top + 150, body_top + 251
    flutes = []
    for i in range(-3, 4):
        xt = cx + i * (top_w / 8)
        xb = cx + i * (bot_w / 8)
        # interpolate x along the taper so each flute follows the body edge
        def xat(y):
            t = (y - body_top) / (body_bot - body_top)
            return xt + (xb - xt) * t
        for y1, y2 in ((body_top + 24, band_top - 16), (band_bot + 16, body_bot - 24)):
            # thin tapered quad, 10 px wide, as a subpath for the even-odd cut
            flutes.append(f'M{xat(y1) - 5:.1f} {y1} L{xat(y1) + 5:.1f} {y1} '
                          f'L{xat(y2) + 5:.1f} {y2} L{xat(y2) - 5:.1f} {y2} Z ')
    band_cut = (f'M{cx - 150} {band_top} L{cx} {band_top + 65} L{cx + 150} {band_top} '
                f'L{cx + 150} {band_top + 36} L{cx} {band_top + 101} L{cx - 150} {band_top + 36} Z ')

    if transparent:
        background = ""
        frame_opacity = "1"
        ray_opacity = "0.55"
        shadow = ""
    else:
        background = f'''
  <rect x="{X0}" y="{Y0}" width="{SQ}" height="{SQ}" rx="{R}" fill="url(#bg)"/>
  <rect x="{X0}" y="{Y0}" width="{SQ}" height="{SQ}" rx="{R}" fill="url(#vignette)"/>'''
        frame_opacity = "0.9"
        ray_opacity = "0.35"
        shadow = f'<rect x="{X0}" y="{Y0 + 12}" width="{SQ}" height="{SQ}" rx="{R}" fill="#000" opacity="0.28" filter="url(#blur)"/>'

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{bg_top or '#000'}"/>
      <stop offset="1" stop-color="{bg_bot or '#000'}"/>
    </linearGradient>
    <radialGradient id="vignette" cx="0.5" cy="0.95" r="0.9">
      <stop offset="0" stop-color="{g2}" stop-opacity="0.35"/>
      <stop offset="0.55" stop-color="{g2}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{g1}"/>
      <stop offset="0.5" stop-color="{g2}"/>
      <stop offset="1" stop-color="{g1}"/>
    </linearGradient>
    <linearGradient id="goldV" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{g1}"/>
      <stop offset="1" stop-color="{g2}"/>
    </linearGradient>
    <filter id="blur" x="-10%" y="-10%" width="120%" height="130%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>
    <clipPath id="clip"><rect x="{X0}" y="{Y0}" width="{SQ}" height="{SQ}" rx="{R}"/></clipPath>
  </defs>

  {shadow}
  {background}

  <!-- Sunburst rays from the bottom centre, clipped to the icon -->
  <g clip-path="url(#clip)" opacity="{ray_opacity}">
    {sunburst(cx, Y0 + SQ + 40, 300, 900, 22, g1, 6)}
  </g>

  <!-- Stepped double frame -->
  <g fill="none" stroke="url(#gold)" opacity="{frame_opacity}">
    <rect x="{X0 + 58}" y="{Y0 + 58}" width="{SQ - 116}" height="{SQ - 116}" rx="{R - 58}" stroke-width="10"/>
    <rect x="{X0 + 84}" y="{Y0 + 84}" width="{SQ - 168}" height="{SQ - 168}" rx="{R - 84}" stroke-width="4"/>
  </g>

  <!-- Lid: three-tier ziggurat with a finial -->
  <g fill="url(#goldV)">
    <rect x="{cx - 24}" y="{lid_y - 54}" width="48" height="22" rx="4"/>
    <rect x="{cx - 70}" y="{lid_y - 32}" width="140" height="22"/>
    <rect x="{cx - 150}" y="{lid_y - 10}" width="300" height="24"/>
    <rect x="{cx - 230}" y="{lid_y + 14}" width="460" height="34" rx="6"/>
  </g>

  <!-- Body: tapered, fluted -->
  <path d="M{cx - top_w / 2} {body_top} L{cx + top_w / 2} {body_top}
           L{cx + bot_w / 2} {body_bot} Q{cx + bot_w / 2} {body_bot + 26} {cx + bot_w / 2 - 26} {body_bot + 26}
           L{cx - bot_w / 2 + 26} {body_bot + 26} Q{cx - bot_w / 2} {body_bot + 26} {cx - bot_w / 2} {body_bot} Z
           {"".join(flutes)} {band_cut}"
        fill="url(#gold)" fill-rule="evenodd"/>

  <!-- Gold chevron inside the cut-out band -->
  <g fill="{g1}">
    <path d="M{cx - 150} {body_top + 158} L{cx} {body_top + 223} L{cx + 150} {body_top + 158}
             L{cx + 150} {body_top + 176} L{cx} {body_top + 241} L{cx - 150} {body_top + 176} Z"/>
  </g>

  <!-- Base plinth -->
  <rect x="{cx - 200}" y="{body_bot + 34}" width="400" height="16" rx="4" fill="url(#gold)"/>
  <rect x="{cx - 120}" y="{body_bot + 58}" width="240" height="8" rx="3" fill="url(#gold)" opacity="0.8"/>
</svg>'''


MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]


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

        # macOS appiconset entries (appearances only apply to the iOS slot, but
        # the Any slot plus iOS dark/tinted keep Xcode happy on every target)
        for pt in [16, 32, 128, 256, 512]:
            for scale in (1, 2):
                px = pt * scale
                name = f"mac-{v}-{pt}x{pt}@{scale}x.png"
                big.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
                entry = {"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"}
                if v != "light":
                    entry["appearances"] = [{"appearance": "luminosity", "value": v}]
                images.append(entry)

        # iOS universal 1024 slot with appearance variants
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
            from PIL import ImageDraw
            ImageDraw.Draw(tile).rounded_rectangle((OFF, OFF, OFF + SQ, OFF + SQ), R, fill=(40, 40, 46, 255))
            tint = Image.new("RGBA", (1024, 1024), (120, 170, 255, 255))
            tinted = Image.composite(tint, Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)), im.split()[3])
            tile.alpha_composite(tinted)
            im = tile
        sheet.alpha_composite(im, (40 + i * (1024 + 40), 40))
    sheet.save(os.path.join(OUT, "preview.png"))
    print("Wrote", OUT)


if __name__ == "__main__":
    main()


# ---- Icon Composer layers -------------------------------------------------
# Icon Composer (Xcode 26+) wants transparent artwork per layer; it supplies the
# background fill and derives Dark / Tinted / Clear itself. Three layers:
#   1-rays, 2-frame, 3-bin (lid + body + chevron + plinth)
def layers():
    import re
    out = os.path.join(HERE, "icon-composer-layers")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    full = svg("light")
    head, *parts = full.split("<!--")
    defs = head.split("</defs>")[0] + "</defs>\n"
    named = {}
    for p in parts:
        title, body = p.split("-->", 1)
        named[title.strip().split(":")[0].split(" ")[0].lower()] = body
    groups = {
        "1-rays": [named["sunburst"]],
        "2-frame": [named["stepped"]],
        "3-bin": [named["lid"], named["body"], named["gold"], named["base"]],
    }
    for name, bodies in groups.items():
        body = "".join(bodies).replace("</svg>", "")
        doc = defs + body + "</svg>"
        p = os.path.join(out, name + ".svg")
        open(p, "w").write(doc)
        cairosvg.svg2png(url=p, write_to=os.path.join(out, name + ".png"),
                         output_width=1024, output_height=1024)
    open(os.path.join(out, "background-colors.txt"), "w").write(
        "Light fill: linear #1B2A4A (top) -> #0B1322 (bottom)\n"
        "Dark fill:  linear #15151A (top) -> #050507 (bottom)\n")
    print("Wrote", out)


if __name__ == "__main__" and "--layers" in os.sys.argv:
    layers()
