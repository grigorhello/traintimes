#!/usr/bin/env python3
"""The launch screen's still (TT-206, D94): the app mark, 96 pt with radius 21.5 and its accent glow, on a transparent
176 x 220 pt image whose centre is 22 pt below the mark's, so iOS (which centres the image) puts the mark's centre 22 pt
above the screen's middle, where the Bloom splash starts. Writes Resources/AppIcon.xcassets/LaunchMark.imageset.
Usage: python3 scripts/make-launch-mark.py (needs Pillow)."""
import json, os
from PIL import Image, ImageDraw, ImageFilter

W, H, LEFT, TOP, MARK = 176, 220, 40, 40, 96
STYLES = {'light': ((0x0C, 0x7B, 0x53), (0xFF, 0xFF, 0xFF)), 'dark': ((0x6E, 0xE7, 0xB7), (0x0B, 0x1F, 0x17))}
OUT = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'AppIcon.xcassets', 'LaunchMark.imageset')


def render(accent, on_accent, scale):
    ss = 4
    k = scale * ss
    img = Image.new('RGBA', (W * k, H * k), (0, 0, 0, 0))
    # The glow: accent at 28 %, 34 pt blur, 14 pt down (CSS box-shadow), and a 1 pt ink shadow at 10 %.
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [LEFT * k, (TOP + 14) * k, (LEFT + MARK) * k, (TOP + 14 + MARK) * k], radius=21.5 * k, fill=accent + (int(255 * 0.28),))
    glow = glow.filter(ImageFilter.GaussianBlur(17 * k))
    img = Image.alpha_composite(img, glow)
    ink = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(ink).rounded_rectangle(
        [LEFT * k, (TOP + 1) * k, (LEFT + MARK) * k, (TOP + 1 + MARK) * k], radius=21.5 * k, fill=(17, 24, 39, int(255 * 0.10)))
    img = Image.alpha_composite(img, ink.filter(ImageFilter.GaussianBlur(1 * k)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([LEFT * k, TOP * k, (LEFT + MARK) * k, (TOP + MARK) * k], radius=21.5 * k, fill=accent + (255,))
    u = MARK / 100 * k  # the glyph's 100 unit box

    def box(x0, y0, x1, y1):
        return [LEFT * k + x0 * u, TOP * k + y0 * u, LEFT * k + x1 * u, TOP * k + y1 * u]
    fg, hole = on_accent + (255,), accent + (255,)
    d.rounded_rectangle(box(18, 18, 82, 50), radius=18 * u, fill=fg, corners=(True, True, False, False))
    d.rounded_rectangle(box(18, 40, 82, 80), radius=10 * u, fill=fg, corners=(False, False, True, True))
    d.rounded_rectangle(box(28, 30, 72, 52), radius=5 * u, fill=hole)
    d.ellipse(box(30, 60, 42, 72), fill=hole)
    d.ellipse(box(58, 60, 70, 72), fill=hole)
    d.rounded_rectangle(box(24, 86, 76, 93), radius=3.5 * u, fill=fg)
    return img.resize((W * scale, H * scale), Image.LANCZOS)


images = []
for style, (accent, on_accent) in STYLES.items():
    for scale in (2, 3):
        name = 'LaunchMark-%s@%dx.png' % (style, scale)
        render(accent, on_accent, scale).save(os.path.join(OUT, name), optimize=True)
        entry = {'filename': name, 'idiom': 'universal', 'scale': '%dx' % scale}
        if style == 'dark':
            entry['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
        images.append(entry)
with open(os.path.join(OUT, 'Contents.json'), 'w') as f:
    json.dump({'images': images, 'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    f.write('\n')
