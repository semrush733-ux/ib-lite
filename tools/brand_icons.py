#!/usr/bin/env python3
"""Makes every Android icon, the TV banner, the splash logo and the in-app logos
from brand/icon.png (square symbol, transparent) and brand/logo.png (wide logo).
Run from the repository root (the build does this before compiling)."""
import os
import shutil
from PIL import Image, ImageDraw

RES = 'android_overlay/app/src/main/res'
ICON = Image.open('brand/icon.png').convert('RGBA')
LOGO = Image.open('brand/logo.png').convert('RGBA')
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def fit(img, w, h, pad=0.0):
    """img scaled to fit inside w x h (minus padding), centred on a transparent canvas."""
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    bw, bh = int(w * (1 - 2 * pad)), int(h * (1 - 2 * pad))
    bb = img.getbbox() or (0, 0, img.width, img.height)
    src = img.crop(bb)
    k = min(bw / src.width, bh / src.height)
    src = src.resize((max(1, int(src.width * k)), max(1, int(src.height * k))), Image.LANCZOS)
    out.paste(src, ((w - src.width) // 2, (h - src.height) // 2), src)
    return out


def mono(img):
    """White silhouette from the picture's shape (Android themed icons)."""
    a = img.getchannel('A')
    white = Image.new('RGBA', img.size, (255, 255, 255, 0))
    white.putalpha(a)
    return white


for name, k in DENS.items():
    d = '%s/mipmap-%s' % (RES, name)
    os.makedirs(d, exist_ok=True)
    s = int(48 * k)
    fit(ICON, s, s, 0.02).save(d + '/ic_launcher.png')
    fit(ICON, s, s, 0.02).save(d + '/ic_launcher_round.png')
    fg = int(108 * k)  # adaptive icon: the symbol stays inside the 66 % safe zone
    fit(ICON, fg, fg, 0.19).save(d + '/ic_launcher_foreground.png')
    mono(fit(ICON, fg, fg, 0.19)).save(d + '/ic_launcher_monochrome.png')

    dd = '%s/drawable-%s' % (RES, name)
    os.makedirs(dd, exist_ok=True)
    sp = int(96 * k)
    fit(ICON, sp, sp, 0.0).save(dd + '/splash_logo.png')
    # TV banner 16:9: the wide logo on a dark red gradient.
    bw, bh = int(320 * k), int(180 * k)
    ban = Image.new('RGBA', (bw, bh))
    dr = ImageDraw.Draw(ban)
    for y in range(bh):
        t = y / bh
        dr.line([(0, y), (bw, y)], fill=(int(46 - 20 * t), int(10 - 4 * t), int(14 - 6 * t), 255))
    lg = fit(LOGO, bw, bh, 0.12)
    ban.paste(lg, (0, 0), lg)
    ban.convert('RGB').save(dd + '/tv_banner.png')

os.makedirs('assets', exist_ok=True)
shutil.copyfile('brand/icon.png', 'assets/symbol.png')
shutil.copyfile('brand/logo.png', 'assets/logo.png')
print('brand pictures written')

# Browser version: favicon and home-screen icons.
for root, _, files in os.walk('web_brand'):
    for f in files:
        if not f.endswith('.png'):
            continue
        p = os.path.join(root, f)
        w, h = Image.open(p).size
        bg = Image.new('RGBA', (w, h), (14, 17, 24, 255)) if 'maskable' in f else Image.new('RGBA', (w, h), (0, 0, 0, 0))
        ic = fit(ICON, w, h, 0.14 if 'maskable' in f else 0.02)
        bg.paste(ic, (0, 0), ic)
        bg.save(p)
print('web icons written')
